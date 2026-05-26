import SwiftUI
import ImagePlayground

struct ConversationView: View {
    let conversation: Conversation
    @State private var viewModel: ConversationViewModel
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    // Image generation
    @State private var showingImagePlayground = false

    // Edit
    @State private var editingMessage: Message?
    @State private var editText = ""

    init(conversation: Conversation) {
        self.conversation = conversation
        _viewModel = State(initialValue: ConversationViewModel(conversation: conversation))
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            memoryIndicator
            sourceAttributionBar
            InputBarView(
                text: $inputText,
                isStreaming: viewModel.isStreaming,
                onSend: sendMessage,
                onCancel: viewModel.cancelStreaming,
                onGenerateImage: { showingImagePlayground = true }
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.2), value: viewModel.ragSources.isEmpty)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.isIncognito.toggle()
                } label: {
                    Image(systemName: viewModel.isIncognito ? "theatermasks.fill" : "theatermasks")
                        .foregroundStyle(viewModel.isIncognito ? Color.accentColor : .secondary)
                }
                .help(viewModel.isIncognito ? "Incognito on — memory paused" : "Incognito off — memory active")
            }
        }
        .onAppear { viewModel.startObserving() }
        .onDisappear { viewModel.stopObserving() }
        .imagePlaygroundSheet(isPresented: $showingImagePlayground) { url in
            viewModel.saveGeneratedImage(from: url)
        }
        .sheet(item: $editingMessage) { message in
            editSheet(for: message)
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(
                            message: message,
                            isStreaming: false,
                            onRegenerate: { viewModel.regenerate(message) },
                            onEdit: {
                                editText = message.content
                                editingMessage = message
                            }
                        )
                        .id(message.id)
                    }

                    if viewModel.isStreaming {
                        streamingBubble.id("streaming")
                    }

                    if let error = viewModel.error {
                        errorBanner(error)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { scrollToBottom(proxy: proxy) }
            .onChange(of: viewModel.streamingContent) { scrollToBottom(proxy: proxy) }
            .onChange(of: viewModel.ragSources.count) { scrollToBottom(proxy: proxy) }
        }
    }

    // MARK: - Memory indicator

    @ViewBuilder
    private var memoryIndicator: some View {
        if viewModel.isStreaming && viewModel.injectedMemoryCount > 0 {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                    .font(.caption2)
                Text("\(viewModel.injectedMemoryCount) memor\(viewModel.injectedMemoryCount == 1 ? "y" : "ies") active")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 4)
            .transition(.opacity.combined(with: .scale))
        }
    }

    // MARK: - Source attribution

    @ViewBuilder
    private var sourceAttributionBar: some View {
        if !viewModel.ragSources.isEmpty && !viewModel.isStreaming {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let uniqueSources = Array(
                        Dictionary(grouping: viewModel.ragSources, by: \.sourceTitle).keys.sorted()
                    )
                    ForEach(uniqueSources, id: \.self) { title in
                        if let source = viewModel.ragSources.first(where: { $0.sourceTitle == title }) {
                            Label(title, systemImage: source.sourceIcon)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 4)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Subviews

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

    // MARK: - Edit sheet

    private func editSheet(for message: Message) -> some View {
        NavigationStack {
            TextEditor(text: $editText)
                .padding()
                .navigationTitle("Edit Message")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            let content = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !content.isEmpty else { return }
                            editingMessage = nil
                            viewModel.submitEdit(message: message, newContent: content)
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingMessage = nil }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.regularMaterial)
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
