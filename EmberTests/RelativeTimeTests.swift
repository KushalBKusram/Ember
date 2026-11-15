import Testing
import Foundation
@testable import Ember

@Suite("Relative timestamp formatting")
struct RelativeTimeTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("Just-written and slightly-future timestamps read 'Just now'")
    func justNow() {
        #expect(now.relativeFormatted(now: now) == "Just now")
        #expect(now.addingTimeInterval(5).relativeFormatted(now: now) == "Just now")
        #expect(now.addingTimeInterval(-30).relativeFormatted(now: now) == "Just now")
    }

    @Test("Older timestamps are formatted relatively, never as 'in 0s'")
    func older() {
        let text = now.addingTimeInterval(-3600).relativeFormatted(now: now)
        #expect(text != "Just now")
        #expect(!text.hasPrefix("in "))
    }
}
