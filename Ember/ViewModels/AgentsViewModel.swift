import Foundation
import GRDB

@MainActor
@Observable
final class AgentsViewModel {
    var agents: [Agent] = []
    var showingCreate = false

    private let db      = AppDatabase.shared
    private let service = AgentService.shared
    private var observationTask: Task<Void, Never>?

    func startObserving() {
        observationTask?.cancel()
        observationTask = Task {
            do {
                let obs = db.allAgentsObservation()
                for try await updated in obs.values(in: db.dbPool) {
                    guard !Task.isCancelled else { break }
                    self.agents = updated
                }
            } catch { /* non-fatal */ }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    func delete(_ agent: Agent) {
        Task { try? await service.deleteAgent(agent) }
    }
}
