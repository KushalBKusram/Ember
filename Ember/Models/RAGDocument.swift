import Foundation
@preconcurrency import GRDB

struct RAGDocument: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable, Hashable {
    var id: UUID = UUID()
    var title: String
    var source: Source
    var sourceIdentifier: String?
    var indexedAt: Date = Date()
    var isEnabled: Bool = true
    var chunkCount: Int = 0

    static let databaseTableName = "rag_document"

    enum Source: String, Codable, Sendable, CaseIterable {
        case file, calendar, reminders

        var label: String {
            switch self {
            case .file: return "File"
            case .calendar: return "Calendar"
            case .reminders: return "Reminders"
            }
        }

        var icon: String {
            switch self {
            case .file: return "doc.fill"
            case .calendar: return "calendar"
            case .reminders: return "checklist"
            }
        }
    }
}
