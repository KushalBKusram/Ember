import Foundation
import GRDB

@MainActor
@Observable
final class ConversationListViewModel {
    var conversations: [Conversation] = []
    var searchQuery = ""
    var isLoading = false

    private var observationTask: Task<Void, Never>?
    private let db = AppDatabase.shared

    var filteredConversations: [Conversation] {
        guard !searchQuery.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    func startObserving() {
        observationTask?.cancel()
        observationTask = Task {
            do {
                let observation = db.conversationsObservation()
                for try await updated in observation.values(in: db.dbPool) {
                    guard !Task.isCancelled else { break }
                    self.conversations = updated
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

    @discardableResult
    func createConversation() throws -> Conversation {
        var conversation = Conversation()
        try db.save(&conversation)
        return conversation
    }

    func delete(_ conversation: Conversation) throws {
        try db.delete(conversation)
    }

    func rename(_ conversation: Conversation, to title: String) throws {
        var updated = conversation
        updated.title = title
        updated.updatedAt = Date()
        try db.save(&updated)
    }
}
