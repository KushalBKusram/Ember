import Foundation
import UserNotifications

/// Parsed routing decision from a notification's `userInfo` payload.
enum NotificationRouting: Equatable {
    /// Result-ready: job ran in the background — open the agent conversation without re-triggering.
    case openAgent(UUID)
    /// Tap-to-run: job hasn't run yet — navigate to the agent and trigger the job.
    case triggerJob(agentId: UUID, jobId: UUID)
}

/// UNUserNotificationCenter delegate. Set as delegate in EmberApp.init().
/// Extracts agentId + jobId from notification payloads and routes them
/// to AgentNavigationState so the Agents tab can navigate + auto-trigger.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationDelegate()

    /// Pure parsing helper — converts raw `userInfo` to a typed routing decision.
    /// Extracted so it can be unit-tested without constructing a UNNotificationResponse.
    static func routing(from userInfo: [AnyHashable: Any]) -> NotificationRouting? {
        guard let agentStr = userInfo["agentId"] as? String,
              let agentId  = UUID(uuidString: agentStr) else { return nil }
        if let isResult = userInfo["isResult"] as? String, isResult == "1" {
            return .openAgent(agentId)
        }
        if let jobStr = userInfo["jobId"] as? String,
           let jobId  = UUID(uuidString: jobStr) {
            return .triggerJob(agentId: agentId, jobId: jobId)
        }
        return nil
    }

    // Called when the user taps a notification (app in background or killed).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch Self.routing(from: response.notification.request.content.userInfo) {
        case .openAgent(let agentId):
            Task { @MainActor in AgentNavigationState.shared.pendingOpen = agentId }
        case .triggerJob(let agentId, let jobId):
            Task { @MainActor in AgentNavigationState.shared.pendingTrigger = (agentId: agentId, jobId: jobId) }
        case nil:
            break
        }
        completionHandler()
    }

    // Called when a notification arrives while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
