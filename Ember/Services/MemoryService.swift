import Foundation
import FoundationModels

actor MemoryService {
    static let shared = MemoryService()

    private let db = AppDatabase.shared
    private let embedder = EmbeddingService.shared

    private let extractionInstructions = """
        You extract memorable personal facts about a user ONLY from what the user explicitly \
        wrote in their own message.

        Critical rules:
        1. Source ONLY from the user's own words — never from the assistant's reply.
        2. The assistant's reply may contain calendar events, appointments, schedules, reminders, \
           document excerpts, or web content injected by the system. NONE of that is a \
           personal fact about the user. Ignore the assistant's reply entirely.
        3. NEVER extract calendar entries, meetings, interviews, or scheduled events.
        4. NEVER extract general knowledge or AI-generated content.
        5. NEVER extract uncertain or hedged statements — skip anything containing \
           words like "might", "maybe", "probably", "I think", "I believe", \
           "possibly", "not sure", "sort of", "kind of".
        6. Return an empty facts array when the user's message contains nothing \
           personally memorable or clearly stated.
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

            let result = try await session.respond(
                to: prompt,
                generating: ExtractedMemoryList.self
            )

            // Load existing memories once; mutated during the loop as superseded
            // facts are deleted so later iterations don't match stale entries.
            var knownMemories = (try? db.activeMemories()) ?? []

            var savedAny = false
            for fact in result.content.facts {
                let trimmed = fact.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let (sim, topMatch) = await embedder.mostSimilar(of: trimmed, in: knownMemories)

                // ── Band 1 (≥ 0.88): near-identical — reinforce, don't duplicate. ─
                // Bumping lastAccessedAt signals that this fact has been confirmed
                // again, keeping it fresh in recency-ranked retrievals and synthesis.
                if sim >= 0.88 {
                    if var reinforce = topMatch {
                        reinforce.lastAccessedAt = Date()
                        try? db.saveMemory(&reinforce)
                    }
                    continue
                }

                // ── Band 2 (0.70–0.87): related topic — may be a correction. ──────
                // LLM decides: supersession (delete old + save new) vs
                // complementary (save new alongside the existing fact).
                if sim >= 0.70, let conflicting = topMatch {
                    let supersedes = await checkSupersession(newFact: trimmed, against: conflicting)
                    if supersedes {
                        try? db.deleteMemory(conflicting)
                        knownMemories.removeAll { $0.id == conflicting.id }
                    }
                }

                // ── Band 3 (< 0.70): unrelated new fact — save normally. ───────────
                let category = Memory.Category(rawValue: fact.category) ?? .episodic
                var memory = Memory.make(content: trimmed, category: category)
                if let vector = await embedder.embed(trimmed) {
                    memory.embedding = vector.asData
                }
                try db.saveMemory(&memory)
                knownMemories.append(memory)
                savedAny = true
            }

            if savedAny {
                await synthesizeProfile()
            }
        } catch {
            // Extraction is best-effort — silent failure is acceptable
        }
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
        let memories = (try? db.activeMemories()) ?? []
        let enabled = memories.filter { $0.isEnabled }

        // Episodic memories are transient (TTL 30 days) — exclude from the standing
        // profile so temporary events don't define who the user is permanently.
        let profileWorthy = enabled.filter { $0.category != .episodic }
        guard !profileWorthy.isEmpty else { return }

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
        let now = Date()
        for memory in memories {
            var updated = memory
            updated.lastAccessedAt = now
            try? db.saveMemory(&updated)
        }
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

            // Apply the same 3-band pipeline as processExchange so the onboarding
            // path doesn't bypass dedup, reinforcement, or supersession.
            var knownMemories = (try? db.activeMemories()) ?? []

            var savedAny = false
            for fact in result.content.facts {
                let content = fact.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { continue }

                let (sim, topMatch) = await embedder.mostSimilar(of: content, in: knownMemories)

                if sim >= 0.88 {
                    if var reinforce = topMatch {
                        reinforce.lastAccessedAt = Date()
                        try? db.saveMemory(&reinforce)
                    }
                    continue
                }

                if sim >= 0.70, let conflicting = topMatch {
                    let supersedes = await checkSupersession(newFact: content, against: conflicting)
                    if supersedes {
                        try? db.deleteMemory(conflicting)
                        knownMemories.removeAll { $0.id == conflicting.id }
                    }
                }

                let category = Memory.Category(rawValue: fact.category) ?? .preference
                var memory = Memory.make(content: content, category: category)
                if let vector = await embedder.embed(content) {
                    memory.embedding = vector.asData
                }
                try db.saveMemory(&memory)
                knownMemories.append(memory)
                savedAny = true
            }

            if savedAny { await synthesizeProfile() }
        } catch {
            // Best-effort — silent failure acceptable
        }
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
