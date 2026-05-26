import Foundation
import GRDB

@MainActor
@Observable
final class ConversationViewModel {
    var messages: [Message] = []
    var streamingContent = ""
    var isStreaming = false
    var error: String?

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
                // Observation ended — non-fatal
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
        streamingTask = Task {
            await performSend(trimmed)
        }
    }

    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        if !streamingContent.isEmpty {
            finalizeStream()
        }
        isStreaming = false
        streamingContent = ""
    }

    // MARK: - Private

    private func performSend(_ text: String) async {
        error = nil

        var userMsg = Message(conversationId: conversation.id, role: .user, content: text)
        do {
            try db.save(&userMsg)
            try db.touchConversation(id: conversation.id)
        } catch {
            self.error = "Failed to save message."
            return
        }

        isStreaming = true
        streamingContent = ""

        let history = messages.filter { $0.id != userMsg.id }

        do {
            let stream = await llm.streamResponse(to: text, history: history)
            for try await chunk in stream {
                guard !Task.isCancelled else { break }
                streamingContent = chunk
            }
        } catch {
            if !Task.isCancelled {
                self.error = "Failed to get response. Please try again."
            }
        }

        if !Task.isCancelled, !streamingContent.isEmpty {
            finalizeStream()
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

        if conversation.title == "New Conversation", let firstUserMsg = messages.first(where: { $0.role == .user }) {
            autoTitle(from: firstUserMsg.content)
        }
    }

    private func autoTitle(from text: String) {
        let words = text.split(separator: " ").prefix(5).joined(separator: " ")
        let title = words.isEmpty ? "Conversation" : words
        var updated = conversation
        updated.title = String(title)
        updated.updatedAt = Date()
        try? db.save(&updated)
    }
}
