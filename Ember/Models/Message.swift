import Foundation
@preconcurrency import GRDB

struct Message: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: UUID
    var conversationId: UUID
    var role: Role
    var content: String
    var createdAt: Date
    var attachmentPath: String?

    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    init(id: UUID = UUID(), conversationId: UUID, role: Role, content: String, attachmentPath: String? = nil) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.createdAt = Date()
        self.attachmentPath = attachmentPath
    }

    static let databaseTableName = "message"
}
