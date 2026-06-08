import SwiftUI

struct AgentConversationView: View {
    @State private var viewModel: AgentConversationViewModel
    @State private var inputText   = ""
    @FocusState private var inputFocused: Bool
    @State private var showProfile = false

    /// Job ID passed in when launched from a notification tap.
    let triggerJobId: UUID?

    private let db = AppDatabase.shared

    init(agent: Agent, triggerJobId: UUID? = nil) {
        _viewModel   = State(initialValue: AgentConversationViewModel(agent: agent))
        self.triggerJobId = triggerJobId
    }

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.isModelAvailable {
                modelUnavailableBanner
            }
            messageList
            jobCreatedBanner
            sourceAttributionBar
            InputBarView(
                text: $inputText,
                isStreaming: viewModel.isStreaming,
                onSend: sendMessage,
                onCancel: viewModel.cancelStreaming,
                onGenerateImage: { }   // image gen not available in agent context
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
            .disabled(!viewModel.isModelAvailable)
        }
        .navigationTitle(viewModel.agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showProfile = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    runNow()
                } label: {
                    Label("Run Now", systemImage: "play.circle")
                }
                .disabled(viewModel.isStreaming)
            }
        }
        .navigationDestination(isPresented: $showProfile) {
            AgentProfileView(agent: viewModel.agent)
        }
        .onAppear {
            viewModel.startObserving()
            fireJobTriggerIfNeeded()
        }
        .onDisappear { viewModel.stopObserving() }
        .onChange(of: viewModel.newJobBanner) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(6))
                withAnimation { viewModel.newJobBanner = nil }
            }
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty && !viewModel.isStreaming {
                        agentWelcome
                    }
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(
                            message: message,
                            isStreaming: false
                        )
                        .id(message.id)
                    }
                    if viewModel.isStreaming {
                        MessageBubbleView(
                            message: Message(
                                conversationId: viewModel.conversationId,
                                role: .assistant,
                                content: viewModel.streamingContent.isEmpty
                                    ? "▋" : viewModel.streamingContent
                            ),
                            isStreaming: true
                        )
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
            .onChange(of: viewModel.messages.count) { scrollToBottom(proxy: proxy) }
            .onChange(of: viewModel.streamingContent)  { scrollToBottom(proxy: proxy) }
        }
    }

    // MARK: - Subviews

    private var agentWelcome: some View {
        VStack(spacing: 12) {
            Text(viewModel.agent.emoji)
                .font(.system(size: 48))
            Text(viewModel.agent.name)
                .font(.title2).fontWeight(.semibold)
            Text(viewModel.agent.agentDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 40)
    }

    private var modelUnavailableBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("Apple Intelligence is off — enable it in Settings to run this agent.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .glassEffect(in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var jobCreatedBanner: some View {
        if let banner = viewModel.newJobBanner {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.checkmark.fill")
                    .foregroundStyle(.green)
                Text(banner)
                    .font(.caption)
                    .lineLimit(2)
                Spacer()
                Button { withAnimation { viewModel.newJobBanner = nil } } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.green.opacity(0.25), lineWidth: 1))
            .padding(.horizontal)
            .padding(.bottom, 4)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var sourceAttributionBar: some View {
        if !viewModel.ragSources.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let unique = Array(
                        Dictionary(grouping: viewModel.ragSources, by: \.sourceTitle).keys.sorted()
                    )
                    ForEach(unique, id: \.self) { title in
                        if let src = viewModel.ragSources.first(where: { $0.sourceTitle == title }) {
                            Label(title, systemImage: src.sourceIcon)
                                .font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
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

    private func errorBanner(_ msg: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(msg).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(10)
        .glassEffect(in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText
        inputText = ""
        Haptics.tap()
        viewModel.send(text)
    }

    private func fireJobTriggerIfNeeded() {
        guard let jobId = triggerJobId,
              let job = try? db.jobs(for: viewModel.agent.id).first(where: { $0.id == jobId })
        else { return }
        // Small delay so the view is fully laid out before streaming starts.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            viewModel.triggerJob(job)
        }
    }

    private func runNow() {
        // "Run Now" fires the first enabled job, or if none exist prompts the agent directly.
        if let job = (try? db.jobs(for: viewModel.agent.id))?.first(where: { $0.isEnabled }) {
            Haptics.tap()
            viewModel.triggerJob(job)
        } else {
            // No jobs — open a prompt for the user to type manually.
            inputFocused = true
        }
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
