import Foundation
import PDFKit

actor RAGService {
    static let shared = RAGService()

    private let db = AppDatabase.shared
    private let embedder = EmbeddingService.shared
    private let webFetcher = WebFetchService.shared

    // MARK: - Indexing

    func indexFile(at url: URL) async throws -> RAGDocument {
        let startedAccessing = url.startAccessingSecurityScopedResource()
        defer { if startedAccessing { url.stopAccessingSecurityScopedResource() } }

        let text = try extractText(from: url)
        let title = url.deletingPathExtension().lastPathComponent
        var doc = RAGDocument(title: title, source: .file, sourceIdentifier: url.lastPathComponent)
        try db.saveRAGDocument(&doc)
        try db.deleteRAGChunks(for: doc.id)

        let chunks = Self.makeChunks(from: text)
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

    // MARK: - Notes (user-authored short text)

    /// Index a free-form note. Uses the same chunking + embedding path as files;
    /// the original text is recovered for editing via `noteBody(for:)`, which
    /// reverses the chunk overlap.
    @discardableResult
    func indexNote(title: String, body: String, replacing existing: RAGDocument? = nil) async throws -> RAGDocument {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? "Untitled Note" : cleanTitle

        var doc: RAGDocument
        if let existing {
            doc = existing
            doc.title = finalTitle
            doc.indexedAt = Date()
            try db.saveRAGDocument(&doc)
            try db.deleteRAGChunks(for: doc.id)
        } else {
            doc = RAGDocument(title: finalTitle, source: .note, sourceIdentifier: nil)
            try db.saveRAGDocument(&doc)
        }

        let chunks = Self.makeChunks(from: cleanBody)
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

    /// Reconstruct the original note text from its stored chunks.
    func noteBody(for documentId: UUID) throws -> String {
        Self.reassembleChunks(try db.ragChunks(for: documentId).map(\.content))
    }

    // MARK: - Retrieval

    func retrieve(for query: String, webURLs: [URL] = [], limit: Int = 5) async throws -> [RAGResult] {
        guard let queryVec = await embedder.embed(query) else { return [] }

        var candidates: [(content: String, embedding: [Float], title: String, icon: String)] = []

        // Indexed file chunks
        let pairs = try db.allRAGChunks()
        for (chunk, doc) in pairs {
            guard let data = chunk.embedding, let vec = [Float](data: data) else { continue }
            candidates.append((chunk.content, vec, doc.title, doc.source.icon))
        }

        // Calendar events and reminders are injected via a dedicated structured block
        // in LLMService (date-window-aware, chronologically sorted) rather than
        // flowing through MMR. Mixing time-series calendar data with semantic
        // document chunks produced unordered, irrelevant event selection.

        // Web content — fetch all URLs in parallel; chunk + embed each result
        // serially since embedding is CPU-bound and isolated to the actor.
        let fetched = await withTaskGroup(of: (URL, String?).self) { group in
            for url in webURLs {
                group.addTask { [webFetcher] in
                    (url, try? await webFetcher.fetchText(from: url))
                }
            }
            var results: [(URL, String)] = []
            for await (url, text) in group {
                if let text { results.append((url, text)) }
            }
            return results
        }
        for (url, text) in fetched {
            let host = url.host ?? "Web"
            for chunk in Self.makeChunks(from: text) {
                if let vec = await embedder.embed(chunk) {
                    candidates.append((chunk, vec, host, "globe"))
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
    //
    // Pure static pair — `reassembleChunks` is the exact inverse of
    // `makeChunks`, which keeps the note edit round trip lossless and lets
    // the property be unit-tested without a database.

    nonisolated static func makeChunks(from text: String, windowSize: Int = 512, overlap: Int = 50) -> [String] {
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

    /// Chunks carry a `overlap`-word overlap, so every chunk after the first
    /// drops its leading words — naively joining would duplicate text at each
    /// boundary, growing the note every time it is opened and re-saved.
    nonisolated static func reassembleChunks(_ chunks: [String], overlap: Int = 50) -> String {
        guard let first = chunks.first else { return "" }
        let rest = chunks.dropFirst().map { chunk in
            chunk.split(separator: " ", omittingEmptySubsequences: true)
                .dropFirst(overlap)
                .joined(separator: " ")
        }
        return ([first] + rest).joined(separator: " ")
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
                let relevance = EmbeddingService.cosineSimilarity(query, candidates[idx].embedding)
                let redundancy: Float = selected.isEmpty ? 0 :
                    (selected.map { EmbeddingService.cosineSimilarity(candidates[$0].embedding, candidates[idx].embedding) }.max() ?? 0)
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
                score: EmbeddingService.cosineSimilarity(query, candidates[idx].embedding)
            )
        }
    }

}

enum RAGError: Error {
    case unreadableFile
}
