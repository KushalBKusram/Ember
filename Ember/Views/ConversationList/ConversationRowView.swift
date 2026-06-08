import SwiftUI

struct ConversationRowView: View {
    let conversation: Conversation
    let preview: String?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "flame.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(conversation.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer()

                    Text(conversation.updatedAt.relativeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(preview ?? "Tap to continue")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
