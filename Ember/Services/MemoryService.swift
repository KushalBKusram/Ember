import Foundation
import FoundationModels

actor MemoryService {
    static let shared = MemoryService()

    private let db = AppDatabase.shared
    private let embedder = EmbeddingService.shared

    private let extractionInstructions = """
        You extract memorable personal facts about a user from conversation exchanges.
        Extract ONLY facts explicitly stated by or about the user themselves.
        Do NOT extract general knowledge, AI-generated answers, or trivial questions like "what's the capital of France?"
        State each fact concisely and specifically.
        """

    // MARK: - Extraction (background, best-effort)

    func processExchange(userMessage: Message, assistantMessage: Message) async {
        guard AppSettings.memoryEnabled else { return }

        do {
            let session = LanguageModelSession(instructions: extractionInstructions)
            let prompt = """
                User: \(userMessage.content)
                Assistant: \(assistantMessage.content)

                Extract any memorable facts about the user from the above exchange.
                """

            let result = try await session.respond(
                to: prompt,
                generating: ExtractedMemoryList.self
            )

            for fact in result.content.facts {
                let trimmed = fact.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let category = Memory.Category(rawValue: fact.category) ?? .episodic
                var memory = Memory.make(content: trimmed, category: category)

                if let vector = await embedder.embed(trimmed) {
                    memory.embedding = vector.asData
                }

                try db.saveMemory(&memory)
            }
        } catch {
            // Extraction is best-effort — silent failure is acceptable
        }
    }

    // MARK: - Retrieval

    func retrieveRelevant(for text: String, limit: Int = 8) async throws -> [Memory] {
        let all = try db.activeMemories()
        guard !all.isEmpty else { return [] }
        return await embedder.rankMemories(all, for: text, limit: limit)
    }

    // MARK: - Management

    func toggle(_ memory: Memory) throws {
        var updated = memory
        updated.isEnabled = !updated.isEnabled
        try db.saveMemory(&updated)
    }

    func delete(_ memory: Memory) throws {
        try db.deleteMemory(memory)
    }

    func clearAll() throws {
        try db.clearAllMemories()
    }
}
