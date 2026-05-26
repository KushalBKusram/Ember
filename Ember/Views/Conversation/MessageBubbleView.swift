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

            if isUser {
                Button { onEdit?() } label: {
                    Label("Edit", systemImage: "pencil")
                }
            } else if !isStreaming {
                Button { onRegenerate?() } label: {
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
            case .failure:
                Label("Image unavailable", systemImage: "photo")
                    .foregroundStyle(.secondary)
                    .padding()
            default:
                ProgressView()
                    .frame(width: 120, height: 120)
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
