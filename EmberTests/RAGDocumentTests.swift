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
