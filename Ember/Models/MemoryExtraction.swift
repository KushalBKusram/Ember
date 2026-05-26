import FoundationModels

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
        description: "A concise, specific fact about the user stated neutrally. Examples: 'Prefers concise answers over lengthy explanations', 'Building an iOS app called Ember', 'Has a sister named Sophie', 'Felt stressed about a project deadline this week'. Skip trivial exchanges like simple factual questions."
    )
    var content: String

    @Guide(
        description: "Category — 'preference': likes, dislikes, communication style, habits; 'project': work the user is doing; 'relationship': specific people or pets the user mentions; 'episodic': recent temporary events or emotional states.",
        .anyOf(["preference", "project", "relationship", "episodic"])
    )
    var category: String
}
