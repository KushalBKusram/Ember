import Foundation
import GRDB

@MainActor
@Observable
final class DataSourcesViewModel {
    var documents: [RAGDocument] = []
    var isIndexing = false
    var indexingTitle = ""
    var error: String?

    private let db = AppDatabase.shared
    private var observationTask: Task<Void, Never>?

    func startObserving() {
        observationTask?.cancel()
        observationTask = Task {
            do {
                let observation = db.allRAGDocumentsObservation()
                for try await updated in observation.values(in: db.dbPool) {
                    guard !Task.isCancelled else { break }
                    self.documents = updated
                }
            } catch {
                // Non-fatal
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    func importFile(at url: URL) {
        isIndexing = true
        indexingTitle = url.deletingPathExtension().lastPathComponent
        Task {
            do {
                _ = try await RAGService.shared.indexFile(at: url)
            } catch {
                self.error = "Could not index \"\(url.lastPathComponent)\": \(error.localizedDescription)"
            }
            isIndexing = false
            indexingTitle = ""
        }
    }

    func saveNote(title: String, body: String, replacing existing: RAGDocument? = nil) {
        isIndexing = true
        indexingTitle = title.isEmpty ? "Untitled Note" : title
        Task {
            do {
                _ = try await RAGService.shared.indexNote(title: title, body: body, replacing: existing)
            } catch {
                self.error = "Could not save note: \(error.localizedDescription)"
            }
            isIndexing = false
            indexingTitle = ""
        }
    }

    func loadNoteBody(for doc: RAGDocument) async -> String {
        do {
            return (try await RAGService.shared.noteBody(for: doc.id)) ?? ""
        } catch {
            self.error = "Could not load note: \(error.localizedDescription)"
            return ""
        }
    }

    func deleteDocument(_ doc: RAGDocument) {
        Task {
            do { try await RAGService.shared.deleteDocument(doc) }
            catch { self.error = UserFacingError.message("delete \"\(doc.title)\"", error) }
        }
    }

    func deleteDocuments(at offsets: IndexSet) {
        offsets.forEach { deleteDocument(documents[$0]) }
    }

    func toggleDocument(_ doc: RAGDocument) {
        var updated = doc
        updated.isEnabled.toggle()
        do { try db.saveRAGDocument(&updated) }
        catch { self.error = UserFacingError.message("update \"\(doc.title)\"", error) }
    }

    func requestCalendarAccess() {
        Task {
            let granted = await CalendarService.shared.requestCalendarAccess()
            if !granted {
                AppSettings.calendarEnabled = false
                error = "Calendar access was denied. Enable it in Settings > Privacy."
            }
        }
    }

    func requestRemindersAccess() {
        Task {
            let granted = await CalendarService.shared.requestRemindersAccess()
            if !granted {
                AppSettings.remindersEnabled = false
                error = "Reminders access was denied. Enable it in Settings > Privacy."
            }
        }
    }
}
