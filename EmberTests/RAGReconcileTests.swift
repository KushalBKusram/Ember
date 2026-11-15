import Testing
@testable import Ember

@Suite("Web vs personal source reconciliation")
struct RAGReconcileTests {
    private func personal(_ t: String) -> RAGResult { RAGResult(content: t, sourceTitle: t, sourceIcon: "note.text", score: 0.3) }
    private func web(_ t: String) -> RAGResult { RAGResult(content: t, sourceTitle: t, sourceIcon: "globe", score: 0.3, isWeb: true) }

    @Test("With web search results, personal documents are dropped")
    func dropsPersonal() {
        let out = [personal("Rent")].reconciled(withWebSearch: [web("wikipedia.org")])
        #expect(out.map(\.sourceTitle) == ["wikipedia.org"])
    }

    @Test("Without web results, personal documents are kept")
    func keepsPersonal() {
        let out = [personal("Rent")].reconciled(withWebSearch: [])
        #expect(out.map(\.sourceTitle) == ["Rent"])
    }

    @Test("Pasted-URL web content is kept alongside search results")
    func keepsPastedURL() {
        let out = [personal("Rent"), web("pasted.example")].reconciled(withWebSearch: [web("wikipedia.org")])
        #expect(out.map(\.sourceTitle) == ["pasted.example", "wikipedia.org"])
    }
}
