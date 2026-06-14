import SwiftUI

struct RootView: View {
    @AppStorage("isInitialisingProfile") private var isInitialisingProfile = false
    @State private var selectedTab: AppTab = .agents

    private let navState = AgentNavigationState.shared

    private enum AppTab: Hashable {
        case agents, chats, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Agents", systemImage: "sparkles", value: AppTab.agents) {
                AgentsListView()
            }
            Tab("Chats", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.chats) {
                ConversationListView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        // A job notification tap must surface the Agents tab regardless of
        // where the user last was — AgentsListView handles the navigation push.
        .onChange(of: navState.pendingTrigger?.agentId) { _, new in
            if new != nil { selectedTab = .agents }
        }
        .onChange(of: navState.pendingOpen) { _, new in
            if new != nil { selectedTab = .agents }
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
