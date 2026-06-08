import Foundation
import GRDB

struct Agent: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord, Sendable {
    var id: UUID
    var name: String
    var emoji: String
    var agentDescription: String
    var systemPrompt: String
    var webSearchEnabled: Bool
    var calendarEnabled: Bool
    var memoryEnabled: Bool
    var ragEnabled: Bool
    var conversationId: UUID
    var createdAt: Date
    var lastRunAt: Date?

    static let databaseTableName = "agent"

    static func make(name: String, emoji: String, description: String) -> Agent {
        Agent(
            id: UUID(),
            name: name,
            emoji: emoji,
            agentDescription: description,
            systemPrompt: Self.defaultSystemPrompt(name: name, description: description),
            webSearchEnabled: true,
            calendarEnabled: false,
            memoryEnabled: true,
            ragEnabled: false,
            conversationId: UUID(),
            createdAt: Date(),
            lastRunAt: nil
        )
    }

    static func defaultSystemPrompt(name: String, description: String) -> String {
        """
        You are \(name), a specialised AI assistant focused on \(description). \
        You are part of Ember, a private on-device AI app — everything stays on-device. \
        Be helpful, direct, and concise. Use markdown when it aids clarity. \
        When triggered by a scheduled job, complete the requested task thoroughly \
        then offer a brief follow-up insight if useful. \
        Never fabricate data — if information is unavailable, say so plainly.
        """
    }
}
