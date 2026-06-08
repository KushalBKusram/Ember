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
           let jobStr   = info["jobId"]   as? String,
           let agentId  = UUID(uuidString: agentStr),
           let jobId    = UUID(uuidString: jobStr) {
            Task { @MainActor in
                AgentNavigationState.shared.pendingTrigger = (agentId: agentId, jobId: jobId)
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
