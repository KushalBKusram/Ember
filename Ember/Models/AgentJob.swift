import Foundation
import GRDB

struct AgentJob: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: UUID
    var agentId: UUID
    var name: String
    var prompt: String
    var scheduleHour: Int            // 0–23  (used only when intervalMinutes is nil)
    var scheduleMinute: Int          // 0–59  (used only when intervalMinutes is nil)
    /// Comma-separated weekday numbers (1 = Sun … 7 = Sat).
    /// Empty string means every day. Only used when intervalMinutes is nil.
    var scheduleDaysRaw: String
    /// When non-nil the job fires on a repeating interval instead of a
    /// calendar time. Minimum value enforced by the UI/factory is 15 minutes.
    var intervalMinutes: Int?
    var isEnabled: Bool
    var createdAt: Date
    var lastRunAt: Date?

    static let databaseTableName = "agent_job"

    // MARK: - Derived schedule properties

    var isIntervalBased: Bool { intervalMinutes != nil }

    /// Parsed weekday set. Empty means every day. Ignored for interval jobs.
    var scheduleDays: Set<Int> {
        Set(scheduleDaysRaw.split(separator: ",").compactMap { Int($0) })
    }

    /// Weekdays that should receive a calendar notification trigger.
    /// Only relevant when `isIntervalBased` is false.
    var effectiveWeekdays: [Int] {
        let days = scheduleDays
        return days.isEmpty ? Array(1...7) : days.sorted()
    }

    var scheduleTimeString: String {
        let period = scheduleHour >= 12 ? "PM" : "AM"
        let h = scheduleHour == 0 ? 12 : (scheduleHour > 12 ? scheduleHour - 12 : scheduleHour)
        return String(format: "%d:%02d %@", h, scheduleMinute, period)
    }

    /// True when the job's scheduled time has arrived and it has not yet run for this period.
    /// Used by `BackgroundJobService` to determine which jobs to execute during a BGAppRefreshTask.
    var isDue: Bool {
        if let mins = intervalMinutes {
            // Interval job: due if never run, or enough time has elapsed since the last run.
            guard let last = lastRunAt else { return true }
            return Date().timeIntervalSince(last) >= TimeInterval(max(15, mins) * 60)
        } else {
            // Time-based: due when today is a scheduled weekday, the clock time has passed,
            // and we haven't already run since that time today.
            let cal     = Calendar.current
            let now     = Date()
            let weekday = cal.component(.weekday, from: now)
            guard effectiveWeekdays.contains(weekday) else { return false }
            var comps   = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour   = scheduleHour
            comps.minute = scheduleMinute
            comps.second = 0
            guard let todayRun = cal.date(from: comps), now >= todayRun else { return false }
            guard let last = lastRunAt else { return true }
            return last < todayRun
        }
    }

    /// The earliest date at which this job should next fire.
    /// Passed as `BGAppRefreshTaskRequest.earliestBeginDate` so the system knows
    /// when to wake the app — it will not wake the app before this date.
    var nextFireDate: Date {
        let cal = Calendar.current
        let now = Date()

        if let mins = intervalMinutes {
            guard let last = lastRunAt else { return now }
            let candidate = last.addingTimeInterval(TimeInterval(max(15, mins) * 60))
            return candidate > now ? candidate : now
        } else {
            // Find the soonest upcoming scheduled weekday+time occurrence.
            // Search from 1 minute before now so a job due right now is found as "today"
            // rather than next week.
            var comps        = DateComponents()
            comps.hour       = scheduleHour
            comps.minute     = scheduleMinute
            comps.second     = 0
            let searchFrom   = Date(timeIntervalSinceNow: -60)
            var soonest: Date?
            for wd in effectiveWeekdays {
                comps.weekday = wd
                if let d = cal.nextDate(
                    after: searchFrom,
                    matching: comps,
                    matchingPolicy: .nextTimePreservingSmallerComponents
                ), soonest == nil || d < soonest! {
                    soonest = d
                }
            }
            return soonest ?? now.addingTimeInterval(24 * 3600)
        }
    }

    var scheduleDescription: String {
        if let mins = intervalMinutes {
            return Self.intervalLabel(mins)
        }
        let days = scheduleDays
        if days.isEmpty { return "Every day at \(scheduleTimeString)" }
        let names = days.sorted().map(Self.weekdayAbbrev).joined(separator: ", ")
        return "\(names) at \(scheduleTimeString)"
    }

    static func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "Every \(minutes) min" }
        let hours = minutes / 60
        return hours == 1 ? "Every hour" : "Every \(hours) hours"
    }

    /// Stable notification identifier for interval-based jobs.
    var intervalNotificationId: String { "ember-job-\(id)-interval" }

    /// Base identifier for calendar-based jobs. Individual day notifications
    /// are keyed `"\(notificationBase)-day-\(weekday)"`.
    var notificationBase: String { "ember-job-\(id)" }

    // MARK: - Factory — time-based

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
            intervalMinutes: nil,
            isEnabled: true,
            createdAt: Date(),
            lastRunAt: nil
        )
    }

    // MARK: - Factory — interval-based

    static func makeInterval(
        agentId: UUID,
        name: String,
        prompt: String,
        intervalMinutes: Int
    ) -> AgentJob {
        let clamped = max(15, intervalMinutes)   // enforce minimum
        return AgentJob(
            id: UUID(),
            agentId: agentId,
            name: name,
            prompt: prompt,
            scheduleHour: 9,        // unused
            scheduleMinute: 0,      // unused
            scheduleDaysRaw: "",    // unused
            intervalMinutes: clamped,
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
