import Foundation

/// Tracks which jobs are running right now so a foreground "Run Now" / notification
/// tap and a background refresh can never run the same job at the same time.
actor JobRunGuard {
    static let shared = JobRunGuard()

    private var running: Set<UUID> = []

    /// Returns `false` if the job is already running; otherwise marks it running.
    func tryBegin(_ jobId: UUID) -> Bool {
        running.insert(jobId).inserted
    }

    func end(_ jobId: UUID) {
        running.remove(jobId)
    }
}
