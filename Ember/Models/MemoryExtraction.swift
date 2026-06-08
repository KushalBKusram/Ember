import FoundationModels

// MARK: - Supersession check

/// Used to decide whether a newly extracted fact should replace an existing one.
@Generable
struct SupersessionDecision {
    @Guide(description: """
        true if the new fact (B) supersedes, corrects, or contradicts the existing fact (A) — \
        meaning A is no longer accurate or relevant given B. \
        false if A and B can both be true at the same time, or if they describe different things.
        Examples where true: A="Has a sister named Sophie", B="Does not have a sister named Sophie". \
        Examples where false: A="Prefers Python", B="Also uses C++".
        """)
    var supersedes: Bool
}

// MARK: - Extraction

@Generable
struct ExtractedMemoryList {
    @Guide(
        description: "Factual memories about the user extracted from this exchange. Return an empty array if the exchange has no memorable personal facts about the user.",
        .minimumCount(0),
        .maximumCount(8)
    )
    var facts: [ExtractedFact]
}

@Generable
struct ExtractedFact {
    @Guide(
        description: """
            A concise, specific fact about the user stated neutrally, derived ONLY from what the \
            user themselves wrote. Examples: 'Prefers concise answers', 'Building an iOS app called Ember', \
            'Has a sister named Sophie', 'Felt stressed about a deadline this week'. \
            NEVER include calendar events, appointments, meetings, reminders, or schedule data — \
            those are system-injected and not personal facts about the user.
            """
    )
    var content: String

    @Guide(
        description: """
            Category for this user-stated fact: \
            'preference' — likes, dislikes, communication style, habits; \
            'project' — work or personal projects the user is actively building or pursuing; \
            'relationship' — specific named people or pets the user mentions knowing personally; \
            'episodic' — a recent temporary event or emotional state the user described. \
            NEVER use 'project' for calendar appointments or scheduled interviews.
            """,
        .anyOf(["preference", "project", "relationship", "episodic"])
    )
    var category: String
}
