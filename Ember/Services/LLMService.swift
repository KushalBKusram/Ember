import Foundation
import FoundationModels
import OSLog

#if DEBUG
private let llmLog = Logger(subsystem: "com.kushal.ember", category: "llm-debug")

private func llmPrint(_ items: Any...) {
    let line = items.map { "\($0)" }.joined(separator: " ")
    llmLog.debug("\(line, privacy: .public)")
    print(line)   // also mirrors to Xcode console
}
#endif

// MARK: - LLMError

/// Typed errors surfaced to callers so each case shows the right message.
enum LLMError: LocalizedError {
    case contextExhausted
    case guardrailViolation
    case refusal
    case rateLimited
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .contextExhausted:
            return "Conversation history trimmed — oldest context was removed to continue."
        case .guardrailViolation, .refusal:
            return "I'm not able to respond to that."
        case .rateLimited:
            return "Too many requests — please wait a moment and try again."
        case .modelUnavailable:
            return "Model unavailable. Make sure Apple Intelligence is enabled in Settings."
        }
    }
}

// MARK: - LLMService

actor LLMService {
    static let shared = LLMService()

    // Compressed from ~350 tokens → ~80 tokens.
    // The 4 096-token context window is shared by instructions, every user
    // message, and every response. Verbose policy prose costs real turns.
    private let defaultSystemPrompt = """
        You are Ember, a private on-device AI. Be helpful, direct, and concise. \
        Use markdown when it aids clarity.
        When asked about themselves ("who am I?", "what do I do?"), describe the USER \
        in second person. For all other questions answer factually — never frame \
        general knowledge as a claim about the user.
        Treat injected memory as best-effort; accept corrections plainly. \
        User messages may open with a <context> block — use it, don't quote it back.
        """

    // Caps runaway replies that eat the 4 096-token session budget.
    // 500 tokens ≈ 1 500–2 000 characters — sufficient for chat responses.
    private static let generationOptions: GenerationOptions = {
        var opts = GenerationOptions()
        opts.maximumResponseTokens = 500
        return opts
    }()

    // MARK: - Session cache

    private struct CachedSession {
        let session: LanguageModelSession
        // Keyed on the BASE prompt only — profile changes no longer evict
        // the session and discard its KV cache after every memory extraction.
        let baseFingerprint: String
    }

    private var sessions: [UUID: CachedSession] = [:]
    private var sessionOrder: [UUID] = []
    private let maxSessions = 15

    // MARK: - Session lifecycle

    private func getSession(for id: UUID, base: String, userProfile: String) -> LanguageModelSession {
        if let cached = sessions[id], cached.baseFingerprint == base {
            #if DEBUG
            llmPrint("[LLM] session CACHE HIT  id=\(id.uuidString.prefix(8))")
            #endif
            return cached.session
        }
        #if DEBUG
        let reason = sessions[id] != nil ? "base-prompt changed" : "no cached session"
        llmPrint("[LLM] session CACHE MISS  id=\(id.uuidString.prefix(8))  reason=\(reason)")
        #endif
        while sessionOrder.count >= maxSessions {
            let oldest = sessionOrder.removeFirst()
            sessions.removeValue(forKey: oldest)
        }
        let session = makeSession(base: base, userProfile: userProfile)
        sessions[id] = CachedSession(session: session, baseFingerprint: base)
        sessionOrder.removeAll { $0 == id }
        sessionOrder.append(id)
        return session
    }

    private func makeSession(base: String, userProfile: String) -> LanguageModelSession {
        let instructions = buildStableInstructions(base: base, userProfile: userProfile)
        #if DEBUG
        llmPrint("[LLM] ── instructions (\(instructions.count) chars, ~\(instructions.count / 4) tokens) ──────────────────────")
        llmPrint(instructions)
        llmPrint("[LLM] ────────────────────────────────────────────────────────────────────")
        #endif
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm(promptPrefix: nil)
        return session
    }

    func invalidateSession(for id: UUID) {
        sessions.removeValue(forKey: id)
        sessionOrder.removeAll { $0 == id }
    }

    /// Pre-create and warm the session before the first message arrives.
    /// Call from the conversation view's startObserving / onAppear.
    func prewarmSession(for id: UUID, userProfile: String, systemPromptOverride: String? = nil) {
        _ = getSession(for: id, base: systemPromptOverride ?? defaultSystemPrompt, userProfile: userProfile)
    }

    // MARK: - Context overflow: compact + retry

    /// Keeps the leading instructions entry + the most recent `keepExchanges`
    /// exchange pairs, then rebuilds the session from that condensed transcript.
    private func compactSession(for id: UUID, keepExchanges: Int = 3) -> LanguageModelSession? {
        guard let entry = sessions[id] else { return nil }
        let all = Array(entry.session.transcript)
        var kept: [Transcript.Entry] = []
        if let first = all.first { kept.append(first) }               // instructions — always keep
        kept.append(contentsOf: all.dropFirst().suffix(keepExchanges * 2))
        #if DEBUG
        llmPrint("[LLM] ⚠️ COMPACTING session  id=\(id.uuidString.prefix(8))  kept=\(kept.count)/\(all.count) entries")
        #endif
        let compacted = LanguageModelSession(
            model: SystemLanguageModel.default,
            transcript: Transcript(entries: kept)
        )
        compacted.prewarm(promptPrefix: nil)
        sessions[id] = CachedSession(session: compacted, baseFingerprint: entry.baseFingerprint)
        return compacted
    }

    // MARK: - Error classification
    // Uses LanguageModelSession.GenerationError (iOS 26+).
    // When Xcode 27 becomes stable, add LanguageModelError cases behind #available(iOS 27, *).

    private func isContextOverflow(_ error: Error) -> Bool {
        guard let e = error as? LanguageModelSession.GenerationError,
              case .exceededContextWindowSize = e else { return false }
        return true
    }

    private func classify(_ error: Error) -> LLMError? {
        guard let e = error as? LanguageModelSession.GenerationError else { return nil }
        switch e {
        case .exceededContextWindowSize: return .contextExhausted
        case .guardrailViolation:        return .guardrailViolation
        case .refusal:                   return .refusal
        case .rateLimited:               return .rateLimited
        default:                         return nil
        }
    }

    // MARK: - Streaming (foreground conversations)

    func streamResponse(
        to userMessage: String,
        conversationId: UUID,
        userProfile: String = "",
        ragContext: [RAGResult] = [],
        scheduleContext: String = "",
        relevantMemories: [String] = [],
        systemPromptOverride: String? = nil,
        systemNote: String = ""
    ) -> AsyncThrowingStream<String, Error> {
        let base = systemPromptOverride ?? defaultSystemPrompt
        let contextBlock = buildContextBlock(
            ragContext: ragContext,
            scheduleContext: scheduleContext,
            relevantMemories: relevantMemories,
            systemNote: systemNote
        )
        let fullMessage = contextBlock.isEmpty ? userMessage : "\(contextBlock)\n\n\(userMessage)"

        #if DEBUG
        llmPrint("[LLM] ══════════════════════════════════════════════════════════════════════")
        llmPrint("[LLM] SEND  id=\(conversationId.uuidString.prefix(8))  maxTokens=500")
        llmPrint("[LLM] context block (\(contextBlock.count) chars):")
        llmPrint(contextBlock.isEmpty ? "(none)" : contextBlock)
        llmPrint("[LLM] full message to model (\(fullMessage.count) chars, ~\(fullMessage.count / 4) tokens):")
        llmPrint(fullMessage)
        llmPrint("[LLM] ══════════════════════════════════════════════════════════════════════")
        #endif

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = self.getSession(for: conversationId, base: base, userProfile: userProfile)
                    let stream = session.streamResponse(to: fullMessage, options: Self.generationOptions)
                    for try await partial in stream { continuation.yield(partial.content) }
                    continuation.finish()
                } catch {
                    guard !Task.isCancelled else { continuation.finish(); return }
                    if self.isContextOverflow(error) {
                        // Compact history and retry once before surfacing the error.
                        if let compacted = self.compactSession(for: conversationId) {
                            do {
                                let stream2 = compacted.streamResponse(to: fullMessage, options: Self.generationOptions)
                                for try await partial in stream2 { continuation.yield(partial.content) }
                                continuation.finish()
                            } catch {
                                guard !Task.isCancelled else { continuation.finish(); return }
                                continuation.finish(throwing: self.classify(error) ?? LLMError.modelUnavailable)
                            }
                        } else {
                            continuation.finish(throwing: LLMError.contextExhausted)
                        }
                    } else {
                        continuation.finish(throwing: self.classify(error) ?? error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Non-streaming (background jobs)

    /// Single-shot variant used by BackgroundJobService.
    /// History capped at suffix(8) — suffix(20) exceeded the 4 096-token window
    /// on conversations longer than ~15 turns.
    func respond(
        to userMessage: String,
        history: [Message],
        userProfile: String = "",
        ragContext: [RAGResult] = [],
        scheduleContext: String = "",
        relevantMemories: [String] = [],
        systemPromptOverride: String? = nil,
        systemNote: String = ""
    ) async throws -> String {
        let instructions = buildFullInstructions(
            base: systemPromptOverride ?? defaultSystemPrompt,
            history: history,
            userProfile: userProfile,
            ragContext: ragContext,
            scheduleContext: scheduleContext,
            relevantMemories: relevantMemories,
            systemNote: systemNote
        )
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: userMessage, options: Self.generationOptions)
            return response.content
        } catch {
            throw classify(error) ?? error
        }
    }

    // MARK: - Instruction builders

    private func buildStableInstructions(base: String, userProfile: String) -> String {
        guard !userProfile.isEmpty else { return base }
        return """
            \(base)

            --- About the USER (not you — you are Ember) ---
            \(userProfile)
            --- End of profile ---
            Refer to the user in second person. If they correct a fact, acknowledge briefly and move on.
            """
    }

    private func buildContextBlock(
        ragContext: [RAGResult],
        scheduleContext: String,
        relevantMemories: [String],
        systemNote: String
    ) -> String {
        var parts: [String] = []
        if !relevantMemories.isEmpty {
            parts.append("Facts from memory:\n" + relevantMemories.map { "• \($0)" }.joined(separator: "\n"))
        }
        if !scheduleContext.isEmpty {
            parts.append("Calendar & reminders:\n\(scheduleContext)")
        }
        let personal = ragContext.filter { !$0.isWeb }
        if !personal.isEmpty {
            parts.append("User documents:\n" + personal.map { "[\($0.sourceTitle)] \($0.content)" }.joined(separator: "\n\n"))
        }
        let web = ragContext.filter { $0.isWeb }
        if !web.isEmpty {
            parts.append("Web results (verify before acting):\n" + web.map { "[\($0.sourceTitle)] \($0.content)" }.joined(separator: "\n\n"))
        }
        if !systemNote.isEmpty {
            parts.append("Action completed — acknowledge in response: \(systemNote)")
        }
        guard !parts.isEmpty else { return "" }
        return "<context>\n\(parts.joined(separator: "\n\n"))\n</context>"
    }

    private func buildFullInstructions(
        base: String,
        history: [Message],
        userProfile: String,
        ragContext: [RAGResult],
        scheduleContext: String,
        relevantMemories: [String],
        systemNote: String
    ) -> String {
        var s = buildStableInstructions(base: base, userProfile: userProfile)
        if !relevantMemories.isEmpty {
            s += "\n\n--- Memory ---\n" + relevantMemories.map { "• \($0)" }.joined(separator: "\n")
        }
        if !scheduleContext.isEmpty {
            s += "\n\n--- Calendar ---\n\(scheduleContext)"
        }
        let personal = ragContext.filter { !$0.isWeb }
        if !personal.isEmpty {
            s += "\n\n--- Documents ---\n" + personal.map { "[\($0.sourceTitle)] \($0.content)" }.joined(separator: "\n\n")
        }
        let web = ragContext.filter { $0.isWeb }
        if !web.isEmpty {
            s += "\n\n--- Web results ---\n" + web.map { "[\($0.sourceTitle)] \($0.content)" }.joined(separator: "\n\n")
        }
        if !history.isEmpty {
            // Explicit String concatenation (not interpolation) avoids Swift resolving
            // these literals as GRDB.SQL via Message's ExpressibleByStringInterpolation.
            let lines: String = history.suffix(8).map { (msg: Message) -> String in
                let tag: String = msg.role == .user ? "<user>" : "<ember>"
                let end: String = msg.role == .user ? "</user>" : "</ember>"
                return tag + msg.content + end
            }.joined(separator: "\n")
            s += "\n\n--- History ---\n\(lines)"
        }
        if !systemNote.isEmpty {
            s += "\n\n--- Action ---\n\(systemNote)"
        }
        return s
    }
}

// MARK: - Model availability

extension LLMService {
    nonisolated var isModelAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }
}
