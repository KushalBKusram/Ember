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
