import Foundation
import GRDB
import OSLog

private let perfLog        = OSLog(subsystem: "com.kushal.ember", category: "agent-perf")
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

        // ── Context gathering ─────────────────────────────────────────────────
        var userProfile       = ""
        var relevantMemories: [String] = []
        if agent.memoryEnabled {
            userProfile       = AppSettings.userProfile
            let mems          = await MemoryService.shared.retrieveRelevantIfEnabled(for: text)
            relevantMemories  = mems.map { $0.content }
        }

        var ragContext      : [RAGResult] = []
        var scheduleContext = ""
        async let ragFetch      = agent.ragEnabled
            ? RAGService.shared.retrieve(for: text, webURLs: [])
            : []
        async let scheduleFetch = agent.calendarEnabled
            ? CalendarService.shared.fetchContext(for: text)
            : nil
        async let searchFetch   = agent.webSearchEnabled
            ? WebSearchService.shared.searchIfEnabled(text)
            : []

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
                systemPromptOverride: agent.systemPrompt
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
}
