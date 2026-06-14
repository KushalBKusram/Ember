import SwiftUI

struct MessageBubbleView: View {
    let message: Message
    var isStreaming = false
    var onRegenerate: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

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
        .contextMenu {
            if !message.content.isEmpty {
                Button {
                    UIPasteboard.general.string = message.content
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }

            // Only offer actions a handler was provided for — agent
            // conversations pass neither, so they get no dead menu items.
            if isUser, let onEdit {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
            } else if !isUser, !isStreaming, let onRegenerate {
                Button(action: onRegenerate) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: - Bubble content

    @ViewBuilder
    private var bubbleContent: some View {
        if let path = message.attachmentPath {
            imageContent(path: path)
        } else {
            textContent
        }
    }

    private var textContent: some View {
        MarkdownText(text: message.content, foreground: isUser ? .white : .primary)
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if isUser {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.accentColor)
                } else {
                    Color.clear
                        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .overlay {
                if isStreaming {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                }
            }
    }

    private func imageContent(path: String) -> some View {
        let url = ConversationViewModel.imagesDirectory.appendingPathComponent(path)
        return AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: 260)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            case .failure:
                Label("Image unavailable", systemImage: "photo")
                    .foregroundStyle(.secondary)
                    .padding()
            default:
                // Placeholder sized to match typical square generated images.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 200, height: 200)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .animation(.easeOut(duration: 0.3), value: url)
    }

    private var timestamp: some View {
        Text(message.createdAt.formatted(date: .omitted, time: .shortened))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
    }
}
