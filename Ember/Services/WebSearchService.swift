import Foundation
import FoundationModels
@preconcurrency import SwiftSoup

/// Provides free web search via DuckDuckGo's no-JavaScript HTML endpoint.
/// No API key required. Queries are sent to DuckDuckGo only when the user
/// has explicitly enabled web search in Settings.
actor WebSearchService {
    static let shared = WebSearchService()

    private let session = URLSession(configuration: .ephemeral)

    // MARK: - General chat search

    /// Conservative gate for regular conversations. Fires only on explicit
    /// research signals (factual questions, current events, etc.).
    /// Synchronous guards keep the disabled path effectively free.
    func searchIfEnabled(_ query: String, maxResults: Int = 5) async -> [RAGResult] {
        guard AppSettings.webSearchEnabled else { return [] }
        guard Self.hasSearchIntent(query) else { return [] }
        return await search(query, maxResults: maxResults)
    }

    // MARK: - Agent search (LLM-routed)

    /// Model-driven search for agent conversations.
    ///
    /// Instead of keyword matching, a lightweight `LanguageModelSession` with the
    /// `SearchDecision` schema decides:
    ///   1. **Does this query need live data?** — the model understands phrasing and
    ///      intent, so "Help me understand what Bitcoin is doing" triggers correctly
    ///      while "Explain what a P/E ratio means" does not.
    ///   2. **What should we search for?** — the model writes a concise, search-engine-
    ///      optimised query rather than forwarding the raw user message verbatim.
    ///
    /// The `agentContext` (agent description) is passed so the model can factor in
    /// what kind of agent is running — a finance agent and a cooking agent react
    /// differently to the same ambiguous message.
    ///
    /// This runs inside an `async let` block alongside other context fetches, so it
    /// adds no sequential latency when other fetches (RAG, calendar) take longer.
    func searchWithIntelligence(
        for userMessage: String,
        agentContext: String,
        maxResults: Int = 5
    ) async -> [RAGResult] {
        do {
            let session = LanguageModelSession(instructions: """
                You are a search-routing assistant for an AI agent. \
                Decide whether the user's message needs a live web search to be answered \
                accurately with up-to-date information.

                SEARCH when the answer depends on real-time or frequently changing data: \
                live prices, stock quotes, today's news headlines, current weather, recent \
                sports results, newly released products or announcements, current events.

                DO NOT SEARCH for: explaining concepts or definitions, historical facts, \
                creative writing, personal tasks, scheduling requests, or anything that is \
                well-covered by stable general knowledge.

                When searching, write a concise, search-engine-optimised query — not a copy \
                of the user's message. Include "today" or the relevant year when temporal \
                context matters.

                Agent focus area: \(agentContext)
                """)
            let result = try await session.respond(
                to: "User message: \"\(userMessage)\"",
                generating: SearchDecision.self
            )
            let decision = result.content
            guard decision.needsSearch, !decision.searchQuery.isEmpty else { return [] }
            return await search(decision.searchQuery, maxResults: maxResults)
        } catch {
            return []  // Best-effort — never block a response on search failure.
        }
    }

    // MARK: - Chat search intent (keyword gate for general chat only)

    nonisolated static func hasSearchIntent(_ query: String) -> Bool {
        let lower = query.lowercased()
        guard lower.split(separator: " ").count >= 3 else { return false }

        let personalPrefixes = ["my ", "i am ", "i'm ", "i have ", "remind me",
                                "remember that", "my name", "about me"]
        if personalPrefixes.contains(where: { lower.hasPrefix($0) }) { return false }

        // "When is my rent due?" starts with a search keyword but is about the
        // user's own data; sending it to the web injects unrelated third-party
        // pages into the answer. Only an explicit request overrides this.
        let explicitSearch = ["search", "look up", "latest", "news", "find out"]
        let mentionsUser = lower.range(of: #"\b(my|mine|our|ours|me)\b"#, options: .regularExpression) != nil
        if mentionsUser && !explicitSearch.contains(where: { lower.contains($0) }) { return false }

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
            "Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15",
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
                score: 1.0,
                isWeb: true
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
