import Foundation
import UserNotifications

/// UNUserNotificationCenter delegate. Set as delegate in EmberApp.init().
/// Extracts agentId + jobId from notification payloads and routes them
/// to AgentNavigationState so the Agents tab can navigate + auto-trigger.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationDelegate()

    // Called when the user taps a notification (app in background or killed).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo

        if let agentStr = info["agentId"] as? String,
           let agentId  = UUID(uuidString: agentStr) {

            if let isResult = info["isResult"] as? String, isResult == "1" {
                // Result-ready notification: job already ran in the background.
                // Just navigate to the agent conversation — don't re-trigger the job.
                Task { @MainActor in
                    AgentNavigationState.shared.pendingOpen = agentId
                }
            } else if let jobStr = info["jobId"] as? String,
                      let jobId  = UUID(uuidString: jobStr) {
                // Legacy tap-to-run notification: navigate and trigger the job.
                Task { @MainActor in
                    AgentNavigationState.shared.pendingTrigger = (agentId: agentId, jobId: jobId)
                }
            }
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
