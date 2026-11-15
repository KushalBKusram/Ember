import Testing
import Foundation
@testable import Ember

/// Exercises RAGService.indexFile against real temp files (the system file picker
/// can't be driven in the Simulator). Documents are removed afterwards.
@Suite("RAG file import", .serialized)
struct RAGImportTests {
    private let db = AppDatabase.shared

    private func tempFile(_ name: String, _ data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ember-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func docs(named id: String) -> [RAGDocument] {
        ((try? db.allRAGDocuments()) ?? []).filter { $0.source == .file && $0.sourceIdentifier == id }
    }

    @Test("Importing the same file twice leaves exactly one document")
    func reimportIsIdempotent() async throws {
        let name = "ember-reimport-\(UUID().uuidString.prefix(6)).txt"
        let url = try tempFile(name, Data("Rent is due on the first of the month.".utf8))
        let first = try await RAGService.shared.indexFile(at: url)
        let second = try await RAGService.shared.indexFile(at: url)
        defer { for d in docs(named: name) { try? db.deleteRAGDocument(d) } }

        #expect(first.id == second.id)
        #expect(docs(named: name).count == 1)
        #expect(second.chunkCount == 1)
    }

    @Test("An empty file imports without crashing and yields no chunks")
    func emptyFile() async throws {
        let name = "ember-empty-\(UUID().uuidString.prefix(6)).txt"
        let url = try tempFile(name, Data())
        let doc = try await RAGService.shared.indexFile(at: url)
        defer { for d in docs(named: name) { try? db.deleteRAGDocument(d) } }
        #expect(doc.chunkCount == 0)
    }

    @Test("A corrupt PDF fails gracefully: either an error or an empty document, never a crash")
    func corruptPDF() async throws {
        let name = "ember-corrupt-\(UUID().uuidString.prefix(6)).pdf"
        let url = try tempFile(name, Data("this is not a pdf".utf8))
        defer { for d in docs(named: name) { try? db.deleteRAGDocument(d) } }
        do {
            let doc = try await RAGService.shared.indexFile(at: url)
            #expect(doc.chunkCount == 0)
        } catch {
            #expect(!docs(named: name).contains { $0.chunkCount > 0 })
        }
    }

    @Test("A large text file (about 60k words) is chunked and indexed")
    func largeFile() async throws {
        let name = "ember-large-\(UUID().uuidString.prefix(6)).txt"
        let text = (0..<60_000).map { "word\($0 % 500)" }.joined(separator: " ")
        let url = try tempFile(name, Data(text.utf8))
        let doc = try await RAGService.shared.indexFile(at: url)
        defer { for d in docs(named: name) { try? db.deleteRAGDocument(d) } }
        #expect(doc.chunkCount > 100)
    }
}
