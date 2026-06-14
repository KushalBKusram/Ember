import Testing
import Foundation
@testable import Ember

@Suite("NotificationDelegate routing")
struct NotificationRoutingTests {
    let agentId = UUID()
    let jobId   = UUID()

    @Test("Result-ready notification routes to openAgent")
    func resultReady() {
        let info: [AnyHashable: Any] = ["agentId": agentId.uuidString, "isResult": "1"]
        #expect(NotificationDelegate.routing(from: info) == .openAgent(agentId))
    }

    @Test("Tap-to-run notification routes to triggerJob")
    func tapToRun() {
        let info: [AnyHashable: Any] = ["agentId": agentId.uuidString, "jobId": jobId.uuidString]
        #expect(NotificationDelegate.routing(from: info) == .triggerJob(agentId: agentId, jobId: jobId))
    }

    @Test("isResult != '1' falls through to tap-to-run path")
    func isResultNonOne() {
        let info: [AnyHashable: Any] = [
            "agentId": agentId.uuidString,
            "isResult": "0",
            "jobId": jobId.uuidString
        ]
        #expect(NotificationDelegate.routing(from: info) == .triggerJob(agentId: agentId, jobId: jobId))
    }

    @Test("Missing agentId returns nil")
    func missingAgentId() {
        let info: [AnyHashable: Any] = ["jobId": jobId.uuidString]
        #expect(NotificationDelegate.routing(from: info) == nil)
    }

    @Test("Malformed agentId UUID returns nil")
    func malformedAgentId() {
        let info: [AnyHashable: Any] = ["agentId": "not-a-uuid"]
        #expect(NotificationDelegate.routing(from: info) == nil)
    }

    @Test("Valid agentId with no jobId and no isResult returns nil")
    func agentIdOnly() {
        let info: [AnyHashable: Any] = ["agentId": agentId.uuidString]
        #expect(NotificationDelegate.routing(from: info) == nil)
    }

    @Test("Malformed jobId UUID returns nil even with valid agentId")
    func malformedJobId() {
        let info: [AnyHashable: Any] = ["agentId": agentId.uuidString, "jobId": "bad-uuid"]
        #expect(NotificationDelegate.routing(from: info) == nil)
    }

    @Test("Empty userInfo returns nil")
    func emptyUserInfo() {
        #expect(NotificationDelegate.routing(from: [:]) == nil)
    }
}
