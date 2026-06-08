import SwiftUI

struct MemoryView: View {
    @State private var viewModel = MemoryViewModel()
    @AppStorage("memoryEnabled") private var memoryEnabled = true
    @AppStorage("userProfile") private var userProfile = ""
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
                Button("Clear All", role: .destructive) { viewModel.clearAll() }
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

            // ── Profile card ───────────────────────────────────────────────
            Section {
                profileCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            }

            // ── Memory paused notice ───────────────────────────────────────
            if !memoryEnabled {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "pause.circle")
                            .foregroundStyle(.secondary)
                        Text("Memory learning is paused. Ember won't learn from new conversations.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            // ── Saved: Preferences + Projects + Relationships ──────────────
            if !savedMemories.isEmpty {
                Section {
                    ForEach(savedMemories) { memory in
                        MemoryRowView(memory: memory, showCategoryChip: true) {
                            viewModel.toggle(memory)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { viewModel.delete(memory) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("What Ember knows")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                } footer: {
                    Text("Stored permanently and referenced when relevant to your conversations.")
                }
            }

            // ── Recent: Episodic only ──────────────────────────────────────
            if !recentMemories.isEmpty {
                Section {
                    ForEach(recentMemories) { memory in
                        MemoryRowView(memory: memory, showCategoryChip: false) {
                            viewModel.toggle(memory)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { viewModel.delete(memory) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Recent")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                } footer: {
                    Text("Temporary observations — each expires after 30 days.")
                }
            }
        }
        .listSectionSpacing(.compact)
    }

    // MARK: - Profile card

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Your Profile", systemImage: "person.text.rectangle")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.regenerateProfile()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .disabled(viewModel.isRegeneratingProfile || viewModel.memories.isEmpty)
            }

            Divider()

            if viewModel.isRegeneratingProfile {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Rebuilding…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if userProfile.isEmpty {
                Text("Profile will appear here once Ember has learned enough about you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(userProfile)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            Text("Ember uses this as a starting point in every conversation, alongside the individual facts below.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    // MARK: - Grouped memory helpers (delegated to ViewModel)

    private var savedMemories: [Memory] { viewModel.savedMemories }
    private var recentMemories: [Memory] { viewModel.recentMemories }

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
