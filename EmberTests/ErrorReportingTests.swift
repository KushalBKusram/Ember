import Testing
import Foundation
@testable import Ember

@Suite("User-facing error reporting")
struct ErrorReportingTests {
    private struct Boom: LocalizedError { var errorDescription: String? { "disk full" } }

    @Test("Message names the failed action and hides the technical reason")
    func message() {
        let m = UserFacingError.message("delete the conversation", Boom())
        #expect(m == "Couldn't delete the conversation. Please try again.")
        #expect(!m.contains("disk full"))
    }

    @MainActor
    @Test("A failing write sets the view model's error instead of being swallowed")
    func attemptReportsFailure() {
        let vm = ConversationListViewModel()
        vm.attempt("rename the conversation") { throw Boom() }
        #expect(vm.error == "Couldn't rename the conversation. Please try again.")
    }

    @MainActor
    @Test("A successful write leaves no error")
    func attemptSuccess() {
        let vm = ConversationListViewModel()
        vm.attempt("rename the conversation") {}
        #expect(vm.error == nil)
    }
}
