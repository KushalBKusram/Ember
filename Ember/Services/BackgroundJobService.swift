import Foundation
import BackgroundTasks
import UserNotifications
import UIKit
import OSLog

private let logger = Logger(subsystem: "com.kushal.ember", category: "background-jobs")

/// Runs scheduled agent jobs silently in the background via `BGAppRefreshTask`.
///
/// ## Flow
/// 1. System wakes the app via `BGAppRefreshTask` at approximately the job's scheduled time.
/// 2. `handleRefreshTask(_:)` finds all enabled jobs whose `isDue` flag is true.
/// 3. Each due job runs its LLM prompt — same context gathering (RAG / calendar / web search)
///    as a normal foreground send, but using the non-streaming `LLMService.respond(to:)`.
/// 4. The assistant response is saved to the agent's conversation in the database.
/// 5. A **result-ready** notification fires immediately with a preview of the first line.
/// 6. The pending **tap-to-run** notification for that job is cancelled — it would only
///    cause a duplicate run of a job that has already completed.
/// 7. The next `BGAppRefreshTask` is re-scheduled for the soonest upcoming job fire date.
///
/// The existing `UNCalendarNotificationTrigger` / `UNTimeIntervalNotificationTrigger`
/// remain as a safety net: if the system never fires the `BGAppRefreshTask` in time
/// (low battery, no usage signal), the user still receives the original tap-to-run banner.
actor BackgroundJobService {
    static let shared = BackgroundJobService()

    /// Must match `Info.plist` → `BGTaskSchedulerPermittedIdentifiers`.
    static let taskIdentifier = "com.kushal.ember.job-runner"

    private let db  = AppDatabase.shared
    private let llm = LLMService.shared

    // MARK: - BGAppRefreshTask entry point

    /// Called from `EmberApp` when the system fires the registered BGAppRefreshTask.
    func handleRefreshTask(_ task: BGAppRefreshTask) async {
        // Re-schedule immediately so the chain continues even if this run is cut short.
        scheduleNextRefresh()

        var shouldContinue = true
        task.expirationHandler = { shouldContinue = false }

        let allJobs = (try? db.allEnabledJobs()) ?? []
        let dueJobs = allJobs.filter(\.isDue)

        logger.info("BGAppRefreshTask — \(dueJobs.count) due / \(allJobs.count) enabled")

        var completedCount = 0
        for (index, job) in dueJobs.enumerated() {
            guard shouldContinue else {
                logger.warning("Expiry reached after \(index) job(s) — will retry next refresh")
                break
            }
            do {
                try await runJob(job)
                completedCount += 1
            } catch {
                logger.error("Job '\(job.name)' failed: \(error.localizedDescription)")
            }
        }

        task.setTaskCompleted(success: completedCount > 0 || dueJobs.isEmpty)
        logger.info("BGAppRefreshTask done — \(completedCount) completed")
    }

    // MARK: - Run a single job

    private func runJob(_ job: AgentJob) async throws {
        guard let agent = try? db.agent(id: job.agentId) else {
            throw BackgroundJobError.agentNotFound(job.agentId)
        }

        logger.debug("Running job '\(job.name)' for agent '\(agent.name)'")

        // ── Persist the user-side message ──────────────────────────────────
        var userMsg = Message(
            conversationId: agent.conversationId,
            role: .user,
            content: job.prompt
        )
        try db.save(&userMsg)
        try db.touchConversation(id: agent.conversationId)

        // ── Gather context in parallel (mirrors AgentConversationViewModel) ─
        var userProfile      = ""
        var relevantMemories = [String]()
        if agent.memoryEnabled {
            userProfile      = AppSettings.userProfile
            let mems         = await MemoryService.shared.retrieveRelevantIfEnabled(for: job.prompt)
            relevantMemories = mems.map(\.content)
        }

        // Drop the user message just saved above — it goes out as the prompt
        // itself, so leaving it in history would duplicate it.
        var history = (try? db.messages(for: agent.conversationId)) ?? []
        if let last = history.last, last.role == .user, last.content == job.prompt {
            history.removeLast()
        }

        async let ragFetch      = agent.ragEnabled
            ? RAGService.shared.retrieve(for: job.prompt, webURLs: [])
            : []
        async let scheduleFetch = agent.calendarEnabled
            ? CalendarService.shared.fetchContext(for: job.prompt)
            : nil
        async let searchFetch   = agent.webSearchEnabled
            ? WebSearchService.shared.searchWithIntelligence(
                for: job.prompt,
                agentContext: agent.agentDescription
              )
            : []

        var ragContext       = (try? await ragFetch) ?? []
        let scheduleContext  = await scheduleFetch ?? ""
        let webResults       = await searchFetch
        ragContext.append(contentsOf: webResults)

        // ── Non-streaming LLM call ─────────────────────────────────────────
        let responseText = try await llm.respond(
            to: job.prompt,
            history: history
                .filter { $0.role == .user || $0.role == .assistant }
                .filter { $0.attachmentPath == nil },
            userProfile: userProfile,
            ragContext: ragContext,
            scheduleContext: scheduleContext,
            relevantMemories: relevantMemories,
            systemPromptOverride: agent.systemPrompt
        )

        // ── Persist the assistant response ────────────────────────────────
        var assistantMsg = Message(
            conversationId: agent.conversationId,
            role: .assistant,
            content: responseText
        )
        try db.save(&assistantMsg)
        try db.touchConversation(id: agent.conversationId)

        // ── Mark the job and agent as run ─────────────────────────────────
        try db.touchJobAndAgentRunDate(jobId: job.id, agentId: job.agentId)

        // ── Swap tap-to-run notification → result-ready notification ──────
        cancelTapToRunNotification(for: job)
        await postResultNotification(for: job, agent: agent, preview: responseText)

        logger.info("Job '\(job.name)' done — \(responseText.count) chars saved")
    }

    // MARK: - Notifications

    /// Cancels the pending "tap to run" banner for the job so the user
    /// doesn't see a stale call-to-action after the result is already in the DB.
    private func cancelTapToRunNotification(for job: AgentJob) {
        let calendarIds = (1...7).map { "\(job.notificationBase)-day-\($0)" }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: calendarIds + [job.intervalNotificationId])
    }

    /// Fires a local notification immediately with a one-line preview of the response.
    /// `isResult = "1"` in `userInfo` tells `NotificationDelegate` to open the
    /// conversation without re-triggering the job.
    private func postResultNotification(for job: AgentJob, agent: Agent, preview: String) async {
        // Skip the notification if the app is active — the conversation list
        // updates via ValueObservation, so the user will see the result inline.
        let appIsActive = await MainActor.run { UIApplication.shared.applicationState == .active }
        guard !appIsActive else { return }

        let firstLine = preview
            .components(separatedBy: "\n")
            .map    { $0.trimmingCharacters(in: .whitespaces) }
            .first  { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("*") && !$0.hasPrefix("-") }
            ?? String(preview.prefix(140))
        let body = firstLine.count > 140 ? String(firstLine.prefix(140)) + "…" : firstLine

        let content          = UNMutableNotificationContent()
        content.title        = "\(agent.emoji) \(job.name)"
        content.body         = body.isEmpty ? "Result ready — tap to view." : body
        content.sound        = .default
        content.userInfo     = [
            "agentId":  agent.id.uuidString,
            "isResult": "1"
        ]

        let request = UNNotificationRequest(
            identifier: "\(job.notificationBase)-result",
            content: content,
            trigger: nil          // nil = deliver immediately
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Scheduling

    /// Submits a `BGAppRefreshTaskRequest` whose `earliestBeginDate` is the
    /// soonest `nextFireDate` across all enabled jobs.
    /// Safe to call multiple times — BGTaskScheduler replaces any existing
    /// pending request with the same identifier.
    func scheduleNextRefresh() {
        let jobs = (try? db.allEnabledJobs()) ?? []
        guard !jobs.isEmpty else {
            logger.debug("No enabled jobs — skipping BGAppRefreshTask scheduling")
            return
        }

        let soonest = jobs.map(\.nextFireDate).min() ?? Date(timeIntervalSinceNow: 3600)

        let request               = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = soonest

        BGTaskScheduler.shared.submitTaskRequest(request) { error in
            if let error {
                logger.error("Failed to schedule BGAppRefreshTask: \(error.localizedDescription)")
            } else {
                logger.info("BGAppRefreshTask scheduled — earliest: \(soonest)")
            }
        }
    }
}

// MARK: - Errors

enum BackgroundJobError: Error, LocalizedError {
    case agentNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .agentNotFound(let id): return "Agent \(id) not found for background job."
        }
    }
}
