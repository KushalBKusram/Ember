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
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }

        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -3, to: now) ?? now
        let end = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now

        // Pass nil when empty: a non-nil empty array creates a predicate matching nothing
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendars.isEmpty ? nil : calendars
        )
        return store.events(matching: predicate).map(formatEvent)
    }

    func fetchReminders() async -> [String] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return [] }

        let calendars = store.calendars(for: .reminder)
        return await withCheckedContinuation { continuation in
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: calendars.isEmpty ? nil : calendars
            )
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(self.formatReminder))
            }
        }
    }

    // MARK: - Private

    private func formatEvent(_ event: EKEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = event.isAllDay ? .none : .short

        var desc = event.isAllDay
            ? "\(event.title ?? "Untitled event") all day on \(formatter.string(from: event.startDate))"
            : "\(event.title ?? "Untitled event") on \(formatter.string(from: event.startDate))"

        if let loc = event.location, !loc.isEmpty { desc += " at \(loc)" }
        if let notes = event.notes, !notes.isEmpty { desc += ". \(notes)" }
        return desc
    }

    private func formatReminder(_ reminder: EKReminder) -> String {
        var desc = reminder.title ?? "Untitled reminder"
        if let components = reminder.dueDateComponents,
           let date = Calendar.current.date(from: components) {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .short
            desc += " due \(formatter.string(from: date))"
        }
        if let notes = reminder.notes, !notes.isEmpty { desc += ". \(notes)" }
        return desc
    }
}
