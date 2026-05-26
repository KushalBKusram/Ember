import SwiftUI

struct MemoryView: View {
    @State private var viewModel = MemoryViewModel()
    @AppStorage("memoryEnabled") private var memoryEnabled = true
    @State private var showingClearConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.memories.isEmpty {
                    emptyState
                } else {
                    memoryList
                }
            }
            .navigationTitle("Memory")
            .searchable(text: $viewModel.searchQuery, prompt: "Search memories")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle(isOn: $memoryEnabled) {
                            Label("Memory Learning", systemImage: "brain.head.profile")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showingClearConfirm = true
                        } label: {
                            Label("Clear All Memories", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog(
                "Clear all memories?",
                isPresented: $showingClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    viewModel.clearAll()
                }
            } message: {
                Text("This permanently deletes everything Ember has learned about you.")
            }
        }
        .onAppear { viewModel.startObserving() }
        .onDisappear { viewModel.stopObserving() }
    }

    // MARK: - Memory list

    private var memoryList: some View {
        List {
            if !memoryEnabled {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(.secondary)
                        Text("Memory learning is paused. Ember won't learn from new conversations.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            ForEach(viewModel.memoriesByCategory, id: \.0) { category, items in
                Section {
                    ForEach(items) { memory in
                        MemoryRowView(memory: memory) {
                            viewModel.toggle(memory)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.delete(memory)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Label(category.label, systemImage: category.icon)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Memories Yet", systemImage: "brain.head.profile")
        } description: {
            Text("As you chat with Ember, it will learn facts about you and store them here — privately, on this device.")
        }
    }
}

#Preview {
    MemoryView()
}
