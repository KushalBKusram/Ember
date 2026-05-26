import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
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
    }
}
