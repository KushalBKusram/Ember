import SwiftUI
import LocalAuthentication

struct LockView: View {
    @Binding var isUnlocked: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var failed = false
    @State private var authenticating = false

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.accentColor)

                    Text("Ember")
                        .font(.largeTitle.bold())
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        authenticate()
                    } label: {
                        Label("Unlock with Face ID", systemImage: "faceid")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 40)
                    .disabled(authenticating)

                    if failed {
                        Text("Authentication failed. Try again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .task { authenticate() }
        .onChange(of: scenePhase) { _, phase in
            // Retry automatically whenever the app comes back to active —
            // covers the "user cancelled Face ID, then re-engaged the app"
            // case without needing another tap.
            if phase == .active && !authenticating { authenticate() }
        }
    }

    /// A cancelled or interrupted prompt (user cancel, app backgrounded, system
    /// pre-empted it) is not a failed attempt and shouldn't say "failed".
    nonisolated static func isGenuineFailure(_ error: Error?) -> Bool {
        guard let error = error as? LAError else { return true }
        switch error.code {
        // notInteractive: the prompt was requested while the app was still inactive
        // (launch / returning from background); the next attempt succeeds.
        case .userCancel, .systemCancel, .appCancel, .notInteractive: return false
        default: return true
        }
    }

    private func authenticate() {
        guard !authenticating else { return }
        authenticating = true

        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Ember to access your private conversations"
            ) { success, authError in
                DispatchQueue.main.async {
                    isUnlocked = success
                    failed = !success && Self.isGenuineFailure(authError)
                    authenticating = false
                    if success { Haptics.success() } else { Haptics.warning() }
                }
            }
        } else {
            isUnlocked = true
            authenticating = false
        }
    }
}
