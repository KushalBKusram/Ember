import Foundation
import FoundationModels
import OSLog

#if DEBUG
private let memLog = Logger(subsystem: "com.kushal.ember", category: "memory-debug")
#endif

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
        You turn a list of facts about a person into a short third-person summary. \
        Use ONLY the facts provided. Do not add, infer, embellish, or guess anything — \
        no traits, skills, habits, or opinions that are not literally in the list. \
        Write as few sentences as the facts need: one fact means one short sentence. \
        Never exceed 4 sentences. Output only the summary, with no preamble or commentary.
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
            #if DEBUG
            let extractedList = result.content.facts.map(\.content).joined(separator: " | ")
            memLog.debug("extracted \(result.content.facts.count, privacy: .public) facts from: \(userMessage.content, privacy: .public) -> \(extractedList, privacy: .public)")
            #endif
            var known = (try? db.activeMemories()) ?? []
            if try await absorbFacts(result.content.facts, into: &known,
                                     fallbackCategory: .episodic,
                                     originalMessage: userMessage.content) {
                await synthesizeProfile()
            }
        } catch {
            #if DEBUG
            memLog.debug("extraction failed: \(String(describing: error), privacy: .public)")
            #endif
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

    // MARK: - Batch supersession check

    /// Evaluates multiple (existing, new) pairs in a single LLM session rather than
    /// N sequential sessions. Pads with `false` if the model returns fewer decisions
    /// than pairs — we never silently delete without a confirmed supersession.
    private func batchCheckSupersession(
        _ pairs: [(newFact: String, existing: Memory)],
        originalMessage: String = ""
    ) async -> [Bool] {
        guard !pairs.isEmpty else { return [] }
        let list = pairs.enumerated().map { i, p in
            "Pair \(i + 1):\n  Existing (A): \(p.existing.content)\n  New (B): \(p.newFact)"
        }.joined(separator: "\n\n")
        let contextNote = originalMessage.isEmpty ? "" :
            "The new facts were extracted from this original message: \"\(originalMessage)\"\n\n"
        let session = LanguageModelSession(instructions: """
            For each numbered pair below, decide whether the new fact (B) supersedes the \
            existing fact (A). Answer true when B directly corrects, contradicts, or makes \
            A obsolete — pay special attention when the original message contains correction \
            signals like "actually", "wait", "no", "I meant", or "correction". \
            Answer false when both A and B can genuinely be true simultaneously.
            """)
        let result = try? await session.respond(
            to: "\(contextNote)\(list)\n\nReturn one boolean decision per pair, in the same order.",
            generating: BatchSupersessionDecision.self
        )
        let decisions = result?.content.results ?? []
        guard decisions.count < pairs.count else { return Array(decisions.prefix(pairs.count)) }
        return decisions + Array(repeating: false, count: pairs.count - decisions.count)
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
            var profile = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !Self.isGrounded(profile: profile, facts: profileWorthy.map(\.content)) {
                profile = "About the user: " + profileWorthy.map(\.content).joined(separator: ". ") + "."
            }
            if !profile.isEmpty {
                AppSettings.userProfile = profile
                touchAccessed(profileWorthy)
            }
        } catch {
            // Keep existing profile on failure
        }
    }

    /// A summary far longer than its source facts means the model padded it with
    /// invented detail; callers fall back to the plain facts in that case.
    nonisolated static func isGrounded(profile: String, facts: [String]) -> Bool {
        func words(_ t: String) -> Int { t.split(whereSeparator: \.isWhitespace).count }
        let source = facts.reduce(0) { $0 + words($1) }
        return words(profile) <= max(20, source * 2)
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
            if try await absorbFacts(result.content.facts, into: &known,
                                     fallbackCategory: .preference,
                                     originalMessage: trimmed) {
                await synthesizeProfile()
            }
        } catch { /* best-effort */ }
    }

    // MARK: - 3-band absorption pipeline

    enum Band: Equatable { case reinforce, llmCheck, new }

    /// NLEmbedding scores same-shaped corrections ("works at Acme" → "now works
    /// at Globex") at ~0.92, above the old 0.88 reinforce cutoff, so the new
    /// fact was silently dropped. Only near-verbatim matches are reinforced
    /// automatically; everything from 0.70 up gets the LLM supersession check.
    nonisolated static func band(forSimilarity sim: Float) -> Band {
        if sim >= 0.97 { return .reinforce }
        if sim >= 0.70 { return .llmCheck }
        return .new
    }

    /// Applies deduplication, reinforcement, and supersession to a list of extracted facts,
    /// mutating `knownMemories` as entries are added or removed.
    ///
    /// Uses two passes to collapse N sequential supersession LLM calls into one batch call:
    ///   Pass 1 — embed + classify each fact; apply band-1 reinforcements immediately.
    ///   Pass 2 — single batch LLM call for all band-2 pairs, then apply results and save.
    ///
    /// - Returns: `true` if at least one new fact was persisted (gates profile re-synthesis).
    private func absorbFacts(
        _ facts: [ExtractedFact],
        into knownMemories: inout [Memory],
        fallbackCategory: Memory.Category,
        originalMessage: String = ""
    ) async throws -> Bool {
        struct ScoredFact {
            let content: String
            let category: Memory.Category
            let sim: Float
            let topMatch: Memory?
        }

        // Pass 1: classify. Band-1 reinforcements are applied immediately since they
        // only update `lastAccessedAt` and don't change the memory set seen by later facts.
        var deferred: [ScoredFact] = []
        var band2Indices: [Int] = []

        for fact in facts {
            let trimmed = fact.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let category = Memory.Category(rawValue: fact.category) ?? fallbackCategory
            let (sim, topMatch) = await embedder.mostSimilar(of: trimmed, in: knownMemories)

            if Self.band(forSimilarity: sim) == .reinforce {
                // ── Band 1: near-identical — reinforce in-place, don't duplicate. ──
                if var reinforce = topMatch {
                    reinforce.lastAccessedAt = Date()
                    try? db.saveMemory(&reinforce)
                }
            } else {
                if Self.band(forSimilarity: sim) == .llmCheck && topMatch != nil { band2Indices.append(deferred.count) }
                deferred.append(ScoredFact(content: trimmed, category: category, sim: sim, topMatch: topMatch))
            }
        }

        guard !deferred.isEmpty else { return false }

        // Pass 2a: one batch LLM call for all band-2 pairs.
        var supersessionMap: [Int: Bool] = [:]
        if !band2Indices.isEmpty {
            let pairs = band2Indices.map { i in (newFact: deferred[i].content, existing: deferred[i].topMatch!) }
            let decisions = await batchCheckSupersession(pairs, originalMessage: originalMessage)
            for (offset, idx) in band2Indices.enumerated() {
                supersessionMap[idx] = offset < decisions.count ? decisions[offset] : false
            }
        }

        // Pass 2b: apply supersessions and save all deferred facts.
        var savedAny = false
        for (i, scored) in deferred.enumerated() {
            // ── LLM-check band (0.70–0.97): supersede the old fact if the LLM decided so. ──
            if Self.band(forSimilarity: scored.sim) == .llmCheck, let conflicting = scored.topMatch,
               supersessionMap[i] == true {
                try? db.deleteMemory(conflicting)
                knownMemories.removeAll { $0.id == conflicting.id }
            }

            // ── Band 2 + 3: save the new fact (band-2 after possible old-fact deletion). ──
            var memory = Memory.make(content: scored.content, category: scored.category)
            if let vector = await embedder.embed(scored.content) {
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
