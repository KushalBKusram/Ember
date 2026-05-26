import Foundation
import PDFKit

actor RAGService {
    static let shared = RAGService()

    private let db = AppDatabase.shared
    private let embedder = EmbeddingService.shared
    private let calendar = CalendarService.shared

    // MARK: - Indexing

    func indexFile(at url: URL) async throws -> RAGDocument {
        let startedAccessing = url.startAccessingSecurityScopedResource()
        defer { if startedAccessing { url.stopAccessingSecurityScopedResource() } }

        let text = try extractText(from: url)
        let title = url.deletingPathExtension().lastPathComponent
        var doc = RAGDocument(title: title, source: .file, sourceIdentifier: url.lastPathComponent)
        try db.saveRAGDocument(&doc)
        try db.deleteRAGChunks(for: doc.id)

        let chunks = makeChunks(from: text)
        for (i, chunkText) in chunks.enumerated() {
            var ragChunk = RAGChunk(documentId: doc.id, content: chunkText, chunkIndex: i)
            if let vec = await embedder.embed(chunkText) {
                ragChunk.embedding = vec.asData
            }
            try db.saveRAGChunk(&ragChunk)
        }

        doc.chunkCount = chunks.count
        try db.saveRAGDocument(&doc)
        return doc
    }

    func deleteDocument(_ document: RAGDocument) throws {
        try db.deleteRAGDocument(document)
    }

    // MARK: - Retrieval

    func retrieve(for query: String, limit: Int = 5) async throws -> [RAGResult] {
        guard let queryVec = await embedder.embed(query) else { return [] }

        var candidates: [(content: String, embedding: [Float], title: String, icon: String)] = []

        // Indexed file chunks
        let pairs = try db.allRAGChunks()
        for (chunk, doc) in pairs {
            guard let data = chunk.embedding, let vec = [Float](data: data) else { continue }
            candidates.append((chunk.content, vec, doc.title, doc.source.icon))
        }

        // Live calendar events
        if AppSettings.calendarEnabled {
            let events = await calendar.fetchEvents()
            for event in events {
                if let vec = await embedder.embed(event) {
                    candidates.append((event, vec, "Calendar", "calendar"))
                }
            }
        }

        // Live reminders
        if AppSettings.remindersEnabled {
            let reminders = await calendar.fetchReminders()
            for reminder in reminders {
                if let vec = await embedder.embed(reminder) {
                    candidates.append((reminder, vec, "Reminders", "checklist"))
                }
            }
        }

        guard !candidates.isEmpty else { return [] }
        return mmr(query: queryVec, candidates: candidates, k: limit)
    }

    // MARK: - Text extraction

    private func extractText(from url: URL) throws -> String {
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(url: url) else { throw RAGError.unreadableFile }
            return pdf.string ?? ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Chunking (512 words, 50-word overlap)

    private func makeChunks(from text: String, windowSize: Int = 512, overlap: Int = 50) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return [] }
        var chunks: [String] = []
        var start = 0
        while start < words.count {
            let end = min(start + windowSize, words.count)
            chunks.append(words[start..<end].joined(separator: " "))
            if end == words.count { break }
            start += windowSize - overlap
        }
        return chunks
    }

    // MARK: - MMR (λ = 0.7)

    private func mmr(
        query: [Float],
        candidates: [(content: String, embedding: [Float], title: String, icon: String)],
        lambda: Float = 0.7,
        k: Int
    ) -> [RAGResult] {
        var selected: [Int] = []
        var remaining = Array(candidates.indices)

        while selected.count < k && !remaining.isEmpty {
            var bestScore = -Float.infinity
            var bestIdx = remaining.first!

            for idx in remaining {
                let relevance = cosineSimilarity(query, candidates[idx].embedding)
                let redundancy: Float = selected.isEmpty ? 0 :
                    (selected.map { cosineSimilarity(candidates[$0].embedding, candidates[idx].embedding) }.max() ?? 0)
                let score = lambda * relevance - (1 - lambda) * redundancy
                if score > bestScore {
                    bestScore = score
                    bestIdx = idx
                }
            }

            selected.append(bestIdx)
            remaining.removeAll { $0 == bestIdx }
        }

        return selected.map { idx in
            RAGResult(
                content: candidates[idx].content,
                sourceTitle: candidates[idx].title,
                sourceIcon: candidates[idx].icon,
                score: cosineSimilarity(query, candidates[idx].embedding)
            )
        }
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

enum RAGError: Error {
    case unreadableFile
}
