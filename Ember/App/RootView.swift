import SwiftUI

struct RootView: View {
    @AppStorage("isInitialisingProfile") private var isInitialisingProfile = false

    var body: some View {
        TabView {
            Tab("Agents", systemImage: "sparkles") {
                AgentsListView()
            }
            Tab("Chats", systemImage: "bubble.left.and.bubble.right.fill") {
                ConversationListView()
            }
            Tab("Memory", systemImage: "brain.head.profile") {
                MemoryView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .overlay(alignment: .top) {
            if isInitialisingProfile {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Building your profile…")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: isInitialisingProfile)
    }
}
