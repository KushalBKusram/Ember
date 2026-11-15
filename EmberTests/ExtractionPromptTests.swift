import Testing
@testable import Ember

@Suite("Memory extraction prompt")
struct ExtractionPromptTests {
    @Test("Contains the user's words and nothing from the assistant")
    func userOnly() {
        let p = MemoryService.extractionPrompt(for: "My dog is named Biscuit")
        #expect(p.contains("My dog is named Biscuit"))
        #expect(!p.lowercased().contains("assistant"))
    }
}

@Suite("Profile synthesis prompt")
struct SynthesisPromptTests {
    @Test("Explains that first-person facts about a pet are not the person's name")
    func ownershipNotIdentity() {
        let p = MemoryService.synthesisPrompt
        #expect(p.contains("OWNS a dog"))
        #expect(p.contains("not called Biscuit"))
        #expect(p.contains("explicitly says it is their name"))
        #expect(p.contains("Mention EVERY fact"))
    }
}
