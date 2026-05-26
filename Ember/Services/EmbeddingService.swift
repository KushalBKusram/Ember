import Foundation
import NaturalLanguage

actor EmbeddingService {
    static let shared = EmbeddingService()

    private var sentenceEmbedding: NLEmbedding?

    private func embedding() -> NLEmbedding? {
        if sentenceEmbedding == nil {
            sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
        }
        return sentenceEmbedding
    }

    func embed(_ text: String) -> [Float]? {
        guard let emb = embedding(),
              let vector = emb.vector(for: text) else { return nil }
        return vector.map { Float($0) }
    }

    func rankMemories(_ memories: [Memory], for query: String, limit: Int = 8) -> [Memory] {
        guard let queryVec = embed(query) else {
            return Array(memories.prefix(limit))
        }

        typealias Scored = (memory: Memory, score: Float)

        let withEmbedding: [Scored] = memories.compactMap { m in
            guard let data = m.embedding, let vec = [Float](data: data) else { return nil }
            return (m, cosineSimilarity(queryVec, vec))
        }.sorted { $0.score > $1.score }

        let withoutEmbedding = memories.filter { $0.embedding == nil }

        return Array((withEmbedding.map(\.memory) + withoutEmbedding).prefix(limit))
    }

    // MARK: - Math

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
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
