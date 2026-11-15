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
    /// Character-by-character view of the in-progress response.
    /// The view binds to this instead of `streamingContent` so text types out
    /// smoothly rather than arriving in large dumps.
    var displayContent        = ""
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
    /// Buffer between LLM delivery and the display layer.
    private var charQueue: [Character] = []
    /// Task that drains `charQueue` → `displayContent` at a human-readable pace.
    private var dripTask: Task<Void, Never>?

    var isModelAvailable: Bool { llm.isModelAvailable }
    var conversationId: UUID   { agent.conversationId }

    init(agent: Agent) {
        self.agent = agent
    }

    // MARK: - Observation

    func startObserving() {
        observationTask?.cancel()
        observationTask = Task {
            let profile = agent.memoryEnabled ? AppSettings.userProfile : ""
            let override = agent.systemPrompt.isEmpty ? nil : agent.systemPrompt
            await llm.prewarmSession(for: agent.conversationId, userProfile: profile, systemPromptOverride: override)
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

    /// Set synchronously so a second tap before `isStreaming` flips (it only does
    /// after memory/RAG/calendar lookups finish) cannot start a duplicate send.
    private var isBusy = false

    private func runExclusive(_ work: @escaping () async -> Void) {
        isBusy = true
        streamingTask?.cancel()
        streamingTask = Task {
            await work()
            if !Task.isCancelled { isBusy = false }
        }
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming, !isBusy else { return }
        runExclusive { await self.performSend(trimmed, jobId: nil) }
    }

    func cancelStreaming() {
        isBusy = false
        streamingTask?.cancel()
        streamingTask = nil
        dripTask?.cancel()
        dripTask = nil
        charQueue = []
        if !streamingContent.isEmpty {
            wasCancelled = true
            finalizeStream()
        }
        isStreaming      = false
        streamingContent = ""
        displayContent   = ""
    }

    // MARK: - Character drip

    /// Drains `charQueue` → `displayContent` one character at a time.
    /// Adaptive speed: slow for small backlogs (natural feel), faster when
    /// the model outruns the display.
    private func startDrip() {
        dripTask?.cancel()
        dripTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                guard !self.charQueue.isEmpty else {
                    if !self.isStreaming { break }
                    try? await Task.sleep(nanoseconds: 8_000_000)  // 8 ms idle poll
                    continue
                }
                let ch = self.charQueue.removeFirst()
                self.displayContent.append(ch)
                let backlog = self.charQueue.count
                let ns: UInt64 = backlog < 20  ? 12_000_000   // 12 ms — natural typing
                               : backlog < 80  ?  6_000_000   //  6 ms — catching up
                               :                   3_000_000  //  3 ms — sprint
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }

    // MARK: - Job trigger (auto-send from notification or "Run Now")

    func triggerJob(_ job: AgentJob) {
        guard !isStreaming, !isBusy else { return }
        runExclusive {
            await self.performSend(job.prompt, jobId: job.id)
            // Mark both job and agent as run.
            try? await AgentService.shared.touchJobRun(job.id, agentId: self.agent.id)
            // Refresh the agent so lastRunAt updates in the list.
            if let updated = try? self.db.agent(id: self.agent.id) { self.agent = updated }
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

        // All four context fetches run in parallel via async let.
        //
        // searchWithIntelligence uses a lightweight LLM to decide:
        //   (a) does THIS query for THIS agent need live web data?
        //   (b) what is the optimal search engine query to run?
        // This replaces the fragile keyword-list approach and means a finance agent
        // correctly fetches live prices while a cooking agent doesn't trigger
        // unnecessary web searches for the same ambiguous phrasing.
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
            ? WebSearchService.shared.searchWithIntelligence(
                for: text,
                agentContext: agent.agentDescription
              )
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
        displayContent   = ""
        charQueue        = []
        startDrip()

        var firstToken = false
        var prevLen    = 0   // tracks how many chars of the cumulative chunk we've queued
        do {
            let stream = await llm.streamResponse(
                to: text,
                conversationId: agent.conversationId,
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
                // `chunk` is cumulative — enqueue only the newly arrived characters.
                if chunk.count > prevLen {
                    charQueue.append(contentsOf: chunk.dropFirst(prevLen))
                    prevLen = chunk.count
                }
                streamingContent = chunk
            }
        } catch let err as LLMError {
            self.error = err.errorDescription
        } catch {
            if !Task.isCancelled {
                self.error = LLMError.modelUnavailable.errorDescription
            }
        }

        if !firstToken { perfSignposter.endInterval("agent.send→firstToken", sendState) }

        // Stop the background drip and drain the tail inline so `isStreaming`
        // stays true (cursor visible) until every character is displayed.
        dripTask?.cancel()
        dripTask = nil
        if !Task.isCancelled {
            if charQueue.count <= 40 {
                while !charQueue.isEmpty {
                    displayContent.append(charQueue.removeFirst())
                    try? await Task.sleep(nanoseconds: 3_000_000)  // 3 ms
                }
            } else {
                displayContent.append(contentsOf: charQueue)
                charQueue = []
            }
        }

        if !Task.isCancelled, !streamingContent.isEmpty {
            finalizeStream()
            // Background memory extraction — gated on the agent's memory flag.
            if agent.memoryEnabled {
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
        }

        isStreaming    = false
        displayContent = ""   // streaming bubble gone; DB message takes over
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

    /// Scheduling vocabulary that strongly implies a recurring schedule request.
    /// Checked synchronously before spinning up a `LanguageModelSession` so that
    /// the vast majority of non-scheduling messages never touch the LLM at all.
    private static let schedulingKeywords: [String] = [
        // Clock-time schedules
        "every day", "every morning", "every night", "every evening", "every week",
        "every month", "every monday", "every tuesday", "every wednesday",
        "every thursday", "every friday", "every saturday", "every sunday",
        "daily", "weekly", "monthly", "each morning", "each night", "each week",
        "each day", "recurring", "remind me each", "remind me every",
        "give me a report", "send me a report", "schedule a",
        // Interval schedules
        "every 15", "every 30", "every hour", "every 2 hour", "every 4 hour",
        "every 6 hour", "every 12 hour", "every 24 hour",
        "every minute", "each hour", "hourly",
    ]

    /// Returns `true` when `text` contains at least one scheduling keyword.
    private func hasSchedulingVocab(_ text: String) -> Bool {
        let lower = text.lowercased()
        return Self.schedulingKeywords.contains { lower.contains($0) }
    }

    /// Analyses the user's message with a lightweight `LanguageModelSession` to determine
    /// whether it requests a recurring scheduled task ("give me a report every day at 8am"
    /// or "check prices every 15 minutes"). If detected, auto-creates an `AgentJob` and
    /// returns a system note so the model acknowledges the job in its reply.
    /// Returns `nil` if no scheduling intent is found or on any error (best-effort, silent).
    private func detectAndCreateJobIfNeeded(_ text: String) async -> String? {
        // Fast path: skip the LLM round-trip when the message clearly lacks
        // scheduling vocabulary. This covers the overwhelming majority of messages.
        guard hasSchedulingVocab(text) else { return nil }
        do {
            let session = LanguageModelSession(instructions: """
                You are a scheduling-intent parser for a personal AI agent app.
                Analyse the user message and extract any recurring-schedule request.
                Only set hasScheduleIntent=true when the message clearly describes a repeating
                schedule — e.g. "every day", "daily", "every morning at 8am", "weekly on Mon",
                "every 15 minutes", "every hour", "every 2 hours".
                A one-off question or single request is NOT a scheduled task.
                """)
            let result = try await session.respond(
                to: "User message: \"\(text)\"",
                generating: ScheduleIntentResult.self
            )
            let intent = result.content
            guard intent.hasScheduleIntent, !intent.jobName.isEmpty else { return nil }

            // Use the model-cleaned prompt when available; otherwise strip scheduling
            // language from the raw message so the job prompt is self-contained.
            let corePrompt: String = !intent.jobPrompt.isEmpty
                ? intent.jobPrompt
                : await WebSearchService.shared.stripSchedulingLanguage(text)

            // Build the appropriate job type based on what the model detected.
            var job: AgentJob
            if intent.isIntervalBased, intent.intervalMinutes >= 15 {
                job = AgentJob.makeInterval(
                    agentId: agent.id,
                    name: intent.jobName,
                    prompt: corePrompt,
                    intervalMinutes: intent.intervalMinutes
                )
            } else {
                let daySet = Set(
                    intent.scheduleDaysString
                        .split(separator: ",")
                        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                        .filter { (1...7).contains($0) }
                )
                job = AgentJob.make(
                    agentId: agent.id,
                    name: intent.jobName,
                    prompt: corePrompt,
                    hour:   max(0, min(23, intent.scheduleHour)),
                    minute: max(0, min(59, intent.scheduleMinute)),
                    days:   daySet
                )
            }
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
