import Foundation
import NaturalLanguage
import CryptoKit

actor EmbeddingService {
    static let shared = EmbeddingService()

    private let db = AppDatabase.shared
    private var sentenceEmbedding: NLEmbedding?

    private func embedding() -> NLEmbedding? {
        if sentenceEmbedding == nil {
            sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
        }
        return sentenceEmbedding
    }

    /// Compute (or return cached) embedding for the given text.
    /// The cache is keyed on SHA-256 of the trimmed text — calendar events
    /// and reminders re-appear with identical content on every query, so
    /// caching saves ~5ms each and adds up fast.
    func embed(_ text: String) -> [Float]? {
        embedCached(text)
    }

    /// Skip the cache lookup. Used by indexing paths where the content is
    /// being hashed and saved anyway.
    private func embedUncached(_ text: String) -> [Float]? {
        guard let emb = embedding(),
              let vector = emb.vector(for: text) else { return nil }
        return vector.map { Float($0) }
    }

    private func embedCached(_ text: String) -> [Float]? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let hash = Self.hash(key)

        if let cached = try? db.cachedEmbedding(forHash: hash),
           let vec = [Float](data: cached) {
            return vec
        }

        guard let vec = embedUncached(key) else { return nil }
        try? db.setCachedEmbedding(vec.asData, forHash: hash)
        return vec
    }

    private static func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the highest cosine similarity between `text` and any memory that has a stored
    /// embedding, together with the memory that produced that score.
    /// Used for dedup (skip if ≥ 0.97) and supersession (LLM check if 0.70–0.97).
    func mostSimilar(of text: String, in memories: [Memory]) -> (score: Float, memory: Memory?) {
        guard !memories.isEmpty, let vec = embed(text) else { return (0, nil) }
        var bestScore: Float = 0
        var bestMemory: Memory? = nil
        for m in memories {
            guard let data = m.embedding, let existingVec = [Float](data: data) else { continue }
            let score = Self.cosineSimilarity(vec, existingVec)
            if score > bestScore { bestScore = score; bestMemory = m }
        }
        return (bestScore, bestMemory)
    }

    func rankMemories(_ memories: [Memory], for query: String, limit: Int = 8) -> [Memory] {
        guard let queryVec = embed(query) else {
            return Array(memories.prefix(limit))
        }

        typealias Scored = (memory: Memory, score: Float)

        let withEmbedding: [Scored] = memories.compactMap { m in
            guard let data = m.embedding, let vec = [Float](data: data) else { return nil }
            return (m, Self.cosineSimilarity(queryVec, vec))
        }.sorted { $0.score > $1.score }

        let withoutEmbedding = memories.filter { $0.embedding == nil }

        return Array((withEmbedding.map(\.memory) + withoutEmbedding).prefix(limit))
    }

    // MARK: - Math

    /// Cosine similarity between two equal-length float vectors.
    /// `nonisolated static` so `RAGService` (a different actor) can call it
    /// without `await`, avoiding unnecessary actor hops for a pure computation.
    nonisolated static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        let magA = sqrt(a.reduce(Float(0)) { $0 + $1 * $1 })
        let magB = sqrt(b.reduce(Float(0)) { $0 + $1 * $1 })
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }
}

// MARK: - Float array ↔ Data

extension Array where Element == Float {
    var asData: Data {
        withUnsafeBytes { Data($0) }
    }

    init?(data: Data) {
        let stride = MemoryLayout<Float>.stride
        guard !data.isEmpty, data.count % stride == 0 else { return nil }
        self = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
