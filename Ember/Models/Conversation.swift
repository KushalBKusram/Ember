import Foundation
@preconcurrency import GRDB

struct Conversation: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord, Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool

    init(id: UUID = UUID(), title: String = "New Conversation") {
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isPinned = false
    }

    static let databaseTableName = "conversation"
}
