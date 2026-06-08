import Foundation
import EventKit

actor CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()

    // MARK: - Authorisation

    func requestCalendarAccess() async -> Bool {
        do { return try await store.requestFullAccessToEvents() } catch { return false }
    }

    func requestRemindersAccess() async -> Bool {
        do { return try await store.requestFullAccessToReminders() } catch { return false }
    }

    // MARK: - Unified context (calendar events + reminders)

    /// Returns a structured schedule string for injection into the LLM system prompt,
    /// or nil if:
    ///   • Neither calendar nor reminders are enabled/authorised, OR
    ///   • The query has no detectable scheduling intent (prevents Ember from
    ///     volunteering calendar data in unrelated conversations).
    ///
    /// The returned string is split into two sections so the LLM can present a
    /// clean title-only list by default and fall back to the detail section only
    /// when the user asks about a specific event.
    func fetchContext(for query: String) async -> String? {
        // Gate: only pull calendar data when the user is actually asking about
        // their schedule. "My name is Kushal" must not produce a calendar dump.
        guard hasScheduleIntent(query) else { return nil }

        var sections: [String] = []

        if AppSettings.calendarEnabled {
            let (start, end, label) = detectDateWindow(from: query)
            let events = fetchSortedEvents(from: start, to: end)
            if events.isEmpty {
                sections.append("Events (\(label)): none scheduled.")
            } else {
                let titles  = events.map { "• \($0.title ?? "Untitled")" }.joined(separator: "\n")
                let details = events.map { detailLine($0) }.joined(separator: "\n")
                sections.append("""
                    Events (\(label)):
                    \(titles)

                    Event details (times/locations — reference only when user asks about a specific event):
                    \(details)
                    """)
            }
        }

        if AppSettings.remindersEnabled {
            let reminders = await fetchActiveReminders()
            if !reminders.isEmpty {
                sections.append("Incomplete reminders:\n\(reminders.joined(separator: "\n"))")
            }
        }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    // MARK: - Schedule intent detection

    /// Returns true when the query contains clear scheduling vocabulary.
    /// Keeps the threshold broad (includes time words, day names, common verbs)
    /// while reliably blocking unrelated messages like introductions or questions
    /// about code, recipes, or general knowledge.
    private func hasScheduleIntent(_ query: String) -> Bool {
        let lower = query.lowercased()
        let keywords: [String] = [
            // Time anchors
            "today", "tomorrow", "tonight", "yesterday",
            "this week", "next week", "last week", "this month",
            "monday", "tuesday", "wednesday", "thursday",
            "friday", "saturday", "sunday",
            // Scheduling nouns
            "schedule", "agenda", "calendar", "event", "reminder",
            "meeting", "appointment", "standup", "stand-up", "interview",
            "task", "deadline", "due date",
            // Common query verbs / phrases
            "when is", "what time", "am i free", "am i busy",
            "do i have", "what do i have", "what's on", "what is on",
            "any meetings", "any events", "upcoming", "coming up",
        ]
        return keywords.contains { lower.contains($0) }
    }

    // MARK: - Date window detection

    private func detectDateWindow(from query: String) -> (start: Date, end: Date, label: String) {
        let lower = query.lowercased()
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)

        // ── Explicit day references ────────────────────────────────────────────
        if lower.contains("today") || lower.contains("tonight") {
            return (todayStart, cal.date(byAdding: .day, value: 1, to: todayStart)!, "today")
        }
        if lower.contains("tomorrow") {
            let s = cal.date(byAdding: .day, value: 1, to: todayStart)!
            return (s, cal.date(byAdding: .day, value: 1, to: s)!, "tomorrow")
        }

        // ── Week references (check "next week" before "this week" / "week") ───
        if lower.contains("next week") {
            let thisWeekStart = cal.date(
                from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let s = cal.date(byAdding: .day, value: 7, to: thisWeekStart)!
            return (s, cal.date(byAdding: .day, value: 7, to: s)!, "next week")
        }
        if lower.contains("this week") || lower.contains("week") {
            let s = cal.date(
                from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return (s, cal.date(byAdding: .day, value: 7, to: s)!, "this week")
        }

        // ── Month references ───────────────────────────────────────────────────
        if lower.contains("this month") || lower.contains("month") {
            let s = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            return (s, cal.date(byAdding: .month, value: 1, to: s)!, "this month")
        }

        // ── Named weekdays ─────────────────────────────────────────────────────
        // Start search from "yesterday" so asking about today's weekday name
        // returns today rather than the same day next week.
        let weekdays = ["sunday","monday","tuesday","wednesday",
                        "thursday","friday","saturday"]
        let searchFrom = cal.date(byAdding: .day, value: -1, to: todayStart)!
        for (i, name) in weekdays.enumerated() where lower.contains(name) {
            var comps = DateComponents(); comps.weekday = i + 1
            if let target = cal.nextDate(
                after: searchFrom, matching: comps,
                matchingPolicy: .nextTimePreservingSmallerComponents
            ) {
                return (target, cal.date(byAdding: .day, value: 1, to: target)!, name.capitalized)
            }
        }

        // ── Default: just today ────────────────────────────────────────────────
        // If we've reached here the query had schedule intent (passed the gate)
        // but no explicit time window — "do I have any meetings?" → today.
        return (todayStart, cal.date(byAdding: .day, value: 1, to: todayStart)!, "today")
    }

    // MARK: - Data fetching

    private func fetchSortedEvents(from start: Date, to end: Date) -> [EKEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(
            withStart: start, end: end,
            calendars: calendars.isEmpty ? nil : calendars
        )
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
    }

    // Returns already-formatted strings so [EKReminder] (non-Sendable) never
    // crosses the actor boundary from the EventKit callback thread.
    private func fetchActiveReminders() async -> [String] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return [] }
        let calendars = store.calendars(for: .reminder)
        return await withCheckedContinuation { continuation in
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil,
                calendars: calendars.isEmpty ? nil : calendars
            )
            store.fetchReminders(matching: predicate) { reminders in
                let lines = (reminders ?? []).map { Self.formatReminder($0) }
                continuation.resume(returning: lines)
            }
        }
    }

    // MARK: - Formatting

    /// Shared formatter for event time display. `nonisolated static` so it is
    /// accessible from `detailLine` (also nonisolated) without crossing the actor.
    private nonisolated static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt
    }()

    /// Full detail line used in the "Event details" section.
    /// Format: "Title: h:mm a–h:mm a · Location · First line of notes (≤80 chars)"
    private nonisolated func detailLine(_ event: EKEvent) -> String {
        let timePart: String
        if event.isAllDay {
            timePart = "All day"
        } else {
            let fmt = Self.timeFormatter
            timePart = "\(fmt.string(from: event.startDate))–\(fmt.string(from: event.endDate))"
        }

        var parts = ["\(event.title ?? "Untitled"): \(timePart)"]
        if let loc = event.location, !loc.isEmpty { parts.append(loc) }

        // First non-empty line of notes, capped at 80 chars.
        if let notes = event.notes, !notes.isEmpty,
           let firstLine = notes.split(separator: "\n", omittingEmptySubsequences: true)
               .first.map(String.init) {
            let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed)
            }
        }
        return parts.joined(separator: " · ")
    }

    private nonisolated static let dueDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt
    }()

    /// "• Buy groceries (due Jun 9, 5:00 PM)"
    /// Static + nonisolated so it is safe to call from the EventKit callback thread.
    private static func formatReminder(_ reminder: EKReminder) -> String {
        var text = "• \(reminder.title ?? "Untitled")"
        if let comps = reminder.dueDateComponents,
           let date = Calendar.current.date(from: comps) {
            text += " (due \(dueDateFormatter.string(from: date)))"
        }
        return text
    }
}
