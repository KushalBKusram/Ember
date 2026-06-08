import Foundation
import GRDB

struct AgentJob: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: UUID
    var agentId: UUID
    var name: String
    var prompt: String
    var scheduleHour: Int            // 0–23
    var scheduleMinute: Int          // 0–59
    /// Comma-separated weekday numbers (1 = Sun … 7 = Sat).
    /// Empty string means every day.
    var scheduleDaysRaw: String
    var isEnabled: Bool
    var createdAt: Date
    var lastRunAt: Date?

    static let databaseTableName = "agent_job"

    // MARK: - Derived schedule properties

    /// Parsed weekday set. Empty means every day.
    var scheduleDays: Set<Int> {
        Set(scheduleDaysRaw.split(separator: ",").compactMap { Int($0) })
    }

    /// Weekdays that should actually receive a notification trigger.
    var effectiveWeekdays: [Int] {
        let days = scheduleDays
        return days.isEmpty ? Array(1...7) : days.sorted()
    }

    var scheduleTimeString: String {
        let period = scheduleHour >= 12 ? "PM" : "AM"
        let h = scheduleHour == 0 ? 12 : (scheduleHour > 12 ? scheduleHour - 12 : scheduleHour)
        return String(format: "%d:%02d %@", h, scheduleMinute, period)
    }

    var scheduleDescription: String {
        let days = scheduleDays
        if days.isEmpty { return "Every day at \(scheduleTimeString)" }
        let names = days.sorted().map(Self.weekdayAbbrev).joined(separator: ", ")
        return "\(names) at \(scheduleTimeString)"
    }

    /// Base identifier — individual day notifications are keyed
    /// `"\(notificationBase)-day-\(weekday)"` so they can be
    /// cancelled/re-scheduled independently.
    var notificationBase: String { "ember-job-\(id)" }

    // MARK: - Factory

    static func make(
        agentId: UUID,
        name: String,
        prompt: String,
        hour: Int,
        minute: Int,
        days: Set<Int>
    ) -> AgentJob {
        AgentJob(
            id: UUID(),
            agentId: agentId,
            name: name,
            prompt: prompt,
            scheduleHour: hour,
            scheduleMinute: minute,
            scheduleDaysRaw: days.sorted().map(String.init).joined(separator: ","),
            isEnabled: true,
            createdAt: Date(),
            lastRunAt: nil
        )
    }

    // MARK: - Helpers

    static func weekdayAbbrev(_ day: Int) -> String {
        ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][safe: day] ?? ""
    }

    static func makeDaysRaw(_ days: Set<Int>) -> String {
        days.sorted().map(String.init).joined(separator: ",")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
