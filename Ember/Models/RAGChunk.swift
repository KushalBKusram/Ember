import Foundation
@preconcurrency import GRDB

struct RAGChunk: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: UUID = UUID()
    var documentId: UUID
    var content: String
    var chunkIndex: Int
    var embedding: Data?
    var createdAt: Date = Date()

    static let databaseTableName = "rag_chunk"
}
