import FoundationModels

// MARK: - Search routing

/// Structured decision from the LLM search router used in agent conversations.
/// The model decides *whether* a live web search is needed and, if so, writes
/// an optimised search-engine query rather than forwarding the raw user message.
@Generable
struct SearchDecision {
    @Guide(description: """
        true when the query needs real-time or frequently changing data to be answered
        accurately — e.g. live stock prices, today's news headlines, current weather,
        recent sports results, newly announced products or events.
        false for conceptual explanations, historical facts, creative writing, personal
        tasks, scheduling requests, or anything well-covered by general knowledge.
        """)
    var needsSearch: Bool

    @Guide(description: """
        When needsSearch is true: a concise, search-engine-optimised query.
        Prefer specific terms over vague phrases. Include temporal context when relevant.
        Good examples: "AAPL stock price today", "BTC USD live price", "top market movers today",
        "Fed interest rate decision 2025", "Premier League standings June 2025".
        Empty string when needsSearch is false.
        """)
    var searchQuery: String
}

// MARK: - Schedule intent

/// Structured result from analysing a user message for scheduling intent.
/// Used by AgentConversationViewModel to auto-create AgentJobs from natural language.
/// Supports both clock-time schedules ("every day at 8am") and interval schedules
/// ("every 15 minutes", "every hour").
@Generable
struct ScheduleIntentResult {
    @Guide(description: """
        true if the message requests a recurring scheduled task — e.g. phrases like
        "every day", "daily", "every morning at 8am", "weekly on Mon",
        "every 15 minutes", "every hour", "every 2 hours", "every 30 min".
        false for one-off questions or single requests.
        """)
    var hasScheduleIntent: Bool

    @Guide(description: """
        Short descriptive name for this job if hasScheduleIntent is true.
        Examples: "Daily Market Report", "Morning News Digest", "Hourly Price Check", "15-Min Update".
        Empty string if hasScheduleIntent is false.
        """)
    var jobName: String

    @Guide(description: """
        The core request re-written as a standalone prompt WITHOUT scheduling language.
        Must be self-contained and action-oriented.
        Example: "give me a brief report of the top-5 market movers every day at 8am"
                 → "Give me a brief report of today's top 5 market movers with percentage
                    changes and a one-line reason for each move."
        Empty string if hasScheduleIntent is false.
        """)
    var jobPrompt: String

    @Guide(description: """
        true when the schedule is interval-based ("every 15 minutes", "every hour",
        "every 2 hours") rather than a specific clock time ("at 8am", "every morning").
        false for clock-time schedules.
        """)
    var isIntervalBased: Bool

    @Guide(description: """
        Only used when isIntervalBased is true.
        The repeat interval in minutes (minimum 15).
        Examples: "every 15 minutes" → 15, "every 30 minutes" → 30,
        "every hour" → 60, "every 2 hours" → 120, "every 4 hours" → 240.
        Use 0 when isIntervalBased is false.
        """)
    var intervalMinutes: Int

    @Guide(description: """
        Only used when isIntervalBased is false.
        Hour of day (0-23). Parse from message. Default to 9 if not mentioned.
        """)
    var scheduleHour: Int

    @Guide(description: """
        Only used when isIntervalBased is false.
        Minute (0-59). Parse from message. Default to 0 if only an hour is given.
        """)
    var scheduleMinute: Int

    @Guide(description: """
        Only used when isIntervalBased is false.
        Comma-separated weekday numbers. 1=Sun 2=Mon 3=Tue 4=Wed 5=Thu 6=Fri 7=Sat.
        Empty string means every day.
        """)
    var scheduleDaysString: String
}
