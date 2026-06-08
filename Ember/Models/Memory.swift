import Foundation
import GRDB
import SwiftUI

struct Memory: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable, Hashable {
    var id: UUID
    var content: String
    var category: Category
    var embedding: Data?
    var createdAt: Date
    var lastAccessedAt: Date
    var expiresAt: Date?
    var isEnabled: Bool

    enum Category: String, Codable, Sendable, CaseIterable {
        case preference
        case project
        case relationship
        case episodic

        var label: String {
            switch self {
            case .preference:   return "Preferences"
            case .project:      return "Projects"
            case .relationship: return "Relationships"
            case .episodic:     return "Episodic"
            }
        }

        var icon: String {
            switch self {
            case .preference:   return "heart.fill"
            case .project:      return "hammer.fill"
            case .relationship: return "person.2.fill"
            case .episodic:     return "clock.fill"
            }
        }

        var chipColor: Color {
            switch self {
            case .preference:   return .pink
            case .project:      return .orange
            case .relationship: return .blue
            case .episodic:     return .purple
            }
        }
    }

    static let databaseTableName = "memory"

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }

    static func make(content: String, category: Category) -> Memory {
        Memory(
            id: UUID(),
            content: content,
            category: category,
            embedding: nil,
            createdAt: Date(),
            lastAccessedAt: Date(),
            expiresAt: category == .episodic
                ? Calendar.current.date(byAdding: .day, value: 30, to: Date())
                : nil,
            isEnabled: true
        )
    }
}
