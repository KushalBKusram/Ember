import Testing
import Foundation
@testable import Ember

@Suite("Web URL detection")
struct WebFetchURLDetectionTests {

    @Test("Detects a single URL inline")
    func singleURL() async {
        let urls = WebFetchService.shared.detectURLs(in: "Check out https://example.com today")
        #expect(urls.count == 1)
        #expect(urls.first?.host == "example.com")
    }

    @Test("Detects multiple URLs")
    func multipleURLs() async {
        let urls = WebFetchService.shared.detectURLs(in: "First https://a.com and second http://b.org/page")
        #expect(urls.count == 2)
    }

    @Test("Empty text yields no URLs")
    func empty() async {
        let urls = WebFetchService.shared.detectURLs(in: "")
        #expect(urls.isEmpty)
    }

    @Test("Plain prose without URLs yields no results")
    func noURLs() async {
        let urls = WebFetchService.shared.detectURLs(in: "Just some thoughts, nothing linked.")
        #expect(urls.isEmpty)
    }
}
