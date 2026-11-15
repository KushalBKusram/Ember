import Testing
@testable import Ember

@Suite("System prompt")
struct SystemPromptTests {
    @Test("Does not tell the model to answer only factually, which made it refuse poems and essays")
    func allowsCreativeWork() {
        let p = LLMService.baseSystemPrompt.lowercased()
        #expect(!p.contains("answer factually"))
        #expect(p.contains("creative writing"))
    }

    @Test("Still keeps the identity and no-tag rules")
    func keepsRules() {
        let p = LLMService.baseSystemPrompt
        #expect(p.contains("describe the USER"))
        #expect(p.contains("XML-style tags"))
    }
}
