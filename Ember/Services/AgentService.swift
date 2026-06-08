import Foundation
import UserNotifications

actor AgentService {
    static let shared = AgentService()

    private let db = AppDatabase.shared

    // MARK: - Agent CRUD

    func createAgent(_ agent: inout Agent) throws {
        // Create the backing conversation so the persistent thread exists immediately.
        var conversation = Conversation(id: agent.conversationId, title: agent.name)
        try db.dbPool.write { db in
            try conversation.save(db)
            try agent.save(db)
        }
    }

    func updateAgent(_ agent: Agent) throws {
        // Sync conversation title if name changed.
        try db.dbPool.write { db in
            try agent.save(db)
            try db.execute(
                sql: "UPDATE conversation SET title = ? WHERE id = ?",
                arguments: [agent.name, agent.conversationId]
            )
        }
    }

    func deleteAgent(_ agent: Agent) throws {
        // Cancel all job notifications before deletion.
        let jobs = (try? db.jobs(for: agent.id)) ?? []
        jobs.forEach { cancelNotifications(for: $0) }
        try db.deleteAgent(agent)
        // Conversation and messages are cascade-deleted by the FK on conversation.
        // Agent FK on agent_job also cascade-deletes jobs.
    }

    // MARK: - Job CRUD

    func saveJob(_ job: inout AgentJob) async throws {
        cancelNotifications(for: job)
        try db.saveJob(&job)
        if job.isEnabled {
            await scheduleNotifications(for: job)
        }
    }

    func deleteJob(_ job: AgentJob) throws {
        cancelNotifications(for: job)
        try db.deleteJob(job)
    }

    func toggleJob(_ job: AgentJob) async throws {
        var updated = job
        updated.isEnabled = !updated.isEnabled
        cancelNotifications(for: job)
        try db.saveJob(&updated)
        if updated.isEnabled {
            await scheduleNotifications(for: updated)
        }
    }

    func touchJobRun(_ jobId: UUID, agentId: UUID) throws {
        try db.touchJobRunDate(jobId)
        try db.touchAgentRunDate(agentId)
    }

    // MARK: - Notification scheduling

    /// Requests permission (if not yet granted) then schedules one
    /// `UNCalendarNotificationTrigger` per effective weekday for the job.
    func scheduleNotifications(for job: AgentJob) async {
        let center = UNUserNotificationCenter.current()

        let settings = await center.notificationSettings()
        if settings.authorizationStatus != .authorized {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
        }

        for weekday in job.effectiveWeekdays {
            let content = UNMutableNotificationContent()
            content.title = job.name
            content.body = "Your scheduled job is ready to run."
            content.sound = .default
            content.userInfo = [
                "agentId": job.agentId.uuidString,
                "jobId":   job.id.uuidString
            ]

            var components = DateComponents()
            components.hour    = job.scheduleHour
            components.minute  = job.scheduleMinute
            components.weekday = weekday

            let trigger    = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let identifier = "\(job.notificationBase)-day-\(weekday)"
            let request    = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func cancelNotifications(for job: AgentJob) {
        let ids = (1...7).map { "\(job.notificationBase)-day-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Re-schedules all enabled job notifications — called on launch to repair
    /// any notifications that were cleared by an OS update or app reinstall.
    func rescheduleAllIfNeeded() async throws {
        let jobs = try db.allEnabledJobs()
        for job in jobs {
            await scheduleNotifications(for: job)
        }
    }
}
