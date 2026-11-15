import Testing
@testable import Ember

@Suite("Calendar access note")
struct CalendarAccessNoteTests {
    @Test("Missing access is stated explicitly and never as an empty calendar")
    func note() {
        let n = CalendarService.accessUnavailableNote.lowercased()
        #expect(n.contains("unavailable"))
        #expect(n.contains("cannot see"))
        #expect(n.contains("never say there are no events"))
        #expect(!n.contains("none scheduled"))
    }
}
