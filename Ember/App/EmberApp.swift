import SwiftUI
import UserNotifications
import BackgroundTasks

@main
struct EmberApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appLockEnabled") private var appLockEnabled = true
    @State private var isLocked = AppSettings.appLockEnabled

    init() {
        // isInitialisingProfile is a transient UI state flag — it must never
        // survive an app restart.
        AppSettings.isInitialisingProfile = false
        VersionMigrator.runIfNeeded()
        // Register notification delegate so job taps route to the Agents tab.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Register the BGAppRefreshTask handler. Must be called before the app
        // finishes launching — this is the correct place in SwiftUI apps.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundJobService.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // BGAppRefreshTask is an ObjC class with reference semantics — safe to cross
            // the Sendable boundary; nonisolated(unsafe) suppresses the Swift 6 diagnostic.
            nonisolated(unsafe) let sendableTask = refreshTask
            Task { await BackgroundJobService.shared.handleRefreshTask(sendableTask) }
        }
        #if DEBUG
        NetworkGuard.arm()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !DeviceCapability.meetsMinimumSpec {
                    UnsupportedDeviceView()
                        .transition(.opacity)
                } else if !hasCompletedOnboarding {
                    OnboardingView()
                        .transition(.opacity)
                } else if isLocked && appLockEnabled {
                    LockView(isUnlocked: $isLocked.inverted)
                        .transition(.opacity)
                } else {
                    RootView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: hasCompletedOnboarding)
            .animation(.easeInOut(duration: 0.25), value: isLocked)
            .animation(.easeInOut(duration: 0.25), value: appLockEnabled)
            .onChange(of: hasCompletedOnboarding) { _, completed in
                // Sync lock state to whatever the user chose during onboarding
                if completed { isLocked = appLockEnabled }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                if appLockEnabled { withAnimation { isLocked = true } }
                // Re-submit the BGAppRefreshTask each time the app backgrounds so
                // the system always has an up-to-date earliestBeginDate.
                Task { await BackgroundJobService.shared.scheduleNextRefresh() }
            }
        }
    }
}

// MARK: - Binding inversion helper

private extension Binding where Value == Bool {
    var inverted: Binding<Bool> {
        Binding(get: { !wrappedValue }, set: { wrappedValue = !$0 })
    }
}
