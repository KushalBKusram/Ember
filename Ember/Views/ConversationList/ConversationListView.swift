import SwiftUI

struct ConversationListView: View {
    @State private var viewModel = ConversationListViewModel()
    @State private var selectedConversation: Conversation?
    @State private var showingNewChat = false
    @State private var deletionTarget: Conversation?

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
        }
        .onAppear { viewModel.startObserving() }
        .onDisappear { viewModel.stopObserving() }
    }

    // MARK: - Subviews

    private var conversationList: some View {
        List {
            ForEach(viewModel.filteredConversations) { conversation in
                ConversationRowView(conversation: conversation)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedConversation = conversation
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
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

    // MARK: - Actions

    private func startNewConversation() {
        guard let conversation = try? viewModel.createConversation() else { return }
        selectedConversation = conversation
    }
}

#Preview {
    ConversationListView()
}
