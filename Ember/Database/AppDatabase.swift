import GRDB
import Foundation

final class AppDatabase: Sendable {
    static let shared: AppDatabase = {
        do {
            let url = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("ember.sqlite")
            return try AppDatabase(path: url.path)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }()

    let dbPool: DatabasePool

    init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbPool = try DatabasePool(path: path, configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "conversation") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("isPinned", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "message") { t in
                t.primaryKey("id", .text)
                t.column("conversationId", .text).notNull()
                    .references("conversation", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(
                indexOn: "message",
                columns: ["conversationId", "createdAt"]
            )
        }

        try migrator.migrate(dbPool)
    }
}

// MARK: - Conversation queries

extension AppDatabase {
    func allConversations() throws -> [Conversation] {
        try dbPool.read { db in
            try Conversation
                .order(Column("isPinned").desc, Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    func conversationsObservation() -> ValueObservation<ValueReducers.Fetch<[Conversation]>> {
        ValueObservation.tracking { db in
            try Conversation
                .order(Column("isPinned").desc, Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    func save(_ conversation: inout Conversation) throws {
        try dbPool.write { db in
            try conversation.save(db)
        }
    }

    func delete(_ conversation: Conversation) throws {
        try dbPool.write { db in
            _ = try conversation.delete(db)
        }
    }
}

// MARK: - Message queries

extension AppDatabase {
    func messages(for conversationId: UUID) throws -> [Message] {
        try dbPool.read { db in
            try Message
                .filter(Column("conversationId") == conversationId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func messagesObservation(for conversationId: UUID) -> ValueObservation<ValueReducers.Fetch<[Message]>> {
        ValueObservation.tracking { db in
            try Message
                .filter(Column("conversationId") == conversationId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func save(_ message: inout Message) throws {
        try dbPool.write { db in
            try message.save(db)
        }
    }

    func touchConversation(id: UUID) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE conversation SET updatedAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }
}
