import SwiftUI

struct ConversationListView: View {
    @State private var viewModel = ConversationListViewModel()
    @State private var selectedConversation: Conversation?
    @State private var renameTarget: Conversation?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.filteredConversations.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .navigationTitle("Ember")
            .searchable(text: $viewModel.searchQuery, prompt: "Search conversations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        startNewConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationDestination(item: $selectedConversation) { conversation in
                ConversationView(conversation: conversation)
            }
            .sheet(item: $renameTarget) { conversation in
                renameSheet(for: conversation)
            }
        }
        .onAppear { viewModel.startObserving() }
        .onDisappear { viewModel.stopObserving() }
    }

    // MARK: - Subviews

    private var conversationList: some View {
        List {
            ForEach(viewModel.filteredConversations) { conversation in
                ConversationRowView(
                    conversation: conversation,
                    preview: viewModel.lastMessagePreview[conversation.id]
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.tap()
                    selectedConversation = conversation
                }
                .contextMenu {
                    Button {
                        try? viewModel.togglePin(conversation)
                    } label: {
                        Label(
                            conversation.isPinned ? "Unpin" : "Pin",
                            systemImage: conversation.isPinned ? "pin.slash" : "pin"
                        )
                    }
                    Button {
                        renameText = conversation.title
                        renameTarget = conversation
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        try? viewModel.delete(conversation)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        try? viewModel.togglePin(conversation)
                    } label: {
                        Label(
                            conversation.isPinned ? "Unpin" : "Pin",
                            systemImage: conversation.isPinned ? "pin.slash" : "pin"
                        )
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Haptics.warning()
                        try? viewModel.delete(conversation)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Conversations", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Tap the compose button to start a private conversation.")
        } actions: {
            Button("Start Chatting") {
                startNewConversation()
            }
            .buttonStyle(.bordered)
        }
    }

    private func renameSheet(for conversation: Conversation) -> some View {
        NavigationStack {
            Form {
                TextField("Conversation title", text: $renameText)
                    .submitLabel(.done)
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        try? viewModel.rename(conversation, to: renameText.trimmingCharacters(in: .whitespacesAndNewlines))
                        renameTarget = nil
                    }
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { renameTarget = nil }
                }
            }
        }
        .presentationDetents([.fraction(0.25)])
    }

    // MARK: - Actions

    private func startNewConversation() {
        guard let conversation = try? viewModel.createConversation() else { return }
        Haptics.tap()
        selectedConversation = conversation
    }
}

#Preview {
    ConversationListView()
}
