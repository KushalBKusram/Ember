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

    // MARK: - Private

    private func performSend(_ text: String) async {
        error = nil
        injectedMemoryCount = 0

        var userMsg = Message(conversationId: conversation.id, role: .user, content: text)
        do {
            try db.save(&userMsg)
            try db.touchConversation(id: conversation.id)
        } catch {
            self.error = "Failed to save message."
            return
        }

        // Retrieve relevant memories before streaming
        var memories: [Memory] = []
        if AppSettings.memoryEnabled && !isIncognito {
            memories = (try? await MemoryService.shared.retrieveRelevant(for: text)) ?? []
            injectedMemoryCount = memories.count
        }

        isStreaming = true
        streamingContent = ""

        let history = messages.filter { $0.id != userMsg.id }

        do {
            let stream = await llm.streamResponse(to: text, history: history, memories: memories)
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
                triggerMemoryExtraction(userMessage: userMsg)
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

    private func triggerMemoryExtraction(userMessage: Message) {
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
