import FoundationModels

/// Structured result from analysing a user message for scheduling intent.
/// Used by AgentConversationViewModel to auto-create AgentJobs from natural language.
@Generable
struct ScheduleIntentResult {
    @Guide(description: """
        true if the message requests a recurring scheduled task — e.g. contains phrases like
        "every day", "daily", "every morning", "weekly", "every Monday", "at 8am every day",
        "remind me each week", "give me a report every night". false for one-off questions.
        """)
    var hasScheduleIntent: Bool

    @Guide(description: """
        Short descriptive name for this job if hasScheduleIntent is true.
        Examples: "Daily Market Report", "Morning News Digest", "Weekly Portfolio Review".
        Empty string if hasScheduleIntent is false.
        """)
    var jobName: String

    @Guide(description: """
        The core request re-written as a standalone prompt the agent should execute when the
        job fires — WITHOUT the scheduling language. The prompt should be self-contained and
        action-oriented. Examples:
          User said: "give me a brief report of the top-5 market movers every day at 8am"
          Prompt:    "Give me a brief report of today's top 5 market movers with percentage
                      changes and a one-line reason for each move."
        Empty string if hasScheduleIntent is false.
        """)
    var jobPrompt: String

    @Guide(description: """
        Hour of day (0–23) to run the job. Parse from the user's message.
        Examples: "8am" → 8, "9pm" → 21, "noon" → 12. Default to 9 if not mentioned.
        """)
    var scheduleHour: Int

    @Guide(description: """
        Minute (0–59) to run the job. Parse from the user's message.
        Example: "8:30am" → 30. Default to 0 if only an hour is mentioned.
        """)
    var scheduleMinute: Int

    @Guide(description: """
        Comma-separated weekday numbers the job should run on.
        1=Sunday, 2=Monday, 3=Tuesday, 4=Wednesday, 5=Thursday, 6=Friday, 7=Saturday.
        Use empty string for every day (no specific days mentioned).
        Example: "weekdays only" → "2,3,4,5,6". "every Monday" → "2".
        """)
    var scheduleDaysString: String
}
