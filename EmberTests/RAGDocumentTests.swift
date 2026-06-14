import Testing
import Foundation
@testable import Ember

@Suite("RAGDocument source taxonomy")
struct RAGDocumentTests {

    @Test("All four source types have labels and icons")
    func allSourcesAreComplete() {
        for source in RAGDocument.Source.allCases {
            #expect(!source.label.isEmpty)
            #expect(!source.icon.isEmpty)
        }
    }

    @Test("Note source maps to note.text icon")
    func noteIcon() {
        #expect(RAGDocument.Source.note.icon == "note.text")
    }

    @Test("New document defaults to isEnabled = true and chunkCount = 0")
    func defaults() {
        let doc = RAGDocument(title: "Foo", source: .file)
        #expect(doc.isEnabled)
        #expect(doc.chunkCount == 0)
    }
}

@Suite("Note chunk round trip")
struct NoteChunkRoundTripTests {

    private func words(_ n: Int) -> String {
        (0..<n).map { "w\($0)" }.joined(separator: " ")
    }

    @Test("Empty text produces no chunks and reassembles to empty")
    func empty() {
        #expect(RAGService.makeChunks(from: "") == [])
        #expect(RAGService.reassembleChunks([]) == "")
    }

    @Test("Short note stays a single chunk and survives the round trip")
    func shortNote() {
        let text = "groceries: oat milk, eggs,\nand the good coffee"
        let chunks = RAGService.makeChunks(from: text)
        #expect(chunks.count == 1)
        #expect(RAGService.reassembleChunks(chunks) == text)
    }

    @Test("Long note splits into overlapping chunks yet reassembles exactly")
    func longNote() {
        let text = words(1500)
        let chunks = RAGService.makeChunks(from: text)
        #expect(chunks.count > 1)
        #expect(RAGService.reassembleChunks(chunks) == text)
    }

    // Word counts straddling the chunk-window boundaries (512-word window,
    // 462-word stride): exactly one window, one word over, multiple windows.
    @Test("Boundary lengths survive the round trip", arguments: [511, 512, 513, 924, 925, 974, 975, 1436])
    func boundaryLengths(count: Int) {
        let text = words(count)
        #expect(RAGService.reassembleChunks(RAGService.makeChunks(from: text)) == text)
    }
}
