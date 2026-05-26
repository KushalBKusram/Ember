import Foundation
import FoundationModels

actor MemoryService {
    static let shared = MemoryService()

    private let db = AppDatabase.shared
    private let embedder = EmbeddingService.shared

    private let extractionInstructions = """
        You extract memorable personal facts about a user from conversation exchanges.
        Extract ONLY facts explicitly stated by or about the user themselves.
        Do NOT extract general knowledge, AI-generated answers, or trivial questions.
        State each fact concisely and specifically.
        """

    private let synthesisInstructions = """
        You are a precise summariser. Your only job is to synthesise a list of facts about a person \
        into a short, natural biographical paragraph. Write exactly 2–4 sentences. Use third person. \
        Blend related facts into cohesive statements — no lists, no bullet points, no preamble, \
        no commentary. Output only the paragraph itself.
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

            var savedAny = false
            for fact in result.content.facts {
                let trimmed = fact.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let category = Memory.Category(rawValue: fact.category) ?? .episodic
                var memory = Memory.make(content: trimmed, category: category)

                if let vector = await embedder.embed(trimmed) {
                    memory.embedding = vector.asData
                }

                try db.saveMemory(&memory)
                savedAny = true
            }

            if savedAny {
                await synthesizeProfile()
            }
        } catch {
            // Extraction is best-effort — silent failure is acceptable
        }
    }

    // MARK: - Profile synthesis

    func synthesizeProfile() async {
        let memories = (try? db.activeMemories()) ?? []
        let enabled = memories.filter { $0.isEnabled }
        guard !enabled.isEmpty else {
            AppSettings.userProfile = ""
            return
        }

        let byCategory = Dictionary(grouping: enabled, by: \.category)
        var categoryBlocks: [String] = []
        for category in Memory.Category.allCases {
            guard let facts = byCategory[category], !facts.isEmpty else { continue }
            let lines = facts.map { "- \($0.content)" }.joined(separator: "\n")
            categoryBlocks.append("\(category.label):\n\(lines)")
        }
        let factList = categoryBlocks.joined(separator: "\n\n")

        do {
            let session = LanguageModelSession(instructions: synthesisInstructions)
            let result = try await session.respond(to: factList)
            let profile = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !profile.isEmpty {
                AppSettings.userProfile = profile
            }
        } catch {
            // Keep existing profile on failure
        }
    }

    func synthesizeProfileIfNeeded() async {
        guard AppSettings.userProfile.isEmpty else { return }
        await synthesizeProfile()
    }

    // MARK: - Management

    func toggle(_ memory: Memory) throws {
        var updated = memory
        updated.isEnabled = !updated.isEnabled
        try db.saveMemory(&updated)
        Task { await synthesizeProfile() }
    }

    func delete(_ memory: Memory) throws {
        try db.deleteMemory(memory)
        Task { await synthesizeProfile() }
    }

    func clearAll() throws {
        try db.clearAllMemories()
        AppSettings.userProfile = ""
    }
}
