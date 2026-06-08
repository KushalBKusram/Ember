import Foundation
import FoundationModels
import GRDB
import OSLog

private let perfSignposter = OSSignposter(logHandle: .init(subsystem: "com.kushal.ember", category: "agent-perf"))

@MainActor
@Observable
final class AgentConversationViewModel {
    var messages: [Message]   = []
    var streamingContent      = ""
    var isStreaming            = false
    var wasCancelled           = false
    var error: String?
    var ragSources: [RAGResult] = []
    /// Set when a scheduled job is auto-created from the user's message.
    /// The conversation view observes this to show a brief confirmation banner.
    var newJobBanner: String?  = nil

    private(set) var agent: Agent

    private let db             = AppDatabase.shared
    private let llm            = LLMService.shared
    private var observationTask: Task<Void, Never>?
    private var streamingTask:   Task<Void, Never>?

    var isModelAvailable: Bool { llm.isModelAvailable }
    var conversationId: UUID   { agent.conversationId }

    init(agent: Agent) {
        self.agent = agent
    }

    // MARK: - Observation

    func startObserving() {
        observationTask?.cancel()
        observationTask = Task {
            do {
                let obs = db.messagesObservation(for: agent.conversationId)
                for try await updated in obs.values(in: db.dbPool) {
                    guard !Task.isCancelled else { break }
                    self.messages = updated
                }
            } catch { /* non-fatal */ }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    // MARK: - Manual send

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        streamingTask?.cancel()
        streamingTask = Task { await performSend(trimmed, jobId: nil) }
    }

    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        if !streamingContent.isEmpty {
            wasCancelled = true
            finalizeStream()
        }
        isStreaming      = false
        streamingContent = ""
    }

    // MARK: - Job trigger (auto-send from notification or "Run Now")

    func triggerJob(_ job: AgentJob) {
        guard !isStreaming else { return }
        streamingTask?.cancel()
        streamingTask = Task {
            await performSend(job.prompt, jobId: job.id)
            // Mark both job and agent as run.
            try? await AgentService.shared.touchJobRun(job.id, agentId: agent.id)
            // Refresh the agent so lastRunAt updates in the list.
            if let updated = try? db.agent(id: agent.id) { agent = updated }
        }
    }

    // MARK: - Private

    private func performSend(_ text: String, jobId: UUID?) async {
        error        = nil
        wasCancelled = false
        ragSources   = []
        newJobBanner = nil

        var userMsg = Message(
            conversationId: agent.conversationId,
            role: .user,
            content: text
        )
        do {
            try db.save(&userMsg)
            try db.touchConversation(id: agent.conversationId)
        } catch {
            self.error = "Failed to save message."
            return
        }

        let sendId    = perfSignposter.makeSignpostID()
        let sendState = perfSignposter.beginInterval("agent.send→firstToken", id: sendId)

        // ── Context gathering (parallel) ──────────────────────────────────────
        var userProfile       = ""
        var relevantMemories: [String] = []
        if agent.memoryEnabled {
            userProfile      = AppSettings.userProfile
            let mems         = await MemoryService.shared.retrieveRelevantIfEnabled(for: text)
            relevantMemories = mems.map { $0.content }
        }

        var ragContext      : [RAGResult] = []
        var scheduleContext = ""
        var systemNote      = ""

        // Scheduling-intent detection runs only for user-typed messages (jobId == nil).
        // Web search uses the liberal real-time gate (searchForAgent) instead of the
        // conservative chat gate so finance/market/news terms always trigger a fetch.
        async let jobNoteFetch: String? = (jobId == nil)
            ? detectAndCreateJobIfNeeded(text)
            : nil
        async let ragFetch      = agent.ragEnabled
            ? RAGService.shared.retrieve(for: text, webURLs: [])
            : []
        async let scheduleFetch = agent.calendarEnabled
            ? CalendarService.shared.fetchContext(for: text)
            : nil
        async let searchFetch   = agent.webSearchEnabled
            ? WebSearchService.shared.searchForAgent(text)
            : []

        systemNote      = await jobNoteFetch ?? ""
        ragContext      = (try? await ragFetch) ?? []
        scheduleContext = await scheduleFetch ?? ""
        let webResults  = await searchFetch
        ragContext.append(contentsOf: webResults)
        ragSources = ragContext

        // ── Stream ────────────────────────────────────────────────────────────
        isStreaming      = true
        streamingContent = ""

        let history = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .filter { $0.attachmentPath == nil }

        var firstToken = false
        do {
            let stream = await llm.streamResponse(
                to: text,
                history: history,
                userProfile: userProfile,
                ragContext: ragContext,
                scheduleContext: scheduleContext,
                relevantMemories: relevantMemories,
                systemPromptOverride: agent.systemPrompt,
                systemNote: systemNote
            )
            for try await chunk in stream {
                guard !Task.isCancelled else { break }
                if !firstToken {
                    perfSignposter.endInterval("agent.send→firstToken", sendState)
                    firstToken = true
                }
                streamingContent = chunk
            }
        } catch {
            if !Task.isCancelled {
                self.error = "Model unavailable. Make sure Apple Intelligence is enabled."
            }
        }

        if !firstToken { perfSignposter.endInterval("agent.send→firstToken", sendState) }

        if !Task.isCancelled, !streamingContent.isEmpty {
            finalizeStream()
            // Background memory extraction — same pipeline as regular conversations.
            let convId = agent.conversationId
            Task.detached(priority: .background) {
                let db   = AppDatabase.shared
                let msgs = (try? db.messages(for: convId)) ?? []
                guard let lastUser      = msgs.last(where: { $0.role == .user }),
                      let lastAssistant = msgs.last(where: { $0.role == .assistant }) else { return }
                await MemoryService.shared.processExchange(
                    userMessage: lastUser,
                    assistantMessage: lastAssistant
                )
            }
        }

        isStreaming = false
    }

    private func finalizeStream() {
        var msg = Message(
            conversationId: agent.conversationId,
            role: .assistant,
            content: streamingContent
        )
        try? db.save(&msg)
        try? db.touchConversation(id: agent.conversationId)
        streamingContent = ""
    }

    // MARK: - Scheduling intent detection

    /// Analyses the user's message with a lightweight `LanguageModelSession` to determine
    /// whether it requests a recurring scheduled task ("give me a report every day at 8am").
    /// If detected, auto-creates an `AgentJob` and returns a system note string to inject
    /// into the LLM context so the model naturally acknowledges the job in its reply.
    /// Returns `nil` if no scheduling intent is found or on any error (best-effort, silent).
    private func detectAndCreateJobIfNeeded(_ text: String) async -> String? {
        do {
            let session = LanguageModelSession(instructions: """
                You are a scheduling-intent parser for a personal AI agent app.
                Analyse the user message and extract any recurring-schedule request.
                Only set hasScheduleIntent=true when the message clearly describes a repeating
                schedule — e.g. "every day", "daily", "every morning at 8am", "weekly on Mon".
                A one-off question or single request is NOT a scheduled task.
                """)
            let result = try await session.respond(
                to: "User message: \"\(text)\"",
                generating: ScheduleIntentResult.self
            )
            let intent = result.content
            guard intent.hasScheduleIntent, !intent.jobName.isEmpty else { return nil }

            // Parse weekday set; empty means every day.
            let daySet = Set(
                intent.scheduleDaysString
                    .split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { (1...7).contains($0) }
            )

            // Use the model-cleaned prompt when available; otherwise strip scheduling
            // language from the raw message so the job prompt is self-contained.
            let corePrompt: String
            if !intent.jobPrompt.isEmpty {
                corePrompt = intent.jobPrompt
            } else {
                corePrompt = await WebSearchService.shared.stripSchedulingLanguage(text)
            }

            var job = AgentJob.make(
                agentId: agent.id,
                name: intent.jobName,
                prompt: corePrompt,
                hour:   max(0, min(23, intent.scheduleHour)),
                minute: max(0, min(59, intent.scheduleMinute)),
                days:   daySet
            )
            try await AgentService.shared.saveJob(&job)

            // Surface a banner in the conversation view.
            newJobBanner = "📅 Job created: \"\(intent.jobName)\" · \(job.scheduleDescription)"

            return """
                A recurring scheduled job was automatically created from the user's message. \
                Job name: "\(intent.jobName)". \
                Schedule: \(job.scheduleDescription). \
                Job prompt saved: "\(corePrompt)". \
                Notifications are set. In your response, confirm what was scheduled — \
                tell the user the job name, when it will run, and what it will do.
                """
        } catch {
            return nil  // Silent — never let detection failure block the response.
        }
    }
}
