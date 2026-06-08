import Foundation
@preconcurrency import SwiftSoup

/// Provides free web search via DuckDuckGo's no-JavaScript HTML endpoint.
/// No API key required. Queries are sent to DuckDuckGo only when the user
/// has explicitly enabled web search in Settings.
actor WebSearchService {
    static let shared = WebSearchService()

    private let session = URLSession(configuration: .ephemeral)

    // MARK: - Public interface

    /// Conservative gate for general chat — only fires on explicit research signals.
    /// Designed for `async let` parallelism — both guards are synchronous so the
    /// disabled/non-search path is effectively free.
    func searchIfEnabled(_ query: String, maxResults: Int = 5) async -> [RAGResult] {
        guard AppSettings.webSearchEnabled else { return [] }
        guard hasSearchIntent(query) else { return [] }
        return await search(query, maxResults: maxResults)
    }

    /// Liberal gate for agent conversations. Strips scheduling language first
    /// ("every day at 8am" → core query), then searches whenever the core query
    /// could benefit from real-time data. Never uses cached/training knowledge
    /// for financial, market, news, or weather queries.
    func searchForAgent(_ query: String, maxResults: Int = 5) async -> [RAGResult] {
        let coreQuery = stripSchedulingLanguage(query)
        guard hasRealTimeIntent(coreQuery) else { return [] }
        return await search(coreQuery, maxResults: maxResults)
    }

    // MARK: - Search intent detection

    /// Conservative gate — for general chat.
    private func hasSearchIntent(_ query: String) -> Bool {
        let lower = query.lowercased()
        guard lower.split(separator: " ").count >= 3 else { return false }

        let personalPrefixes = ["my ", "i am ", "i'm ", "i have ", "remind me",
                                "remember that", "my name", "about me"]
        if personalPrefixes.contains(where: { lower.hasPrefix($0) }) { return false }

        let keywords: [String] = [
            "who is", "who was", "who are", "what is", "what are", "what was",
            "when is", "when was", "when did", "where is", "where are",
            "how to", "how do", "how does", "how much", "how many",
            "why is", "why does", "why did",
            "latest", "recent", "news", "current", "today's", "right now",
            "just announced", "just released", "breaking",
            "search", "look up", "find out", "tell me about",
            "price of", "cost of", "weather", "temperature",
            "definition of", "meaning of", "explain", "tutorial",
        ]
        return keywords.contains { lower.contains($0) }
    }

    /// Liberal gate — for agent conversations. Triggers on any query that
    /// likely requires real-time data: financial, market, news, weather, sports.
    func hasRealTimeIntent(_ query: String) -> Bool {
        let lower = query.lowercased()
        guard lower.split(separator: " ").count >= 2 else { return false }

        // Pure personal intent → no search.
        let personalPrefixes = ["my ", "i am ", "i'm ", "i feel ", "i want to ", "help me "]
        if personalPrefixes.contains(where: { lower.hasPrefix($0) }) { return false }

        let realTimeTerms: [String] = [
            // Finance & markets
            "market", "stock", "share", "mover", "gainer", "loser", "ticker",
            "nasdaq", "s&p", "dow", "nyse", "ftse", "nikkei", "crypto",
            "bitcoin", "ethereum", "price", "trading", "earnings", "ipo",
            "inflation", "gdp", "interest rate", "fed", "fed rate",
            "portfolio", "invest", "dividend", "index", "etf",
            // News & current events
            "news", "latest", "today", "current", "right now", "breaking",
            "headline", "report", "update", "just", "recently", "announced",
            "happening", "trending",
            // Weather
            "weather", "forecast", "temperature", "rain", "snow", "humidity",
            // Sports
            "score", "game", "match", "result", "standings", "league",
            // General real-time
            "how much is", "price of", "value of", "rate of",
            "who won", "who is leading",
        ]
        return realTimeTerms.contains { lower.contains($0) }
    }

    // MARK: - Scheduling language stripping

    /// Removes scheduling phrases from a query so the core information request
    /// can be searched. "Top 5 market movers every day at 8am" → "Top 5 market movers".
    func stripSchedulingLanguage(_ query: String) -> String {
        var result = query

        // Remove time expressions: "at 8am", "at 9:30 PM", etc.
        result = result.replacingOccurrences(
            of: #"\bat\s+\d{1,2}(:\d{2})?\s*(am|pm|AM|PM)?\b"#,
            with: " ", options: .regularExpression
        )
        // Remove recurrence: "every day", "every morning", "every weekday", "daily", "weekly"
        result = result.replacingOccurrences(
            of: #"\b(every\s+(day|morning|night|evening|weekday|weekend|week|month|\w+day)|daily|weekly|monthly)\b"#,
            with: " ", options: [.regularExpression, .caseInsensitive]
        )
        // Remove "can you" / "could you" / "please" filler
        result = result.replacingOccurrences(
            of: #"^(can you|could you|please|i'd like you to|i want you to)\s+"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        // Collapse whitespace
        result = result
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return result.isEmpty ? query : result
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
