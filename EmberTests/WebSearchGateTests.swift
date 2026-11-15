import Testing
@testable import Ember

@Suite("Web search intent gate")
struct WebSearchGateTests {

    @Test("Questions about the user's own data never go to the web")
    func personalBlocked() {
        #expect(!WebSearchService.hasSearchIntent("When is my rent due?"))
        #expect(!WebSearchService.hasSearchIntent("What is on my schedule today"))
        #expect(!WebSearchService.hasSearchIntent("Where are our tax documents"))
    }

    @Test("General current-events questions still search")
    func generalAllowed() {
        #expect(WebSearchService.hasSearchIntent("What is the weather in Seattle today"))
        #expect(WebSearchService.hasSearchIntent("Who is the president of France"))
    }

    @Test("An explicit search request overrides the personal block")
    func explicitOverrides() {
        #expect(WebSearchService.hasSearchIntent("Search the latest news about my favorite team"))
    }
}
