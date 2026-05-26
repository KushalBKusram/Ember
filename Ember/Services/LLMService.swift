import Foundation
import FoundationModels

actor LLMService {
    static let shared = LLMService()

    private let defaultSystemPrompt = """
        You are Ember, a personal AI assistant that runs entirely on this device. \
        Everything you know about the user stays private — no data ever leaves their iPhone. \
        Be helpful, direct, and concise. Format responses with markdown when it aids clarity.
        """

    func streamResponse(
        to userMessage: String,
        history: [Message],
        memories: [Memory] = [],
        ragContext: [RAGResult] = [],
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let instructions = buildInstructions(
            base: systemPrompt ?? defaultSystemPrompt,
            history: history,
            memories: memories,
            ragContext: ragContext
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
        memories: [Memory],
        ragContext: [RAGResult]
    ) -> String {
        var sections = [base]

        if !memories.isEmpty {
            let memBlock = memories
                .filter { $0.isEnabled }
                .map { "[\($0.category.rawValue)] \($0.content)" }
                .joined(separator: "\n")
            if !memBlock.isEmpty {
                sections.append("""

                    --- What Ember remembers about you (use naturally, don't announce) ---
                    \(memBlock)
                    --- End of memories ---
                    """)
            }
        }

        if !ragContext.isEmpty {
            let ragBlock = ragContext.map { result in
                "[\(result.sourceTitle)] \(result.content)"
            }.joined(separator: "\n\n")
            sections.append("""

                --- Personal context retrieved from the user's own data ---
                \(ragBlock)
                --- End of personal context ---
                This is the user's real, current data. Treat it as ground truth and reference specific details \
                from it naturally in your answer. Do not say where the information came from unless asked.
                """)
        }

        if !history.isEmpty {
            let transcript = history.suffix(20).map { msg in
                "\(msg.role == .user ? "User" : "Ember"): \(msg.content)"
            }.joined(separator: "\n\n")
            sections.append("""

                --- Previous conversation context (do not repeat or acknowledge this block) ---
                \(transcript)
                --- End of context ---
                """)
        }

        return sections.joined(separator: "\n")
    }
}

// MARK: - Model availability

extension LLMService {
    nonisolated var isModelAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }
}
