import SwiftUI
import UserNotifications

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
            if phase == .background && appLockEnabled {
                withAnimation { isLocked = true }
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
