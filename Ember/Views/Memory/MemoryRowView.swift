import SwiftUI

struct MemoryRowView: View {
    let memory: Memory
    let showCategoryChip: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(memory.content)
                    .font(.body)
                    .foregroundStyle(memory.isEnabled ? .primary : .secondary)
                    .strikethrough(!memory.isEnabled)

                HStack(spacing: 6) {
                    if showCategoryChip {
                        categoryChip
                    }
                    if let days = daysUntilExpiry {
                        expiryChip(days: days)
                    }
                }
            }

            Spacer(minLength: 8)

            Button(action: onToggle) {
                Image(systemName: memory.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(memory.isEnabled ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .opacity(memory.isEnabled ? 1 : 0.55)
    }

    // MARK: - Category chip

    private var categoryChip: some View {
        Label(memory.category.label, systemImage: memory.category.icon)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(memory.category.chipColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(memory.category.chipColor.opacity(0.12), in: Capsule())
    }

    // MARK: - Expiry chip (episodic only)

    private func expiryChip(days: Int) -> some View {
        let urgent = days <= 7
        return Label(
            days == 0 ? "Expires today" : "Expires in \(days)d",
            systemImage: "clock"
        )
        .font(.caption2)
        .fontWeight(.medium)
        .foregroundStyle(urgent ? .orange : .secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((urgent ? Color.orange : Color.secondary).opacity(0.1), in: Capsule())
    }

    // MARK: - Helpers

    private var daysUntilExpiry: Int? {
        guard let expiresAt = memory.expiresAt else { return nil }
        let days = Calendar.current.dateComponents([.day], from: .now, to: expiresAt).day ?? 0
        return max(days, 0)
    }
}
