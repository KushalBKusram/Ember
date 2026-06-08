import Foundation
@preconcurrency import SwiftSoup

/// Provides free web search via DuckDuckGo's no-JavaScript HTML endpoint.
/// No API key required. Queries are sent to DuckDuckGo only when the user
/// has explicitly enabled web search in Settings.
actor WebSearchService {
    static let shared = WebSearchService()

    private let session = URLSession(configuration: .ephemeral)

    // MARK: - Public interface

    /// Returns search results when web search is enabled AND the query has clear
    /// research intent. Designed for `async let` parallelism — both guards are
    /// synchronous so the disabled/non-search path is effectively free.
    func searchIfEnabled(_ query: String, maxResults: Int = 5) async -> [RAGResult] {
        guard AppSettings.webSearchEnabled else { return [] }
        guard hasSearchIntent(query) else { return [] }
        return await search(query, maxResults: maxResults)
    }

    // MARK: - Search intent detection

    /// Returns true only when the query is clearly asking for external information
    /// that the model cannot answer from memory, calendar, or local documents.
    ///
    /// Intentionally conservative: personal questions ("my name is…", "remind me…"),
    /// short conversational messages, and anything already handled by calendar or
    /// memory should NOT trigger a web search.
    private func hasSearchIntent(_ query: String) -> Bool {
        let lower = query.lowercased()
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines)

        // Too short to be a research question.
        guard trimmed.split(separator: " ").count >= 3 else { return false }

        // Clearly personal — about the user themselves, not the world.
        let personalPrefixes = ["my ", "i am ", "i'm ", "i have ", "remind me",
                                "remember that", "my name", "about me"]
        if personalPrefixes.contains(where: { lower.hasPrefix($0) }) { return false }

        // Explicit research signals.
        let researchKeywords: [String] = [
            // Question words aimed at facts
            "who is", "who was", "who are", "who were",
            "what is", "what are", "what was", "what were",
            "when is", "when was", "when did", "when does",
            "where is", "where was", "where are",
            "how to", "how do", "how does", "how did", "how much", "how many",
            "why is", "why does", "why did", "why are",
            // Current-event signals
            "latest", "recent", "news", "current", "today's", "right now",
            "just announced", "just released", "breaking",
            // Explicit search intent
            "search", "look up", "find out", "google", "tell me about",
            // Common factual lookups
            "price of", "cost of", "weather", "temperature",
            "definition of", "meaning of", "explain",
            "tutorial", "how-to", "guide",
        ]
        return researchKeywords.contains { lower.contains($0) }
    }

    // MARK: - Core search

    private func search(_ query: String, maxResults: Int) async -> [RAGResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return []
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        // Required so NetworkGuard (DEBUG) doesn't block this outbound request.
        request.setValue("1", forHTTPHeaderField: "X-Ember-Fetch")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return []
        }

        return parseResults(html, maxResults: maxResults)
    }

    // MARK: - HTML parsing

    private func parseResults(_ html: String, maxResults: Int) -> [RAGResult] {
        guard let doc = try? SwiftSoup.parse(html) else { return [] }

        var results: [RAGResult] = []
        let elements = (try? doc.select(".result__body").array()) ?? []

        for element in elements.prefix(maxResults) {
            guard let titleEl  = try? element.select(".result__a").first(),
                  let title    = try? titleEl.text(),
                  !title.isEmpty else { continue }

            let snippet = (try? element.select(".result__snippet").first()?.text()) ?? ""
            let href    = (try? titleEl.attr("href")) ?? ""
            let host    = extractURL(from: href)?.host ?? "Web"

            // Use snippet if available, otherwise fall back to the title.
            // Both contain enough signal for the model to answer common fact
            // questions without fetching the full page.
            let content = snippet.isEmpty ? title : "\(title) — \(snippet)"
            results.append(RAGResult(
                content: content,
                sourceTitle: host,
                sourceIcon: "globe.americas",
                score: 1.0
            ))
        }

        return results
    }

    // MARK: - URL helpers

    /// DuckDuckGo wraps result URLs as redirect links:
    /// "//duckduckgo.com/l/?uddg=https%3A%2F%2Factual.com%2Fpage&rut=..."
    /// Extract and decode the `uddg` parameter to get the real URL.
    private func extractURL(from href: String) -> URL? {
        let full = href.hasPrefix("//") ? "https:" + href : href
        guard let components = URLComponents(string: full),
              let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value else {
            return URL(string: full)
        }
        return URL(string: uddg)
    }
}
