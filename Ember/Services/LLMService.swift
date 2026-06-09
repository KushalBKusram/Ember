import Foundation
import FoundationModels

actor LLMService {
    static let shared = LLMService()

    private let defaultSystemPrompt = """
        You are Ember — a private, on-device AI assistant. You are the assistant. \
        The person messaging you is the user. These are two different identities. \
        Everything stays on-device. Be helpful, direct, and concise. \
        Use markdown formatting when it aids clarity.

        Identity rules — never break these:
        • You are Ember. The user's name and personal details will be provided below — \
          those describe the USER, not you.
        • When answering "who am I?" or similar, describe the USER in second person \
          ("You are…", "You work at…") — never claim their identity as your own.
        • Never say "I am [user's name]" or describe yourself using the user's job, \
          skills, or relationships.

        Memory correction rules:
        • Injected memory facts are your best current understanding — they can be wrong.
        • When the user contradicts something you stated from memory, it is a factual \
          correction. Acknowledge it briefly and move on.
        • Never express sympathy for a factual correction or offer help based on a \
          wrong premise. Never argue.
        """

    func streamResponse(
        to userMessage: String,
        history: [Message],
        userProfile: String = "",
        ragContext: [RAGResult] = [],
        scheduleContext: String = "",
        relevantMemories: [String] = [],
        systemPromptOverride: String? = nil,
        systemNote: String = ""
    ) -> AsyncThrowingStream<String, Error> {
        let instructions = buildInstructions(
            base: systemPromptOverride ?? defaultSystemPrompt,
            history: history,
            userProfile: userProfile,
            ragContext: ragContext,
            scheduleContext: scheduleContext,
            relevantMemories: relevantMemories,
            systemNote: systemNote
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let stream = session.streamResponse(to: userMessage)
                    for try await partial in stream {
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func buildInstructions(
        base: String,
        history: [Message],
        userProfile: String,
        ragContext: [RAGResult],
        scheduleContext: String,
        relevantMemories: [String],
        systemNote: String = ""
    ) -> String {
        var sections = [base]

        if !userProfile.isEmpty {
            sections.append("""

                --- About the USER you are talking to (not about you — you are Ember) ---
                \(userProfile)
                --- End of user profile ---
                This describes the person messaging you. Use it to personalise your tone. \
                Refer to the user in second person ("you are…", "you have…") when discussing \
                their profile. Never use this to describe yourself. \
                If the user corrects anything, acknowledge briefly and move on.
                """)
        }

        // Specific memories ranked by relevance to the current message.
        // These are raw facts retrieved at query time — more precise than the
        // synthesised profile paragraph, which compresses everything to 2–4 sentences.
        // Use these when the user asks about specific details of their personal life.
        if !relevantMemories.isEmpty {
            let lines = relevantMemories.map { "• \($0)" }.joined(separator: "\n")
            sections.append("""

                --- Facts from memory most relevant to this message (may have errors) ---
                \(lines)
                --- End of facts ---
                Use these to answer specific questions. They are ranked by relevance. \
                If the user disputes any fact here, acknowledge the correction plainly and move on — \
                do not treat it as emotional news or offer help based on the incorrect premise.
                """)
        }

        if !scheduleContext.isEmpty {
            sections.append("""

                --- Live calendar & reminders ---
                \(scheduleContext)
                --- End of calendar ---
                Rules for responding about the user's schedule:
                - Present events as a simple bullet list of titles only. Do NOT include times, \
                locations, or notes in your answer unless the user explicitly asks about a specific event.
                - Times, locations, and other details are in the "Event details" section above — \
                use that section only for follow-up questions about a particular event.
                - Keep the list in the order shown (already chronological). Do not reformat or expand it.
                - Do not infer the user's availability or work status from event titles. \
                A holiday name does not mean the user has the day off.
                - Do not fabricate events not present in this data.
                """)
        }

        // Split RAG results into personal documents and live web results so
        // the model receives different instructions for each: personal data is
        // the user's own ground truth; web results are public and may be imprecise.
        let personalContext = ragContext.filter { !$0.isWeb }
        let webContext      = ragContext.filter { $0.isWeb }

        if !personalContext.isEmpty {
            let block = personalContext.map { "[\($0.sourceTitle)] \($0.content)" }
                .joined(separator: "\n\n")
            sections.append("""

                --- Personal context from the user's own documents ---
                \(block)
                --- End of personal context ---
                This is the user's own data. Treat it as accurate and reference \
                specific details from it directly in your answer. Do not mention \
                the source unless asked.
                """)
        }

        if !webContext.isEmpty {
            let block = webContext.map { "[\($0.sourceTitle)] \($0.content)" }
                .joined(separator: "\n\n")
            sections.append("""

                --- Web search results ---
                \(block)
                --- End of web results ---
                These snippets come from a DuckDuckGo search. They are cached page \
                excerpts, NOT real-time API data. Critical rules:
                - For prices, fares, stock quotes, or any numeric data: treat values \
                  as approximate and potentially stale. Always tell the user the figures \
                  are indicative and they should verify on the source site before acting.
                - Do not present numbers (prices, rates, scores) as exact or current facts.
                - Summarise the overall picture; do not quote specific figures as authoritative.
                - Do not mention that a search was performed unless the user asks.
                """)
        }

        if !history.isEmpty {
            // Explicit String types + concatenation (not interpolation) to prevent
            // Swift's bidirectional type inference from resolving these literals as
            // GRDB.SQL — which happens because Message.swift imports GRDB and exposes
            // SQL's ExpressibleByStringInterpolation conformance to the whole module.
            let transcript: String = history.suffix(20).map { (msg: Message) -> String in
                let tag: String = msg.role == .user ? "<user>" : "<ember>"
                let end: String = msg.role == .user ? "</user>" : "</ember>"
                return tag + msg.content + end
            }.joined(separator: "\n")
            sections.append("""

                --- Conversation history — for context only ---
                \(transcript)
                --- End of history ---
                Use the above purely for context. Do not repeat, quote, or echo any part \
                of it in your response.
                """)
        }

        if !systemNote.isEmpty {
            sections.append("""

                --- Completed action (acknowledge in your response) ---
                \(systemNote)
                --- End of action ---
                """)
        }

        let combined = sections.joined(separator: "\n")

        #if DEBUG
        print("""

        ╔══ EMBER SYSTEM PROMPT ═══════════════════════════════════════════╗
        \(combined)
        ╚══════════════════════════════════════════════════════════════════╝

        """)
        #endif

        return combined
    }
}

// MARK: - Model availability

extension LLMService {
    nonisolated var isModelAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }
}
