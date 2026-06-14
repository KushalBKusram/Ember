import Testing
import Foundation
@testable import Ember

@Suite("Memory.Category resolution")
struct MemoryCategoryTests {

    @Test("All categories have non-empty label and icon")
    func categoryMetadata() {
        for cat in Memory.Category.allCases {
            #expect(!cat.label.isEmpty)
            #expect(!cat.icon.isEmpty)
        }
    }

    @Test("Known raw-value strings round-trip through Category(rawValue:)")
    func rawValueRoundTrip() {
        #expect(Memory.Category(rawValue: "preference")   == .preference)
        #expect(Memory.Category(rawValue: "project")      == .project)
        #expect(Memory.Category(rawValue: "relationship") == .relationship)
        #expect(Memory.Category(rawValue: "episodic")     == .episodic)
    }

    @Test("Legacy and unknown category strings return nil — not a silent fallback")
    func unknownCategoriesReturnNil() {
        // These were in an earlier iteration of the model; the code must not accept them.
        #expect(Memory.Category(rawValue: "identity") == nil)
        #expect(Memory.Category(rawValue: "skill")    == nil)
        // Other unrecognised strings
        #expect(Memory.Category(rawValue: "")         == nil)
        #expect(Memory.Category(rawValue: "PREFERENCE") == nil)  // case-sensitive
    }

    @Test("Nil-coalescing to a fallback works correctly")
    func fallbackPattern() {
        let category = Memory.Category(rawValue: "unknown") ?? .preference
        #expect(category == .preference)

        let category2 = Memory.Category(rawValue: "episodic") ?? .preference
        #expect(category2 == .episodic)  // known → no fallback needed
    }

    @Test("Episodic memories have a 30-day TTL; all other categories have none")
    func expiryByCategory() {
        for cat in Memory.Category.allCases {
            let mem = Memory.make(content: "test", category: cat)
            if cat == .episodic {
                #expect(mem.expiresAt != nil)
            } else {
                #expect(mem.expiresAt == nil)
            }
        }
    }

    @Test("Memory.make produces an enabled, unembedded memory with the correct content and category")
    func makeDefaults() {
        let mem = Memory.make(content: "Prefers dark mode", category: .preference)
        #expect(mem.isEnabled)
        #expect(mem.embedding == nil)
        #expect(mem.content == "Prefers dark mode")
        #expect(mem.category == .preference)
        #expect(mem.expiresAt == nil)
    }

    @Test("Memory.Category has exactly four cases")
    func caseCount() {
        #expect(Memory.Category.allCases.count == 4)
    }
}
