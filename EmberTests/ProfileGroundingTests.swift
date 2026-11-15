import Testing
@testable import Ember

@Suite("Profile synthesis grounding")
struct ProfileGroundingTests {

    @Test("A short summary of a short fact passes")
    func shortPasses() {
        #expect(MemoryService.isGrounded(profile: "The user is a designer.", facts: ["I am a designer"]))
    }

    @Test("The padded paragraph observed in the simulator is rejected")
    func paddedFails() {
        let padded = "A designer with a keen eye for detail values clean lines and functional forms. They often work with minimal palettes, focusing on clarity and balance. The approach reflects a deep understanding of space and composition."
        #expect(!MemoryService.isGrounded(profile: padded, facts: ["I am a designer"]))
    }

    @Test("More facts allow a proportionally longer summary")
    func scalesWithFacts() {
        let facts = ["Works at Acme as a software engineer", "Lives in Seattle with two cats", "Plays jazz piano on weekends"]
        let profile = "The user is a software engineer at Acme who lives in Seattle with two cats and plays jazz piano on weekends."
        #expect(MemoryService.isGrounded(profile: profile, facts: facts))
    }
}
