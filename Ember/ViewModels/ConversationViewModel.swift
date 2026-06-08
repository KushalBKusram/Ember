import Foundation
import GRDB
import OSLog

private let perfSignposter = OSSignposter(logHandle: .init(subsystem: "com.kushal.ember", category: "perf"))

@MainActor
@Observable
final class ConversationViewModel {
    var messages: [Message] = []
    var streamingContent = ""
    var isStreaming = false
    var wasCancelled = false
    var error: String?
    var isIncognito = false
    var injectedMemoryCount = 0
    var ragSources: [RAGResult] = []
    #if DEBUG
    /// Snapshot of all context injected into the last LLM call.
    /// Consumed by the debug export button in ConversationView.
    var lastDebugContext: String = ""
    #endif

    private(set) var conversation: Conversation
    private let db = AppDatabase.shared
    private let llm = LLMService.shared
    private var observationTask: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?

    var isModelAvailable: Bool { llm.isModelAvailable }

    init(conversation: Conversation) {
        self.conversation = conversation
    }

    func startObserving() {
        observationTask?.cancel()
        observationTask = Task {
            do {
                let observation = db.messagesObservation(for: conversation.id)
                for try await updated in observation.values(in: db.dbPool) {
                    guard !Task.isCancelled else { break }
                    self.messages = updated
                }
            } catch {
                // Non-fatal
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        streamingTask?.cancel()
        streamingTask = Task { await performSend(trimmed) }
    }

    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        if !streamingContent.isEmpty {
            wasCancelled = true
            finalizeStream()
        }
        isStreaming = false
        streamingContent = ""
    }

    /// Mark the most recent assistant message as having been cancelled.
    /// Cleared after the next send.
    func clearCancelFlag() { wasCancelled = false }

    // MARK: - Image messages

    func saveGeneratedImage(from sourceURL: URL) {
        Task {
            do {
                let filename = "\(UUID().uuidString).jpg"
                let dest = Self.imagesDirectory.appendingPathComponent(filename)
                try FileManager.default.copyItem(at: sourceURL, to: dest)

                var msg = Message(
                    conversationId: conversation.id,
                    role: .assistant,
                    content: "",
                    attachmentPath: filename
                )
                try db.save(&msg)
                try db.touchConversation(id: conversation.id)
            } catch {
                self.error = "Could not save generated image."
            }
        }
    }

    static var imagesDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeneratedImages")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Regenerate & Edit

    func regenerate(_ message: Message) {
        guard !isStreaming else { return }
        guard let idx = messages.firstIndex(where: { $0.id == message.id }),
              let userMsg = messages[..<idx].last(where: { $0.role == .user }) else { return }

        // Delete the assistant message and everything after
        for msg in messages[idx...] { try? db.deleteMessage(msg) }

        streamingTask?.cancel()
        streamingTask = Task { await performSendText(userMsg.content) }
    }

    func submitEdit(message: Message, newContent: String) {
        guard !isStreaming,
              let idx = messages.firstIndex(where: { $0.id == message.id }) else { return }

        var updated = message
        updated.content = newContent
        try? db.save(&updated)

        // Delete everything after the edited message
        for msg in messages[(idx + 1)...] { try? db.deleteMessage(msg) }

        streamingTask?.cancel()
        streamingTask = Task { await performSendText(newContent) }
    }

    // MARK: - Private send

    private func performSend(_ text: String) async {
        error = nil
        wasCancelled = false
        injectedMemoryCount = 0
        ragSources = []

        var userMsg = Message(conversationId: conversation.id, role: .user, content: text)
        do {
            try db.save(&userMsg)
            try db.touchConversation(id: conversation.id)
        } catch {
            self.error = "Failed to save message."
            return
        }

        await performSendText(text)
    }

    // Sends text to the LLM without saving a new user message (used by regen/edit)
    private func performSendText(_ text: String) async {
        #if DEBUG
        lastDebugContext = ""
        #endif

        // First-token latency signpost — open in Instruments → Logging to
        // verify we stay under the PRD's 500ms target.
        let sendId = perfSignposter.makeSignpostID()
        let sendState = perfSignposter.beginInterval("send→firstToken", id: sendId)

        // Profile (narrative summary) + query-specific memory retrieval.
        // The profile gives the LLM general tone/context; retrieved memories
        // give precision for questions the 2–4 sentence profile may have compressed away.
        var userProfile = ""
        var relevantMemoryFacts: [String] = []
        if AppSettings.memoryEnabled && !isIncognito {
            userProfile = AppSettings.userProfile
            let relevantMemories = await MemoryService.shared.retrieveRelevantIfEnabled(for: text)
            relevantMemoryFacts = relevantMemories.map { $0.content }
            injectedMemoryCount = relevantMemories.count
        }

        // Detect URLs in message and retrieve RAG (files, notes, web chunks).
        // Calendar/reminders are fetched separately below — they bypass MMR and
        // get injected as a dedicated structured schedule block.
        let webURLs = WebFetchService.shared.detectURLs(in: text)
        let retrieveState = perfSignposter.beginInterval("rag.retrieve", id: sendId)
        var ragContext: [RAGResult] = []
        var scheduleContext = ""
        if !isIncognito {
            // All three data sources run in parallel.
            async let ragFetch      = RAGService.shared.retrieve(for: text, webURLs: webURLs)
            async let scheduleFetch = CalendarService.shared.fetchContext(for: text)
            async let searchFetch   = WebSearchService.shared.searchIfEnabled(text)

            ragContext      = (try? await ragFetch) ?? []
            scheduleContext = await scheduleFetch ?? ""
            let webResults  = await searchFetch
            ragContext.append(contentsOf: webResults)
            ragSources = ragContext
        }
        perfSignposter.endInterval("rag.retrieve", retrieveState)

        #if DEBUG
        do {
            var _lines: [String] = []
            if isIncognito {
                _lines.append("Mode: INCOGNITO (memory & RAG disabled)")
            } else {
                _lines.append("Profile: \(userProfile.isEmpty ? "—" : userProfile)")
                if relevantMemoryFacts.isEmpty {
                    _lines.append("Memories: none")
                } else {
                    _lines.append("Memories (\(relevantMemoryFacts.count) injected):")
                    relevantMemoryFacts.forEach { _lines.append("  • \($0)") }
                }
                _lines.append("Schedule: \(scheduleContext.isEmpty ? "—" : scheduleContext)")
                if ragContext.isEmpty {
                    _lines.append("RAG: none")
                } else {
                    let sources = ragContext.map { "[\($0.sourceTitle)]" }.joined(separator: " ")
                    _lines.append("RAG (\(ragContext.count)): \(sources)")
                }
            }
            lastDebugContext = _lines.joined(separator: "\n")
        }
        #endif

        isStreaming = true
        streamingContent = ""

        let history = messages.filter { $0.role == .user || $0.role == .assistant }
            .filter { $0.attachmentPath == nil }

        var firstTokenReceived = false
        do {
            let stream = await llm.streamResponse(
                to: text,
                history: history,
                userProfile: userProfile,
                ragContext: ragContext,
                scheduleContext: scheduleContext,
                relevantMemories: relevantMemoryFacts
            )
            for try await chunk in stream {
                guard !Task.isCancelled else { break }
                if !firstTokenReceived {
                    perfSignposter.endInterval("send→firstToken", sendState)
                    firstTokenReceived = true
                }
                streamingContent = chunk
            }
        } catch {
            if !Task.isCancelled {
                self.error = "Model unavailable. Make sure Apple Intelligence is enabled in Settings."
            }
        }

        if !Task.isCancelled, !streamingContent.isEmpty {
            finalizeStream()
            if !isIncognito {
                triggerMemoryExtraction()
            }
        }

        // If we cancelled or errored before any tokens arrived, close the signpost.
        if !firstTokenReceived {
            perfSignposter.endInterval("send→firstToken", sendState)
        }

        isStreaming = false
    }

    private func finalizeStream() {
        var assistantMsg = Message(
            conversationId: conversation.id,
            role: .assistant,
            content: streamingContent
        )
        try? db.save(&assistantMsg)
        try? db.touchConversation(id: conversation.id)
        streamingContent = ""

        // Auto-title only on the first exchange. We check the live conversation
        // title (since `self.conversation` is mutated after auto-title) AND the
        // count of user messages — belt and braces against the observation
        // potentially being mid-flight.
        let userMessageCount = messages.filter { $0.role == .user }.count
        if conversation.title == "New Conversation",
           userMessageCount == 1,
           let firstUser = messages.first(where: { $0.role == .user }) {
            autoTitle(from: firstUser.content)
        }
    }

    private func triggerMemoryExtraction() {
        let conversationId = conversation.id
        Task.detached(priority: .background) {
            let db = AppDatabase.shared
            let msgs = (try? db.messages(for: conversationId)) ?? []
            guard let lastUser = msgs.last(where: { $0.role == .user }),
                  let lastAssistant = msgs.last(where: { $0.role == .assistant }) else { return }
            await MemoryService.shared.processExchange(
                userMessage: lastUser,
                assistantMessage: lastAssistant
            )
        }
    }

    private func autoTitle(from text: String) {
        let words = text.split(separator: " ").prefix(5).joined(separator: " ")
        var updated = conversation
        updated.title = words.isEmpty ? "Conversation" : String(words)
        updated.updatedAt = Date()
        try? db.save(&updated)
        conversation = updated
    }
}
