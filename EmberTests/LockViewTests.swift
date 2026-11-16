import Testing
import LocalAuthentication
@testable import Ember

@Suite("Lock screen failure messaging")
struct LockViewTests {
    @Test("A cancelled or interrupted prompt is not reported as a failed attempt")
    func cancelsAreNotFailures() {
        #expect(!LockView.isGenuineFailure(LAError(.userCancel)))
        #expect(!LockView.isGenuineFailure(LAError(.systemCancel)))
        #expect(!LockView.isGenuineFailure(LAError(.appCancel)))
        #expect(!LockView.isGenuineFailure(LAError(.notInteractive)))
    }

    @Test("A real authentication failure is reported")
    func realFailures() {
        #expect(LockView.isGenuineFailure(LAError(.authenticationFailed)))
        #expect(LockView.isGenuineFailure(nil))
    }
}
