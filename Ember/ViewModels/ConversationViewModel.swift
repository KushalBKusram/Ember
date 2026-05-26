import Foundation
import GRDB

@MainActor
@Observable
final class ConversationViewModel {
    var messages: [Message] = []
    var streamingContent = ""
    var isStreaming = false
    var error: String?
    var isIncognito = false
    var injectedMemoryCount = 0
    var ragSources: [RAGResult] = []

    let conversation: Conversation
    private let db = AppDatabase.shared
    private let llm = LLMService.shared
    private var observationTask: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?

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
        if !streamingContent.isEmpty { finalizeStream() }
        isStreaming = false
        streamingContent = ""
    }

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
        // Profile injection
        var userProfile = ""
        if AppSettings.memoryEnabled && !isIncognito {
            userProfile = AppSettings.userProfile
            if !userProfile.isEmpty {
                injectedMemoryCount = (try? db.activeMemories().count) ?? 0
            }
        }

        // Detect URLs in message and retrieve RAG (file + calendar + web)
        let webURLs = WebFetchService.shared.detectURLs(in: text)
        var ragContext: [RAGResult] = []
        if !isIncognito {
            ragContext = (try? await RAGService.shared.retrieve(for: text, webURLs: webURLs)) ?? []
            ragSources = ragContext
        }

        isStreaming = true
        streamingContent = ""

        let history = messages.filter { $0.role == .user || $0.role == .assistant }
            .filter { $0.attachmentPath == nil }

        do {
            let stream = await llm.streamResponse(
                to: text,
                history: history,
                userProfile: userProfile,
                ragContext: ragContext
            )
            for try await chunk in stream {
                guard !Task.isCancelled else { break }
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

        if conversation.title == "New Conversation",
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
    }
}
