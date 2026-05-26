import SwiftUI

struct ConversationView: View {
    let conversation: Conversation
    @State private var viewModel: ConversationViewModel
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(conversation: Conversation) {
        self.conversation = conversation
        _viewModel = State(initialValue: ConversationViewModel(conversation: conversation))
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            InputBarView(
                text: $inputText,
                isStreaming: viewModel.isStreaming,
                onSend: sendMessage,
                onCancel: viewModel.cancelStreaming
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.startObserving() }
        .onDisappear { viewModel.stopObserving() }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }

                    if viewModel.isStreaming {
                        streamingBubble
                            .id("streaming")
                    }

                    if let error = viewModel.error {
                        errorBanner(error)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.streamingContent) {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var streamingBubble: some View {
        MessageBubbleView(
            message: Message(
                conversationId: conversation.id,
                role: .assistant,
                content: viewModel.streamingContent.isEmpty ? "▋" : viewModel.streamingContent
            ),
            isStreaming: true
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText
        inputText = ""
        viewModel.send(text)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.spring(duration: 0.3)) {
            if viewModel.isStreaming {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let last = viewModel.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
