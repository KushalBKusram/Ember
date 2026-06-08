import Foundation

/// Shared state that carries a pending notification tap from the OS
/// notification handler into the Agents UI. Observed by AgentsListView
/// to navigate to the right agent and auto-trigger the job.
@MainActor
@Observable
final class AgentNavigationState {
    static let shared = AgentNavigationState()

    /// Set by NotificationDelegate when a job notification is tapped.
    /// Cleared by AgentConversationView once the trigger has fired.
    var pendingTrigger: (agentId: UUID, jobId: UUID)? = nil
}
