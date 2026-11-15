import Foundation

struct RAGResult: Sendable {
    let content: String
    let sourceTitle: String
    let sourceIcon: String
    let score: Float
    /// `true` for results from a live web search; `false` for the user's own
    /// documents, calendar data, or other personal context. Used by LLMService
    /// to present the two source types under different headings and instructions.
    let isWeb: Bool

    init(content: String, sourceTitle: String, sourceIcon: String, score: Float, isWeb: Bool = false) {
        self.content = content
        self.sourceTitle = sourceTitle
        self.sourceIcon = sourceIcon
        self.score = score
        self.isWeb = isWeb
    }
}

extension Array where Element == RAGResult {
    /// A general-knowledge question that triggered a web search should be
    /// answered from the web alone: otherwise any personal note that happens to
    /// score above the relevance floor is injected and cited next to it, which
    /// reads as the note having informed an answer it had nothing to do with.
    /// Web results fetched for URLs the user pasted are kept either way.
    func reconciled(withWebSearch webResults: [RAGResult]) -> [RAGResult] {
        guard !webResults.isEmpty else { return self }
        return filter(\.isWeb) + webResults
    }
}
