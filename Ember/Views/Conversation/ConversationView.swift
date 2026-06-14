import SwiftUI
import ImagePlayground

struct ConversationView: View {
    @State private var viewModel: ConversationViewModel
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    // Image generation
    @State private var showingImagePlayground = false
    /// True from the moment the wand is tapped until the sheet fully dismisses.
    /// Drives the loading spinner on the wand button so the user has instant feedback.
    @State private var isImagePlaygroundLoading = false

    // Edit
    @State private var editingMessage: Message?
    @State private var editText = ""

    #if DEBUG
    @State private var debugLogSaved = false
    #endif

    init(conversation: Conversation) {
        _viewModel = State(initialValue: ConversationViewModel(conversation: conversation))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.isModelAvailable {
                modelUnavailableBanner
            }
            messageList
            memoryIndicator
            sourceAttributionBar
            InputBarView(
                text: $inputText,
                isStreaming: viewModel.isStreaming,
                onSend: sendMessage,
                onCancel: viewModel.cancelStreaming,
                onGenerateImage: {
                    isImagePlaygroundLoading = true
                    showingImagePlayground = true
                },
                isImagePlaygroundLoading: isImagePlaygroundLoading
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
            .disabled(!viewModel.isModelAvailable)
        }
        .navigationTitle(viewModel.conversation.title)
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
            #if DEBUG
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    saveDebugLog()
                } label: {
                    Label("Save Debug Log", systemImage: "ladybug.fill")
                }
            }
            #endif
        }
        .onAppear { viewModel.startObserving() }
        .onDisappear {
            viewModel.stopObserving()
        }
        .imagePlaygroundSheet(isPresented: $showingImagePlayground) { url in
            viewModel.saveGeneratedImage(from: url)
        }
        .onChange(of: showingImagePlayground) { _, isShowing in
            // Clear the loading state as soon as the sheet dismisses (whether
            // the user accepted an image or cancelled).
            if !isShowing { isImagePlaygroundLoading = false }
        }
        .sheet(item: $editingMessage) { message in
            editSheet(for: message)
        }
        #if DEBUG
        .alert("Debug Log Saved", isPresented: $debugLogSaved) {
            Button("OK") {}
        } message: {
            Text("ember_debug_latest.txt written to the app's Documents folder. Claude can read it directly.")
        }
        #endif
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty && !viewModel.isStreaming {
                        suggestionChips
                    }

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

                    if viewModel.wasCancelled && !viewModel.isStreaming {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.circle.fill")
                                .foregroundStyle(.secondary)
                            Text("Stopped")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
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
            .onChange(of: viewModel.displayContent) { scrollToBottom(proxy: proxy) }
            .onChange(of: viewModel.ragSources.count) { scrollToBottom(proxy: proxy) }
        }
    }

    // MARK: - Suggestion chips

    @AppStorage("calendarEnabled") private var calendarEnabled = false
    @AppStorage("remindersEnabled") private var remindersEnabled = false

    private var suggestionPrompts: [String] {
        var prompts: [String] = []
        if calendarEnabled { prompts.append("What's on my schedule today?") }
        if remindersEnabled { prompts.append("What do I need to get done?") }
        prompts.append("Help me think through something")
        prompts.append("Summarize what you know about me")
        return prompts
    }

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try asking…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            ForEach(suggestionPrompts, id: \.self) { prompt in
                Button {
                    Haptics.tap()
                    inputText = prompt
                    sendMessage()
                } label: {
                    HStack {
                        Text(prompt)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Model unavailable banner

    private var modelUnavailableBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Intelligence is off").font(.subheadline).fontWeight(.semibold)
                Text("Enable it in Settings → Apple Intelligence & Siri to chat with Ember.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .glassEffect(in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
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
            .glassEffect(in: Capsule())
            .padding(.bottom, 4)
            .transition(.opacity.combined(with: .scale))
        }
    }

    // MARK: - Source attribution

    @ViewBuilder
    private var sourceAttributionBar: some View {
        if !viewModel.ragSources.isEmpty {
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
                                .glassEffect(in: Capsule())
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
                conversationId: viewModel.conversation.id,
                role: .assistant,
                content: viewModel.displayContent.isEmpty ? "▏" : viewModel.displayContent
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
        .glassEffect(in: RoundedRectangle(cornerRadius: 10))
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
        Haptics.tap()
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

    // MARK: - Debug export (DEBUG builds only)

    #if DEBUG
    /// Writes a plain-text dump of the full conversation + injected context to
    /// `Documents/ember_debug_latest.txt` in the simulator sandbox.
    /// Claude can read it directly without any copy-pasting:
    ///   find ~/Library/Developer/CoreSimulator/Devices \
    ///        -name "ember_debug_latest.txt" | head -1
    private func saveDebugLog() {
        let text = buildDebugExportText()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = docs.appendingPathComponent("ember_debug_latest.txt")
        try? text.write(to: file, atomically: true, encoding: .utf8)
        debugLogSaved = true
    }

    private func buildDebugExportText() -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        let divider = String(repeating: "─", count: 52)

        var lines: [String] = [
            "EMBER DEBUG EXPORT",
            "Conversation: \"\(viewModel.conversation.title)\"",
            "Exported: \(df.string(from: Date()))",
            divider,
            "",
            "MESSAGES",
        ]

        for msg in viewModel.messages {
            let speaker = msg.role == .user ? "You" : "Ember"
            let body    = msg.attachmentPath != nil ? "[Image]" : msg.content
            lines.append("")
            lines.append("[\(speaker)] \(body)")
        }

        if !viewModel.lastDebugContext.isEmpty {
            lines.append("")
            lines.append(divider)
            lines.append("INJECTED CONTEXT (last message)")
            lines.append("")
            lines.append(viewModel.lastDebugContext)
        }

        return lines.joined(separator: "\n")
    }
    #endif
}
