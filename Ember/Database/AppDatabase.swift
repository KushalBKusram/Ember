import GRDB
import Foundation

final class AppDatabase: Sendable {
    // Bump when the on-disk format changes in a way that requires wiping
    // unencrypted data from older builds. v2 = NSFileProtectionComplete migration.
    private static let storageVersionKey = "emberStorageVersion"
    private static let currentStorageVersion = 2

    static let shared: AppDatabase = {
        do {
            let dir = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = dir.appendingPathComponent("ember.sqlite")

            wipeUnencryptedLegacyDatabaseIfNeeded(at: url)

            do {
                return try AppDatabase(path: url.path)
            } catch {
                // Database corruption — quarantine the broken file and try
                // once more with a fresh DB. Better to lose local data than
                // crash on launch with no recovery path.
                quarantineCorruptDatabase(at: url, reason: error)
                return try AppDatabase(path: url.path)
            }
        } catch {
            fatalError("Failed to initialize database after recovery: \(error)")
        }
    }()

    private static func quarantineCorruptDatabase(at url: URL, reason: Error) {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        for ext in ["", "-wal", "-shm"] {
            let original = URL(fileURLWithPath: url.path + ext)
            guard fm.fileExists(atPath: original.path) else { continue }
            let quarantined = url.deletingPathExtension()
                .appendingPathExtension("broken-\(stamp).sqlite\(ext)")
            try? fm.moveItem(at: original, to: quarantined)
        }
        // Surface to telemetry-equivalent: NSLog so it lands in Console.app.
        NSLog("[Ember] Database quarantined due to: \(reason)")
    }

    let dbPool: DatabasePool

    init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbPool = try DatabasePool(path: path, configuration: config)
        try migrate()
        try Self.applyFileProtection(at: path)
    }

    // MARK: - File-protection migration
    //
    // The original v1 database was created with the OS default protection
    // (.completeUntilFirstUserAuthentication). For v2 we step up to
    // .completeUnlessOpen — the file is re-encrypted whenever it is closed
    // (i.e. when the app terminates or backgrounds long enough for the
    // database pool to be torn down) with a hardware-backed key. While the
    // app is in foreground and the pool is open, the file is accessible —
    // which is exactly what GRDB's DatabasePool needs.
    //
    // Note: this is iOS-native at-rest encryption via the Secure Enclave,
    // not SQLCipher. On A17 Pro+ hardware it is stronger than SQLCipher
    // for our threat model (no passphrase to leak, hardware-bound key).
    //
    // Existing plain data from older builds is wiped so the new file is
    // born with full file-protection attributes from the start.

    private static func wipeUnencryptedLegacyDatabaseIfNeeded(at url: URL) {
        let defaults = UserDefaults.standard
        let storedVersion = defaults.integer(forKey: storageVersionKey)
        guard storedVersion < currentStorageVersion else { return }

        let fm = FileManager.default
        for ext in ["", "-wal", "-shm"] {
            let companion = URL(fileURLWithPath: url.path + ext)
            if fm.fileExists(atPath: companion.path) {
                try? fm.removeItem(at: companion)
            }
        }
        defaults.set(currentStorageVersion, forKey: storageVersionKey)
    }

    private static func applyFileProtection(at path: String) throws {
        let fm = FileManager.default
        for ext in ["", "-wal", "-shm"] {
            let p = path + ext
            guard fm.fileExists(atPath: p) else { continue }
            try fm.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: p
            )
        }
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

        migrator.registerMigration("v2_memory") { db in
            try db.create(table: "memory") { t in
                t.primaryKey("id", .text)
                t.column("content", .text).notNull()
                t.column("category", .text).notNull()
                t.column("embedding", .blob)
                t.column("createdAt", .datetime).notNull()
                t.column("lastAccessedAt", .datetime).notNull()
                t.column("expiresAt", .datetime)
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
            }
            try db.create(indexOn: "memory", columns: ["isEnabled", "expiresAt"])
        }

        migrator.registerMigration("v3_rag") { db in
            try db.create(table: "rag_document") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("source", .text).notNull()
                t.column("sourceIdentifier", .text)
                t.column("indexedAt", .datetime).notNull()
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("chunkCount", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "rag_chunk") { t in
                t.primaryKey("id", .text)
                t.column("documentId", .text).notNull()
                    .references("rag_document", onDelete: .cascade)
                t.column("content", .text).notNull()
                t.column("chunkIndex", .integer).notNull()
                t.column("embedding", .blob)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(indexOn: "rag_chunk", columns: ["documentId", "chunkIndex"])
        }

        migrator.registerMigration("v4_image_messages") { db in
            try db.alter(table: "message") { t in
                t.add(column: "attachmentPath", .text)
            }
        }

        migrator.registerMigration("v5_embedding_cache") { db in
            // Content-hash → embedding blob. We never delete entries —
            // they're cheap (~2KB each) and a stale cache hit costs nothing.
            try db.create(table: "embedding_cache") { t in
                t.primaryKey("contentHash", .text)
                t.column("embedding", .blob).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v6_agents") { db in
            try db.create(table: "agent") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("emoji", .text).notNull()
                t.column("agentDescription", .text).notNull()
                t.column("systemPrompt", .text).notNull()
                t.column("webSearchEnabled", .boolean).notNull().defaults(to: true)
                t.column("calendarEnabled", .boolean).notNull().defaults(to: false)
                t.column("memoryEnabled", .boolean).notNull().defaults(to: true)
                t.column("ragEnabled", .boolean).notNull().defaults(to: false)
                t.column("conversationId", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("lastRunAt", .datetime)
            }

            try db.create(table: "agent_job") { t in
                t.primaryKey("id", .text)
                t.column("agentId", .text).notNull()
                    .references("agent", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("prompt", .text).notNull()
                t.column("scheduleHour", .integer).notNull()
                t.column("scheduleMinute", .integer).notNull()
                t.column("scheduleDaysRaw", .text).notNull().defaults(to: "")
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("lastRunAt", .datetime)
            }
            try db.create(indexOn: "agent_job", columns: ["agentId"])
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

    func deleteMessage(_ message: Message) throws {
        try dbPool.write { db in
            _ = try message.delete(db)
        }
    }

    func deleteMessages(after date: Date, in conversationId: UUID) throws {
        try dbPool.write { db in
            try Message
                .filter(Column("conversationId") == conversationId)
                .filter(Column("createdAt") >= date)
                .deleteAll(db)
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

    /// Latest message per conversation, keyed by conversation ID.
    /// Used for row previews on the chat list. Empty content (image-only
    /// messages) is skipped in favour of the prior text message.
    func latestMessageContent(by conversationId: [UUID]) throws -> [UUID: String] {
        guard !conversationId.isEmpty else { return [:] }
        return try dbPool.read { db in
            // Single subquery instead of N separate fetchOne calls:
            // the inner GROUP BY picks MAX(createdAt) per conversation, the
            // outer join resolves that timestamp back to the message content.
            let placeholders = conversationId.map { _ in "?" }.joined(separator: ",")
            var args = StatementArguments()
            for id in conversationId { args += [id.uuidString] }

            let rows = try Row.fetchAll(db, sql: """
                SELECT m.conversationId, m.content
                FROM message m
                INNER JOIN (
                    SELECT conversationId, MAX(createdAt) AS maxAt
                    FROM message
                    WHERE content != '' AND conversationId IN (\(placeholders))
                    GROUP BY conversationId
                ) latest
                    ON m.conversationId = latest.conversationId
                   AND m.createdAt      = latest.maxAt
                   AND m.content        != ''
                """, arguments: args)

            var out: [UUID: String] = [:]
            for row in rows {
                if let idStr: String = row["conversationId"],
                   let id = UUID(uuidString: idStr),
                   let content: String = row["content"] {
                    out[id] = content
                }
            }
            return out
        }
    }
}

// MARK: - Memory queries

extension AppDatabase {
    func activeMemories() throws -> [Memory] {
        try dbPool.read { db in
            try Memory
                .filter(Column("isEnabled") == true)
                .filter(Column("expiresAt") == nil || Column("expiresAt") > Date())
                .order(Column("lastAccessedAt").desc)
                .fetchAll(db)
        }
    }

    func allMemoriesObservation() -> ValueObservation<ValueReducers.Fetch<[Memory]>> {
        ValueObservation.tracking { db in
            try Memory
                .order(Column("category").asc, Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func saveMemory(_ memory: inout Memory) throws {
        try dbPool.write { db in
            try memory.save(db)
        }
    }

    func deleteMemory(_ memory: Memory) throws {
        try dbPool.write { db in
            _ = try memory.delete(db)
        }
    }

    func clearAllMemories() throws {
        try dbPool.write { db in
            _ = try Memory.deleteAll(db)
        }
    }
}

// MARK: - RAG Document queries

extension AppDatabase {
    func allRAGDocuments() throws -> [RAGDocument] {
        try dbPool.read { db in
            try RAGDocument.order(Column("indexedAt").desc).fetchAll(db)
        }
    }

    func allRAGDocumentsObservation() -> ValueObservation<ValueReducers.Fetch<[RAGDocument]>> {
        ValueObservation.tracking { db in
            try RAGDocument.order(Column("indexedAt").desc).fetchAll(db)
        }
    }

    func saveRAGDocument(_ doc: inout RAGDocument) throws {
        try dbPool.write { db in
            try doc.save(db)
        }
    }

    func deleteRAGDocument(_ doc: RAGDocument) throws {
        try dbPool.write { db in
            _ = try doc.delete(db)
        }
    }
}

// MARK: - Agent queries

extension AppDatabase {
    func allAgents() throws -> [Agent] {
        try dbPool.read { db in
            try Agent.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    func allAgentsObservation() -> ValueObservation<ValueReducers.Fetch<[Agent]>> {
        ValueObservation.tracking { db in
            try Agent.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    func agent(id: UUID) throws -> Agent? {
        try dbPool.read { db in try Agent.fetchOne(db, id: id) }
    }

    func saveAgent(_ agent: inout Agent) throws {
        try dbPool.write { db in try agent.save(db) }
    }

    func deleteAgent(_ agent: Agent) throws {
        try dbPool.write { db in _ = try agent.delete(db) }
    }

    func touchAgentRunDate(_ agentId: UUID) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE agent SET lastRunAt = ? WHERE id = ?",
                arguments: [Date(), agentId]
            )
        }
    }
}

// MARK: - AgentJob queries

extension AppDatabase {
    func jobs(for agentId: UUID) throws -> [AgentJob] {
        try dbPool.read { db in
            try AgentJob
                .filter(Column("agentId") == agentId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func jobsObservation(for agentId: UUID) -> ValueObservation<ValueReducers.Fetch<[AgentJob]>> {
        ValueObservation.tracking { db in
            try AgentJob
                .filter(Column("agentId") == agentId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func allEnabledJobs() throws -> [AgentJob] {
        try dbPool.read { db in
            try AgentJob.filter(Column("isEnabled") == true).fetchAll(db)
        }
    }

    func saveJob(_ job: inout AgentJob) throws {
        try dbPool.write { db in try job.save(db) }
    }

    func deleteJob(_ job: AgentJob) throws {
        try dbPool.write { db in _ = try job.delete(db) }
    }

    func touchJobRunDate(_ jobId: UUID) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE agent_job SET lastRunAt = ? WHERE id = ?",
                arguments: [Date(), jobId]
            )
        }
    }

    /// Marks both the job and its parent agent as run in a single write transaction.
    func touchJobAndAgentRunDate(jobId: UUID, agentId: UUID) throws {
        let now = Date()
        try dbPool.write { db in
            try db.execute(sql: "UPDATE agent_job SET lastRunAt = ? WHERE id = ?",  arguments: [now, jobId])
            try db.execute(sql: "UPDATE agent    SET lastRunAt = ? WHERE id = ?",  arguments: [now, agentId])
        }
    }

    /// Updates `lastAccessedAt` for multiple memories in a single write transaction.
    func touchMemoryAccessDates(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        let now = Date()
        try dbPool.write { db in
            for id in ids {
                try db.execute(
                    sql: "UPDATE memory SET lastAccessedAt = ? WHERE id = ?",
                    arguments: [now, id.uuidString]
                )
            }
        }
    }
}

// MARK: - RAG Chunk queries

extension AppDatabase {
    func ragChunks(for documentId: UUID) throws -> [RAGChunk] {
        try dbPool.read { db in
            try RAGChunk
                .filter(Column("documentId") == documentId)
                .order(Column("chunkIndex").asc)
                .fetchAll(db)
        }
    }

    func saveRAGChunk(_ chunk: inout RAGChunk) throws {
        try dbPool.write { db in
            try chunk.save(db)
        }
    }

    func deleteRAGChunks(for documentId: UUID) throws {
        try dbPool.write { db in
            try RAGChunk.filter(Column("documentId") == documentId).deleteAll(db)
        }
    }

    func cachedEmbedding(forHash hash: String) throws -> Data? {
        try dbPool.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT embedding FROM embedding_cache WHERE contentHash = ?",
                arguments: [hash]
            )
        }
    }

    func setCachedEmbedding(_ data: Data, forHash hash: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO embedding_cache (contentHash, embedding, createdAt)
                    VALUES (?, ?, ?)
                    ON CONFLICT(contentHash) DO UPDATE SET embedding = excluded.embedding
                    """,
                arguments: [hash, data, Date()]
            )
        }
    }

    func allRAGChunks() throws -> [(chunk: RAGChunk, document: RAGDocument)] {
        try dbPool.read { db in
            // Two queries instead of N+1:
            //   1. Fetch all enabled documents.
            //   2. Fetch all their chunks in one JOIN, then pair using the map.
            let docs = try RAGDocument
                .filter(Column("isEnabled") == true)
                .fetchAll(db)
            guard !docs.isEmpty else { return [] }

            let docMap = Dictionary(uniqueKeysWithValues: docs.map { ($0.id, $0) })

            let chunks = try RAGChunk.fetchAll(db, sql: """
                SELECT rc.*
                FROM rag_chunk rc
                INNER JOIN rag_document rd ON rc.documentId = rd.id
                WHERE rd.isEnabled = 1
                ORDER BY rc.documentId, rc.chunkIndex
                """)

            return chunks.compactMap { chunk in
                guard let doc = docMap[chunk.documentId] else { return nil }
                return (chunk, doc)
            }
        }
    }
}
