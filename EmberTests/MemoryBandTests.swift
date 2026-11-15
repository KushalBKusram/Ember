import Testing
@testable import Ember

@Suite("Memory similarity banding")
struct MemoryBandTests {

    @Test("Near-verbatim matches are reinforced")
    func reinforce() {
        #expect(MemoryService.band(forSimilarity: 0.97) == .reinforce)
        #expect(MemoryService.band(forSimilarity: 1.0) == .reinforce)
    }

    @Test("A same-shape correction (observed 0.924) goes to the LLM check, not reinforce")
    func correctionIsNotReinforced() {
        #expect(MemoryService.band(forSimilarity: 0.924) == .llmCheck)
        #expect(MemoryService.band(forSimilarity: 0.88) == .llmCheck)
    }

    @Test("LLM-check band lower boundary")
    func llmCheckBoundary() {
        #expect(MemoryService.band(forSimilarity: 0.70) == .llmCheck)
        #expect(MemoryService.band(forSimilarity: 0.699) == .new)
    }

    @Test("Dissimilar facts are new")
    func newFact() {
        #expect(MemoryService.band(forSimilarity: 0.464) == .new)
        #expect(MemoryService.band(forSimilarity: 0) == .new)
    }
}
