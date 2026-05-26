import Foundation
import GRDB

@MainActor
@Observable
final class MemoryViewModel {
    var memories: [Memory] = []
    var searchQuery = ""
    var isRegeneratingProfile = false

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
        Task { try? await service.delete(memory) }
    }

    func toggle(_ memory: Memory) {
        Task { try? await service.toggle(memory) }
    }

    func clearAll() {
        Task { try? await service.clearAll() }
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
