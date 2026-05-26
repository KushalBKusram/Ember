import SwiftUI

struct MemoryStubView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Memory", systemImage: "brain.head.profile")
            } description: {
                Text("Ember will automatically learn about you from your conversations.\nMemory engine coming in the next milestone.")
            }
            .navigationTitle("Memory")
        }
    }
}
