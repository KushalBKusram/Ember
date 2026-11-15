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

    @Test("Tells the model not to guess personal facts it was not given")
    func noGuessing() {
        let p = LLMService.baseSystemPrompt
        #expect(p.contains("Never guess personal facts"))
        #expect(p.contains("I don't have that information"))
    }

    @Test("An empty calendar window is not phrased as a schedule answer")
    func emptyCalendarNote() {
        let n = CalendarService.noEventsNote(label: "today")
        #expect(n.contains("no events found for today"))
        #expect(n.contains("says nothing about bills"))
        #expect(!n.contains("none scheduled"))
    }
}
