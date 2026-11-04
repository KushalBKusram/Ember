import Testing
import Foundation
@testable import Ember

/// Measures actual capability of the on-device semantic layer (NLEmbedding +
/// cosine similarity) against a small hand-labeled dataset, rather than just
/// checking plumbing. Runs entirely in the simulator — no Apple Intelligence
/// hardware required, since NLEmbedding is unrelated to FoundationModels.
///
/// These are reporting evals, not strict gates: thresholds are loose sanity
/// floors. The real signal is the printed numbers, which should be copied
/// into the release-readiness writeup.
@Suite("Capability eval — semantic retrieval")
struct SemanticRetrievalEvalTests {

    private static let corpus: [String] = [
        "The rent payment is due on the 1st of every month.",                         // 0
        "My dentist appointment is scheduled for the second week of March.",          // 1
        "I prefer dark roast coffee over light roast in the mornings.",               // 2
        "Project Ember uses Swift 6 with strict concurrency checking throughout.",    // 3
        "My sister Priya is visiting from Chicago next weekend.",                     // 4
        "The car's oil change is overdue by about two thousand miles.",               // 5
        "I'm allergic to shellfish, especially shrimp and crab.",                     // 6
        "The quarterly tax filing deadline is the fifteenth of the month.",           // 7
        "My gym membership renews automatically every January.",                      // 8
        "I switched from Android to iPhone last year for better integration.",        // 9
        "The team stand-up meeting happens every weekday morning at nine.",           // 10
        "My passport expires next summer and needs to be renewed.",                  // 11
    ]

    private static let queries: [(text: String, expected: Int)] = [
        ("When do I need to pay my landlord?", 0),
        ("When is my next trip to the dentist?", 1),
        ("What kind of coffee do I like?", 2),
        ("What concurrency model does the Ember codebase use?", 3),
        ("Who is coming to visit me soon?", 4),
        ("Does my car need maintenance?", 5),
        ("What foods should I avoid eating?", 6),
        ("When are my taxes due?", 7),
        ("Does my fitness membership auto-renew?", 8),
        ("What phone do I currently use?", 9),
        ("What time does the daily team meeting start?", 10),
        ("Is my travel document going to expire soon?", 11),
    ]

    @Test("Top-1 semantic match accuracy over a 12-query labeled set")
    func top1Accuracy() async {
        let embed = EmbeddingService.shared
        var docVectors: [[Float]] = []
        for doc in Self.corpus {
            guard let v = await embed.embed(doc) else {
                Issue.record("Failed to embed corpus doc: \(doc)")
                return
            }
            docVectors.append(v)
        }

        var hits = 0
        var misses: [String] = []
        for (query, expected) in Self.queries {
            guard let qv = await embed.embed(query) else {
                Issue.record("Failed to embed query: \(query)")
                continue
            }
            let scored = docVectors.enumerated().map { idx, dv in
                (idx, EmbeddingService.cosineSimilarity(qv, dv))
            }
            let best = scored.max { $0.1 < $1.1 }
            if best?.0 == expected {
                hits += 1
            } else {
                misses.append("\"\(query)\" → got [\(best?.0 ?? -1)] \(Self.corpus[safe: best?.0 ?? -1] ?? "?"), expected [\(expected)] \(Self.corpus[expected])")
            }
        }

        let accuracy = Double(hits) / Double(Self.queries.count)
        print("[EVAL] Semantic retrieval top-1 accuracy: \(hits)/\(Self.queries.count) (\(Int(accuracy * 100))%)")
        for miss in misses { print("[EVAL]   miss: \(miss)") }

        // Sanity floor, not a quality bar — catches a broken embedding pipeline,
        // not a mediocre one. The real number belongs in the writeup.
        #expect(accuracy >= 0.5)
    }
}

@Suite("Capability eval — memory dedup/supersession banding")
struct MemoryBandingEvalTests {

    private enum Relationship { case duplicate, correction, unrelated }

    private static let pairs: [(a: String, b: String, rel: Relationship)] = [
        ("I prefer dark roast coffee in the mornings.", "I like dark roast coffee for breakfast.", .duplicate),
        ("My favorite color is blue.", "Blue has always been my favorite color.", .duplicate),
        ("I work at Acme Corp as a software engineer.", "I now work at Globex Corp as a software engineer.", .correction),
        ("I live in Seattle.", "I just moved to Austin.", .correction),
        ("I prefer dark roast coffee in the mornings.", "My passport expires next summer.", .unrelated),
        ("I work at Acme Corp as a software engineer.", "I'm allergic to shellfish.", .unrelated),
    ]

    @Test("Duplicate and correction pairs score above unrelated pairs")
    func rankOrdering() async {
        let embed = EmbeddingService.shared
        var scores: [(Relationship, Float, String)] = []
        for pair in Self.pairs {
            guard let va = await embed.embed(pair.a), let vb = await embed.embed(pair.b) else {
                Issue.record("Failed to embed pair: \(pair.a) / \(pair.b)")
                continue
            }
            let score = EmbeddingService.cosineSimilarity(va, vb)
            scores.append((pair.rel, score, "\"\(pair.a)\" ↔ \"\(pair.b)\""))
        }

        for (rel, score, desc) in scores {
            let band = score >= 0.88 ? "REINFORCE(≥0.88)" : score >= 0.70 ? "SUPERSESSION-CHECK(0.70-0.87)" : "NEW(<0.70)"
            print("[EVAL] \(rel) score=\(String(format: "%.3f", score)) band=\(band)  \(desc)")
        }

        let avg: (Relationship) -> Float = { rel in
            let matching = scores.filter { $0.0 == rel }.map(\.1)
            return matching.isEmpty ? 0 : matching.reduce(0, +) / Float(matching.count)
        }
        let dup = avg(.duplicate), corr = avg(.correction), unrel = avg(.unrelated)
        print("[EVAL] averages — duplicate=\(dup) correction=\(corr) unrelated=\(unrel)")

        #expect(dup > unrel)
        #expect(corr > unrel)

        // The real correctness property: a correction must never score high enough
        // to be silently treated as a duplicate and reinforced instead of superseded.
        let misclassifiedCorrections = scores.filter { $0.0 == .correction && $0.1 >= 0.88 }
        for bad in misclassifiedCorrections {
            Issue.record("Correction pair scored ≥0.88 (would be wrongly reinforced, not superseded): \(bad.2)")
        }
        #expect(misclassifiedCorrections.isEmpty)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
