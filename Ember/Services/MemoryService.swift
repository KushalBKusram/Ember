import Foundation
import FoundationModels

actor MemoryService {
    static let shared = MemoryService()

    private let db = AppDatabase.shared
    private let embedder = EmbeddingService.shared

    /// Guards against two concurrent callers each starting an LLM synthesis
    /// session and writing the profile twice. Because `MemoryService` is an
    /// `actor`, this flag is read/written on the actor's executor without races.
    private var isSynthesizing = false

    private let extractionInstructions = """
        You extract memorable personal facts about a user ONLY from what the user explicitly \
        wrote in their own message.

        Critical rules:
        1. Source ONLY from the user's own words — never from the assistant's reply.
        2. The assistant's reply may contain calendar events, appointments, schedules, reminders, \
           document excerpts, or web content injected by the system. NONE of that is a \
           personal fact about the user. Ignore the assistant's reply entirely.
        3. NEVER extract questions, requests, or queries. A question like "How is AMZN doing?" \
           or "What is the weather?" tells you nothing permanent about the user. Only extract \
           clear, declarative statements of fact ("I work at Acme", "I have two kids").
        4. NEVER extract calendar entries, meetings, interviews, or scheduled events.
        5. NEVER extract general knowledge or AI-generated content.
        6. NEVER extract uncertain or hedged statements — skip anything containing \
           words like "might", "maybe", "probably", "I think", "I believe", \
           "possibly", "not sure", "sort of", "kind of".
        7. Return an empty facts array when the user's message contains nothing \
           personally memorable or clearly stated as a fact.
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
                [USER'S MESSAGE — extract personal facts from here only]
                \(userMessage.content)

                [ASSISTANT'S RESPONSE — contains system-injected calendar/document data, ignore entirely]
                \(assistantMessage.content)

                Extract memorable personal facts ONLY from what the user wrote above. \
                Ignore everything the assistant said.
                """
            let result = try await session.respond(to: prompt, generating: ExtractedMemoryList.self)
            var known = (try? db.activeMemories()) ?? []
            if try await absorbFacts(result.content.facts, into: &known, fallbackCategory: .episodic) {
                await synthesizeProfile()
            }
        } catch { /* best-effort */ }
    }

    // MARK: - Query-time retrieval

    /// Returns the memories most semantically relevant to `query`, ranked by
    /// cosine similarity. At conversation time this is injected alongside (not
    /// instead of) the profile paragraph so the LLM can answer precise personal
    /// questions that the 2–4 sentence profile may have compressed away.
    func retrieveRelevantIfEnabled(for query: String, limit: Int = 6) async -> [Memory] {
        guard AppSettings.memoryEnabled else { return [] }
        let memories = (try? db.activeMemories()) ?? []
        guard !memories.isEmpty else { return [] }
        return await embedder.rankMemories(memories, for: query, limit: limit)
    }

    // MARK: - Supersession check

    /// Returns true when the LLM determines that `newFact` corrects or contradicts
    /// `existing`. Defaults to false on any failure — never silently deletes without
    /// a confirmed decision.
    private func checkSupersession(newFact: String, against existing: Memory) async -> Bool {
        let session = LanguageModelSession(instructions: """
            You decide whether a new personal fact (B) supersedes an existing one (A).
            Answer true only when B directly corrects, contradicts, or makes A obsolete.
            Answer false when both A and B can be true simultaneously.
            """)
        let prompt = """
            Existing fact (A): \(existing.content)
            New fact (B): \(newFact)
            Does B supersede or correct A?
            """
        let result = try? await session.respond(to: prompt, generating: SupersessionDecision.self)
        return result?.content.supersedes ?? false
    }

    // MARK: - Profile synthesis

    func synthesizeProfile() async {
        guard !isSynthesizing else { return }
        isSynthesizing = true
        defer { isSynthesizing = false }

        let memories = (try? db.activeMemories()) ?? []
        let enabled = memories.filter { $0.isEnabled }

        // Episodic memories are transient (TTL 30 days) — exclude from the standing
        // profile so temporary events don't define who the user is permanently.
        let profileWorthy = enabled.filter { $0.category != .episodic }
        guard !profileWorthy.isEmpty else {
            // Nothing left to build a profile from (user deleted or disabled
            // every fact) — clear the old paragraph too, or it would keep
            // describing the user in every future conversation.
            AppSettings.userProfile = ""
            return
        }

        let byCategory = Dictionary(grouping: profileWorthy, by: \.category)
        var categoryBlocks: [String] = []
        for category in Memory.Category.allCases where category != .episodic {
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
                touchAccessed(profileWorthy)
            }
        } catch {
            // Keep existing profile on failure
        }
    }

    private func touchAccessed(_ memories: [Memory]) {
        // Batch all updates into a single write transaction instead of N separate ones.
        try? db.touchMemoryAccessDates(ids: memories.map(\.id))
    }

    func synthesizeProfileIfNeeded() async {
        guard AppSettings.userProfile.isEmpty else { return }
        await synthesizeProfile()
    }

    // MARK: - Identity seeding (onboarding)

    /// Runs the same full extraction pipeline as `processExchange` — including
    /// deduplication, reinforcement, and supersession — so onboarding doesn't
    /// bypass the memory quality controls.
    func initializeFromIdentity(_ text: String) async {
        guard AppSettings.memoryEnabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let identityInstructions = """
            You extract memorable personal facts from a person's self-written introduction.
            The text is written directly by the user about themselves.
            Extract specific, useful facts about their background, interests, work, \
            relationships, and goals. State each fact concisely in third person.
            Only extract clearly stated facts — skip anything hedged or uncertain.
            """
        do {
            let session = LanguageModelSession(instructions: identityInstructions)
            let prompt = """
                The user wrote the following introduction about themselves:

                \(trimmed)

                Extract memorable facts about this person.
                """
            let result = try await session.respond(to: prompt, generating: ExtractedMemoryList.self)
            var known = (try? db.activeMemories()) ?? []
            // Onboarding defaults to .preference when the model returns an unrecognised category.
            if try await absorbFacts(result.content.facts, into: &known, fallbackCategory: .preference) {
                await synthesizeProfile()
            }
        } catch { /* best-effort */ }
    }

    // MARK: - 3-band absorption pipeline

    /// Applies deduplication, reinforcement, and supersession to a list of extracted facts,
    /// mutating `knownMemories` as entries are added or removed so later facts in the
    /// same batch do not collide against stale data.
    ///
    /// - Returns: `true` if at least one new fact was persisted (used to gate profile re-synthesis).
    private func absorbFacts(
        _ facts: [ExtractedFact],
        into knownMemories: inout [Memory],
        fallbackCategory: Memory.Category
    ) async throws -> Bool {
        var savedAny = false
        for fact in facts {
            let trimmed = fact.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let (sim, topMatch) = await embedder.mostSimilar(of: trimmed, in: knownMemories)

            // ── Band 1 (≥ 0.88): near-identical — reinforce, don't duplicate. ─────
            if sim >= 0.88 {
                if var reinforce = topMatch {
                    reinforce.lastAccessedAt = Date()
                    try? db.saveMemory(&reinforce)
                }
                continue
            }

            // ── Band 2 (0.70–0.87): related topic — LLM decides supersession. ─────
            if sim >= 0.70, let conflicting = topMatch {
                if await checkSupersession(newFact: trimmed, against: conflicting) {
                    try? db.deleteMemory(conflicting)
                    knownMemories.removeAll { $0.id == conflicting.id }
                }
            }

            // ── Band 3 (< 0.70): genuinely new fact — save. ──────────────────────
            let category = Memory.Category(rawValue: fact.category) ?? fallbackCategory
            var memory = Memory.make(content: trimmed, category: category)
            if let vector = await embedder.embed(trimmed) {
                memory.embedding = vector.asData
            }
            try db.saveMemory(&memory)
            knownMemories.append(memory)
            savedAny = true
        }
        return savedAny
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
