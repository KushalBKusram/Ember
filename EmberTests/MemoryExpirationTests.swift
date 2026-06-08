import Testing
import Foundation
@testable import Ember

@Suite("Memory expiration")
struct MemoryExpirationTests {

    @Test("Episodic memories carry a 30-day TTL")
    func episodicHasTTL() {
        let mem = Memory.make(content: "Felt tired today", category: .episodic)
        #expect(mem.expiresAt != nil)
        let interval = mem.expiresAt!.timeIntervalSince(mem.createdAt)
        let thirtyDays: TimeInterval = 30 * 24 * 3600
        // Allow ±1 day tolerance for clock skew at midnight boundaries.
        #expect(abs(interval - thirtyDays) < 24 * 3600)
    }

    @Test("Persistent categories never expire")
    func persistentCategoriesNoTTL() {
        for category in [Memory.Category.preference, .project, .relationship] {
            let mem = Memory.make(content: "X", category: category)
            #expect(mem.expiresAt == nil)
        }
    }

    @Test("isExpired flips at expiry boundary")
    func isExpiredHonoursDate() {
        var mem = Memory.make(content: "A", category: .episodic)
        #expect(!mem.isExpired)
        mem.expiresAt = Date().addingTimeInterval(-1)
        #expect(mem.isExpired)
        mem.expiresAt = Date().addingTimeInterval(60)
        #expect(!mem.isExpired)
    }
}
