import Foundation
import GRDB

@MainActor
@Observable
final class MemoryViewModel {
    var memories: [Memory] = []
    var searchQuery = ""
    var isRegeneratingProfile = false
    var error: String?

    private let db = AppDatabase.shared
    private let service = MemoryService.shared
    private var observationTask: Task<Void, Never>?

    var memoriesByCategory: [(Memory.Category, [Memory])] {
        let filtered = searchQuery.isEmpty
            ? memories
            : memories.filter { $0.content.localizedCaseInsensitiveContains(searchQuery) }

        return Memory.Category.allCases.compactMap { category in
            let group = filtered.filter { $0.category == category }
            return group.isEmpty ? nil : (category, group)
        }
    }

    /// Non-episodic memories (Preferences, Projects, Relationships) shown
    /// under "What Ember knows" as permanent facts.
    var savedMemories: [Memory] {
        memoriesByCategory
            .filter { $0.0 != .episodic }
            .flatMap { $0.1 }
    }

    /// Episodic-only memories — temporary observations with a 30-day TTL.
    var recentMemories: [Memory] {
        memoriesByCategory.first { $0.0 == .episodic }?.1 ?? []
    }

    func startObserving() {
        observationTask?.cancel()
        observationTask = Task {
            do {
                let observation = db.allMemoriesObservation()
                for try await updated in observation.values(in: db.dbPool) {
                    guard !Task.isCancelled else { break }
                    self.memories = updated
                }
            } catch {
                // Non-fatal
            }
        }

        Task { await service.synthesizeProfileIfNeeded() }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    func delete(_ memory: Memory) {
        Task {
            do { try await service.delete(memory) }
            catch { self.error = UserFacingError.message("delete that memory", error) }
        }
    }

    func toggle(_ memory: Memory) {
        Task {
            do { try await service.toggle(memory) }
            catch { self.error = UserFacingError.message("update that memory", error) }
        }
    }

    func clearAll() {
        Task {
            do { try await service.clearAll() }
            catch { self.error = UserFacingError.message("clear your memories", error) }
        }
    }

    func regenerateProfile() {
        guard !isRegeneratingProfile else { return }
        isRegeneratingProfile = true
        Task {
            await service.synthesizeProfile()
            isRegeneratingProfile = false
        }
    }
}
