import XCTest
import Foundation
import SuperflowKernel

private func a1Contains(_ haystack: String, _ needle: String) -> Bool {
    let h = haystack.lowercased(), n = needle.lowercased()
    let wordish = n.unicodeScalars.allSatisfy { c in
        (c.value >= 97 && c.value <= 122) || (c.value >= 48 && c.value <= 57) || c.value == 32
    }
    let numeric = n.filter { $0 != " " }.allSatisfy { $0.isNumber }
    let suffix = numeric ? "" : "(?!\\w)"
    if wordish, let rx = try? NSRegularExpression(
        pattern: "(?<!\\w)" + NSRegularExpression.escapedPattern(for: n) + suffix) {
        return rx.firstMatch(in: h, range: NSRange(h.startIndex..., in: h)) != nil
    }
    return h.contains(n)
}

import SuperflowPorts
@testable import SuperflowTextPipeline

/// Agent 1 — extreme transcription quality corpus (short + long tiers).
///
/// 200 deliberately-broken ASR fixtures. FULL corpus is delivered as data and
/// validated structurally by `testFullCorpusFixtureIntegrity`. Only a small
/// representative subset (20) is EXECUTED through the real pipeline, gated by
/// `SUPERFLOW_CORPUS_EXECUTE=1` (machine-throttle safety). Executed samples
/// are scored on five dimensions using required/forbidden token assertions and
/// the verdicts are written to `SUPERFLOW_CORPUS_OUTPUT` as JSON; the 180
/// non-executed samples are reported as NOT EXERCISED, never as PASS.
struct A1DimAssert: Sendable {
    let requiredAny: [[String]]
    let forbidden: [String]
}
struct A1Dims: Sendable {
    let facts, grammar, terms, format, novel: A1DimAssert
}
struct A1Sample: Sendable {
    let id: String, tier: String, domain: String, raw: String
    let wordCount: Int
    let requiredAll: [String]
    let requiredAny: [[String]]
    let forbidden: [String]
    let dims: A1Dims
}

final class AggressiveCorpusShortTests: XCTestCase {

    private let corpus: [A1Sample] = [
        A1Sample(
            id: "A1-S-0001", tier: "short", domain: "software/code",
            raw: "I need you to open the the the file hero dot t s x then fix the get user by id function and change the timeout from three thousand to five thousand milliseconds as I mentioned earlier in the week which is important for the timeline um and then we",
            wordCount: 50,
            requiredAll: ["hero.tsx", "getUserById", "5000", "3000"],
            requiredAny: [["getUserById", "get user by id", "get-user-by-id"], ["5000", "5k", "5 K", "five thousand"], ["3000", "3k", "3 K", "three thousand"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "6000", "9000"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["getUserById", "get user by id", "get-user-by-id"], ["5000", "5k", "5 K", "five thousand"], ["3000", "3k", "3 K", "three thousand"], ["hero.tsx"]], forbidden: ["6000", "9000"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["6000", "9000"])
            )
        ),
        A1Sample(
            id: "A1-S-0002", tier: "short", domain: "software/code",
            raw: "I need you um to open the the the file hero dot t s x then fix the the the get user by id function and change the timeout from three thousand to five thousand milliseconds um and then we can decide so please keep me posted on that right so",
            wordCount: 51,
            requiredAll: ["hero.tsx", "getUserById", "5000", "3000"],
            requiredAny: [["getUserById", "get user by id", "get-user-by-id"], ["5000", "5k", "5 K", "five thousand"], ["3000", "3k", "3 K", "three thousand"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "6000", "9000"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["getUserById", "get user by id", "get-user-by-id"], ["5000", "5k", "5 K", "five thousand"], ["3000", "3k", "3 K", "three thousand"], ["hero.tsx"]], forbidden: ["6000", "9000"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["6000", "9000"])
            )
        ),
        A1Sample(
            id: "A1-S-0003", tier: "short", domain: "software/code",
            raw: "I need you to open you know the file hero dot t s x then fix the get user by id function and change the the the the the the the timeout from three thousand to five thousand milliseconds you know what I mean as I mentioned earlier in the week which is",
            wordCount: 53,
            requiredAll: ["hero.tsx", "getUserById", "5000", "3000"],
            requiredAny: [["getUserById", "get user by id", "get-user-by-id"], ["5000", "5k", "5 K", "five thousand"], ["3000", "3k", "3 K", "three thousand"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "6000", "9000"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["getUserById", "get user by id", "get-user-by-id"], ["5000", "5k", "5 K", "five thousand"], ["3000", "3k", "3 K", "three thousand"], ["hero.tsx"]], forbidden: ["6000", "9000"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["6000", "9000"])
            )
        ),
        A1Sample(
            id: "A1-S-0004", tier: "short", domain: "software/code",
            raw: "I need you to I mean open the file hero dot t s x then fix the get user by id function and change the the the timeout from three thousand to five thousand milliseconds but I want to be careful here and we should double check the numbers you know what I mean",
            wordCount: 54,
            requiredAll: ["hero.tsx", "getUserById", "5000", "3000"],
            requiredAny: [["getUserById", "get user by id", "get-user-by-id"], ["5000", "5k", "5 K", "five thousand"], ["3000", "3k", "3 K", "three thousand"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "6000", "9000"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["getUserById", "get user by id", "get-user-by-id"], ["5000", "5k", "5 K", "five thousand"], ["3000", "3k", "3 K", "three thousand"], ["hero.tsx"]], forbidden: ["6000", "9000"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["6000", "9000"])
            )
        ),
        A1Sample(
            id: "A1-S-0005", tier: "short", domain: "software/code",
            raw: "the a p i endpoint is returning a four zero three because the the the redish cash is full so switch to the skeptical decoding path and enable open trace logging and we should double check the numbers you know what I mean as I mentioned earlier in the week",
            wordCount: 50,
            requiredAll: ["API endpoint", "403", "Redis cache", "speculative decoding", "OpenTelemetry"],
            requiredAny: [["403", "four zero three"]],
            forbidden: ["a p i endpoint", "redish cash", "skeptical decoding", "open trace", "the the", "i i i", "it it it", "we we we", "is is is", "404", "500", "PostgreSQL"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["API endpoint"], ["Redis cache"], ["speculative decoding"], ["OpenTelemetry"]], forbidden: ["404", "500", "PostgreSQL"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["API endpoint"], ["Redis cache"], ["speculative decoding"], ["OpenTelemetry"]], forbidden: ["a p i endpoint", "redish cash", "skeptical decoding", "open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["404", "500", "PostgreSQL"])
            )
        ),
        A1Sample(
            id: "A1-S-0006", tier: "short", domain: "software/code",
            raw: "the a p um i endpoint is returning a four zero three because the Redis cache is is is full so switch to the the the speculative decoding path and enable open trace logging but I want to be careful here and we should double check the numbers you know what",
            wordCount: 51,
            requiredAll: ["API endpoint", "403", "Redis cache", "speculative decoding", "OpenTelemetry"],
            requiredAny: [["403", "four zero three"]],
            forbidden: ["open trace", "the the", "i i i", "it it it", "we we we", "is is is", "404", "500", "PostgreSQL"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["API endpoint"], ["Redis cache"], ["speculative decoding"], ["OpenTelemetry"]], forbidden: ["404", "500", "PostgreSQL"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["OpenTelemetry"]], forbidden: ["open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["404", "500", "PostgreSQL"])
            )
        ),
        A1Sample(
            id: "A1-S-0007", tier: "short", domain: "software/code",
            raw: "the a a a p i endpoint you know is returning a four zero three because the the the the the redish cash is full so switch to the skeptical decoding path and enable open trace logging um and then we can decide so please keep me posted on that right so that",
            wordCount: 53,
            requiredAll: ["API endpoint", "403", "Redis cache", "speculative decoding", "OpenTelemetry"],
            requiredAny: [["403", "four zero three"]],
            forbidden: ["a p i endpoint", "redish cash", "skeptical decoding", "open trace", "the the", "i i i", "it it it", "we we we", "is is is", "404", "500", "PostgreSQL"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["API endpoint"], ["Redis cache"], ["speculative decoding"], ["OpenTelemetry"]], forbidden: ["404", "500", "PostgreSQL"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["API endpoint"], ["Redis cache"], ["speculative decoding"], ["OpenTelemetry"]], forbidden: ["a p i endpoint", "redish cash", "skeptical decoding", "open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["404", "500", "PostgreSQL"])
            )
        ),
        A1Sample(
            id: "A1-S-0008", tier: "short", domain: "software/code",
            raw: "the a p i I mean endpoint is returning a four zero three because the the the redish cash is full so switch to the speculative decoding path and enable OpenTelemetry logging and we should double check the numbers you know what I mean as I mentioned earlier in the week which is important",
            wordCount: 54,
            requiredAll: ["API endpoint", "403", "Redis cache", "speculative decoding", "OpenTelemetry"],
            requiredAny: [["403", "four zero three"]],
            forbidden: ["redish cash", "the the", "i i i", "it it it", "we we we", "is is is", "404", "500", "PostgreSQL"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["API endpoint"], ["Redis cache"], ["speculative decoding"], ["OpenTelemetry"]], forbidden: ["404", "500", "PostgreSQL"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["Redis cache"]], forbidden: ["redish cash"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["404", "500", "PostgreSQL"])
            )
        ),
        A1Sample(
            id: "A1-S-0009", tier: "short", domain: "meeting",
            raw: "thanks everyone the the the Q three revenue was two point four million which is up from one point eight million last quarter and churn dropped to two point one percent and we should double check the numbers you know what I mean as I mentioned earlier in the week",
            wordCount: 50,
            requiredAll: ["Q3", "2.4", "1.8", "2.1%"],
            requiredAny: [["Q3", "Q 3", "q3", "q 3"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "3.4", "9.1"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q3", "Q 3", "q3", "q 3"], ["2.4"], ["1.8"], ["2.1%"]], forbidden: ["3.4", "9.1"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["3.4", "9.1"])
            )
        ),
        A1Sample(
            id: "A1-S-0010", tier: "short", domain: "meeting",
            raw: "thanks everyone the the the um Q three revenue was two point four million which is is is up from one point eight million last quarter and churn dropped to two point one percent but I want to be careful here and we should double check the numbers you know what",
            wordCount: 51,
            requiredAll: ["Q3", "2.4", "1.8", "2.1%"],
            requiredAny: [["Q3", "Q 3", "q3", "q 3"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "3.4", "9.1"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q3", "Q 3", "q3", "q 3"], ["2.4"], ["1.8"], ["2.1%"]], forbidden: ["3.4", "9.1"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["3.4", "9.1"])
            )
        ),
        A1Sample(
            id: "A1-S-0011", tier: "short", domain: "meeting",
            raw: "thanks everyone the Q three you know revenue was two point four million which is is is is is is is up from one point eight million last quarter and churn dropped to two point one percent um and then we can decide so please keep me posted on that right so that",
            wordCount: 53,
            requiredAll: ["Q3", "2.4", "1.8", "2.1%"],
            requiredAny: [["Q3", "Q 3", "q3", "q 3"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "3.4", "9.1"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q3", "Q 3", "q3", "q 3"], ["2.4"], ["1.8"], ["2.1%"]], forbidden: ["3.4", "9.1"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["3.4", "9.1"])
            )
        ),
        A1Sample(
            id: "A1-S-0012", tier: "short", domain: "meeting",
            raw: "thanks everyone the Q I mean three revenue was two point four million which is is is up from one point eight million last quarter and churn dropped to two point one percent so please keep me posted on that right so that is the plan let me know if that makes sense so",
            wordCount: 54,
            requiredAll: ["Q3", "2.4", "1.8", "2.1%"],
            requiredAny: [["Q3", "Q 3", "q3", "q 3"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "3.4", "9.1"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q3", "Q 3", "q3", "q 3"], ["2.4"], ["1.8"], ["2.1%"]], forbidden: ["3.4", "9.1"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["3.4", "9.1"])
            )
        ),
        A1Sample(
            id: "A1-S-0013", tier: "short", domain: "email",
            raw: "please send the revised contract to Sarah by Wednesday actually no wait Thursday actually no wait Wednesday and make sure the status code is is is four two nine when the rate limit is hit let me know if that makes sense so please keep me posted on that right",
            wordCount: 50,
            requiredAll: ["Sarah", "Wednesday", "429"],
            requiredAny: [["429", "four two nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Friday", "500"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["429", "four two nine"], ["Sarah"], ["Wednesday"]], forbidden: ["Friday", "500"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Friday", "500"])
            )
        ),
        A1Sample(
            id: "A1-S-0014", tier: "short", domain: "email",
            raw: "please send the um revised contract to Sarah by Thursday actually no wait Wednesday and make sure the status code is four two nine when the the the the the rate limit is hit but I want to be careful here and we should double check the numbers you know what",
            wordCount: 51,
            requiredAll: ["Sarah", "Wednesday", "429"],
            requiredAny: [["429", "four two nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Friday", "500"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["429", "four two nine"], ["Sarah"], ["Wednesday"]], forbidden: ["Friday", "500"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Friday", "500"])
            )
        ),
        A1Sample(
            id: "A1-S-0015", tier: "short", domain: "email",
            raw: "please send the revised contract you know to Sarah by Thursday actually no wait Wednesday and make sure the status code is four two nine when the the the rate limit is is is is is hit um and then we can decide so please keep me posted on that right so that",
            wordCount: 53,
            requiredAll: ["Sarah", "Wednesday", "429"],
            requiredAny: [["429", "four two nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Friday", "500"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["429", "four two nine"], ["Sarah"], ["Wednesday"]], forbidden: ["Friday", "500"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Friday", "500"])
            )
        ),
        A1Sample(
            id: "A1-S-0016", tier: "short", domain: "email",
            raw: "please send the revised I mean contract to Sarah by Wednesday actually no wait Thursday actually no wait Wednesday and make sure the the the status code is four two nine when the rate limit is hit um and then we can decide so please keep me posted on that right so that is",
            wordCount: 54,
            requiredAll: ["Sarah", "Wednesday", "429"],
            requiredAny: [["429", "four two nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Friday", "500"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["429", "four two nine"], ["Sarah"], ["Wednesday"]], forbidden: ["Friday", "500"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Friday", "500"])
            )
        ),
        A1Sample(
            id: "A1-S-0017", tier: "short", domain: "medical",
            raw: "the patient has a history of type two diabetes and is allergic to penicillin so do not prescribe amoxicillin and the dosage is is is twenty milligrams twice daily right so that is the plan let me know if that makes sense so please keep me posted on that right",
            wordCount: 50,
            requiredAll: ["type 2 diabetes", "penicillin", "not", "amoxicillin", "20 mg"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "insulin", "500 mg"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["type 2 diabetes"], ["penicillin"], ["not"], ["amoxicillin"], ["20 mg"]], forbidden: ["insulin", "500 mg"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["insulin", "500 mg"])
            )
        ),
        A1Sample(
            id: "A1-S-0018", tier: "short", domain: "medical",
            raw: "the patient has um a history of type two diabetes and is is is is is allergic to penicillin so do not prescribe amoxicillin and the dosage is twenty milligrams twice daily so please keep me posted on that right so that is the plan let me know if that makes",
            wordCount: 51,
            requiredAll: ["type 2 diabetes", "penicillin", "not", "amoxicillin", "20 mg"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "insulin", "500 mg"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["type 2 diabetes"], ["penicillin"], ["not"], ["amoxicillin"], ["20 mg"]], forbidden: ["insulin", "500 mg"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["insulin", "500 mg"])
            )
        ),
        A1Sample(
            id: "A1-S-0019", tier: "short", domain: "medical",
            raw: "the patient has a a a history you know of type two diabetes and is allergic to penicillin so do not prescribe amoxicillin and the the the the the dosage is twenty milligrams twice daily but I want to be careful here and we should double check the numbers you know what I",
            wordCount: 53,
            requiredAll: ["type 2 diabetes", "penicillin", "not", "amoxicillin", "20 mg"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "insulin", "500 mg"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["type 2 diabetes"], ["penicillin"], ["not"], ["amoxicillin"], ["20 mg"]], forbidden: ["insulin", "500 mg"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["insulin", "500 mg"])
            )
        ),
        A1Sample(
            id: "A1-S-0020", tier: "short", domain: "medical",
            raw: "the patient has a a a I mean history of type two diabetes and is allergic to penicillin so do not prescribe amoxicillin and the dosage is twenty milligrams twice daily which is important for the timeline um and then we can decide so please keep me posted on that right so that is",
            wordCount: 54,
            requiredAll: ["type 2 diabetes", "penicillin", "not", "amoxicillin", "20 mg"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "insulin", "500 mg"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["type 2 diabetes"], ["penicillin"], ["not"], ["amoxicillin"], ["20 mg"]], forbidden: ["insulin", "500 mg"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["insulin", "500 mg"])
            )
        ),
        A1Sample(
            id: "A1-S-0021", tier: "short", domain: "legal",
            raw: "the plaintiff filed the the the motion on Tuesday but the deadline was extended to Thursday actually no wait Friday so we do not need to respond until the end of next week as I mentioned earlier in the week which is important for the timeline um and then we",
            wordCount: 50,
            requiredAll: ["plaintiff", "motion", "Friday", "not"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "default judgment"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["plaintiff"], ["motion"], ["Friday"], ["not"]], forbidden: ["Monday", "default judgment"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "default judgment"])
            )
        ),
        A1Sample(
            id: "A1-S-0022", tier: "short", domain: "legal",
            raw: "the plaintiff filed um the motion on Tuesday but the deadline was extended to Friday so we we we do not need to respond until the the the end of next week so please keep me posted on that right so that is the plan let me know if that makes",
            wordCount: 51,
            requiredAll: ["plaintiff", "motion", "Friday", "not"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "default judgment"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["plaintiff"], ["motion"], ["Friday"], ["not"]], forbidden: ["Monday", "default judgment"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "default judgment"])
            )
        ),
        A1Sample(
            id: "A1-S-0023", tier: "short", domain: "legal",
            raw: "the the the the the the the plaintiff filed the motion you know on Tuesday but the deadline was extended to Friday so we do not need to respond until the end of next week but I want to be careful here and we should double check the numbers you know what I",
            wordCount: 53,
            requiredAll: ["plaintiff", "motion", "Friday", "not"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "default judgment"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["plaintiff"], ["motion"], ["Friday"], ["not"]], forbidden: ["Monday", "default judgment"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "default judgment"])
            )
        ),
        A1Sample(
            id: "A1-S-0024", tier: "short", domain: "legal",
            raw: "the plaintiff filed the I mean motion on Tuesday but the the the deadline was extended to Thursday actually no wait Friday so we do not need to respond until the end of next week but I want to be careful here and we should double check the numbers you know what I mean",
            wordCount: 54,
            requiredAll: ["plaintiff", "motion", "Friday", "not"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "default judgment"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["plaintiff"], ["motion"], ["Friday"], ["not"]], forbidden: ["Monday", "default judgment"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "default judgment"])
            )
        ),
        A1Sample(
            id: "A1-S-0025", tier: "short", domain: "finance",
            raw: "the budget is is is four hundred fifty thousand dollars and we need two point five full time engineers by Q one next year but I want to be careful here and we should double check the numbers you know what I mean as I mentioned earlier in the week",
            wordCount: 50,
            requiredAll: ["450", "2.5", "Q1"],
            requiredAny: [["Q1", "Q 1", "q1", "q 1"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "500", "3.5"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q1", "Q 1", "q1", "q 1"], ["450"], ["2.5"]], forbidden: ["500", "3.5"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "3.5"])
            )
        ),
        A1Sample(
            id: "A1-S-0026", tier: "short", domain: "finance",
            raw: "the budget is is is um four hundred fifty thousand dollars and we we we need two point five full time engineers by Q one next year I I think that is the right call let me know if that makes sense so please keep me posted on that right so",
            wordCount: 51,
            requiredAll: ["450", "2.5", "Q1"],
            requiredAny: [["Q1", "Q 1", "q1", "q 1"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "500", "3.5"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q1", "Q 1", "q1", "q 1"], ["450"], ["2.5"]], forbidden: ["500", "3.5"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "3.5"])
            )
        ),
        A1Sample(
            id: "A1-S-0027", tier: "short", domain: "finance",
            raw: "the the the budget is is is is is four hundred you know fifty thousand dollars and we need two point five full time engineers by Q one next year right so that is the plan let me know if that makes sense so please keep me posted on that right so that",
            wordCount: 53,
            requiredAll: ["450", "2.5", "Q1"],
            requiredAny: [["Q1", "Q 1", "q1", "q 1"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "500", "3.5"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q1", "Q 1", "q1", "q 1"], ["450"], ["2.5"]], forbidden: ["500", "3.5"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "3.5"])
            )
        ),
        A1Sample(
            id: "A1-S-0028", tier: "short", domain: "finance",
            raw: "the the the budget is four I mean hundred fifty thousand dollars and we need two point five full time engineers by Q one next year let me know if that makes sense so please keep me posted on that right so that is the plan let me know if that makes sense so",
            wordCount: 54,
            requiredAll: ["450", "2.5", "Q1"],
            requiredAny: [["Q1", "Q 1", "q1", "q 1"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "500", "3.5"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q1", "Q 1", "q1", "q 1"], ["450"], ["2.5"]], forbidden: ["500", "3.5"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "3.5"])
            )
        ),
        A1Sample(
            id: "A1-S-0029", tier: "short", domain: "non-native English",
            raw: "sorry my English is not so good but I am trying to say the server is down since yesterday and we are not able to deploy the the the new version and we should double check the numbers you know what I mean as I mentioned earlier in the week",
            wordCount: 50,
            requiredAll: ["not", "server", "yesterday", "deploy"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "tomorrow", "rollback"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["not"], ["server"], ["yesterday"], ["deploy"]], forbidden: ["tomorrow", "rollback"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["tomorrow", "rollback"])
            )
        ),
        A1Sample(
            id: "A1-S-0030", tier: "short", domain: "non-native English",
            raw: "sorry my English um is not so good but I am trying to say the the the server is down since yesterday and we we we are not able to deploy the new version but I want to be careful here and we should double check the numbers you know what",
            wordCount: 51,
            requiredAll: ["not", "server", "yesterday", "deploy"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "tomorrow", "rollback"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["not"], ["server"], ["yesterday"], ["deploy"]], forbidden: ["tomorrow", "rollback"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["tomorrow", "rollback"])
            )
        ),
        A1Sample(
            id: "A1-S-0031", tier: "short", domain: "non-native English",
            raw: "sorry my English is not you know so good but I am trying to say the the the the the the the server is down since yesterday and we are not able to deploy the new version um and then we can decide so please keep me posted on that right so that",
            wordCount: 53,
            requiredAll: ["not", "server", "yesterday", "deploy"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "tomorrow", "rollback"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["not"], ["server"], ["yesterday"], ["deploy"]], forbidden: ["tomorrow", "rollback"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["tomorrow", "rollback"])
            )
        ),
        A1Sample(
            id: "A1-S-0032", tier: "short", domain: "non-native English",
            raw: "sorry my English is is is I mean not so good but I am trying to say the server is down since yesterday and we are not able to deploy the new version so please keep me posted on that right so that is the plan let me know if that makes sense so",
            wordCount: 54,
            requiredAll: ["not", "server", "yesterday", "deploy"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "tomorrow", "rollback"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["not"], ["server"], ["yesterday"], ["deploy"]], forbidden: ["tomorrow", "rollback"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["tomorrow", "rollback"])
            )
        ),
        A1Sample(
            id: "A1-S-0033", tier: "short", domain: "noisy ASR",
            raw: "the the deployment failed with error four zero three then four two nine and uh the the log says connection timeout but not a a a server crash you know what I mean as I mentioned earlier in the week which is important for the timeline um and then we",
            wordCount: 50,
            requiredAll: ["403", "429", "timeout", "not"],
            requiredAny: [["403", "four zero three"], ["429", "four two nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "500", "outage"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["429", "four two nine"], ["timeout"], ["not"]], forbidden: ["500", "outage"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "outage"])
            )
        ),
        A1Sample(
            id: "A1-S-0034", tier: "short", domain: "noisy ASR",
            raw: "the the deployment um failed with error four zero three then four two nine and uh the the log says connection timeout but not a a a a a server crash and we should double check the numbers you know what I mean as I mentioned earlier in the week which",
            wordCount: 51,
            requiredAll: ["403", "429", "timeout", "not"],
            requiredAny: [["403", "four zero three"], ["429", "four two nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "500", "outage"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["429", "four two nine"], ["timeout"], ["not"]], forbidden: ["500", "outage"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "outage"])
            )
        ),
        A1Sample(
            id: "A1-S-0035", tier: "short", domain: "noisy ASR",
            raw: "the the the the deployment failed with you know error four zero three then four two nine and uh the the the the log says connection timeout but not a a a server crash as I mentioned earlier in the week which is important for the timeline um and then we can decide",
            wordCount: 53,
            requiredAll: ["403", "429", "timeout", "not"],
            requiredAny: [["403", "four zero three"], ["429", "four two nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "500", "outage"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["429", "four two nine"], ["timeout"], ["not"]], forbidden: ["500", "outage"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "outage"])
            )
        ),
        A1Sample(
            id: "A1-S-0036", tier: "short", domain: "noisy ASR",
            raw: "the the the the deployment failed I mean with error four zero three then four two nine and uh the the log says connection timeout but not a server crash right so that is the plan let me know if that makes sense so please keep me posted on that right so that is",
            wordCount: 54,
            requiredAll: ["403", "429", "timeout", "not"],
            requiredAny: [["403", "four zero three"], ["429", "four two nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "500", "outage"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["429", "four two nine"], ["timeout"], ["not"]], forbidden: ["500", "outage"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "outage"])
            )
        ),
        A1Sample(
            id: "A1-S-0037", tier: "short", domain: "extreme Unicode",
            raw: "the the the caf r sum and na ve details are in the contrat d j vu file please translate from Z rich to S o Paulo by email right so that is the plan let me know if that makes sense so please keep me posted on that right",
            wordCount: 50,
            requiredAll: ["café", "résumé", "naïve", "Zürich", "São Paulo"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "München", "Lisbon"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["café"], ["résumé"], ["naïve"], ["Zürich"], ["São Paulo"]], forbidden: ["München", "Lisbon"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["München", "Lisbon"])
            )
        ),
        A1Sample(
            id: "A1-S-0038", tier: "short", domain: "extreme Unicode",
            raw: "the the the the the caf r um sum and na ve details are in the contrat d j vu file please translate from Z rich to S o Paulo by email so please keep me posted on that right so that is the plan let me know if that makes",
            wordCount: 51,
            requiredAll: ["café", "résumé", "naïve", "Zürich", "São Paulo"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "München", "Lisbon"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["café"], ["résumé"], ["naïve"], ["Zürich"], ["São Paulo"]], forbidden: ["München", "Lisbon"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["München", "Lisbon"])
            )
        ),
        A1Sample(
            id: "A1-S-0039", tier: "short", domain: "extreme Unicode",
            raw: "the the the caf r sum and you know na ve details are in the the the the the contrat d j vu file please translate from Z rich to S o Paulo by email but I want to be careful here and we should double check the numbers you know what I",
            wordCount: 53,
            requiredAll: ["café", "résumé", "naïve", "Zürich", "São Paulo"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "München", "Lisbon"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["café"], ["résumé"], ["naïve"], ["Zürich"], ["São Paulo"]], forbidden: ["München", "Lisbon"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["München", "Lisbon"])
            )
        ),
        A1Sample(
            id: "A1-S-0040", tier: "short", domain: "extreme Unicode",
            raw: "the caf r sum I mean and na ve details are in the the the contrat d j vu file please translate from Z rich to S o Paulo by email which is important for the timeline um and then we can decide so please keep me posted on that right so that is",
            wordCount: 54,
            requiredAll: ["café", "résumé", "naïve", "Zürich", "São Paulo"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "München", "Lisbon"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["café"], ["résumé"], ["naïve"], ["Zürich"], ["São Paulo"]], forbidden: ["München", "Lisbon"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["München", "Lisbon"])
            )
        ),
        A1Sample(
            id: "A1-S-0041", tier: "short", domain: "standup",
            raw: "yesterday I worked on the auth flow and today I am reviewing the the the pull request for the billing service unless the API contract changes then I will pair with Priya so please keep me posted on that right so that is the plan let me know if that",
            wordCount: 50,
            requiredAll: ["auth flow", "billing service", "API", "Priya"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Bob", "staging"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["auth flow"], ["billing service"], ["API"], ["Priya"]], forbidden: ["Bob", "staging"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Bob", "staging"])
            )
        ),
        A1Sample(
            id: "A1-S-0042", tier: "short", domain: "standup",
            raw: "yesterday I worked um on the auth flow and today I am reviewing the pull request for the billing service unless the the the the the API contract changes then I will pair with Priya let me know if that makes sense so please keep me posted on that right so",
            wordCount: 51,
            requiredAll: ["auth flow", "billing service", "API", "Priya"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Bob", "staging"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["auth flow"], ["billing service"], ["API"], ["Priya"]], forbidden: ["Bob", "staging"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Bob", "staging"])
            )
        ),
        A1Sample(
            id: "A1-S-0043", tier: "short", domain: "standup",
            raw: "yesterday I worked on the you know auth flow and today I am reviewing the pull request for the the the the the the the billing service unless the API contract changes then I will pair with Priya I I think that is the right call let me know if that makes sense",
            wordCount: 53,
            requiredAll: ["auth flow", "billing service", "API", "Priya"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Bob", "staging"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["auth flow"], ["billing service"], ["API"], ["Priya"]], forbidden: ["Bob", "staging"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Bob", "staging"])
            )
        ),
        A1Sample(
            id: "A1-S-0044", tier: "short", domain: "standup",
            raw: "yesterday I worked on I mean the auth flow and today I am reviewing the the the pull request for the billing service unless the API contract changes then I will pair with Priya as I mentioned earlier in the week which is important for the timeline um and then we can decide so",
            wordCount: 54,
            requiredAll: ["auth flow", "billing service", "API", "Priya"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Bob", "staging"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["auth flow"], ["billing service"], ["API"], ["Priya"]], forbidden: ["Bob", "staging"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Bob", "staging"])
            )
        ),
        A1Sample(
            id: "A1-S-0045", tier: "short", domain: "customer support",
            raw: "your order number is is is four eight two one and it has not shipped yet because the payment of ninety nine dollars did not go through I I think that is the right call let me know if that makes sense so please keep me posted on that right",
            wordCount: 50,
            requiredAll: ["4821", "not", "99"],
            requiredAny: [["99", "ninety nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "4822", "199"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["99", "ninety nine"], ["4821"], ["not"]], forbidden: ["4822", "199"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["4822", "199"])
            )
        ),
        A1Sample(
            id: "A1-S-0046", tier: "short", domain: "customer support",
            raw: "your order number um is four eight two one and it has not shipped yet because the the the the the payment of ninety nine dollars did not go through which is important for the timeline um and then we can decide so please keep me posted on that right so",
            wordCount: 51,
            requiredAll: ["4821", "not", "99"],
            requiredAny: [["99", "ninety nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "4822", "199"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["99", "ninety nine"], ["4821"], ["not"]], forbidden: ["4822", "199"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["4822", "199"])
            )
        ),
        A1Sample(
            id: "A1-S-0047", tier: "short", domain: "customer support",
            raw: "your order number is four you know eight two one and it it it it it it it has not shipped yet because the payment of ninety nine dollars did not go through so please keep me posted on that right so that is the plan let me know if that makes sense",
            wordCount: 53,
            requiredAll: ["4821", "not", "99"],
            requiredAny: [["99", "ninety nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "4822", "199"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["99", "ninety nine"], ["4821"], ["not"]], forbidden: ["4822", "199"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["4822", "199"])
            )
        ),
        A1Sample(
            id: "A1-S-0048", tier: "short", domain: "customer support",
            raw: "your order number is I mean four eight two one and it has not shipped yet because the the the payment of ninety nine dollars did not go through you know what I mean as I mentioned earlier in the week which is important for the timeline um and then we can decide so",
            wordCount: 54,
            requiredAll: ["4821", "not", "99"],
            requiredAny: [["99", "ninety nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "4822", "199"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["99", "ninety nine"], ["4821"], ["not"]], forbidden: ["4822", "199"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["4822", "199"])
            )
        ),
        A1Sample(
            id: "A1-S-0049", tier: "short", domain: "science",
            raw: "the sample temperature was thirty seven degrees Celsius and the p value was zero point zero three so the the the result is statistically significant but not conclusive you know what I mean as I mentioned earlier in the week which is important for the timeline um and then we",
            wordCount: 50,
            requiredAll: ["37", "0.03", "significant", "not"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "0.3", "unproven"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["37"], ["0.03"], ["significant"], ["not"]], forbidden: ["0.3", "unproven"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["0.3", "unproven"])
            )
        ),
        A1Sample(
            id: "A1-S-0050", tier: "short", domain: "science",
            raw: "the sample temperature um was thirty seven degrees Celsius and the the the p value was zero point zero three so the the the result is statistically significant but not conclusive and we should double check the numbers you know what I mean as I mentioned earlier in the week which",
            wordCount: 51,
            requiredAll: ["37", "0.03", "significant", "not"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "0.3", "unproven"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["37"], ["0.03"], ["significant"], ["not"]], forbidden: ["0.3", "unproven"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["0.3", "unproven"])
            )
        ),
        A1Sample(
            id: "A1-S-0051", tier: "short", domain: "science",
            raw: "the the the the the the the sample temperature was thirty you know seven degrees Celsius and the p value was zero point zero three so the result is statistically significant but not conclusive as I mentioned earlier in the week which is important for the timeline um and then we can decide",
            wordCount: 53,
            requiredAll: ["37", "0.03", "significant", "not"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "0.3", "unproven"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["37"], ["0.03"], ["significant"], ["not"]], forbidden: ["0.3", "unproven"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["0.3", "unproven"])
            )
        ),
        A1Sample(
            id: "A1-S-0052", tier: "short", domain: "science",
            raw: "the sample temperature was I mean thirty seven degrees Celsius and the p value was zero point zero three so the result is is is statistically significant but not conclusive right so that is the plan let me know if that makes sense so please keep me posted on that right so that is",
            wordCount: 54,
            requiredAll: ["37", "0.03", "significant", "not"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "0.3", "unproven"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["37"], ["0.03"], ["significant"], ["not"]], forbidden: ["0.3", "unproven"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["0.3", "unproven"])
            )
        ),
        A1Sample(
            id: "A1-S-0053", tier: "short", domain: "sales call",
            raw: "the discount is fifteen percent if you sign by Thursday actually no wait Friday otherwise the the the list price of twelve thousand dollars applies to all seats you know what I mean as I mentioned earlier in the week which is important for the timeline um and then we",
            wordCount: 50,
            requiredAll: ["15%", "Friday", "12000"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "20%", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["15%"], ["Friday"], ["12000"]], forbidden: ["20%", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["20%", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-S-0054", tier: "short", domain: "sales call",
            raw: "the discount is um fifteen percent if you sign by Friday otherwise the the the the the list price of twelve thousand dollars applies to all seats I I think that is the right call let me know if that makes sense so please keep me posted on that right so",
            wordCount: 51,
            requiredAll: ["15%", "Friday", "12000"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "20%", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["15%"], ["Friday"], ["12000"]], forbidden: ["20%", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["20%", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-S-0055", tier: "short", domain: "sales call",
            raw: "the the the the the discount is is is fifteen percent you know if you sign by Friday otherwise the list price of twelve thousand dollars applies to all seats right so that is the plan let me know if that makes sense so please keep me posted on that right so that",
            wordCount: 53,
            requiredAll: ["15%", "Friday", "12000"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "20%", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["15%"], ["Friday"], ["12000"]], forbidden: ["20%", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["20%", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-S-0056", tier: "short", domain: "sales call",
            raw: "the discount is is is fifteen I mean percent if you sign by Thursday actually no wait Friday otherwise the list price of twelve thousand dollars applies to all seats right so that is the plan let me know if that makes sense so please keep me posted on that right so that is",
            wordCount: 54,
            requiredAll: ["15%", "Friday", "12000"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "20%", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["15%"], ["Friday"], ["12000"]], forbidden: ["20%", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["20%", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-S-0057", tier: "short", domain: "personal notes",
            raw: "remember to call Mom on Sunday and pick up the prescription from the the the pharmacy before the the office closes at five p m let me know if that makes sense so please keep me posted on that right so that is the plan let me know if that",
            wordCount: 50,
            requiredAll: ["Sunday", "pharmacy", "5 PM"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Saturday", "4 PM"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Sunday"], ["pharmacy"], ["5 PM"]], forbidden: ["Saturday", "4 PM"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Saturday", "4 PM"])
            )
        ),
        A1Sample(
            id: "A1-S-0058", tier: "short", domain: "personal notes",
            raw: "remember to call um Mom on Sunday and pick up the prescription from the the the pharmacy before the the the the office closes at five p m you know what I mean as I mentioned earlier in the week which is important for the timeline um and then we can",
            wordCount: 51,
            requiredAll: ["Sunday", "pharmacy", "5 PM"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Saturday", "4 PM"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Sunday"], ["pharmacy"], ["5 PM"]], forbidden: ["Saturday", "4 PM"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Saturday", "4 PM"])
            )
        ),
        A1Sample(
            id: "A1-S-0059", tier: "short", domain: "personal notes",
            raw: "remember to call Mom on you know Sunday and pick up the prescription from the the the pharmacy before the the the the the the office closes at five p m which is important for the timeline um and then we can decide so please keep me posted on that right so that",
            wordCount: 53,
            requiredAll: ["Sunday", "pharmacy", "5 PM"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Saturday", "4 PM"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Sunday"], ["pharmacy"], ["5 PM"]], forbidden: ["Saturday", "4 PM"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Saturday", "4 PM"])
            )
        ),
        A1Sample(
            id: "A1-S-0060", tier: "short", domain: "personal notes",
            raw: "remember to call Mom I mean on Sunday and pick up the prescription from the the the pharmacy before the the office closes at five p m um and then we can decide so please keep me posted on that right so that is the plan let me know if that makes sense so",
            wordCount: 54,
            requiredAll: ["Sunday", "pharmacy", "5 PM"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Saturday", "4 PM"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Sunday"], ["pharmacy"], ["5 PM"]], forbidden: ["Saturday", "4 PM"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Saturday", "4 PM"])
            )
        ),
        A1Sample(
            id: "A1-S-0061", tier: "short", domain: "gaming",
            raw: "I died three times on the the final boss because my latency was two hundred milliseconds so I switched servers and won on the the the fourth try you know what I mean as I mentioned earlier in the week which is important for the timeline um and then we",
            wordCount: 50,
            requiredAll: ["200", "fourth", "boss"],
            requiredAny: [["200", "two hundred"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "300", "fifth"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["200", "two hundred"], ["fourth"], ["boss"]], forbidden: ["300", "fifth"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["300", "fifth"])
            )
        ),
        A1Sample(
            id: "A1-S-0062", tier: "short", domain: "gaming",
            raw: "I died three um times on the the final boss because my latency was two hundred milliseconds so I switched servers and won on the the the the the fourth try and we should double check the numbers you know what I mean as I mentioned earlier in the week which",
            wordCount: 51,
            requiredAll: ["200", "fourth", "boss"],
            requiredAny: [["200", "two hundred"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "300", "fifth"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["200", "two hundred"], ["fourth"], ["boss"]], forbidden: ["300", "fifth"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["300", "fifth"])
            )
        ),
        A1Sample(
            id: "A1-S-0063", tier: "short", domain: "gaming",
            raw: "I died three times on you know the the the the the the final boss because my latency was two hundred milliseconds so I switched servers and won on the the the fourth try as I mentioned earlier in the week which is important for the timeline um and then we can decide",
            wordCount: 53,
            requiredAll: ["200", "fourth", "boss"],
            requiredAny: [["200", "two hundred"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "300", "fifth"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["200", "two hundred"], ["fourth"], ["boss"]], forbidden: ["300", "fifth"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["300", "fifth"])
            )
        ),
        A1Sample(
            id: "A1-S-0064", tier: "short", domain: "gaming",
            raw: "I died three times I mean on the the the the final boss because my latency was two hundred milliseconds so I switched servers and won on the fourth try right so that is the plan let me know if that makes sense so please keep me posted on that right so that is",
            wordCount: 54,
            requiredAll: ["200", "fourth", "boss"],
            requiredAny: [["200", "two hundred"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "300", "fifth"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["200", "two hundred"], ["fourth"], ["boss"]], forbidden: ["300", "fifth"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["300", "fifth"])
            )
        ),
        A1Sample(
            id: "A1-S-0065", tier: "short", domain: "travel",
            raw: "the flight to Tokyo leaves at six thirty a m from gate twelve but it was delayed by forty five minutes because of the the the weather I I think that is the right call let me know if that makes sense so please keep me posted on that right",
            wordCount: 50,
            requiredAll: ["Tokyo", "6:30", "12", "45"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Osaka", "15"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Tokyo"], ["6:30"], ["12"], ["45"]], forbidden: ["Osaka", "15"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Osaka", "15"])
            )
        ),
        A1Sample(
            id: "A1-S-0066", tier: "short", domain: "travel",
            raw: "the flight to um Tokyo leaves at six thirty a a a a a m from gate twelve but it was delayed by forty five minutes because of the weather which is important for the timeline um and then we can decide so please keep me posted on that right so",
            wordCount: 51,
            requiredAll: ["Tokyo", "6:30", "12", "45"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Osaka", "15"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Tokyo"], ["6:30"], ["12"], ["45"]], forbidden: ["Osaka", "15"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Osaka", "15"])
            )
        ),
        A1Sample(
            id: "A1-S-0067", tier: "short", domain: "travel",
            raw: "the flight to Tokyo leaves you know at six thirty a a a a a a a m from gate twelve but it was delayed by forty five minutes because of the weather so please keep me posted on that right so that is the plan let me know if that makes sense",
            wordCount: 53,
            requiredAll: ["Tokyo", "6:30", "12", "45"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Osaka", "15"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Tokyo"], ["6:30"], ["12"], ["45"]], forbidden: ["Osaka", "15"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Osaka", "15"])
            )
        ),
        A1Sample(
            id: "A1-S-0068", tier: "short", domain: "travel",
            raw: "the flight to Tokyo I mean leaves at six thirty a a a m from gate twelve but it was delayed by forty five minutes because of the weather you know what I mean as I mentioned earlier in the week which is important for the timeline um and then we can decide so",
            wordCount: 54,
            requiredAll: ["Tokyo", "6:30", "12", "45"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Osaka", "15"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Tokyo"], ["6:30"], ["12"], ["45"]], forbidden: ["Osaka", "15"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Osaka", "15"])
            )
        ),
        A1Sample(
            id: "A1-S-0069", tier: "short", domain: "academic",
            raw: "the the the hypothesis was not confirmed because the sample size of thirty was too small and the control group showed the same effect but I want to be careful here and we should double check the numbers you know what I mean as I mentioned earlier in the week",
            wordCount: 50,
            requiredAll: ["not", "30", "control group"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "300", "experimental"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["not"], ["control group"]], forbidden: ["300", "experimental"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["300", "experimental"])
            )
        ),
        A1Sample(
            id: "A1-S-0070", tier: "short", domain: "academic",
            raw: "the hypothesis was um not confirmed because the sample size of thirty was too small and the control group showed the the the the the same effect I I think that is the right call let me know if that makes sense so please keep me posted on that right so",
            wordCount: 51,
            requiredAll: ["not", "30", "control group"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "300", "experimental"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["not"], ["control group"]], forbidden: ["300", "experimental"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["300", "experimental"])
            )
        ),
        A1Sample(
            id: "A1-S-0071", tier: "short", domain: "academic",
            raw: "the hypothesis was not confirmed you know because the sample size of thirty was too small and the the the the the control group showed the the the same effect right so that is the plan let me know if that makes sense so please keep me posted on that right so that",
            wordCount: 53,
            requiredAll: ["not", "30", "control group"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "300", "experimental"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["not"], ["control group"]], forbidden: ["300", "experimental"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["300", "experimental"])
            )
        ),
        A1Sample(
            id: "A1-S-0072", tier: "short", domain: "academic",
            raw: "the hypothesis was not I mean confirmed because the sample size of thirty was too small and the control group showed the the the same effect let me know if that makes sense so please keep me posted on that right so that is the plan let me know if that makes sense so",
            wordCount: 54,
            requiredAll: ["not", "30", "control group"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "300", "experimental"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["not"], ["control group"]], forbidden: ["300", "experimental"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["300", "experimental"])
            )
        ),
        A1Sample(
            id: "A1-S-0073", tier: "short", domain: "chat",
            raw: "are you coming to the the party on Saturday I I mean Thursday actually no wait Friday night because we we we need a ride and the the address is forty two Maple Street but I want to be careful here and we should double check the numbers you know",
            wordCount: 50,
            requiredAll: ["Friday", "42", "Maple Street"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Sunday", "24"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Friday"], ["42"], ["Maple Street"]], forbidden: ["Sunday", "24"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Sunday", "24"])
            )
        ),
        A1Sample(
            id: "A1-S-0074", tier: "short", domain: "chat",
            raw: "are you coming um to the the party on Saturday I I mean Friday night because we need a ride and the the the the the the address is forty two Maple Street as I mentioned earlier in the week which is important for the timeline um and then we can",
            wordCount: 51,
            requiredAll: ["Friday", "42", "Maple Street"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Sunday", "24"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Friday"], ["42"], ["Maple Street"]], forbidden: ["Sunday", "24"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Sunday", "24"])
            )
        ),
        A1Sample(
            id: "A1-S-0075", tier: "short", domain: "chat",
            raw: "are you coming to the you know the party on Saturday I I mean Friday night because we we we need a a a ride and the the the the address is forty two Maple Street let me know if that makes sense so please keep me posted on that right so that",
            wordCount: 53,
            requiredAll: ["Friday", "42", "Maple Street"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Sunday", "24"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Friday"], ["42"], ["Maple Street"]], forbidden: ["Sunday", "24"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Sunday", "24"])
            )
        ),
        A1Sample(
            id: "A1-S-0076", tier: "short", domain: "chat",
            raw: "are you coming to I mean the the the the party on Saturday I I mean Thursday actually no wait Friday night because we need a ride and the the address is forty two Maple Street let me know if that makes sense so please keep me posted on that right so that is",
            wordCount: 54,
            requiredAll: ["Friday", "42", "Maple Street"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Sunday", "24"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Friday"], ["42"], ["Maple Street"]], forbidden: ["Sunday", "24"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Sunday", "24"])
            )
        ),
        A1Sample(
            id: "A1-S-0077", tier: "short", domain: "coding interview",
            raw: "I would use a hash map to solve this in O of n time and the the the the space complexity is also O of n because we store every visited node so please keep me posted on that right so that is the plan let me know if that",
            wordCount: 50,
            requiredAll: ["hash map", "O(n)", "space complexity"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "O(n^2)", "array"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["hash map"], ["O(n)"], ["space complexity"]], forbidden: ["O(n^2)", "array"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["O(n^2)", "array"])
            )
        ),
        A1Sample(
            id: "A1-S-0078", tier: "short", domain: "coding interview",
            raw: "I would use um a hash map to solve this in O of n time and the the space complexity is is is is is also O of n because we store every visited node let me know if that makes sense so please keep me posted on that right so",
            wordCount: 51,
            requiredAll: ["hash map", "O(n)", "space complexity"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "O(n^2)", "array"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["hash map"], ["O(n)"], ["space complexity"]], forbidden: ["O(n^2)", "array"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["O(n^2)", "array"])
            )
        ),
        A1Sample(
            id: "A1-S-0079", tier: "short", domain: "coding interview",
            raw: "I would use a hash you know map to solve this in O of n time and the the the the the the the the space complexity is also O of n because we store every visited node I I think that is the right call let me know if that makes sense",
            wordCount: 53,
            requiredAll: ["hash map", "O(n)", "space complexity"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "O(n^2)", "array"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["hash map"], ["O(n)"], ["space complexity"]], forbidden: ["O(n^2)", "array"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["O(n^2)", "array"])
            )
        ),
        A1Sample(
            id: "A1-S-0080", tier: "short", domain: "coding interview",
            raw: "I would use a a a I mean hash map to solve this in O of n time and the the space complexity is also O of n because we store every visited node as I mentioned earlier in the week which is important for the timeline um and then we can decide so",
            wordCount: 54,
            requiredAll: ["hash map", "O(n)", "space complexity"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "O(n^2)", "array"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["hash map"], ["O(n)"], ["space complexity"]], forbidden: ["O(n^2)", "array"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["O(n^2)", "array"])
            )
        ),
        A1Sample(
            id: "A1-S-0081", tier: "short", domain: "medical",
            raw: "the CT scan showed no fracture but there is is is mild swelling so we will monitor for twenty four hours and discharge if the pain does not increase right so that is the plan let me know if that makes sense so please keep me posted on that right",
            wordCount: 50,
            requiredAll: ["CT scan", "no fracture", "24", "not"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "inconclusive", "48"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["CT scan"], ["no fracture"], ["24"], ["not"]], forbidden: ["inconclusive", "48"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["inconclusive", "48"])
            )
        ),
        A1Sample(
            id: "A1-S-0082", tier: "short", domain: "medical",
            raw: "the the the the the CT scan um showed no fracture but there is mild swelling so we will monitor for twenty four hours and discharge if the pain does not increase so please keep me posted on that right so that is the plan let me know if that makes",
            wordCount: 51,
            requiredAll: ["CT scan", "no fracture", "24", "not"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "inconclusive", "48"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["CT scan"], ["no fracture"], ["24"], ["not"]], forbidden: ["inconclusive", "48"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["inconclusive", "48"])
            )
        ),
        A1Sample(
            id: "A1-S-0083", tier: "short", domain: "medical",
            raw: "the the the CT scan showed no you know fracture but there is mild swelling so we will monitor for twenty four hours and discharge if the the the the the pain does not increase but I want to be careful here and we should double check the numbers you know what I",
            wordCount: 53,
            requiredAll: ["CT scan", "no fracture", "24", "not"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "inconclusive", "48"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["CT scan"], ["no fracture"], ["24"], ["not"]], forbidden: ["inconclusive", "48"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["inconclusive", "48"])
            )
        ),
        A1Sample(
            id: "A1-S-0084", tier: "short", domain: "medical",
            raw: "the CT scan showed I mean no fracture but there is is is mild swelling so we will monitor for twenty four hours and discharge if the pain does not increase which is important for the timeline um and then we can decide so please keep me posted on that right so that is",
            wordCount: 54,
            requiredAll: ["CT scan", "no fracture", "24", "not"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "inconclusive", "48"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["CT scan"], ["no fracture"], ["24"], ["not"]], forbidden: ["inconclusive", "48"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["inconclusive", "48"])
            )
        ),
        A1Sample(
            id: "A1-S-0085", tier: "short", domain: "legal",
            raw: "the witness testified that she did not see the defendant at the scene and the the evidence was ruled inadmissible by the the the judge on Tuesday I I think that is the right call let me know if that makes sense so please keep me posted on that right",
            wordCount: 50,
            requiredAll: ["not", "defendant", "inadmissible", "Tuesday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "guilty", "Wednesday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["not"], ["defendant"], ["inadmissible"], ["Tuesday"]], forbidden: ["guilty", "Wednesday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["guilty", "Wednesday"])
            )
        ),
        A1Sample(
            id: "A1-S-0086", tier: "short", domain: "legal",
            raw: "the witness testified um that she did not see the defendant at the scene and the the evidence was ruled inadmissible by the the the the the judge on Tuesday which is important for the timeline um and then we can decide so please keep me posted on that right so",
            wordCount: 51,
            requiredAll: ["not", "defendant", "inadmissible", "Tuesday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "guilty", "Wednesday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["not"], ["defendant"], ["inadmissible"], ["Tuesday"]], forbidden: ["guilty", "Wednesday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["guilty", "Wednesday"])
            )
        ),
        A1Sample(
            id: "A1-S-0087", tier: "short", domain: "legal",
            raw: "the witness testified that she you know did not see the defendant at the the the the the scene and the the the the evidence was ruled inadmissible by the judge on Tuesday so please keep me posted on that right so that is the plan let me know if that makes sense",
            wordCount: 53,
            requiredAll: ["not", "defendant", "inadmissible", "Tuesday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "guilty", "Wednesday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["not"], ["defendant"], ["inadmissible"], ["Tuesday"]], forbidden: ["guilty", "Wednesday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["guilty", "Wednesday"])
            )
        ),
        A1Sample(
            id: "A1-S-0088", tier: "short", domain: "legal",
            raw: "the witness testified that I mean she did not see the defendant at the scene and the the the the evidence was ruled inadmissible by the judge on Tuesday you know what I mean as I mentioned earlier in the week which is important for the timeline um and then we can decide so",
            wordCount: 54,
            requiredAll: ["not", "defendant", "inadmissible", "Tuesday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "guilty", "Wednesday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["not"], ["defendant"], ["inadmissible"], ["Tuesday"]], forbidden: ["guilty", "Wednesday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["guilty", "Wednesday"])
            )
        ),
        A1Sample(
            id: "A1-S-0089", tier: "short", domain: "finance",
            raw: "our runway is eighteen months at the the the the current burn rate of two hundred thousand per month so we do not need another round until Q three right so that is the plan let me know if that makes sense so please keep me posted on that right",
            wordCount: 50,
            requiredAll: ["18", "200000", "not", "Q3"],
            requiredAny: [["200000", "200k", "$200k", "200 K"], ["Q3", "Q 3", "q3", "q 3"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "6", "Q1"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["200000", "200k", "$200k", "200 K"], ["Q3", "Q 3", "q3", "q 3"], ["18"], ["not"]], forbidden: ["6", "Q1"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["6", "Q1"])
            )
        ),
        A1Sample(
            id: "A1-S-0090", tier: "short", domain: "finance",
            raw: "our runway is is is um eighteen months at the the the the current burn rate of two hundred thousand per month so we do not need another round until Q three so please keep me posted on that right so that is the plan let me know if that makes",
            wordCount: 51,
            requiredAll: ["18", "200000", "not", "Q3"],
            requiredAny: [["200000", "200k", "$200k", "200 K"], ["Q3", "Q 3", "q3", "q 3"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "6", "Q1"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["200000", "200k", "$200k", "200 K"], ["Q3", "Q 3", "q3", "q 3"], ["18"], ["not"]], forbidden: ["6", "Q1"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["6", "Q1"])
            )
        ),
        A1Sample(
            id: "A1-S-0091", tier: "short", domain: "finance",
            raw: "our runway is is is is is eighteen months you know at the the the the current burn rate of two hundred thousand per month so we do not need another round until Q three but I want to be careful here and we should double check the numbers you know what I",
            wordCount: 53,
            requiredAll: ["18", "200000", "not", "Q3"],
            requiredAny: [["200000", "200k", "$200k", "200 K"], ["Q3", "Q 3", "q3", "q 3"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "6", "Q1"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["200000", "200k", "$200k", "200 K"], ["Q3", "Q 3", "q3", "q 3"], ["18"], ["not"]], forbidden: ["6", "Q1"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["6", "Q1"])
            )
        ),
        A1Sample(
            id: "A1-S-0092", tier: "short", domain: "finance",
            raw: "our runway is eighteen I mean months at the the the the current burn rate of two hundred thousand per month so we do not need another round until Q three which is important for the timeline um and then we can decide so please keep me posted on that right so that is",
            wordCount: 54,
            requiredAll: ["18", "200000", "not", "Q3"],
            requiredAny: [["200000", "200k", "$200k", "200 K"], ["Q3", "Q 3", "q3", "q 3"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "6", "Q1"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["200000", "200k", "$200k", "200 K"], ["Q3", "Q 3", "q3", "q 3"], ["18"], ["not"]], forbidden: ["6", "Q1"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["6", "Q1"])
            )
        ),
        A1Sample(
            id: "A1-S-0093", tier: "short", domain: "software/code",
            raw: "update the constant max retry count from three to five and make sure the webhook endpoint uses the the the new authentication token before the deploy um and then we can decide so please keep me posted on that right so that is the plan let me know if that",
            wordCount: 50,
            requiredAll: ["MAX_RETRY_COUNT", "5", "3", "webhook endpoint", "authentication token"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "10", "basic auth"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["MAX_RETRY_COUNT"], ["5"], ["3"], ["webhook endpoint"], ["authentication token"]], forbidden: ["10", "basic auth"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["10", "basic auth"])
            )
        ),
        A1Sample(
            id: "A1-S-0094", tier: "short", domain: "software/code",
            raw: "update the the the constant um max retry count from three to five and make sure the webhook endpoint uses the the the new authentication token before the deploy right so that is the plan let me know if that makes sense so please keep me posted on that right so",
            wordCount: 51,
            requiredAll: ["MAX_RETRY_COUNT", "5", "3", "webhook endpoint", "authentication token"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "10", "basic auth"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["MAX_RETRY_COUNT"], ["5"], ["3"], ["webhook endpoint"], ["authentication token"]], forbidden: ["10", "basic auth"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["10", "basic auth"])
            )
        ),
        A1Sample(
            id: "A1-S-0095", tier: "short", domain: "software/code",
            raw: "update the the the the the the the constant max retry you know count from three to five and make sure the webhook endpoint uses the new authentication token before the deploy and we should double check the numbers you know what I mean as I mentioned earlier in the week which is",
            wordCount: 53,
            requiredAll: ["MAX_RETRY_COUNT", "5", "3", "webhook endpoint", "authentication token"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "10", "basic auth"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["MAX_RETRY_COUNT"], ["5"], ["3"], ["webhook endpoint"], ["authentication token"]], forbidden: ["10", "basic auth"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["10", "basic auth"])
            )
        ),
        A1Sample(
            id: "A1-S-0096", tier: "short", domain: "software/code",
            raw: "update the constant max I mean retry count from three to five and make sure the the the webhook endpoint uses the new authentication token before the deploy I I think that is the right call let me know if that makes sense so please keep me posted on that right so that is",
            wordCount: 54,
            requiredAll: ["MAX_RETRY_COUNT", "5", "3", "webhook endpoint", "authentication token"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "10", "basic auth"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["MAX_RETRY_COUNT"], ["5"], ["3"], ["webhook endpoint"], ["authentication token"]], forbidden: ["10", "basic auth"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["10", "basic auth"])
            )
        ),
        A1Sample(
            id: "A1-S-0097", tier: "short", domain: "meeting",
            raw: "action items Priya will own the the the the roadmap and Marcus will send the minutes by Thursday actually no wait Friday while I follow up with the legal team about the contract as I mentioned earlier in the week which is important for the timeline um and then we",
            wordCount: 50,
            requiredAll: ["Priya", "roadmap", "Marcus", "Friday", "legal"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "Sara"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Priya"], ["roadmap"], ["Marcus"], ["Friday"], ["legal"]], forbidden: ["Monday", "Sara"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "Sara"])
            )
        ),
        A1Sample(
            id: "A1-S-0098", tier: "short", domain: "meeting",
            raw: "action items Priya um will own the the roadmap and Marcus will send the minutes by Friday while I follow up with the the the the the legal team about the contract so please keep me posted on that right so that is the plan let me know if that makes",
            wordCount: 51,
            requiredAll: ["Priya", "roadmap", "Marcus", "Friday", "legal"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "Sara"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Priya"], ["roadmap"], ["Marcus"], ["Friday"], ["legal"]], forbidden: ["Monday", "Sara"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "Sara"])
            )
        ),
        A1Sample(
            id: "A1-S-0099", tier: "short", domain: "meeting",
            raw: "action items Priya will own you know the the the the the the roadmap and Marcus will send the minutes by Friday while I follow up with the the the legal team about the contract but I want to be careful here and we should double check the numbers you know what I",
            wordCount: 53,
            requiredAll: ["Priya", "roadmap", "Marcus", "Friday", "legal"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "Sara"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Priya"], ["roadmap"], ["Marcus"], ["Friday"], ["legal"]], forbidden: ["Monday", "Sara"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "Sara"])
            )
        ),
        A1Sample(
            id: "A1-S-0100", tier: "short", domain: "meeting",
            raw: "action items Priya will I mean own the the roadmap and Marcus will send the minutes by Thursday actually no wait Friday while I follow up with the the the legal team about the contract but I want to be careful here and we should double check the numbers you know what I mean",
            wordCount: 54,
            requiredAll: ["Priya", "roadmap", "Marcus", "Friday", "legal"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "Sara"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Priya"], ["roadmap"], ["Marcus"], ["Friday"], ["legal"]], forbidden: ["Monday", "Sara"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "Sara"])
            )
        ),
        A1Sample(
            id: "A1-L-0001", tier: "long", domain: "software/code",
            raw: "the main thing we need to fix today authentication service because keeps returning a four zero three when token expires and retry logic not backing off properly. Priya suggested we move session state into redish cash so survives a restart but Marcus pointed out that cacheTTL only thirty minutes which too short for our use case. we should also update a p i endpoint to return a proper four two nine when rate limiter trips and then enable open trace logging so we can actually see where latency coming from. deploy scheduled for Wednesday actually no wait Thursday actually no wait Wednesday so we need pull request reviewed by Tuesday morning. do not change timeout constant though because that still under investigation and last time we touched whole staging cluster went red. if all that works we can bump version from two point one to two point two",
            wordCount: 148,
            requiredAll: ["403", "Redis cache", "30", "429", "OpenTelemetry", "Wednesday", "not", "2.1", "2.2"],
            requiredAny: [["403", "four zero three"], ["30", "thirty"], ["429", "four two nine"]],
            forbidden: ["a p i endpoint", "redish cash", "open trace", "the the", "i i i", "it it it", "we we we", "is is is", "500", "Friday", "600"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["30", "thirty"], ["429", "four two nine"], ["Redis cache"], ["OpenTelemetry"], ["Wednesday"], ["not"], ["2.1"], ["2.2"]], forbidden: ["500", "Friday", "600"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["API endpoint"], ["Redis cache"], ["OpenTelemetry"]], forbidden: ["a p i endpoint", "redish cash", "open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "Friday", "600"])
            )
        ),
        A1Sample(
            id: "A1-L-0002", tier: "long", domain: "software/code",
            raw: "the main thing we need to fix today authentication service because keeps returning a four zero three when token expires and retry logic not backing off properly. Priya suggested we move session state into redish cash so survives a restart but Marcus pointed out that cacheTTL only thirty minutes which too short for our use case. we should also update API endpoint to return a proper four two nine when rate limiter trips and then enable open trace logging so we can actually see where latency coming from. deploy scheduled for Thursday actually no wait Wednesday so we need pull request reviewed by Tuesday morning. do not change timeout constant though because that still under investigation and last time we touched whole staging cluster went red. if all that works we can bump the version from two point one to two point two",
            wordCount: 143,
            requiredAll: ["403", "Redis cache", "30", "429", "OpenTelemetry", "Wednesday", "not", "2.1", "2.2"],
            requiredAny: [["403", "four zero three"], ["30", "thirty"], ["429", "four two nine"]],
            forbidden: ["redish cash", "open trace", "the the", "i i i", "it it it", "we we we", "is is is", "500", "Friday", "600"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["30", "thirty"], ["429", "four two nine"], ["Redis cache"], ["OpenTelemetry"], ["Wednesday"], ["not"], ["2.1"], ["2.2"]], forbidden: ["500", "Friday", "600"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["Redis cache"], ["OpenTelemetry"]], forbidden: ["redish cash", "open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "Friday", "600"])
            )
        ),
        A1Sample(
            id: "A1-L-0003", tier: "long", domain: "software/code",
            raw: "the main thing you know we need to fix today authentication service because keeps returning a four zero three when token expires and retry logic not backing off properly. Priya suggested we move session state into redish cash so survives a restart but Marcus pointed out that cacheTTL only thirty minutes which too short for our use case. we should also update a p i endpoint to return a proper four two nine when rate limiter trips and then enable open trace logging so we can actually see where latency coming from. deploy scheduled for Thursday actually no wait Wednesday so we need pull request reviewed by Tuesday morning. do not change timeout constant though because that still under investigation and last time we touched whole staging cluster went red. if all that works we we we can bump version from two point one to two point two",
            wordCount: 148,
            requiredAll: ["403", "Redis cache", "30", "429", "OpenTelemetry", "Wednesday", "not", "2.1", "2.2"],
            requiredAny: [["403", "four zero three"], ["30", "thirty"], ["429", "four two nine"]],
            forbidden: ["a p i endpoint", "redish cash", "open trace", "the the", "i i i", "it it it", "we we we", "is is is", "500", "Friday", "600"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["30", "thirty"], ["429", "four two nine"], ["Redis cache"], ["OpenTelemetry"], ["Wednesday"], ["not"], ["2.1"], ["2.2"]], forbidden: ["500", "Friday", "600"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["API endpoint"], ["Redis cache"], ["OpenTelemetry"]], forbidden: ["a p i endpoint", "redish cash", "open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "Friday", "600"])
            )
        ),
        A1Sample(
            id: "A1-L-0004", tier: "long", domain: "software/code",
            raw: "the main I mean thing we need to fix today authentication service because keeps returning a four zero three when token expires and retry logic not backing off properly. Priya suggested we move session state into Redis cache so survives a restart but Marcus pointed out that cacheTTL only thirty minutes which too short for our use case. we should also update a p i endpoint to return a proper four two nine when rate limiter trips and then enable open trace logging so we can actually see where latency coming from. deploy scheduled for Wednesday actually no wait Thursday actually no wait Wednesday so we need pull request reviewed by Tuesday morning. do not change timeout constant though because that still under investigation and last time we touched whole staging cluster went red. if all that works we can bump version from two point one to two point two",
            wordCount: 150,
            requiredAll: ["403", "Redis cache", "30", "429", "OpenTelemetry", "Wednesday", "not", "2.1", "2.2"],
            requiredAny: [["403", "four zero three"], ["30", "thirty"], ["429", "four two nine"]],
            forbidden: ["a p i endpoint", "open trace", "the the", "i i i", "it it it", "we we we", "is is is", "500", "Friday", "600"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["30", "thirty"], ["429", "four two nine"], ["Redis cache"], ["OpenTelemetry"], ["Wednesday"], ["not"], ["2.1"], ["2.2"]], forbidden: ["500", "Friday", "600"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["API endpoint"], ["OpenTelemetry"]], forbidden: ["a p i endpoint", "open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "Friday", "600"])
            )
        ),
        A1Sample(
            id: "A1-L-0005", tier: "long", domain: "medical",
            raw: "the patient a fifty eight year old woman with a a a history of type two diabetes and hypertension who presented with chest pain that started about three hours ago. she allergic to penicillin so we absolutely cannot give amoxicillin or any related antibiotic and we need to document that clearly in chart. EKG shows no acute ST changes but troponin slightly elevated at zero point four so we will repeat in two hours and keep her on telemetry. the blood pressure is one forty over ninety and the heart rate is eighty eight which is stable for now. we should start aspirin unless there is a contraindication and consult cardiology before discharge. please do not discharge her before the repeat labs come back because the the resident wants to review them first. follow up with her primary care physician in one",
            wordCount: 142,
            requiredAll: ["58", "type 2 diabetes", "penicillin", "not", "0.4", "140", "90", "88"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "1.4", "discharge now"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["58"], ["type 2 diabetes"], ["penicillin"], ["not"], ["0.4"], ["140"], ["90"], ["88"]], forbidden: ["1.4", "discharge now"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["1.4", "discharge now"])
            )
        ),
        A1Sample(
            id: "A1-L-0006", tier: "long", domain: "medical",
            raw: "the patient a fifty eight year old woman with a history of type two diabetes and hypertension who presented with chest pain that started about three hours ago. she allergic to penicillin so we we we absolutely cannot give amoxicillin or any related antibiotic and we need to document that clearly in chart. EKG shows no acute ST changes but troponin slightly elevated at zero point four so we will repeat it in two hours and keep her on telemetry. the blood pressure is one forty over ninety and the heart rate is eighty eight which is stable for now. we should start aspirin unless there is a contraindication and consult cardiology before discharge. please do not discharge her before the repeat labs come back because the the resident wants to review them first. follow up with her primary care physician in one",
            wordCount: 143,
            requiredAll: ["58", "type 2 diabetes", "penicillin", "not", "0.4", "140", "90", "88"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "1.4", "discharge now"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["58"], ["type 2 diabetes"], ["penicillin"], ["not"], ["0.4"], ["140"], ["90"], ["88"]], forbidden: ["1.4", "discharge now"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["1.4", "discharge now"])
            )
        ),
        A1Sample(
            id: "A1-L-0007", tier: "long", domain: "medical",
            raw: "the patient a you know fifty eight year old woman with a history of type two diabetes and hypertension who presented with chest pain that started about three hours ago. she allergic to penicillin so we absolutely cannot give amoxicillin or any related antibiotic and we need to document that clearly in chart. EKG shows no acute ST changes but troponin slightly elevated at zero point four so we will repeat in two hours and keep her on telemetry. blood pressure is one forty over ninety and the heart rate is eighty eight which is stable for now. we should start aspirin unless there is a a a contraindication and consult cardiology before discharge. please do not discharge her before the the the repeat labs come back because the the resident wants to review them first. follow up with her primary care physician in one",
            wordCount: 145,
            requiredAll: ["58", "type 2 diabetes", "penicillin", "not", "0.4", "140", "90", "88"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "1.4", "discharge now"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["58"], ["type 2 diabetes"], ["penicillin"], ["not"], ["0.4"], ["140"], ["90"], ["88"]], forbidden: ["1.4", "discharge now"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["1.4", "discharge now"])
            )
        ),
        A1Sample(
            id: "A1-L-0008", tier: "long", domain: "medical",
            raw: "the patient I mean a fifty eight year old woman with a history of type two diabetes and hypertension who presented with chest pain that started about three hours ago. she allergic to penicillin so we absolutely cannot give amoxicillin or any related antibiotic and we need to document that clearly in chart. the EKG shows no acute ST changes but the troponin is slightly elevated at zero point four so we will repeat it in two hours and keep her on telemetry. the blood pressure is one forty over ninety and the heart rate is eighty eight which is stable for now. we should start aspirin unless there is a contraindication and consult cardiology before discharge. please do not discharge her before the repeat labs come back because the the resident wants to review them first. follow up with her primary care physician in one",
            wordCount: 146,
            requiredAll: ["58", "type 2 diabetes", "penicillin", "not", "0.4", "140", "90", "88"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "1.4", "discharge now"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["58"], ["type 2 diabetes"], ["penicillin"], ["not"], ["0.4"], ["140"], ["90"], ["88"]], forbidden: ["1.4", "discharge now"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["1.4", "discharge now"])
            )
        ),
        A1Sample(
            id: "A1-L-0009", tier: "long", domain: "legal",
            raw: "the motion to suppress was filed on Monday but hearing was continued to following Wednesday actually no wait Thursday because prosecution needed more time to respond. our position is that the evidence was obtained without a a a valid warrant and therefore should be ruled inadmissible under the fourth amendment. the defendant did not consent to the search and no exigent circumstances were present at the time. opposing counsel argues that the good faith exception applies but we disagree because the the affidavit was clearly deficient on its face. we need to file our reply brief by Friday at the latest and I want you to review the citations before then. please do not use the old case law from two thousand eight because it was overruled. if the judge denies the motion we will appeal to the circuit court within thirty",
            wordCount: 142,
            requiredAll: ["Monday", "Thursday", "not", "inadmissible", "Friday", "30", "2008"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "guilty", "consented", "2002"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["Monday"], ["Thursday"], ["not"], ["inadmissible"], ["Friday"], ["2008"]], forbidden: ["guilty", "consented", "2002"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["guilty", "consented", "2002"])
            )
        ),
        A1Sample(
            id: "A1-L-0010", tier: "long", domain: "legal",
            raw: "the motion to suppress was filed on Monday but hearing was continued to the following Thursday because the the prosecution needed more time to respond. our position is that the evidence was obtained without a a a valid warrant and therefore should be ruled inadmissible under the fourth amendment. the defendant did not consent to the search and no exigent circumstances were present at the time. opposing counsel argues that the good faith exception applies but we disagree because the the affidavit was clearly deficient on its face. we need to file our reply brief by Friday at the latest and I want you to review the citations before then. please do not use the the the old case law from two thousand eight because it was overruled. if the judge denies the motion we will appeal to the circuit court within thirty",
            wordCount: 143,
            requiredAll: ["Monday", "Thursday", "not", "inadmissible", "Friday", "30", "2008"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "guilty", "consented", "2002"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["Monday"], ["Thursday"], ["not"], ["inadmissible"], ["Friday"], ["2008"]], forbidden: ["guilty", "consented", "2002"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["guilty", "consented", "2002"])
            )
        ),
        A1Sample(
            id: "A1-L-0011", tier: "long", domain: "legal",
            raw: "the motion to suppress was you know filed on Monday but hearing was continued to following Thursday because the prosecution needed more time to respond. our position is that the evidence was obtained without a valid warrant and therefore should be ruled inadmissible under the fourth amendment. the defendant did not consent to the the the search and no exigent circumstances were present at the the the time. opposing counsel argues that the good faith exception applies but we disagree because the the affidavit was clearly deficient on its face. we need to file our reply brief by Friday at the latest and I want you to review the citations before then. please do not use the old case law from two thousand eight because it was overruled. if the judge denies the the the motion we will appeal to the circuit court within thirty",
            wordCount: 145,
            requiredAll: ["Monday", "Thursday", "not", "inadmissible", "Friday", "30", "2008"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "guilty", "consented", "2002"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["Monday"], ["Thursday"], ["not"], ["inadmissible"], ["Friday"], ["2008"]], forbidden: ["guilty", "consented", "2002"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["guilty", "consented", "2002"])
            )
        ),
        A1Sample(
            id: "A1-L-0012", tier: "long", domain: "legal",
            raw: "the motion to suppress I mean was filed on Monday but hearing was continued to following Wednesday actually no wait Thursday because the the prosecution needed more time to respond. our position is that the evidence was obtained without a valid warrant and therefore should be ruled inadmissible under the fourth amendment. the the the defendant did not consent to the search and no exigent circumstances were present at the time. opposing counsel argues that the good faith exception applies but we disagree because the the affidavit was clearly deficient on its face. we need to file our reply brief by Friday at the latest and I want you to review the citations before then. please do not use the old case law from two thousand eight because it was overruled. if the judge denies the motion we will appeal to the circuit court within thirty",
            wordCount: 146,
            requiredAll: ["Monday", "Thursday", "not", "inadmissible", "Friday", "30", "2008"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "guilty", "consented", "2002"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["Monday"], ["Thursday"], ["not"], ["inadmissible"], ["Friday"], ["2008"]], forbidden: ["guilty", "consented", "2002"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["guilty", "consented", "2002"])
            )
        ),
        A1Sample(
            id: "A1-L-0013", tier: "long", domain: "finance",
            raw: "looking at third quarter numbers revenue came in at two point four million dollars which up from one point eight million in prior quarter and above our guidance of two point one million. main driver was enterprise tier that we shipped in July along with a reduction in churn from three point four percent to two point one percent. gross margin improved to seventy two percent because we moved the heavier workloads off the most expensive instances. operating expenses were four hundred fifty thousand for the quarter and we ended with eighteen months of runway at the the the the current burn rate. we are hiring two point five engineers in Q one and we do not expect to need another financing round before Q three. the CFO will present the full deck to the board on Thursday actually no wait Wednesday",
            wordCount: 142,
            requiredAll: ["Q3", "2.4", "1.8", "2.1", "72%", "450", "18", "2.5", "Q1", "not", "Q3", "Wednesday"],
            requiredAny: [["Q3", "Q 3", "q3", "q 3"], ["Q1", "Q 1", "q1", "q 1"], ["Q3", "Q 3", "q3", "q 3"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "3.4 million", "500"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q3", "Q 3", "q3", "q 3"], ["Q1", "Q 1", "q1", "q 1"], ["Q3", "Q 3", "q3", "q 3"], ["2.4"], ["1.8"], ["2.1"], ["72%"], ["450"], ["18"], ["2.5"], ["not"], ["Wednesday"]], forbidden: ["3.4 million", "500"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["3.4 million", "500"])
            )
        ),
        A1Sample(
            id: "A1-L-0014", tier: "long", domain: "finance",
            raw: "looking at third quarter numbers revenue came in at two point four million dollars which up from one point eight million in prior quarter and above our guidance of two point one million. the main driver was the enterprise tier that we shipped in July along with a a a a a reduction in churn from three point four percent to two point one percent. gross margin improved to seventy two percent because we moved the the heavier workloads off the most expensive instances. operating expenses were four hundred fifty thousand for the quarter and we ended with eighteen months of runway at the the current burn rate. we are hiring two point five engineers in Q one and we do not expect to need another financing round before Q three. the CFO will present the full deck to the board on Wednesday",
            wordCount: 143,
            requiredAll: ["Q3", "2.4", "1.8", "2.1", "72%", "450", "18", "2.5", "Q1", "not", "Q3", "Wednesday"],
            requiredAny: [["Q3", "Q 3", "q3", "q 3"], ["Q1", "Q 1", "q1", "q 1"], ["Q3", "Q 3", "q3", "q 3"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "3.4 million", "500"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q3", "Q 3", "q3", "q 3"], ["Q1", "Q 1", "q1", "q 1"], ["Q3", "Q 3", "q3", "q 3"], ["2.4"], ["1.8"], ["2.1"], ["72%"], ["450"], ["18"], ["2.5"], ["not"], ["Wednesday"]], forbidden: ["3.4 million", "500"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["3.4 million", "500"])
            )
        ),
        A1Sample(
            id: "A1-L-0015", tier: "long", domain: "finance",
            raw: "looking at third quarter you know numbers revenue came in at two point four million dollars which up from one point eight million in prior quarter and above our guidance of two point one million. main driver was enterprise tier that we shipped in July along with a a a a a reduction in churn from three point four percent to two point one percent. gross margin improved to seventy two percent because we moved the the heavier workloads off the most expensive instances. operating expenses were four hundred fifty thousand for the quarter and we ended with eighteen months of runway at the the current burn rate. we are hiring two point five engineers in Q one and we do not expect to need another financing round before Q three. the CFO will present the full deck to the the the board on Wednesday",
            wordCount: 145,
            requiredAll: ["Q3", "2.4", "1.8", "2.1", "72%", "450", "18", "2.5", "Q1", "not", "Q3", "Wednesday"],
            requiredAny: [["Q3", "Q 3", "q3", "q 3"], ["Q1", "Q 1", "q1", "q 1"], ["Q3", "Q 3", "q3", "q 3"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "3.4 million", "500"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q3", "Q 3", "q3", "q 3"], ["Q1", "Q 1", "q1", "q 1"], ["Q3", "Q 3", "q3", "q 3"], ["2.4"], ["1.8"], ["2.1"], ["72%"], ["450"], ["18"], ["2.5"], ["not"], ["Wednesday"]], forbidden: ["3.4 million", "500"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["3.4 million", "500"])
            )
        ),
        A1Sample(
            id: "A1-L-0016", tier: "long", domain: "finance",
            raw: "looking at third I mean quarter numbers revenue came in at two point four million dollars which up from one point eight million in prior quarter and above our guidance of two point one million. main driver was the enterprise tier that we shipped in July along with a reduction in churn from three point four percent to two point one percent. gross margin improved to seventy two percent because we moved the the the the heavier workloads off the most expensive instances. operating expenses were four hundred fifty thousand for the quarter and we ended with eighteen months of runway at the the current burn rate. we are hiring two point five engineers in Q one and we do not expect to need another financing round before Q three. the CFO will present the full deck to the board on Thursday actually no wait Wednesday",
            wordCount: 146,
            requiredAll: ["Q3", "2.4", "1.8", "2.1", "72%", "450", "18", "2.5", "Q1", "not", "Q3", "Wednesday"],
            requiredAny: [["Q3", "Q 3", "q3", "q 3"], ["Q1", "Q 1", "q1", "q 1"], ["Q3", "Q 3", "q3", "q 3"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "3.4 million", "500"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q3", "Q 3", "q3", "q 3"], ["Q1", "Q 1", "q1", "q 1"], ["Q3", "Q 3", "q3", "q 3"], ["2.4"], ["1.8"], ["2.1"], ["72%"], ["450"], ["18"], ["2.5"], ["not"], ["Wednesday"]], forbidden: ["3.4 million", "500"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["3.4 million", "500"])
            )
        ),
        A1Sample(
            id: "A1-L-0017", tier: "long", domain: "meeting",
            raw: "thanks everyone for joining the the weekly sync. quick reminder that the all hands is is is on Thursday actually no wait Friday and the the demo slots are still open so if you want to show something please sign up by Wednesday. the the infrastructure team finished migrating the staging cluster and it is finally green again after being red for most of last week. Priya will own the roadmap update and Marcus will send the minutes by end of day. I do not want us to rehash the the pricing discussion from last time because that is already settled. the open action item is the customer escalation with Acme Corp and Sarah is following up with their legal team about so please keep me posted on that right so that is the plan let me know if that makes sense",
            wordCount: 142,
            requiredAll: ["Friday", "Wednesday", "green", "not", "Priya", "Marcus", "Acme Corp", "Sarah"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "paused"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Friday"], ["Wednesday"], ["green"], ["not"], ["Priya"], ["Marcus"], ["Acme Corp"], ["Sarah"]], forbidden: ["Monday", "paused"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "paused"])
            )
        ),
        A1Sample(
            id: "A1-L-0018", tier: "long", domain: "meeting",
            raw: "thanks everyone for um joining the the weekly sync. quick reminder that the all hands is on Friday and the the demo slots are still open so if you want to show something please sign up by Wednesday. the the infrastructure team finished migrating the staging cluster and it it it is finally green again after being red for most of last week. Priya will own the the the roadmap update and Marcus will send the minutes by end of day. I do not want us to rehash the the pricing discussion from last time because that is already settled. the open action item is the customer escalation with Acme Corp and Sarah is following up with their legal team about the so please keep me posted on that right so that is the plan let me know if that makes sense so",
            wordCount: 143,
            requiredAll: ["Friday", "Wednesday", "green", "not", "Priya", "Marcus", "Acme Corp", "Sarah"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "paused"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Friday"], ["Wednesday"], ["green"], ["not"], ["Priya"], ["Marcus"], ["Acme Corp"], ["Sarah"]], forbidden: ["Monday", "paused"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "paused"])
            )
        ),
        A1Sample(
            id: "A1-L-0019", tier: "long", domain: "meeting",
            raw: "thanks everyone for joining the you know the weekly sync. quick reminder that the all hands is on Friday and the the demo slots are still open so if you want to show something please sign up by Wednesday. the the infrastructure team finished migrating the staging cluster and it is finally green again after being red for most of last week. Priya will own the roadmap update and Marcus will send the minutes by end of day. I do not want us to rehash the the pricing discussion from last time because that is already settled. the the the open action item is the the the customer escalation with Acme Corp and Sarah is is is following up with their legal team about the contract let me know if that makes sense so please keep me posted on that right so that is the",
            wordCount: 145,
            requiredAll: ["Friday", "Wednesday", "green", "not", "Priya", "Marcus", "Acme Corp", "Sarah"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "paused"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Friday"], ["Wednesday"], ["green"], ["not"], ["Priya"], ["Marcus"], ["Acme Corp"], ["Sarah"]], forbidden: ["Monday", "paused"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "paused"])
            )
        ),
        A1Sample(
            id: "A1-L-0020", tier: "long", domain: "meeting",
            raw: "thanks everyone for joining I mean the the weekly sync. quick reminder that the all hands is on Thursday actually no wait Friday and the the demo slots are still open so if you want to show something please sign up by Wednesday. the the infrastructure team finished migrating the the the staging cluster and it is finally green again after being red for most of last week. Priya will own the roadmap update and Marcus will send the minutes by end of day. I do not want us to rehash the the pricing discussion from last time because that is already settled. the open action item is the customer escalation with Acme Corp and Sarah is following up with their legal team about the contract renewal. um and then we can decide so please keep me posted on that right so that is the plan",
            wordCount: 146,
            requiredAll: ["Friday", "Wednesday", "green", "not", "Priya", "Marcus", "Acme Corp", "Sarah"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "paused"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Friday"], ["Wednesday"], ["green"], ["not"], ["Priya"], ["Marcus"], ["Acme Corp"], ["Sarah"]], forbidden: ["Monday", "paused"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "paused"])
            )
        ),
        A1Sample(
            id: "A1-L-0021", tier: "long", domain: "non-native English",
            raw: "sorry my English is not perfect but I will try to explain the the problem clearly. since yesterday morning the production server is down and we are not able to deploy the new version because the pipeline keeps failing with a a a four zero three error. I I think the the issue is that the authentication token expired but the retry logic is not handling it correctly. my teammate said we should restart the service and clear the redish cash but I am not sure if that is safe to do during peak hours. we also noticed the the latency increased from two hundred to eight hundred milliseconds after the last release. as I mentioned earlier in the week which is important for the timeline um and then we can decide so please keep me posted on that right so that",
            wordCount: 142,
            requiredAll: ["not", "yesterday", "403", "Redis cache", "200", "800"],
            requiredAny: [["403", "four zero three"], ["200", "two hundred"], ["800", "eight hundred"]],
            forbidden: ["redish cash", "the the", "i i i", "it it it", "we we we", "is is is", "404", "500"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["200", "two hundred"], ["800", "eight hundred"], ["not"], ["yesterday"], ["Redis cache"]], forbidden: ["404", "500"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["Redis cache"]], forbidden: ["redish cash"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["404", "500"])
            )
        ),
        A1Sample(
            id: "A1-L-0022", tier: "long", domain: "non-native English",
            raw: "sorry my English um is not perfect but I will try to explain the the the the problem clearly. since yesterday morning the production server is down and we are not able to deploy the new version because the pipeline keeps failing with a four zero three error. I I think the the issue is that the authentication token expired but the retry logic is is is not handling it correctly. my teammate said we should restart the service and clear the Redis cache but I am not sure if that is safe to do during peak hours. we also noticed the the latency increased from two hundred to eight hundred milliseconds after the last release. um and then we can decide so please keep me posted on that right so that is the plan let me know if that makes sense so",
            wordCount: 143,
            requiredAll: ["not", "yesterday", "403", "Redis cache", "200", "800"],
            requiredAny: [["403", "four zero three"], ["200", "two hundred"], ["800", "eight hundred"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "404", "500"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["200", "two hundred"], ["800", "eight hundred"], ["not"], ["yesterday"], ["Redis cache"]], forbidden: ["404", "500"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["404", "500"])
            )
        ),
        A1Sample(
            id: "A1-L-0023", tier: "long", domain: "non-native English",
            raw: "sorry my English is is is not you know perfect but I will try to explain the the the the problem clearly. since yesterday morning the production server is down and we are not able to deploy the new version because the pipeline keeps failing with a four zero three error. I I think the the issue is that the authentication token expired but the the the retry logic is not handling it correctly. my teammate said we should restart the service and clear the redish cash but I am not sure if that is safe to do during peak hours. we also noticed the the latency increased from two hundred to eight hundred milliseconds after the last release. you know what I mean as I mentioned earlier in the week which is important for the timeline um and then we can decide so please",
            wordCount: 145,
            requiredAll: ["not", "yesterday", "403", "Redis cache", "200", "800"],
            requiredAny: [["403", "four zero three"], ["200", "two hundred"], ["800", "eight hundred"]],
            forbidden: ["redish cash", "the the", "i i i", "it it it", "we we we", "is is is", "404", "500"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["200", "two hundred"], ["800", "eight hundred"], ["not"], ["yesterday"], ["Redis cache"]], forbidden: ["404", "500"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["Redis cache"]], forbidden: ["redish cash"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["404", "500"])
            )
        ),
        A1Sample(
            id: "A1-L-0024", tier: "long", domain: "non-native English",
            raw: "sorry my English is I mean not perfect but I will try to explain the the problem clearly. since yesterday morning the production server is is is down and we are not able to deploy the new version because the pipeline keeps failing with a four zero three error. I I think the the issue is that the authentication token expired but the retry logic is not handling it correctly. my teammate said we should restart the service and clear the Redis cache but I am not sure if that is safe to do during peak hours. we also noticed the the latency increased from two hundred to eight hundred milliseconds after the last release. but I want to be careful here and we should double check the numbers you know what I mean as I mentioned earlier in the week which is important for the",
            wordCount: 146,
            requiredAll: ["not", "yesterday", "403", "Redis cache", "200", "800"],
            requiredAny: [["403", "four zero three"], ["200", "two hundred"], ["800", "eight hundred"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "404", "500"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["200", "two hundred"], ["800", "eight hundred"], ["not"], ["yesterday"], ["Redis cache"]], forbidden: ["404", "500"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["404", "500"])
            )
        ),
        A1Sample(
            id: "A1-L-0025", tier: "long", domain: "extreme Unicode",
            raw: "the the documents for the contrat r sum and the the the caf translation are stored in the Z rich office and need to be reviewed before the S o Paulo meeting on Thursday. please make sure the na ve assumption about the d j vu clause is removed from the draft and replace it with the corrected text from the attorney. the r sum of the candidate includes aGitHub link and a na ve estimate of the the workload that we should verify. we also need the the simplification for the pi ata and the croissant examples before the demo. if the encoding looks wrong in the email please reply and I will resend it as a plain text attachment rather than a PDF. let me know if that makes sense so please keep me posted on that right so that",
            wordCount: 142,
            requiredAll: ["contrat", "résumé", "café", "Zürich", "São Paulo", "naïve", "déjà vu"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "München", "Lisbon"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["contrat"], ["résumé"], ["café"], ["Zürich"], ["São Paulo"], ["naïve"], ["déjà vu"]], forbidden: ["München", "Lisbon"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["München", "Lisbon"])
            )
        ),
        A1Sample(
            id: "A1-L-0026", tier: "long", domain: "extreme Unicode",
            raw: "the the documents um for the contrat r sum and the caf translation are stored in the Z rich office and need to be reviewed before the S o Paulo meeting on Thursday. please make sure the na ve assumption about the d j vu clause is is is removed from the draft and replace it with the corrected text from the attorney. the r sum of the candidate includes aGitHub link and a na ve estimate of the the workload that we should verify. we also need the the the the simplification for the pi ata and the croissant examples before the demo. if the encoding looks wrong in the email please reply and I will resend it as a plain text attachment rather than a PDF. you know what I mean as I mentioned earlier in the week which is important",
            wordCount: 143,
            requiredAll: ["contrat", "résumé", "café", "Zürich", "São Paulo", "naïve", "déjà vu"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "München", "Lisbon"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["contrat"], ["résumé"], ["café"], ["Zürich"], ["São Paulo"], ["naïve"], ["déjà vu"]], forbidden: ["München", "Lisbon"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["München", "Lisbon"])
            )
        ),
        A1Sample(
            id: "A1-L-0027", tier: "long", domain: "extreme Unicode",
            raw: "the the documents for the you know contrat r sum and the caf translation are stored in the Z rich office and need to be reviewed before the the the S o Paulo meeting on Thursday. please make sure the na ve assumption about the d j vu clause is removed from the draft and replace it with the corrected text from the attorney. the r sum of the candidate includes aGitHub link and a na ve estimate of the the the the workload that we should verify. we also need the the simplification for the pi ata and the croissant examples before the demo. if the encoding looks wrong in the the the email please reply and I will resend it as a plain text attachment rather than a PDF. which is important for the timeline um and then we can decide so please",
            wordCount: 145,
            requiredAll: ["contrat", "résumé", "café", "Zürich", "São Paulo", "naïve", "déjà vu"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "München", "Lisbon"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["contrat"], ["résumé"], ["café"], ["Zürich"], ["São Paulo"], ["naïve"], ["déjà vu"]], forbidden: ["München", "Lisbon"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["München", "Lisbon"])
            )
        ),
        A1Sample(
            id: "A1-L-0028", tier: "long", domain: "extreme Unicode",
            raw: "the the documents for I mean the contrat r sum and the caf translation are stored in the Z rich office and need to be reviewed before the S o Paulo meeting on Thursday. please make sure the na ve assumption about the d j vu clause is removed from the draft and replace it with the corrected text from the attorney. the r sum of the candidate includes aGitHub link and a na ve estimate of the the workload that we should verify. we also need the the simplification for the pi ata and the croissant examples before the demo. if the encoding looks wrong in the the the email please reply and I will resend it as a plain text attachment rather than a PDF. um and then we can decide so please keep me posted on that right so that is the plan",
            wordCount: 146,
            requiredAll: ["contrat", "résumé", "café", "Zürich", "São Paulo", "naïve", "déjà vu"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "München", "Lisbon"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["contrat"], ["résumé"], ["café"], ["Zürich"], ["São Paulo"], ["naïve"], ["déjà vu"]], forbidden: ["München", "Lisbon"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["München", "Lisbon"])
            )
        ),
        A1Sample(
            id: "A1-L-0029", tier: "long", domain: "noisy ASR",
            raw: "uh so the the deployment failed again last night and I I think it was a four zero three followed by a four two nine and then uh a five oh three from the gateway. the the logs are hard to read because there is a lot of noise but the the main error seems to be a connection timeout after thirty seconds. we are not sure if the database is the problem or if it is just the the load balancer. can someone check the metrics for the last two hours and tell me whether the the the the error rate went above five percent. if it did we should roll back to version one point nine immediately. please do not so please keep me posted on that right so that is the plan let me know if that makes sense",
            wordCount: 142,
            requiredAll: ["403", "429", "503", "30", "not", "5%", "1.9"],
            requiredAny: [["403", "four zero three"], ["429", "four two nine"], ["503", "five oh three"], ["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "200", "merge now"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["429", "four two nine"], ["503", "five oh three"], ["30", "thirty"], ["not"], ["5%"], ["1.9"]], forbidden: ["200", "merge now"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["200", "merge now"])
            )
        ),
        A1Sample(
            id: "A1-L-0030", tier: "long", domain: "noisy ASR",
            raw: "uh so the um the deployment failed again last night and I I think it was a four zero three followed by a four two nine and then uh a five oh three from the gateway. the the logs are hard to read because there is a lot of noise but the the main error seems to be a connection timeout after thirty seconds. we are not sure if the database is the problem or if it is is is just the the load balancer. can someone check the metrics for the last two hours and tell me whether the the error rate went above five percent. if it did we we we should roll back to version one point nine immediately. please do not let me know if that makes sense so please keep me posted on that right so that is",
            wordCount: 143,
            requiredAll: ["403", "429", "503", "30", "not", "5%", "1.9"],
            requiredAny: [["403", "four zero three"], ["429", "four two nine"], ["503", "five oh three"], ["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "200", "merge now"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["429", "four two nine"], ["503", "five oh three"], ["30", "thirty"], ["not"], ["5%"], ["1.9"]], forbidden: ["200", "merge now"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["200", "merge now"])
            )
        ),
        A1Sample(
            id: "A1-L-0031", tier: "long", domain: "noisy ASR",
            raw: "uh so the the the the deployment you know failed again last night and I I think it was a four zero three followed by a four two nine and then uh a five oh three from the gateway. the the logs are hard to read because there is a lot of noise but the the the the main error seems to be a connection timeout after thirty seconds. we are not sure if the database is the problem or if it is just the the load balancer. can someone check the metrics for the last two hours and tell me whether the the the the error rate went above five percent. if it did we should roll back to version one point nine immediately. please do not I I think that is the right call let me know if that makes sense so please",
            wordCount: 145,
            requiredAll: ["403", "429", "503", "30", "not", "5%", "1.9"],
            requiredAny: [["403", "four zero three"], ["429", "four two nine"], ["503", "five oh three"], ["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "200", "merge now"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["429", "four two nine"], ["503", "five oh three"], ["30", "thirty"], ["not"], ["5%"], ["1.9"]], forbidden: ["200", "merge now"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["200", "merge now"])
            )
        ),
        A1Sample(
            id: "A1-L-0032", tier: "long", domain: "noisy ASR",
            raw: "uh so the the I mean deployment failed again last night and I I think it was a four zero three followed by a four two nine and then uh a five oh three from the gateway. the the logs are hard to read because there is a lot of noise but the the main error seems to be a connection timeout after thirty seconds. we are not sure if the database is is is the problem or if it is just the the load balancer. can someone check the metrics for the last two hours and tell me whether the the error rate went above five percent. if it did we should roll back to version one point nine immediately. please do not as I mentioned earlier in the week which is important for the timeline um and then we can decide so please keep",
            wordCount: 146,
            requiredAll: ["403", "429", "503", "30", "not", "5%", "1.9"],
            requiredAny: [["403", "four zero three"], ["429", "four two nine"], ["503", "five oh three"], ["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "200", "merge now"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["403", "four zero three"], ["429", "four two nine"], ["503", "five oh three"], ["30", "thirty"], ["not"], ["5%"], ["1.9"]], forbidden: ["200", "merge now"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["200", "merge now"])
            )
        ),
        A1Sample(
            id: "A1-L-0033", tier: "long", domain: "coding interview",
            raw: "so for this problem I would first clarify the constraints and then probably use a hash map to track the the frequency of each element. that gives us O of n time and O of n space because in the worst case we store every distinct value. I I considered sorting first but that would be O of n log n which is slower than the hash map approach. the the the the edge cases are an empty input and a single element and we should also handle negative numbers correctly. we can avoid double counting by checking whether the complement already exists in the map before inserting the current value. the the interviewer asked me to optimize the space but I explained that O of n I I think that is the right call let me know if that makes sense",
            wordCount: 142,
            requiredAll: ["hash map", "O(n)", "O(n log n)", "not", "empty"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "O(n^2)", "binary search"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["hash map"], ["O(n)"], ["O(n log n)"], ["not"], ["empty"]], forbidden: ["O(n^2)", "binary search"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["O(n^2)", "binary search"])
            )
        ),
        A1Sample(
            id: "A1-L-0034", tier: "long", domain: "coding interview",
            raw: "so for this um problem I would first clarify the the the constraints and then probably use a hash map to track the the the the frequency of each element. that gives us O of n time and O of n space because in the worst case we store every distinct value. I I considered sorting first but that would be O of n log n which is slower than the hash map approach. the the edge cases are an empty input and a single element and we should also handle negative numbers correctly. we can avoid double counting by checking whether the complement already exists in the map before inserting the current value. the the interviewer asked me to optimize the space but I explained that O of n which is important for the timeline um and then we can decide so",
            wordCount: 143,
            requiredAll: ["hash map", "O(n)", "O(n log n)", "not", "empty"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "O(n^2)", "binary search"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["hash map"], ["O(n)"], ["O(n log n)"], ["not"], ["empty"]], forbidden: ["O(n^2)", "binary search"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["O(n^2)", "binary search"])
            )
        ),
        A1Sample(
            id: "A1-L-0035", tier: "long", domain: "coding interview",
            raw: "so for this problem I you know would first clarify the constraints and then probably use a hash map to track the the the the frequency of each element. that gives us O of n time and O of n space because in the worst case we we we store every distinct value. I I considered sorting first but that would be O of n log n which is slower than the hash map approach. the the the the edge cases are an empty input and a single element and we should also handle negative numbers correctly. we can avoid double counting by checking whether the complement already exists in the map before inserting the current value. the the interviewer asked me to optimize the space but I explained that O of n so please keep me posted on that right so that is the",
            wordCount: 145,
            requiredAll: ["hash map", "O(n)", "O(n log n)", "not", "empty"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "O(n^2)", "binary search"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["hash map"], ["O(n)"], ["O(n log n)"], ["not"], ["empty"]], forbidden: ["O(n^2)", "binary search"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["O(n^2)", "binary search"])
            )
        ),
        A1Sample(
            id: "A1-L-0036", tier: "long", domain: "coding interview",
            raw: "so for this problem I mean I would first clarify the the the constraints and then probably use a hash map to track the the frequency of each element. that gives us O of n time and O of n space because in the worst case we store every distinct value. I I considered sorting first but that would be O of n log n which is slower than the hash map approach. the the edge cases are an empty input and a single element and we should also handle negative numbers correctly. we can avoid double counting by checking whether the complement already exists in the map before inserting the current value. the the interviewer asked me to optimize the space but I explained that O of n you know what I mean as I mentioned earlier in the week which is important for the",
            wordCount: 146,
            requiredAll: ["hash map", "O(n)", "O(n log n)", "not", "empty"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "O(n^2)", "binary search"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["hash map"], ["O(n)"], ["O(n log n)"], ["not"], ["empty"]], forbidden: ["O(n^2)", "binary search"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["O(n^2)", "binary search"])
            )
        ),
        A1Sample(
            id: "A1-L-0037", tier: "long", domain: "customer support",
            raw: "thank you for calling support my name is Alex and I am sorry about the the the the issue with your order. can you confirm the the order number please it is four eight two one okay thank you. I can see here that the payment of ninety nine dollars did not go through because the card was declined so the the order has not shipped yet. I I understand this is frustrating and I apologize for the inconvenience. I can retry the the charge now if you would like and we will expedite the shipping at no extra cost. the the estimated delivery would be Wednesday actually no wait Thursday instead of next Monday. let me know if that makes sense so please keep me posted on that right so that is the plan let me know if that makes sense",
            wordCount: 142,
            requiredAll: ["4821", "99", "not", "Thursday", "Monday"],
            requiredAny: [["99", "ninety nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "4822", "delivered"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["99", "ninety nine"], ["4821"], ["not"], ["Thursday"], ["Monday"]], forbidden: ["4822", "delivered"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["4822", "delivered"])
            )
        ),
        A1Sample(
            id: "A1-L-0038", tier: "long", domain: "customer support",
            raw: "thank you for um calling support my name is Alex and I am sorry about the the issue with your order. can you confirm the the order number please it it it is four eight two one okay thank you. I can see here that the payment of ninety nine dollars did not go through because the card was declined so the the order has not shipped yet. I I understand this is frustrating and I apologize for the inconvenience. I can retry the the charge now if you would like and we will expedite the shipping at no extra cost. the the the the estimated delivery would be Thursday instead of next Monday. but I want to be careful here and we should double check the numbers you know what I mean as I mentioned earlier in the week which is important",
            wordCount: 143,
            requiredAll: ["4821", "99", "not", "Thursday", "Monday"],
            requiredAny: [["99", "ninety nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "4822", "delivered"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["99", "ninety nine"], ["4821"], ["not"], ["Thursday"], ["Monday"]], forbidden: ["4822", "delivered"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["4822", "delivered"])
            )
        ),
        A1Sample(
            id: "A1-L-0039", tier: "long", domain: "customer support",
            raw: "thank you for calling support you know my name is is is Alex and I am sorry about the the issue with your order. can you confirm the the order number please it is four eight two one okay thank you. I can see here that the payment of ninety nine dollars did not go through because the card was declined so the the the the the the order has not shipped yet. I I understand this is frustrating and I apologize for the inconvenience. I can retry the the charge now if you would like and we will expedite the shipping at no extra cost. the the estimated delivery would be Thursday instead of next Monday. um and then we can decide so please keep me posted on that right so that is the plan let me know if that makes sense so please",
            wordCount: 145,
            requiredAll: ["4821", "99", "not", "Thursday", "Monday"],
            requiredAny: [["99", "ninety nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "4822", "delivered"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["99", "ninety nine"], ["4821"], ["not"], ["Thursday"], ["Monday"]], forbidden: ["4822", "delivered"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["4822", "delivered"])
            )
        ),
        A1Sample(
            id: "A1-L-0040", tier: "long", domain: "customer support",
            raw: "thank you for calling I mean support my name is Alex and I am sorry about the the issue with your order. can you confirm the the order number please it is four eight two one okay thank you. I can see here that the payment of ninety nine dollars did not go through because the card was declined so the the the the order has not shipped yet. I I understand this is frustrating and I apologize for the inconvenience. I can retry the the charge now if you would like and we will expedite the shipping at no extra cost. the the estimated delivery would be Wednesday actually no wait Thursday instead of next Monday. is there anything else I can help you with today um and then we can decide so please keep me posted on that right so that is the plan",
            wordCount: 146,
            requiredAll: ["4821", "99", "not", "Thursday", "Monday"],
            requiredAny: [["99", "ninety nine"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "4822", "delivered"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["99", "ninety nine"], ["4821"], ["not"], ["Thursday"], ["Monday"]], forbidden: ["4822", "delivered"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["4822", "delivered"])
            )
        ),
        A1Sample(
            id: "A1-L-0041", tier: "long", domain: "sales call",
            raw: "thanks for taking the time today. as I mentioned the the standard license is twelve thousand dollars per year but if you can sign by Thursday actually no wait Friday we can offer a fifteen percent discount which brings it to ten thousand two hundred. I I know the budget conversation was difficult last quarter and I do not want to push you into something that does not make sense. the the main thing your team gets is the the the enterprise support and the guaranteed uptime of ninety nine point nine percent. Sarah from our legal team can send the the revised contract today so your counsel can review it over the weekend. if everything looks good we can do a kickoff call on Monday um and then we can decide so please keep me posted on that right so that",
            wordCount: 142,
            requiredAll: ["12000", "Friday", "15%", "10200", "99.9", "Monday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "20%", "20000"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["12000"], ["Friday"], ["15%"], ["10200"], ["99.9"], ["Monday"]], forbidden: ["20%", "20000"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["20%", "20000"])
            )
        ),
        A1Sample(
            id: "A1-L-0042", tier: "long", domain: "sales call",
            raw: "thanks for taking um the time today. as I mentioned the the standard license is twelve thousand dollars per year but if you can sign by Friday we can offer a fifteen percent discount which brings it to ten thousand two hundred. I I know the the the budget conversation was difficult last quarter and I do not want to push you into something that does not make sense. the the main thing your team gets is the enterprise support and the guaranteed uptime of ninety nine point nine percent. Sarah from our legal team can send the the the the revised contract today so your counsel can review it over the weekend. if everything looks good we can do a kickoff call on Monday let me know if that makes sense so please keep me posted on that right so that is",
            wordCount: 143,
            requiredAll: ["12000", "Friday", "15%", "10200", "99.9", "Monday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "20%", "20000"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["12000"], ["Friday"], ["15%"], ["10200"], ["99.9"], ["Monday"]], forbidden: ["20%", "20000"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["20%", "20000"])
            )
        ),
        A1Sample(
            id: "A1-L-0043", tier: "long", domain: "sales call",
            raw: "thanks for taking the the the time you know today. as I mentioned the the the the the the standard license is twelve thousand dollars per year but if you can sign by Friday we can offer a fifteen percent discount which brings it to ten thousand two hundred. I I know the budget conversation was difficult last quarter and I do not want to push you into something that does not make sense. the the main thing your team gets is the enterprise support and the guaranteed uptime of ninety nine point nine percent. Sarah from our legal team can send the the revised contract today so your counsel can review it over the weekend. if everything looks good we can do a kickoff call on Monday I I think that is the right call let me know if that makes sense so please",
            wordCount: 145,
            requiredAll: ["12000", "Friday", "15%", "10200", "99.9", "Monday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "20%", "20000"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["12000"], ["Friday"], ["15%"], ["10200"], ["99.9"], ["Monday"]], forbidden: ["20%", "20000"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["20%", "20000"])
            )
        ),
        A1Sample(
            id: "A1-L-0044", tier: "long", domain: "sales call",
            raw: "thanks for taking the I mean time today. as I mentioned the the standard license is twelve thousand dollars per year but if you can sign by Thursday actually no wait Friday we can offer a fifteen percent discount which brings it to ten thousand two hundred. I I know the budget conversation was difficult last quarter and I do not want to push you into something that does not make sense. the the main thing your team gets is is is the enterprise support and the guaranteed uptime of ninety nine point nine percent. Sarah from our legal team can send the the revised contract today so your counsel can review it over the weekend. if everything looks good we can do a kickoff call on Monday I I think that is the right call let me know if that makes sense so please keep",
            wordCount: 146,
            requiredAll: ["12000", "Friday", "15%", "10200", "99.9", "Monday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "20%", "20000"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["12000"], ["Friday"], ["15%"], ["10200"], ["99.9"], ["Monday"]], forbidden: ["20%", "20000"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["20%", "20000"])
            )
        ),
        A1Sample(
            id: "A1-L-0045", tier: "long", domain: "science",
            raw: "in this experiment we measured the reaction rate at three different temperatures to test the the hypothesis that higher heat increases the yield. the the sample at thirty seven degrees Celsius produced the highest yield at eighty two percent while the control at twenty degrees produced only sixty one percent. the p value was zero point zero three which is statistically significant but I want to be careful because the sample size of thirty is fairly small. we did not observe any side reactions at the the higher temperature which supports our original assumption. the the the the next step is to repeat the trial with a larger sample and to verify the the result using the second method. please make sure the the data is recorded in the lab notebook before Friday. as I mentioned earlier in the week which is",
            wordCount: 142,
            requiredAll: ["37", "82%", "61%", "0.03", "not", "30", "Friday"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "0.3", "conclusive"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["37"], ["82%"], ["61%"], ["0.03"], ["not"], ["Friday"]], forbidden: ["0.3", "conclusive"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["0.3", "conclusive"])
            )
        ),
        A1Sample(
            id: "A1-L-0046", tier: "long", domain: "science",
            raw: "in this experiment um we measured the reaction rate at three different temperatures to test the the hypothesis that higher heat increases the the the yield. the the sample at thirty seven degrees Celsius produced the highest yield at eighty two percent while the control at twenty degrees produced only sixty one percent. the p value was zero point zero three which is statistically significant but I want to be careful because the sample size of thirty is fairly small. we did not observe any side reactions at the the higher temperature which supports our original assumption. the the next step is to repeat the trial with a larger sample and to verify the the result using the second method. please make sure the the the the data is recorded in the lab notebook before Friday. um and then we can decide so",
            wordCount: 143,
            requiredAll: ["37", "82%", "61%", "0.03", "not", "30", "Friday"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "0.3", "conclusive"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["37"], ["82%"], ["61%"], ["0.03"], ["not"], ["Friday"]], forbidden: ["0.3", "conclusive"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["0.3", "conclusive"])
            )
        ),
        A1Sample(
            id: "A1-L-0047", tier: "long", domain: "science",
            raw: "in this experiment we measured you know the reaction rate at three different temperatures to test the the hypothesis that higher heat increases the yield. the the sample at thirty seven degrees Celsius produced the highest yield at eighty two percent while the control at twenty degrees produced only sixty one percent. the p value was zero point zero three which is is is statistically significant but I want to be careful because the sample size of thirty is fairly small. we did not observe any side reactions at the the the the the the higher temperature which supports our original assumption. the the next step is to repeat the trial with a larger sample and to verify the the result using the second method. please make sure the the data is recorded in the lab notebook before Friday. you know what I mean as",
            wordCount: 145,
            requiredAll: ["37", "82%", "61%", "0.03", "not", "30", "Friday"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "0.3", "conclusive"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["37"], ["82%"], ["61%"], ["0.03"], ["not"], ["Friday"]], forbidden: ["0.3", "conclusive"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["0.3", "conclusive"])
            )
        ),
        A1Sample(
            id: "A1-L-0048", tier: "long", domain: "science",
            raw: "in this experiment we I mean measured the reaction rate at three different temperatures to test the the hypothesis that higher heat increases the yield. the the sample at thirty seven degrees Celsius produced the highest yield at eighty two percent while the control at twenty degrees produced only sixty one percent. the p value was zero point zero three which is statistically significant but I want to be careful because the sample size of thirty is fairly small. we did not observe any side reactions at the the the the higher temperature which supports our original assumption. the the next step is to repeat the trial with a larger sample and to verify the the result using the second method. please make sure the the data is recorded in the lab notebook before Friday. but I want to be careful here and we should double",
            wordCount: 146,
            requiredAll: ["37", "82%", "61%", "0.03", "not", "30", "Friday"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "0.3", "conclusive"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["37"], ["82%"], ["61%"], ["0.03"], ["not"], ["Friday"]], forbidden: ["0.3", "conclusive"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["0.3", "conclusive"])
            )
        ),
        A1Sample(
            id: "A1-L-0049", tier: "long", domain: "email",
            raw: "hi team just a quick follow up on the the contract review. I have attached the the revised version with the changes that Sarah requested on Tuesday and I believe we have addressed all of the the open comments. the the main change is the payment term which is now net thirty instead of net sixty and the the liability cap is updated to the amount specified in section nine. please do not forward this to the client until the legal team has signed off because we want to make sure the the language is consistent with the master agreement. if you have any comments can you leave them in the document by Wednesday actually no wait Thursday evening so I can send the the the the final copy on Friday and we should double check the numbers you know what I",
            wordCount: 142,
            requiredAll: ["Tuesday", "30", "60", "9", "not", "Thursday", "Friday"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "section 5"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["Tuesday"], ["60"], ["9"], ["not"], ["Thursday"], ["Friday"]], forbidden: ["Monday", "section 5"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "section 5"])
            )
        ),
        A1Sample(
            id: "A1-L-0050", tier: "long", domain: "email",
            raw: "hi team just um a quick follow up on the the contract review. I have attached the the the the revised version with the changes that Sarah requested on Tuesday and I believe we have addressed all of the the open comments. the the main change is the payment term which is now net thirty instead of net sixty and the the liability cap is is is updated to the amount specified in section nine. please do not forward this to the client until the legal team has signed off because we want to make sure the the language is consistent with the master agreement. if you have any comments can you leave them in the document by Thursday evening so I can send the the final copy on Friday which is important for the timeline um and then we can decide so",
            wordCount: 143,
            requiredAll: ["Tuesday", "30", "60", "9", "not", "Thursday", "Friday"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "section 5"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["Tuesday"], ["60"], ["9"], ["not"], ["Thursday"], ["Friday"]], forbidden: ["Monday", "section 5"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "section 5"])
            )
        ),
        A1Sample(
            id: "A1-L-0051", tier: "long", domain: "email",
            raw: "hi team just a quick you know follow up on the the contract review. I have attached the the the the revised version with the changes that Sarah requested on Tuesday and I believe we have addressed all of the the open comments. the the the the main change is the payment term which is now net thirty instead of net sixty and the the liability cap is updated to the amount specified in section nine. please do not forward this to the client until the legal team has signed off because we want to make sure the the the the language is consistent with the master agreement. if you have any comments can you leave them in the document by Thursday evening so I can send the the final copy on Friday so please keep me posted on that right so that is the",
            wordCount: 145,
            requiredAll: ["Tuesday", "30", "60", "9", "not", "Thursday", "Friday"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "section 5"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["Tuesday"], ["60"], ["9"], ["not"], ["Thursday"], ["Friday"]], forbidden: ["Monday", "section 5"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "section 5"])
            )
        ),
        A1Sample(
            id: "A1-L-0052", tier: "long", domain: "email",
            raw: "hi team just a I mean quick follow up on the the contract review. I have attached the the revised version with the changes that Sarah requested on Tuesday and I believe we have addressed all of the the open comments. the the main change is the payment term which is now net thirty instead of net sixty and the the liability cap is updated to the amount specified in section nine. please do not forward this to the client until the the the legal team has signed off because we want to make sure the the language is consistent with the master agreement. if you have any comments can you leave them in the document by Wednesday actually no wait Thursday evening so I can send the the final copy on Friday so please keep me posted on that right so that is the plan",
            wordCount: 146,
            requiredAll: ["Tuesday", "30", "60", "9", "not", "Thursday", "Friday"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Monday", "section 5"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["Tuesday"], ["60"], ["9"], ["not"], ["Thursday"], ["Friday"]], forbidden: ["Monday", "section 5"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Monday", "section 5"])
            )
        ),
        A1Sample(
            id: "A1-L-0053", tier: "long", domain: "standup",
            raw: "yesterday I finished the the auth flow refactor and I also fixed the bug in the billing service that Marcus reported on Wednesday. today I am going to review the pull request for the API contract and then pair with Priya on the the caching layer unless something more urgent comes up. the the main blocker is is is that the staging cluster is still red because the the migration did not complete over the weekend. I do not think that will affect our Thursday actually no wait Friday demo but I will confirm with the infrastructure team after this meeting. if the the API contract changes again we may need to push the release to next Tuesday. you know what I mean as I mentioned earlier in the week which is important for the timeline um and then we can decide",
            wordCount: 142,
            requiredAll: ["Wednesday", "API", "Priya", "red", "not", "Friday", "Tuesday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "green", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Wednesday"], ["API"], ["Priya"], ["red"], ["not"], ["Friday"], ["Tuesday"]], forbidden: ["green", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["green", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-L-0054", tier: "long", domain: "standup",
            raw: "yesterday I finished um the the auth flow refactor and I also fixed the bug in the billing service that Marcus reported on Wednesday. today I am going to review the the the pull request for the API contract and then pair with Priya on the the caching layer unless something more urgent comes up. the the main blocker is that the staging cluster is still red because the the migration did not complete over the weekend. I do not think that will affect our Friday demo but I will confirm with the infrastructure team after this meeting. if the the the the API contract changes again we may need to push the release to next Tuesday. I I think that is the right call let me know if that makes sense so please keep me posted on that right so that is",
            wordCount: 143,
            requiredAll: ["Wednesday", "API", "Priya", "red", "not", "Friday", "Tuesday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "green", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Wednesday"], ["API"], ["Priya"], ["red"], ["not"], ["Friday"], ["Tuesday"]], forbidden: ["green", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["green", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-L-0055", tier: "long", domain: "standup",
            raw: "yesterday I finished the the you know auth flow refactor and I also fixed the bug in the billing service that Marcus reported on Wednesday. today I am going to review the pull request for the API contract and then pair with Priya on the the the the caching layer unless something more urgent comes up. the the main blocker is that the staging cluster is still red because the the migration did not complete over the weekend. I do not think that will affect our Friday demo but I will confirm with the the the infrastructure team after this meeting. if the the the the API contract changes again we may need to push the release to next Tuesday. right so that is the plan let me know if that makes sense so please keep me posted on that right so that is the",
            wordCount: 145,
            requiredAll: ["Wednesday", "API", "Priya", "red", "not", "Friday", "Tuesday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "green", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Wednesday"], ["API"], ["Priya"], ["red"], ["not"], ["Friday"], ["Tuesday"]], forbidden: ["green", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["green", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-L-0056", tier: "long", domain: "standup",
            raw: "yesterday I finished the I mean the auth flow refactor and I also fixed the bug in the billing service that Marcus reported on Wednesday. today I am going to review the pull request for the API contract and then pair with Priya on the the caching layer unless something more urgent comes up. the the main blocker is that the staging cluster is still red because the the migration did not complete over the weekend. I do not think that will affect our Thursday actually no wait Friday demo but I will confirm with the infrastructure team after this meeting. if the the API contract changes again we may need to push the the the release to next Tuesday. right so that is the plan let me know if that makes sense so please keep me posted on that right so that is the plan",
            wordCount: 146,
            requiredAll: ["Wednesday", "API", "Priya", "red", "not", "Friday", "Tuesday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "green", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Wednesday"], ["API"], ["Priya"], ["red"], ["not"], ["Friday"], ["Tuesday"]], forbidden: ["green", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["green", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-L-0057", tier: "long", domain: "personal notes",
            raw: "okay so I need to remember a few things for this weekend. first call Mom on Sunday because I forgot last week and she asked about the the family dinner. second pick up the prescription from the pharmacy before the the the the office closes at five p m because otherwise I will not have it until Monday. third I should probably clean the the apartment before Priya comes over on Saturday afternoon. I also want to finish the book that I started on the the train because I am almost at the the last chapter. do not forget to set the alarm for six thirty a m so we can make the the flight to Tokyo on you know what I mean as I mentioned earlier in the week which is important for the timeline um and then we can decide",
            wordCount: 142,
            requiredAll: ["Sunday", "5 PM", "not", "Monday", "Saturday", "6:30", "Tokyo"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "4 PM", "Osaka"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Sunday"], ["5 PM"], ["not"], ["Monday"], ["Saturday"], ["6:30"], ["Tokyo"]], forbidden: ["4 PM", "Osaka"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["4 PM", "Osaka"])
            )
        ),
        A1Sample(
            id: "A1-L-0058", tier: "long", domain: "personal notes",
            raw: "okay so I um need to remember a a a few things for this weekend. first call Mom on Sunday because I forgot last week and she asked about the the family dinner. second pick up the prescription from the pharmacy before the the office closes at five p m because otherwise I will not have it until Monday. third I should probably clean the the apartment before Priya comes over on Saturday afternoon. I also want to finish the book that I started on the the train because I am almost at the the last chapter. do not forget to set the alarm for six thirty a m so we can make the the the the flight to Tokyo on time. so please keep me posted on that right so that is the plan let me know if that makes sense so",
            wordCount: 143,
            requiredAll: ["Sunday", "5 PM", "not", "Monday", "Saturday", "6:30", "Tokyo"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "4 PM", "Osaka"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Sunday"], ["5 PM"], ["not"], ["Monday"], ["Saturday"], ["6:30"], ["Tokyo"]], forbidden: ["4 PM", "Osaka"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["4 PM", "Osaka"])
            )
        ),
        A1Sample(
            id: "A1-L-0059", tier: "long", domain: "personal notes",
            raw: "okay so I need to you know remember a a a few things for this weekend. first call Mom on Sunday because I forgot last week and she asked about the the family dinner. second pick up the prescription from the pharmacy before the the office closes at five p m because otherwise I will not have it until Monday. third I should probably clean the the apartment before Priya comes over on Saturday afternoon. I also want to finish the book that I started on the the the the the the train because I am almost at the the last chapter. do not forget to set the alarm for six thirty a m so we can make the the flight to Tokyo on time. but I want to be careful here and we should double check the numbers you know what I mean as",
            wordCount: 145,
            requiredAll: ["Sunday", "5 PM", "not", "Monday", "Saturday", "6:30", "Tokyo"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "4 PM", "Osaka"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Sunday"], ["5 PM"], ["not"], ["Monday"], ["Saturday"], ["6:30"], ["Tokyo"]], forbidden: ["4 PM", "Osaka"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["4 PM", "Osaka"])
            )
        ),
        A1Sample(
            id: "A1-L-0060", tier: "long", domain: "personal notes",
            raw: "okay so I need I mean to remember a few things for this weekend. first call Mom on Sunday because I forgot last week and she asked about the the family dinner. second pick up the prescription from the pharmacy before the the office closes at five p m because otherwise I will not have it until Monday. third I should probably clean the the apartment before Priya comes over on Saturday afternoon. I also want to finish the book that I started on the the train because I am almost at the the last chapter. do not forget to set the alarm for six thirty a a a m so we can make the the flight to Tokyo on time. which is important for the timeline um and then we can decide so please keep me posted on that right so that is the plan",
            wordCount: 146,
            requiredAll: ["Sunday", "5 PM", "not", "Monday", "Saturday", "6:30", "Tokyo"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "4 PM", "Osaka"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Sunday"], ["5 PM"], ["not"], ["Monday"], ["Saturday"], ["6:30"], ["Tokyo"]], forbidden: ["4 PM", "Osaka"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["4 PM", "Osaka"])
            )
        ),
        A1Sample(
            id: "A1-L-0061", tier: "long", domain: "gaming",
            raw: "that was the the hardest raid we have done in weeks. I died three times on the the final boss because my latency was two hundred milliseconds and the the healer could not keep up with the damage. after we switched servers I noticed the the connection was much better and we finally beat it on the fourth attempt. the the the the loot drop was a legendary sword with a critical hit chance of fifteen percent which is better than the one I had before. we should record the the next run because the the strategy we used in phase two was really clever. if the the latency goes above one hundred again we will switch servers immediately. do not and we should double check the numbers you know what I mean as I mentioned earlier in the week which is",
            wordCount: 142,
            requiredAll: ["200", "fourth", "15%", "100", "not"],
            requiredAny: [["200", "two hundred"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "300", "fifth"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["200", "two hundred"], ["fourth"], ["15%"], ["100"], ["not"]], forbidden: ["300", "fifth"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["300", "fifth"])
            )
        ),
        A1Sample(
            id: "A1-L-0062", tier: "long", domain: "gaming",
            raw: "that was the um the hardest raid we have done in weeks. I died three times on the the final boss because my latency was two hundred milliseconds and the the healer could not keep up with the damage. after we switched servers I noticed the the the the connection was much better and we finally beat it it it on the fourth attempt. the the loot drop was a legendary sword with a critical hit chance of fifteen percent which is better than the one I had before. we should record the the next run because the the strategy we used in phase two was really clever. if the the latency goes above one hundred again we will switch servers immediately. do not but I want to be careful here and we should double check the numbers you know what I mean",
            wordCount: 143,
            requiredAll: ["200", "fourth", "15%", "100", "not"],
            requiredAny: [["200", "two hundred"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "300", "fifth"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["200", "two hundred"], ["fourth"], ["15%"], ["100"], ["not"]], forbidden: ["300", "fifth"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["300", "fifth"])
            )
        ),
        A1Sample(
            id: "A1-L-0063", tier: "long", domain: "gaming",
            raw: "that was the the the the hardest you know raid we have done in weeks. I died three times on the the the the final boss because my latency was two hundred milliseconds and the the healer could not keep up with the damage. after we switched servers I noticed the the connection was much better and we finally beat it on the fourth attempt. the the loot drop was a legendary sword with a critical hit chance of fifteen percent which is better than the one I had before. we should record the the next run because the the strategy we used in phase two was really clever. if the the latency goes above one hundred again we we we will switch servers immediately. do not um and then we can decide so please keep me posted on that right so that is the",
            wordCount: 145,
            requiredAll: ["200", "fourth", "15%", "100", "not"],
            requiredAny: [["200", "two hundred"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "300", "fifth"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["200", "two hundred"], ["fourth"], ["15%"], ["100"], ["not"]], forbidden: ["300", "fifth"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["300", "fifth"])
            )
        ),
        A1Sample(
            id: "A1-L-0064", tier: "long", domain: "gaming",
            raw: "that was the the I mean hardest raid we have done in weeks. I died three times on the the final boss because my latency was two hundred milliseconds and the the the the healer could not keep up with the damage. after we switched servers I noticed the the connection was much better and we finally beat it on the fourth attempt. the the loot drop was a legendary sword with a critical hit chance of fifteen percent which is better than the one I had before. we should record the the next run because the the strategy we used in phase two was really clever. if the the latency goes above one hundred again we will switch servers immediately. do not so please keep me posted on that right so that is the plan let me know if that makes sense so please keep",
            wordCount: 146,
            requiredAll: ["200", "fourth", "15%", "100", "not"],
            requiredAny: [["200", "two hundred"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "300", "fifth"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["200", "two hundred"], ["fourth"], ["15%"], ["100"], ["not"]], forbidden: ["300", "fifth"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["300", "fifth"])
            )
        ),
        A1Sample(
            id: "A1-L-0065", tier: "long", domain: "travel",
            raw: "so the the flight to Tokyo leaves at six thirty a m from gate twelve but it was delayed by forty five minutes because of the the weather in the morning. the the airline said we will still make the connection inOsaka if we can get to the the gate quickly. I I checked the the app and the the boarding group is group four which means we board fairly late. we should probably get there early because the the overhead bins fill up fast. the hotel is near the the the the station and the the check in time is three p m so we have a few hours to kill after we land. please do not book the the train ticket until we confirm the the new arrival time because it might be after eight p m. right so that",
            wordCount: 142,
            requiredAll: ["Tokyo", "6:30", "12", "45", "Osaka", "3 PM", "not", "8 PM"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Kyoto", "15"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Tokyo"], ["6:30"], ["12"], ["45"], ["Osaka"], ["3 PM"], ["not"], ["8 PM"]], forbidden: ["Kyoto", "15"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Kyoto", "15"])
            )
        ),
        A1Sample(
            id: "A1-L-0066", tier: "long", domain: "travel",
            raw: "so the the um flight to Tokyo leaves at six thirty a m from gate twelve but it was delayed by forty five minutes because of the the weather in the morning. the the airline said we will still make the connection inOsaka if we can get to the the the the gate quickly. I I checked the the app and the the boarding group is group four which means we board fairly late. we should probably get there early because the the overhead bins fill up fast. the hotel is near the the station and the the check in time is is is three p m so we have a few hours to kill after we land. please do not book the the train ticket until we confirm the the new arrival time because it might be after eight p m. so",
            wordCount: 143,
            requiredAll: ["Tokyo", "6:30", "12", "45", "Osaka", "3 PM", "not", "8 PM"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Kyoto", "15"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Tokyo"], ["6:30"], ["12"], ["45"], ["Osaka"], ["3 PM"], ["not"], ["8 PM"]], forbidden: ["Kyoto", "15"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Kyoto", "15"])
            )
        ),
        A1Sample(
            id: "A1-L-0067", tier: "long", domain: "travel",
            raw: "so the the flight to you know Tokyo leaves at six thirty a m from gate twelve but it it it was delayed by forty five minutes because of the the the the weather in the morning. the the airline said we will still make the connection inOsaka if we can get to the the gate quickly. I I checked the the the the app and the the boarding group is group four which means we board fairly late. we should probably get there early because the the overhead bins fill up fast. the hotel is near the the station and the the check in time is three p m so we have a few hours to kill after we land. please do not book the the train ticket until we confirm the the new arrival time because it might be after eight p m.",
            wordCount: 145,
            requiredAll: ["Tokyo", "6:30", "12", "45", "Osaka", "3 PM", "not", "8 PM"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Kyoto", "15"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Tokyo"], ["6:30"], ["12"], ["45"], ["Osaka"], ["3 PM"], ["not"], ["8 PM"]], forbidden: ["Kyoto", "15"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Kyoto", "15"])
            )
        ),
        A1Sample(
            id: "A1-L-0068", tier: "long", domain: "travel",
            raw: "so the the flight I mean to Tokyo leaves at six thirty a m from gate twelve but it was delayed by forty five minutes because of the the weather in the morning. the the airline said we will still make the connection inOsaka if we can get to the the gate quickly. I I checked the the app and the the boarding group is group four which means we we we board fairly late. we should probably get there early because the the overhead bins fill up fast. the hotel is near the the station and the the check in time is three p m so we have a few hours to kill after we land. please do not book the the train ticket until we confirm the the new arrival time because it might be after eight p m. which is important for the",
            wordCount: 146,
            requiredAll: ["Tokyo", "6:30", "12", "45", "Osaka", "3 PM", "not", "8 PM"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Kyoto", "15"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Tokyo"], ["6:30"], ["12"], ["45"], ["Osaka"], ["3 PM"], ["not"], ["8 PM"]], forbidden: ["Kyoto", "15"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Kyoto", "15"])
            )
        ),
        A1Sample(
            id: "A1-L-0069", tier: "long", domain: "academic",
            raw: "the hypothesis was that increased sleep would improve test performance but the the results did not fully confirm that. we had a sample of thirty students split into two groups and the the control group slept normally while the the treatment group got an extra two hours. the the average score in the treatment group was eighty four compared to seventy nine in the control group which is a difference of five points. the p value was zero point zero four which is significant at the five percent level but the effect size is modest. one limitation is that we did not control for caffeine intake which could have affected the the results. the the next study should use a a a larger sample and measure sleep quality more directly. the full write up is due to the the professor on Friday.",
            wordCount: 142,
            requiredAll: ["not", "30", "2", "84", "79", "5", "0.04", "Friday"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "0.4", "300"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["not"], ["2"], ["84"], ["79"], ["5"], ["0.04"], ["Friday"]], forbidden: ["0.4", "300"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["0.4", "300"])
            )
        ),
        A1Sample(
            id: "A1-L-0070", tier: "long", domain: "academic",
            raw: "the hypothesis was that increased sleep would improve test performance but the the the results did not fully confirm that. we had a sample of thirty students split into two groups and the the control group slept normally while the the treatment group got an extra two hours. the the average score in the treatment group was eighty four compared to seventy nine in the control group which is a difference of five points. the p value was zero point zero four which is significant at the five percent level but the effect size is modest. one limitation is that we did not control for caffeine intake which could have affected the the the the results. the the next study should use a larger sample and measure sleep quality more directly. the full write up is due to the the professor on Friday.",
            wordCount: 143,
            requiredAll: ["not", "30", "2", "84", "79", "5", "0.04", "Friday"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "0.4", "300"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["not"], ["2"], ["84"], ["79"], ["5"], ["0.04"], ["Friday"]], forbidden: ["0.4", "300"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["0.4", "300"])
            )
        ),
        A1Sample(
            id: "A1-L-0071", tier: "long", domain: "academic",
            raw: "the hypothesis was that increased you know sleep would improve test performance but results did not fully confirm that. we had a sample of thirty students split into two groups and the control group slept normally while the the treatment group got an extra two hours. the the average score in the treatment group was eighty four compared to seventy nine in the control group which is a difference of five points. the p value was zero point zero four which is significant at the five percent level but the effect size is modest. one limitation is that we did not control for caffeine intake which could have affected the the results. the the next study should use a larger sample and measure sleep quality more directly. the the the full write up is is is due to the the the the professor on Friday.",
            wordCount: 145,
            requiredAll: ["not", "30", "2", "84", "79", "5", "0.04", "Friday"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "0.4", "300"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["not"], ["2"], ["84"], ["79"], ["5"], ["0.04"], ["Friday"]], forbidden: ["0.4", "300"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["0.4", "300"])
            )
        ),
        A1Sample(
            id: "A1-L-0072", tier: "long", domain: "academic",
            raw: "the hypothesis was that I mean increased sleep would improve test performance but the the results did not fully confirm that. we had a sample of thirty students split into two groups and the the control group slept normally while the the treatment group got an extra two hours. the the average score in the treatment group was eighty four compared to seventy nine in the control group which is a difference of five points. the p value was zero point zero four which is significant at the five percent level but the effect size is modest. one limitation is that we did not control for caffeine intake which could have affected the the results. the the next study should use a larger sample and measure sleep quality more directly. the the the full write up is due to the the professor on Friday. as I",
            wordCount: 146,
            requiredAll: ["not", "30", "2", "84", "79", "5", "0.04", "Friday"],
            requiredAny: [["30", "thirty"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "0.4", "300"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["30", "thirty"], ["not"], ["2"], ["84"], ["79"], ["5"], ["0.04"], ["Friday"]], forbidden: ["0.4", "300"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["0.4", "300"])
            )
        ),
        A1Sample(
            id: "A1-L-0073", tier: "long", domain: "chat",
            raw: "hey are coming to party on Saturday I I mean Thursday actually no wait Friday night because we need a ride and address is forty two Maple Street. I I already told Priya that we would bring the the drinks so do not worry about that part. the the thing is the host said the the party starts at eight but people usually show up around nine so we do not need to be there too early. if you cannot make it let me know by Thursday so I can give Marcus a a a heads up about the the ride. also the the dog is fine now after the the vet visit on Monday so you do not need to worry about that. um call me when you get a chance because I want to confirm the the plan before Friday.",
            wordCount: 142,
            requiredAll: ["Friday", "42", "Maple Street", "not", "Thursday", "Monday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Sunday", "24"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Friday"], ["42"], ["Maple Street"], ["not"], ["Thursday"], ["Monday"]], forbidden: ["Sunday", "24"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Sunday", "24"])
            )
        ),
        A1Sample(
            id: "A1-L-0074", tier: "long", domain: "chat",
            raw: "hey are coming to the party on Saturday I I mean Friday night because we need a ride and the the address is forty two Maple Street. I I already told Priya that we would bring the the the the drinks so do not worry about that part. the the thing is is is the host said the the party starts at eight but people usually show up around nine so we do not need to be there too early. if you cannot make it let me know by Thursday so I can give Marcus a heads up about the the ride. also the the dog is fine now after the the vet visit on Monday so you do not need to worry about that. um call me when you get a chance because I want to confirm the the plan before Friday.",
            wordCount: 143,
            requiredAll: ["Friday", "42", "Maple Street", "not", "Thursday", "Monday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Sunday", "24"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Friday"], ["42"], ["Maple Street"], ["not"], ["Thursday"], ["Monday"]], forbidden: ["Sunday", "24"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Sunday", "24"])
            )
        ),
        A1Sample(
            id: "A1-L-0075", tier: "long", domain: "chat",
            raw: "hey are coming to you know party on Saturday I I mean Friday night because we need a ride and the the the address is forty two Maple Street. I I already told Priya that we would bring the the drinks so do not worry about that part. the the thing is the host said the the party starts at eight but people usually show up around nine so we do not need to be there too early. if you cannot make it let me know by Thursday so I can give Marcus a heads up about the the ride. also the the dog is is is is is fine now after the the vet visit on Monday so you do not need to worry about that. um call me when you get a chance because I want to confirm the the plan before Friday.",
            wordCount: 145,
            requiredAll: ["Friday", "42", "Maple Street", "not", "Thursday", "Monday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Sunday", "24"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Friday"], ["42"], ["Maple Street"], ["not"], ["Thursday"], ["Monday"]], forbidden: ["Sunday", "24"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Sunday", "24"])
            )
        ),
        A1Sample(
            id: "A1-L-0076", tier: "long", domain: "chat",
            raw: "hey are coming I mean to party on Saturday I I mean Thursday actually no wait Friday night because we need a ride and the the address is forty two Maple Street. I I already told Priya that we would bring the the drinks so do not worry about that part. the the thing is the host said the the party starts at eight but people usually show up around nine so we do not need to be there too early. if you cannot make it let me know by Thursday so I can give Marcus a heads up about the the ride. also the the dog is fine now after the the vet visit on Monday so you do not need to worry about that. um call me when you get a chance because I want to confirm the the the the plan before Friday.",
            wordCount: 146,
            requiredAll: ["Friday", "42", "Maple Street", "not", "Thursday", "Monday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Sunday", "24"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Friday"], ["42"], ["Maple Street"], ["not"], ["Thursday"], ["Monday"]], forbidden: ["Sunday", "24"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Sunday", "24"])
            )
        ),
        A1Sample(
            id: "A1-L-0077", tier: "long", domain: "software/code",
            raw: "for the the performance issue I profiled the the application and found that the the bottleneck is in the database query not in the rendering code. the query is doing a a a full table scan because the the index on the user id column was dropped during the last migration. I I added the index back and the query time dropped from eight hundred milliseconds to forty milliseconds which is a twenty fold improvement. we should also add the the redish cash in front of the the hot path so repeated reads do not hit the database at all. the a p i endpoint latency should go down as a result and we can verify with the open trace dashboard. do not merge the the change until the load test passes with at least five thousand I I think that is",
            wordCount: 142,
            requiredAll: ["not", "800", "40", "Redis cache", "API endpoint", "OpenTelemetry", "5000"],
            requiredAny: [["800", "eight hundred"], ["5000", "5k", "5 K", "five thousand"]],
            forbidden: ["a p i endpoint", "redish cash", "open trace", "the the", "i i i", "it it it", "we we we", "is is is", "500", "3000"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["800", "eight hundred"], ["5000", "5k", "5 K", "five thousand"], ["not"], ["40"], ["Redis cache"], ["API endpoint"], ["OpenTelemetry"]], forbidden: ["500", "3000"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["API endpoint"], ["Redis cache"], ["OpenTelemetry"]], forbidden: ["a p i endpoint", "redish cash", "open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "3000"])
            )
        ),
        A1Sample(
            id: "A1-L-0078", tier: "long", domain: "software/code",
            raw: "for the the um performance issue I profiled the the application and found that the the bottleneck is in the database query not in the rendering code. the query is doing a full table scan because the the index on the user id column was dropped during the last migration. I I added the index back and the query time dropped from eight hundred milliseconds to forty milliseconds which is a twenty fold improvement. we should also add the the redish cash in front of the the hot path so repeated reads do not hit the the the database at all. the the the API endpoint latency should go down as a result and we can verify with the open trace dashboard. do not merge the the change until the load test passes with at least five thousand you know what I mean",
            wordCount: 143,
            requiredAll: ["not", "800", "40", "Redis cache", "API endpoint", "OpenTelemetry", "5000"],
            requiredAny: [["800", "eight hundred"], ["5000", "5k", "5 K", "five thousand"]],
            forbidden: ["redish cash", "open trace", "the the", "i i i", "it it it", "we we we", "is is is", "500", "3000"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["800", "eight hundred"], ["5000", "5k", "5 K", "five thousand"], ["not"], ["40"], ["Redis cache"], ["API endpoint"], ["OpenTelemetry"]], forbidden: ["500", "3000"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["Redis cache"], ["OpenTelemetry"]], forbidden: ["redish cash", "open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "3000"])
            )
        ),
        A1Sample(
            id: "A1-L-0079", tier: "long", domain: "software/code",
            raw: "for the the performance issue you know I profiled the the the the the the application and found that the the bottleneck is in the database query not in the rendering code. the query is doing a full table scan because the the index on the the the user id column was dropped during the last migration. I I added the index back and the query time dropped from eight hundred milliseconds to forty milliseconds which is a twenty fold improvement. we should also add the the redish cash in front of the the hot path so repeated reads do not hit the database at all. the a p i endpoint latency should go down as a result and we can verify with the open trace dashboard. do not merge the the change until the load test passes with at least five thousand so please",
            wordCount: 145,
            requiredAll: ["not", "800", "40", "Redis cache", "API endpoint", "OpenTelemetry", "5000"],
            requiredAny: [["800", "eight hundred"], ["5000", "5k", "5 K", "five thousand"]],
            forbidden: ["a p i endpoint", "redish cash", "open trace", "the the", "i i i", "it it it", "we we we", "is is is", "500", "3000"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["800", "eight hundred"], ["5000", "5k", "5 K", "five thousand"], ["not"], ["40"], ["Redis cache"], ["API endpoint"], ["OpenTelemetry"]], forbidden: ["500", "3000"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["API endpoint"], ["Redis cache"], ["OpenTelemetry"]], forbidden: ["a p i endpoint", "redish cash", "open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "3000"])
            )
        ),
        A1Sample(
            id: "A1-L-0080", tier: "long", domain: "software/code",
            raw: "for the the performance I mean issue I profiled the the application and found that the the bottleneck is in the database query not in the rendering code. the query is doing a full table scan because the the the the index on the user id column was dropped during the last migration. I I added the index back and the query time dropped from eight hundred milliseconds to forty milliseconds which is a twenty fold improvement. we should also add the the Redis cache in front of the the hot path so repeated reads do not hit the database at all. the a p i endpoint latency should go down as a result and we can verify with the open trace dashboard. do not merge the the change until the load test passes with at least five thousand you know what I mean as I",
            wordCount: 146,
            requiredAll: ["not", "800", "40", "Redis cache", "API endpoint", "OpenTelemetry", "5000"],
            requiredAny: [["800", "eight hundred"], ["5000", "5k", "5 K", "five thousand"]],
            forbidden: ["a p i endpoint", "open trace", "the the", "i i i", "it it it", "we we we", "is is is", "500", "3000"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["800", "eight hundred"], ["5000", "5k", "5 K", "five thousand"], ["not"], ["40"], ["Redis cache"], ["API endpoint"], ["OpenTelemetry"]], forbidden: ["500", "3000"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["API endpoint"], ["OpenTelemetry"]], forbidden: ["a p i endpoint", "open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "3000"])
            )
        ),
        A1Sample(
            id: "A1-L-0081", tier: "long", domain: "email",
            raw: "hi team following up on weekly report. numbers for Q two are finalized and the total is three point one million which is slightly above the forecast of two point nine million. I have asked Priya to update the dashboard and Marcus to verify the the figures against the the source system before we send anything to the board. the the main risk is the churn in the small business segment which went up from two point one to two point eight percent. we we we do not have a clear explanation yet but the the team is investigating. please do not share the the draft with anyone outside the the leadership group until Thursday. if you spot any errors leave a comment in the the document by Thursday actually no wait Wednesday evening so I can fix them before the Friday",
            wordCount: 142,
            requiredAll: ["Q2", "3.1", "2.9", "Priya", "Marcus", "not", "2.8", "Thursday", "Wednesday", "Friday"],
            requiredAny: [["Q2", "Q 2", "q2", "q 2"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "3.9", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q2", "Q 2", "q2", "q 2"], ["3.1"], ["2.9"], ["Priya"], ["Marcus"], ["not"], ["2.8"], ["Thursday"], ["Wednesday"], ["Friday"]], forbidden: ["3.9", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["3.9", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-L-0082", tier: "long", domain: "email",
            raw: "hi team following up on the weekly report. the numbers for Q two are finalized and the the total is three point one million which is slightly above the forecast of two point nine million. I have asked Priya to update the dashboard and Marcus to verify the the the the figures against the the source system before we send anything to the board. the the main risk is the the the churn in the small business segment which went up from two point one to two point eight percent. we do not have a clear explanation yet but the the team is investigating. please do not share the the draft with anyone outside the the leadership group until Thursday. if you spot any errors leave a comment in the the document by Wednesday evening so I can fix them before the Friday",
            wordCount: 143,
            requiredAll: ["Q2", "3.1", "2.9", "Priya", "Marcus", "not", "2.8", "Thursday", "Wednesday", "Friday"],
            requiredAny: [["Q2", "Q 2", "q2", "q 2"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "3.9", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q2", "Q 2", "q2", "q 2"], ["3.1"], ["2.9"], ["Priya"], ["Marcus"], ["not"], ["2.8"], ["Thursday"], ["Wednesday"], ["Friday"]], forbidden: ["3.9", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["3.9", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-L-0083", tier: "long", domain: "email",
            raw: "hi team following up on you know weekly report. numbers for Q two are finalized and the the total is three point one million which is slightly above the forecast of two point nine million. I have asked Priya to update the dashboard and Marcus to verify the the figures against the the source system before we send anything to the the the board. the the main risk is the churn in the small business segment which went up from two point one to two point eight percent. we do not have a clear explanation yet but the the team is investigating. please do not share the the the the draft with anyone outside the the leadership group until Thursday. if you spot any errors leave a a a comment in the the document by Wednesday evening so I can fix them before the Friday",
            wordCount: 145,
            requiredAll: ["Q2", "3.1", "2.9", "Priya", "Marcus", "not", "2.8", "Thursday", "Wednesday", "Friday"],
            requiredAny: [["Q2", "Q 2", "q2", "q 2"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "3.9", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q2", "Q 2", "q2", "q 2"], ["3.1"], ["2.9"], ["Priya"], ["Marcus"], ["not"], ["2.8"], ["Thursday"], ["Wednesday"], ["Friday"]], forbidden: ["3.9", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["3.9", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-L-0084", tier: "long", domain: "email",
            raw: "hi team following up I mean on weekly report. the numbers for Q two are finalized and the the total is three point one million which is slightly above the forecast of two point nine million. I have asked Priya to update the dashboard and Marcus to verify the the figures against the the source system before we send anything to the the the board. the the main risk is the churn in the small business segment which went up from two point one to two point eight percent. we do not have a clear explanation yet but the the team is investigating. please do not share the the draft with anyone outside the the leadership group until Thursday. if you spot any errors leave a comment in the the document by Thursday actually no wait Wednesday evening so I can fix them before the Friday",
            wordCount: 146,
            requiredAll: ["Q2", "3.1", "2.9", "Priya", "Marcus", "not", "2.8", "Thursday", "Wednesday", "Friday"],
            requiredAny: [["Q2", "Q 2", "q2", "q 2"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "3.9", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q2", "Q 2", "q2", "q 2"], ["3.1"], ["2.9"], ["Priya"], ["Marcus"], ["not"], ["2.8"], ["Thursday"], ["Wednesday"], ["Friday"]], forbidden: ["3.9", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["3.9", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-L-0085", tier: "long", domain: "meeting",
            raw: "alright let us get started. the first topic is the the customer escalation from Acme Corp which has been open for three weeks now. Sarah has been in contact with their legal team and they want a revised service level agreement before they will renew the contract. the the second topic is the hiring plan for Q one where we want two point five engineers and one designer. we do not expect the budget to be a problem because the the finance team approved the the additional headcount last month. Priya will send the updated roadmap by Thursday actually no wait Wednesday and Marcus will schedule the the the the follow up call with the customer for Thursday morning. right so that is the plan let me know if that makes sense so please keep me posted on that right so that",
            wordCount: 142,
            requiredAll: ["Acme Corp", "3", "Sarah", "Q1", "2.5", "not", "Wednesday", "Thursday"],
            requiredAny: [["Q1", "Q 1", "q1", "q 1"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Q2", "Friday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q1", "Q 1", "q1", "q 1"], ["Acme Corp"], ["3"], ["Sarah"], ["2.5"], ["not"], ["Wednesday"], ["Thursday"]], forbidden: ["Q2", "Friday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Q2", "Friday"])
            )
        ),
        A1Sample(
            id: "A1-L-0086", tier: "long", domain: "meeting",
            raw: "alright let us um get started. the first topic is the the customer escalation from Acme Corp which has been open for three weeks now. Sarah has been in contact with their legal team and they want a revised service level agreement before they will renew the the the contract. the the second topic is the hiring plan for Q one where we want two point five engineers and one designer. we do not expect the budget to be a problem because the the finance team approved the the the the additional headcount last month. Priya will send the updated roadmap by Wednesday and Marcus will schedule the the follow up call with the customer for Thursday morning. you know what I mean as I mentioned earlier in the week which is important for the timeline um and then we can decide so",
            wordCount: 143,
            requiredAll: ["Acme Corp", "3", "Sarah", "Q1", "2.5", "not", "Wednesday", "Thursday"],
            requiredAny: [["Q1", "Q 1", "q1", "q 1"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Q2", "Friday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q1", "Q 1", "q1", "q 1"], ["Acme Corp"], ["3"], ["Sarah"], ["2.5"], ["not"], ["Wednesday"], ["Thursday"]], forbidden: ["Q2", "Friday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Q2", "Friday"])
            )
        ),
        A1Sample(
            id: "A1-L-0087", tier: "long", domain: "meeting",
            raw: "alright let us get started. you know the first topic is is is the the customer escalation from Acme Corp which has been open for three weeks now. Sarah has been in contact with their legal team and they want a revised service level agreement before they will renew the contract. the the second topic is the the the hiring plan for Q one where we want two point five engineers and one designer. we we we do not expect the budget to be a problem because the the finance team approved the the additional headcount last month. Priya will send the updated roadmap by Wednesday and Marcus will schedule the the follow up call with the customer for Thursday morning. which is important for the timeline um and then we can decide so please keep me posted on that right so that is the",
            wordCount: 145,
            requiredAll: ["Acme Corp", "3", "Sarah", "Q1", "2.5", "not", "Wednesday", "Thursday"],
            requiredAny: [["Q1", "Q 1", "q1", "q 1"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Q2", "Friday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q1", "Q 1", "q1", "q 1"], ["Acme Corp"], ["3"], ["Sarah"], ["2.5"], ["not"], ["Wednesday"], ["Thursday"]], forbidden: ["Q2", "Friday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Q2", "Friday"])
            )
        ),
        A1Sample(
            id: "A1-L-0088", tier: "long", domain: "meeting",
            raw: "alright let us get I mean started. the first topic is the the customer escalation from Acme Corp which has been open for three weeks now. Sarah has been in contact with their legal team and they want a a a revised service level agreement before they will renew the contract. the the second topic is the hiring plan for Q one where we want two point five engineers and one designer. we do not expect the budget to be a problem because the the finance team approved the the additional headcount last month. Priya will send the updated roadmap by Thursday actually no wait Wednesday and Marcus will schedule the the follow up call with the customer for Thursday morning. which is important for the timeline um and then we can decide so please keep me posted on that right so that is the plan",
            wordCount: 146,
            requiredAll: ["Acme Corp", "3", "Sarah", "Q1", "2.5", "not", "Wednesday", "Thursday"],
            requiredAny: [["Q1", "Q 1", "q1", "q 1"]],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "Q2", "Friday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["Q1", "Q 1", "q1", "q 1"], ["Acme Corp"], ["3"], ["Sarah"], ["2.5"], ["not"], ["Wednesday"], ["Thursday"]], forbidden: ["Q2", "Friday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["Q2", "Friday"])
            )
        ),
        A1Sample(
            id: "A1-L-0089", tier: "long", domain: "medical",
            raw: "the the triage nurse recorded a temperature of thirty eight point five and a heart rate of one hundred and two so the patient was moved to the the examination room immediately. the the doctor noted that the patient had a persistent cough for ten days and no shortness of breath at rest. a rapid test was performed and the the the the result was positive so we started treatment right away. the patient is not allergic to any medications according to the chart but we should still verify before giving the the first dose. we will keep her for observation for twenty four hours and repeat the the blood work in the morning. please document everything carefully and do not forget to update the the discharge summary before the attending physician signs off at five p m. you know what I",
            wordCount: 142,
            requiredAll: ["38.5", "102", "10", "no", "not", "24", "5 PM"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "yes", "48", "4 PM"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["38.5"], ["102"], ["10"], ["no"], ["not"], ["24"], ["5 PM"]], forbidden: ["yes", "48", "4 PM"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["yes", "48", "4 PM"])
            )
        ),
        A1Sample(
            id: "A1-L-0090", tier: "long", domain: "medical",
            raw: "the the triage um nurse recorded a temperature of thirty eight point five and a heart rate of one hundred and two so the patient was moved to the the examination room immediately. the the doctor noted that the patient had a persistent cough for ten days and no shortness of breath at rest. a rapid test was performed and the the result was positive so we started treatment right away. the patient is not allergic to any medications according to the chart but we should still verify before giving the the the the the the first dose. we will keep her for observation for twenty four hours and repeat the the blood work in the morning. please document everything carefully and do not forget to update the the discharge summary before the attending physician signs off at five p m. and we",
            wordCount: 143,
            requiredAll: ["38.5", "102", "10", "no", "not", "24", "5 PM"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "yes", "48", "4 PM"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["38.5"], ["102"], ["10"], ["no"], ["not"], ["24"], ["5 PM"]], forbidden: ["yes", "48", "4 PM"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["yes", "48", "4 PM"])
            )
        ),
        A1Sample(
            id: "A1-L-0091", tier: "long", domain: "medical",
            raw: "the the triage nurse recorded you know a temperature of thirty eight point five and a heart rate of one hundred and two so the patient was moved to the the the the examination room immediately. the the doctor noted that the patient had a persistent cough for ten days and no shortness of breath at rest. a rapid test was performed and the the result was positive so we started treatment right away. the patient is not allergic to any medications according to the chart but we should still verify before giving the the first dose. we we we will keep her for observation for twenty four hours and repeat the the blood work in the morning. please document everything carefully and do not forget to update the the the the discharge summary before the attending physician signs off at five p m. as",
            wordCount: 145,
            requiredAll: ["38.5", "102", "10", "no", "not", "24", "5 PM"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "yes", "48", "4 PM"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["38.5"], ["102"], ["10"], ["no"], ["not"], ["24"], ["5 PM"]], forbidden: ["yes", "48", "4 PM"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["yes", "48", "4 PM"])
            )
        ),
        A1Sample(
            id: "A1-L-0092", tier: "long", domain: "medical",
            raw: "the the triage nurse I mean recorded a temperature of thirty eight point five and a heart rate of one hundred and two so the patient was moved to the the examination room immediately. the the doctor noted that the patient had a persistent cough for ten days and no shortness of breath at rest. a rapid test was performed and the the result was positive so we started treatment right away. the patient is not allergic to any medications according to the chart but we should still verify before giving the the first dose. we will keep her for observation for twenty four hours and repeat the the blood work in the morning. please document everything carefully and do not forget to update the the the the discharge summary before the attending physician signs off at five p m. right so that is the plan",
            wordCount: 146,
            requiredAll: ["38.5", "102", "10", "no", "not", "24", "5 PM"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "yes", "48", "4 PM"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["38.5"], ["102"], ["10"], ["no"], ["not"], ["24"], ["5 PM"]], forbidden: ["yes", "48", "4 PM"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["yes", "48", "4 PM"])
            )
        ),
        A1Sample(
            id: "A1-L-0093", tier: "long", domain: "software/code",
            raw: "the new feature flag ready but I do not want to turn on for everyone yet. let us start with five percent of traffic in the staging environment and watch the the error rate for twenty four hours. if the four two nine rate stays below one percent we can increase to twenty five percent and then to fifty percent. the the rollout script is in the the deploy repository and the the configuration key is enable new checkout. please make sure the redish cash is warmed before we flip the the flag because a cold cache caused problems in the the last test. the a a a p i endpoint should handle the the extra load but we can verify with the open trace dashboard. do not merge the the flag into main until the product team signs off on Wednesday.",
            wordCount: 142,
            requiredAll: ["not", "5%", "24", "429", "1%", "25%", "50%", "Redis cache", "API endpoint", "OpenTelemetry", "Wednesday"],
            requiredAny: [["429", "four two nine"]],
            forbidden: ["a p i endpoint", "redish cash", "open trace", "the the", "i i i", "it it it", "we we we", "is is is", "500", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["429", "four two nine"], ["not"], ["5%"], ["24"], ["1%"], ["25%"], ["50%"], ["Redis cache"], ["API endpoint"], ["OpenTelemetry"], ["Wednesday"]], forbidden: ["500", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["API endpoint"], ["Redis cache"], ["OpenTelemetry"]], forbidden: ["a p i endpoint", "redish cash", "open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-L-0094", tier: "long", domain: "software/code",
            raw: "the new feature flag ready but I do not want to turn on for everyone yet. let us start with five percent of traffic in the the staging environment and watch the the error rate for twenty four hours. if the four two nine rate stays below one percent we can increase to twenty five percent and then to fifty percent. the the rollout script is in the the deploy repository and the the configuration key is enable new checkout. please make sure the redish cash is is is warmed before we flip the the flag because a cold cache caused problems in the the last test. the API endpoint should handle the the the the extra load but we can verify with the open trace dashboard. do not merge the the flag into main until the product team signs off on Wednesday.",
            wordCount: 143,
            requiredAll: ["not", "5%", "24", "429", "1%", "25%", "50%", "Redis cache", "API endpoint", "OpenTelemetry", "Wednesday"],
            requiredAny: [["429", "four two nine"]],
            forbidden: ["redish cash", "open trace", "the the", "i i i", "it it it", "we we we", "is is is", "500", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["429", "four two nine"], ["not"], ["5%"], ["24"], ["1%"], ["25%"], ["50%"], ["Redis cache"], ["API endpoint"], ["OpenTelemetry"], ["Wednesday"]], forbidden: ["500", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["Redis cache"], ["OpenTelemetry"]], forbidden: ["redish cash", "open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-L-0095", tier: "long", domain: "software/code",
            raw: "the new feature flag you know ready but I do not want to turn on for everyone yet. let us start with five percent of traffic in the the staging environment and watch the the error rate for twenty four hours. if the four two nine rate stays below one percent we can increase to twenty five percent and then to fifty percent. the the rollout script is in the the deploy repository and the the configuration key is enable new checkout. please make sure the redish cash is warmed before we flip the the flag because a cold cache caused problems in the the last test. the a p i endpoint should handle the the extra load but we can verify with the open trace dashboard. do not merge the the the the flag into main until the product team signs off on Wednesday.",
            wordCount: 145,
            requiredAll: ["not", "5%", "24", "429", "1%", "25%", "50%", "Redis cache", "API endpoint", "OpenTelemetry", "Wednesday"],
            requiredAny: [["429", "four two nine"]],
            forbidden: ["a p i endpoint", "redish cash", "open trace", "the the", "i i i", "it it it", "we we we", "is is is", "500", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["429", "four two nine"], ["not"], ["5%"], ["24"], ["1%"], ["25%"], ["50%"], ["Redis cache"], ["API endpoint"], ["OpenTelemetry"], ["Wednesday"]], forbidden: ["500", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["API endpoint"], ["Redis cache"], ["OpenTelemetry"]], forbidden: ["a p i endpoint", "redish cash", "open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-L-0096", tier: "long", domain: "software/code",
            raw: "the new feature I mean flag ready but I do not want to turn it on for everyone yet. let us start with five percent of traffic in the the staging environment and watch the the error rate for twenty four hours. if the four two nine rate stays below one percent we can increase to twenty five percent and then to fifty percent. the the rollout script is in the the deploy repository and the the configuration key is enable new checkout. please make sure the Redis cache is warmed before we flip the the flag because a cold cache caused problems in the the the the last test. the a p i endpoint should handle the the extra load but we can verify with the open trace dashboard. do not merge the the flag into main until the product team signs off on Wednesday.",
            wordCount: 146,
            requiredAll: ["not", "5%", "24", "429", "1%", "25%", "50%", "Redis cache", "API endpoint", "OpenTelemetry", "Wednesday"],
            requiredAny: [["429", "four two nine"]],
            forbidden: ["a p i endpoint", "open trace", "the the", "i i i", "it it it", "we we we", "is is is", "500", "Monday"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["429", "four two nine"], ["not"], ["5%"], ["24"], ["1%"], ["25%"], ["50%"], ["Redis cache"], ["API endpoint"], ["OpenTelemetry"], ["Wednesday"]], forbidden: ["500", "Monday"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [["API endpoint"], ["OpenTelemetry"]], forbidden: ["a p i endpoint", "open trace"]),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["500", "Monday"])
            )
        ),
        A1Sample(
            id: "A1-L-0097", tier: "long", domain: "legal",
            raw: "the the contract review is almost done. the main open point is the the indemnification clause in section twelve which our legal team wants to narrow. the other side has agreed to cap liability at the fees paid in the the preceding twelve months which is acceptable to us. we do not want to reopen the the pricing terms because that was already negotiated in June. Sarah from the the the the outside counsel s office will send the redline by Wednesday actually no wait Thursday and we need to turn it around by Friday so the deal can close before the end of the quarter. please do not use the the previous version of the the agreement because it has the old governing law clause. if everything is signed by Monday so please keep me posted on that right so that",
            wordCount: 142,
            requiredAll: ["12", "not", "June", "Thursday", "Friday", "Monday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "24", "October"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["12"], ["not"], ["June"], ["Thursday"], ["Friday"], ["Monday"]], forbidden: ["24", "October"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["24", "October"])
            )
        ),
        A1Sample(
            id: "A1-L-0098", tier: "long", domain: "legal",
            raw: "the the contract um review is almost done. the main open point is the the the the indemnification clause in section twelve which our legal team wants to narrow. the other side has agreed to cap liability at the fees paid in the the preceding twelve months which is acceptable to us. we do not want to reopen the the pricing terms because that was already negotiated in June. Sarah from the the outside counsel s office will send the redline by Thursday and we need to turn it around by Friday so the deal can close before the end of the quarter. please do not use the the the the previous version of the the agreement because it has the old governing law clause. if everything is signed by Monday and we should double check the numbers you know what I mean",
            wordCount: 143,
            requiredAll: ["12", "not", "June", "Thursday", "Friday", "Monday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "24", "October"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["12"], ["not"], ["June"], ["Thursday"], ["Friday"], ["Monday"]], forbidden: ["24", "October"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["24", "October"])
            )
        ),
        A1Sample(
            id: "A1-L-0099", tier: "long", domain: "legal",
            raw: "the the contract review is you know almost done. the main open point is the the the the indemnification clause in section twelve which our legal team wants to narrow. the other side has agreed to cap liability at the fees paid in the the preceding twelve months which is acceptable to us. we do not want to reopen the the pricing terms because that was already negotiated in June. Sarah from the the outside counsel s office will send the redline by Thursday and we we we we we need to turn it around by Friday so the deal can close before the end of the quarter. please do not use the the previous version of the the agreement because it has the old governing law clause. if everything is signed by Monday as I mentioned earlier in the week which is important for",
            wordCount: 145,
            requiredAll: ["12", "not", "June", "Thursday", "Friday", "Monday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "24", "October"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["12"], ["not"], ["June"], ["Thursday"], ["Friday"], ["Monday"]], forbidden: ["24", "October"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["24", "October"])
            )
        ),
        A1Sample(
            id: "A1-L-0100", tier: "long", domain: "legal",
            raw: "the the contract review I mean is almost done. the main open point is the the indemnification clause in section twelve which our legal team wants to narrow. the other side has agreed to cap liability at the fees paid in the the preceding twelve months which is acceptable to us. we do not want to reopen the the pricing terms because that was already negotiated in June. Sarah from the the outside counsel s office will send the redline by Wednesday actually no wait Thursday and we need to turn it around by Friday so the deal can close before the end of the quarter. please do not use the the previous version of the the agreement because it has the old governing law clause. if everything is is is signed by Monday as I mentioned earlier in the week which is important for the",
            wordCount: 146,
            requiredAll: ["12", "not", "June", "Thursday", "Friday", "Monday"],
            requiredAny: [],
            forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "24", "October"],
            dims: A1Dims(
                facts: A1DimAssert(requiredAny: [["12"], ["not"], ["June"], ["Thursday"], ["Friday"], ["Monday"]], forbidden: ["24", "October"]),
                grammar: A1DimAssert(requiredAny: [], forbidden: ["the the", "i i i", "it it it", "we we we", "is is is", "um", "uh", "you know", "i mean", "basically"]),
                terms: A1DimAssert(requiredAny: [], forbidden: []),
                format: A1DimAssert(requiredAny: [[".", "!", "?"]], forbidden: ["  "]),
                novel: A1DimAssert(requiredAny: [], forbidden: ["24", "October"])
            )
        ),
    ]

    private let executableIDs: Set<String> = ["A1-S-0001", "A1-S-0011", "A1-S-0021", "A1-S-0031", "A1-S-0041", "A1-S-0051", "A1-S-0061", "A1-S-0071", "A1-S-0081", "A1-S-0091", "A1-L-0001", "A1-L-0011", "A1-L-0021", "A1-L-0031", "A1-L-0041", "A1-L-0051", "A1-L-0061", "A1-L-0071", "A1-L-0081", "A1-L-0091"]

    // MARK: - fixture integrity (no pipeline, CPU-light) — all 200 samples

    func testFullCorpusFixtureIntegrity() {
        XCTAssertEqual(corpus.count, 200)
        XCTAssertEqual(corpus.filter { $0.tier == "short" }.count, 100)
        XCTAssertEqual(corpus.filter { $0.tier == "long" }.count, 100)
        XCTAssertEqual(Set(corpus.map(\.id)).count, 200, "duplicate sample ids")
        XCTAssertEqual(executableIDs.count, 20)
        for s in corpus {
            XCTAssertFalse(s.raw.isEmpty, "\(s.id) empty raw")
            XCTAssertFalse(s.requiredAll.isEmpty, "\(s.id) no required facts")
            if s.tier == "short" {
                XCTAssertTrue((45...60).contains(s.wordCount), "\(s.id) short wordCount \(s.wordCount)")
            } else {
                XCTAssertTrue((140...150).contains(s.wordCount), "\(s.id) long wordCount \(s.wordCount)")
            }
            for group in s.requiredAny { XCTAssertFalse(group.isEmpty, "\(s.id) empty requiredAny group") }
            // a forbidden token must not also be required
            for f in s.forbidden {
                XCTAssertFalse(s.requiredAll.contains(f), "\(s.id) contradictory assertion: \(f)")
            }
        }
    }

    // MARK: - executed subset (opt-in, real pipeline, recorded verdicts)

    func testExecutedSubsetScores() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_CORPUS_EXECUTE"] == "1" else {
            throw XCTSkip("Set SUPERFLOW_CORPUS_EXECUTE=1 to run the 20-sample executed subset.")
        }
        var settings = AppSettings.default
        // Documented deterministic Tier-0 fallback: no S1-mini, no mocks.
        settings.cleanupEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings)
        let context = TextContext(settings: settings)
        let selected = corpus.filter { executableIDs.contains($0.id) }
        XCTAssertEqual(selected.count, 20)

        var records: [[String: Any]] = []
        for s in selected {
            let result = await pipeline.run(s.raw, context: context)
            let out = result.text
            XCTAssertFalse(out.isEmpty, "\(s.id) pipeline produced empty output")
            var dimScores: [String: Bool] = [:]
            let allDims: [(String, A1DimAssert)] = [
                ("facts", s.dims.facts), ("grammar", s.dims.grammar), ("terms", s.dims.terms),
                ("format", s.dims.format), ("novel", s.dims.novel)]
            for (name, assertion) in allDims {
                let reqOK = assertion.requiredAny.allSatisfy { group in
                    group.contains { a1Contains(out, $0) }
                }
                let forbOK = assertion.forbidden.allSatisfy { !a1Contains(out, $0) }
                dimScores[name] = reqOK && forbOK
            }
            let factsOK = s.requiredAll.allSatisfy { a1Contains(out, $0) }
            let anyOK = s.requiredAny.allSatisfy { group in
                group.contains { a1Contains(out, $0) }
            }
            let forbOK = s.forbidden.allSatisfy { !a1Contains(out, $0) }
            records.append([
                "id": s.id, "tier": s.tier, "domain": s.domain,
                "executed": true, "wordCount": s.wordCount,
                "raw": s.raw, "output": out,
                "coreFactsOK": factsOK, "coreAnyOK": anyOK, "coreForbiddenOK": forbOK,
                "dimensions": dimScores
            ])
        }

        let payload: [String: Any] = ["path": "Tier0-deterministic", "count": records.count, "records": records]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let outPath = ProcessInfo.processInfo.environment["SUPERFLOW_CORPUS_OUTPUT"]
            ?? (FileManager.default.temporaryDirectory.appendingPathComponent("agent1-executed.json").path)
        try data.write(to: URL(fileURLWithPath: outPath))
        NSLog("AGENT1_EXECUTED_WRITTEN \(outPath) records=\(records.count)")
    }
}
