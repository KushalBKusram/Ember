import SwiftUI

@main
struct EmberApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLocked = AppSettings.appLockEnabled

    var body: some Scene {
        WindowGroup {
            if isLocked {
                LockView(isUnlocked: $isLocked.inverted)
                    .transition(.opacity)
            } else {
                RootView()
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && AppSettings.appLockEnabled {
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
