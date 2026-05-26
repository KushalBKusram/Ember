import Foundation
import EventKit

actor CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()

    func requestCalendarAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    func requestRemindersAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    func fetchEvents() -> [String] {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -3, to: now) ?? now
        let end = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).map(formatEvent)
    }

    func fetchReminders() async -> [String] {
        let calendars = store.calendars(for: .reminder)
        return await withCheckedContinuation { continuation in
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: calendars
            )
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(self.formatReminder))
            }
        }
    }

    // MARK: - Private

    private func formatEvent(_ event: EKEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = event.isAllDay ? .none : .short
        var parts = [event.title ?? "Untitled Event"]
        parts.append("Date: \(formatter.string(from: event.startDate))")
        if let loc = event.location, !loc.isEmpty { parts.append("Location: \(loc)") }
        if let notes = event.notes, !notes.isEmpty { parts.append("Notes: \(notes)") }
        return parts.joined(separator: " | ")
    }

    private func formatReminder(_ reminder: EKReminder) -> String {
        var parts = [reminder.title ?? "Untitled Reminder"]
        if let components = reminder.dueDateComponents,
           let date = Calendar.current.date(from: components) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            parts.append("Due: \(formatter.string(from: date))")
        }
        if let notes = reminder.notes, !notes.isEmpty { parts.append("Notes: \(notes)") }
        return parts.joined(separator: " | ")
    }
}
