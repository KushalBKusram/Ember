import SwiftUI
import LocalAuthentication

struct LockView: View {
    @Binding var isUnlocked: Bool
    @State private var failed = false

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
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Ember to access your private conversations"
            ) { success, _ in
                DispatchQueue.main.async {
                    isUnlocked = success
                    failed = !success
                }
            }
        } else {
            isUnlocked = true
        }
    }
}
