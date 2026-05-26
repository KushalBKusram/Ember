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
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let instructions = buildInstructions(
            base: systemPrompt ?? defaultSystemPrompt,
            history: history
        )
        let prompt = userMessage

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let stream = session.streamResponse(to: prompt)
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

    private func buildInstructions(base: String, history: [Message]) -> String {
        guard !history.isEmpty else { return base }

        let recentHistory = history.suffix(20)
        let transcript = recentHistory.map { msg in
            let speaker = msg.role == .user ? "User" : "Ember"
            return "\(speaker): \(msg.content)"
        }.joined(separator: "\n\n")

        return """
            \(base)

            --- Previous conversation context (do not repeat or acknowledge this block) ---
            \(transcript)
            --- End of context ---
            """
    }
}

// MARK: - Model availability

extension LLMService {
    nonisolated func isAvailable() async -> Bool {
        // SystemLanguageModel.default.isAvailable may be the correct API
        // Verify against final Foundation Models docs on device
        return SystemLanguageModel.default.isAvailable
    }
}
