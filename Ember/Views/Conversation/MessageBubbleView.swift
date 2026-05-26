import SwiftUI

struct MessageBubbleView: View {
    let message: Message
    var isStreaming = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                bubbleContent
                timestamp
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    private var bubbleContent: some View {
        MarkdownText(text: message.content)
            .font(.body)
            .foregroundStyle(isUser ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if isUser {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.accentColor)
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                if isStreaming {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                }
            }
    }

    private var timestamp: some View {
        Text(message.createdAt.formatted(date: .omitted, time: .shortened))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
    }
}

#Preview {
    VStack(spacing: 16) {
        MessageBubbleView(message: Message(
            conversationId: UUID(),
            role: .user,
            content: "What's the capital of France?"
        ))
        MessageBubbleView(message: Message(
            conversationId: UUID(),
            role: .assistant,
            content: "The capital of France is **Paris**. It's also the country's largest city."
        ))
    }
    .padding()
}
