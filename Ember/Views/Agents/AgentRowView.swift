import SwiftUI

struct AgentRowView: View {
    let agent: Agent
    @State private var jobCount = 0

    private let db = AppDatabase.shared

    var body: some View {
        HStack(spacing: 14) {
            Text(agent.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(agent.agentDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if jobCount > 0 {
                        Label("\(jobCount) job\(jobCount == 1 ? "" : "s")", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let lastRun = agent.lastRunAt {
                        Label(lastRun.formatted(.relative(presentation: .named)), systemImage: "play.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .task { await loadJobCount() }
    }

    private func loadJobCount() async {
        jobCount = (try? db.jobs(for: agent.id).count) ?? 0
    }
}
