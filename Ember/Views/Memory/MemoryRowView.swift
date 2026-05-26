import SwiftUI

struct MemoryRowView: View {
    let memory: Memory
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: memory.category.icon)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(memory.content)
                    .font(.body)
                    .foregroundStyle(memory.isEnabled ? .primary : .secondary)
                    .strikethrough(!memory.isEnabled)

                HStack(spacing: 6) {
                    Text(memory.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if let expiresAt = memory.expiresAt {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("Expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Button(action: onToggle) {
                Image(systemName: memory.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(memory.isEnabled ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .opacity(memory.isEnabled ? 1 : 0.6)
    }
}
