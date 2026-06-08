import Foundation

/// Centralised place for one-off migrations driven by app version bumps.
/// Add new migrations as `if previous < "1.1.0" { ... }` blocks.
enum VersionMigrator {
    static func runIfNeeded() {
        let previous = AppSettings.lastSeenVersion
        let current = AppSettings.currentVersion
        guard previous != current else { return }
        defer { AppSettings.lastSeenVersion = current }

        // First-ever launch — nothing to migrate, just mark version.
        guard !previous.isEmpty else { return }

        // Add per-version blocks below as features need upgrade cleanup.
        // Example shape (keep commented until needed):
        //
        // if compareVersions(previous, "1.1.0") == .orderedAscending {
        //     // wipe stale on-disk embedding cache for changed model
        //     try? AppDatabase.shared.dbPool.write { try $0.execute(sql: "DELETE FROM embedding_cache") }
        // }
    }
}
