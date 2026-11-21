import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
@testable import SuperflowTextPipeline

/// EXTREME Tier-0 (deterministic, model-free) quality gate.
///
/// This is the FALLBACK path used when S1-mini is unavailable or its output is
/// rejected by a safety guard. Its contract is fact preservation and safe
/// formatting, not model-level polish: filler removal, self-correction
/// resolution and Q-number shaping are owned by the cleanup model and are
/// asserted in `HeadlessExtremeQualityTests` / `HeadlessQualityHarnessTests`.
/// These gates deliberately feed broken ASR text and prove the fallback never
/// loses data, invents content, corrupts technical terms or crashes.
final class ExtremeTranscriptionQualityTests: XCTestCase {

    private func clean(_ raw: String) async -> String {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings)
        return await pipeline.run(raw, context: TextContext(settings: settings)).text
    }

    private func flattened(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: broken grammar with technical terms — facts must survive

    func testExtremeBrokenGrammarKeepsTechnicalFacts() async {
        let raw = "okay so um the the the JWT token it's it's expired you know and the api is is returning a four zero three not a five hundred wait no four two nine because uh the rate limiter is kicking in"
        let out = flattened(await clean(raw))
        XCTAssertTrue(out.localizedCaseInsensitiveContains("jwt"), "JWT lost: \(out)")
        XCTAssertTrue(out.localizedCaseInsensitiveContains("api"), "API lost: \(out)")
        XCTAssertTrue(out.localizedCaseInsensitiveContains("rate limiter"), "term lost: \(out)")
        XCTAssertTrue(out.contains("403") || out.localizedCaseInsensitiveContains("four zero three"), "403 lost: \(out)")
        XCTAssertTrue(out.contains("429") || out.localizedCaseInsensitiveContains("four two nine"), "429 lost: \(out)")
        XCTAssertFalse(out.localizedCaseInsensitiveContains("the the"), "stutter not deduped: \(out)")
        XCTAssertTrue(out.first?.isUppercase == true, "not capitalized: \(out)")
        XCTAssertTrue(out.hasSuffix("."), "no final period: \(out)")
    }

    func testExtremeBrokenGrammarNoContentLoss() async {
        let raw = "um so like I I I don't not want to uh deploy the the config on Friday actually no wait Thursday because the the staging cluster is is still red"
        let out = flattened(await clean(raw))
        let lower = out.lowercased()
        XCTAssertTrue(lower.contains("not") || lower.contains("n't"), "negation lost: \(out)")
        XCTAssertTrue(lower.contains("thursday") || lower.contains("friday"), "a day must survive: \(out)")
        XCTAssertTrue(lower.contains("staging"), "term lost: \(out)")
        XCTAssertTrue(lower.contains("red"), "status lost: \(out)")
    }

    func testExtremeSpokenPathIsReassembled() async {
        let raw = "open lib slash backend slash main slash engine slash router slash prospect dash main dash engine dot t s then fix the get user by id function no wait getUserById and change the timeout from three thousand to five thousand milliseconds"
        let out = flattened(await clean(raw))
        // CodeAware must at least join the slash-separated path stem.
        XCTAssertTrue(out.contains("lib/backend/main/engine/router/"),
                      "slash path not reassembled: \(out)")
        XCTAssertTrue(out.contains(".ts"), "extension not rendered: \(out)")
        XCTAssertTrue(out.localizedCaseInsensitiveContains("getuserbyid")
                      || out.localizedCaseInsensitiveContains("get user by id"),
                      "identifier lost: \(out)")
    }

    func testExtremeStatusCodeChaos() async {
        let raw = "the the response was a four oh four then a five oh three then a four two nine and uh finally a two hundred but but not a five hundred"
        let out = flattened(await clean(raw))
        for spoken in ["four oh four", "five oh three", "four two nine", "two hundred", "five hundred"] {
            let digits = ["four oh four": "404", "five oh three": "503", "four two nine": "429",
                          "two hundred": "200", "five hundred": "500"][spoken]!
            XCTAssertTrue(out.contains(digits) || out.localizedCaseInsensitiveContains(spoken),
                          "code \(digits) lost: \(out)")
        }
        XCTAssertTrue(out.lowercased().contains("not") || out.localizedCaseInsensitiveContains("n't"),
                      "negation lost: \(out)")
    }

    // MARK: professional transcript — facts and formatting must survive

    func testExtremeProfessionalMeetingFacts() async {
        let raw = "thanks everyone um so let's start with the the Q three numbers revenue was uh two point four million dollars which is is up from one point eight million last quarter and the the churn rate dropped to two point one percent from three point four percent the main driver was uh the enterprise tier you know which we shipped in in July"
        let out = flattened(await clean(raw))
        let lower = out.lowercased()
        XCTAssertTrue(lower.contains("q 3") || lower.contains("q3"), "Q3 lost: \(out)")
        XCTAssertTrue(out.contains("2.4") || out.contains("$2.4M"), "2.4 lost: \(out)")
        XCTAssertTrue(out.contains("2.1"), "churn figure lost: \(out)")
        XCTAssertTrue(lower.contains("july"), "proper noun lost: \(out)")
        XCTAssertTrue(lower.contains("enterprise"), "term lost: \(out)")
        XCTAssertTrue(out.first?.isUppercase == true, "not capitalized: \(out)")
        XCTAssertTrue(out.hasSuffix("."), "no final period: \(out)")
    }

    func testExtremeProfessionalStandupFacts() async {
        let raw = "so um yesterday I I worked on the the auth flow and and today I'm going to to review the pull request for the billing service unless uh unless the API contract changes you know then I'll pair with Sarah on that instead"
        let out = flattened(await clean(raw))
        let lower = out.lowercased()
        XCTAssertTrue(lower.contains("auth flow"), "term lost: \(out)")
        XCTAssertTrue(lower.contains("billing service"), "term lost: \(out)")
        XCTAssertTrue(out.contains("API"), "acronym lost: \(out)")
        XCTAssertTrue(out.contains("Sarah"), "name lost: \(out)")
    }

    func testExtremeProfessionalNumbersAndCurrency() async {
        let raw = "the the budget is uh four hundred fifty thousand dollars and we need two point five full time engineers by Q one next year okay"
        let out = flattened(await clean(raw))
        XCTAssertTrue(out.contains("450") || out.contains("$450k"), "budget lost: \(out)")
        XCTAssertTrue(out.contains("2.5"), "headcount lost: \(out)")
        XCTAssertTrue(out.lowercased().contains("q 1") || out.lowercased().contains("q1")
                      || out.lowercased().contains("q one"), "Q1 lost: \(out)")
    }

    // MARK: hostile / edge inputs — never crash, never invent, never corrupt

    func testExtremeOnlyFillersDoesNotInventContent() async {
        let raw = "um uh um you know like I mean um uh basically um"
        let out = flattened(await clean(raw))
        XCTAssertLessThan(out.count, 45, "filler-only input ballooned: \(out)")
        XCTAssertFalse(out.localizedCaseInsensitiveContains("deploy"), "invented content: \(out)")
    }

    func testExtremeEmptyAndWhitespace() async {
        let empty = await clean("")
        let whitespace = await clean("   \n  ")
        XCTAssertEqual(empty, "")
        XCTAssertEqual(whitespace, "")
    }

    func testExtremeUnicodeAndLongInputDoesNotTruncate() async {
        let sentence = "um the the API returned a four zero three you know and and Sarah said café résumé naïve okay "
        let raw = String(repeating: sentence, count: 12)
        let out = await clean(raw)
        XCTAssertTrue(out.contains("café"), "unicode lost: \(String(out.prefix(120)))")
        XCTAssertTrue(out.contains("résumé"), "unicode lost")
        XCTAssertTrue(out.contains("naïve"), "unicode lost")
    }

    func testExtremeOrdinaryWordsNotTechnicalized() async {
        for input in ["see you next year", "I need some cash tomorrow", "open the website please",
                      "we should react to the news"] {
            let out = flattened(await clean(input))
            XCTAssertFalse(out.contains("Next.js"), "over-correction: \(input) -> \(out)")
            XCTAssertFalse(out.contains("OpenAI"), "over-correction: \(input) -> \(out)")
            XCTAssertFalse(out.contains("WebSocket"), "over-correction: \(input) -> \(out)")
            XCTAssertFalse(out.contains("React"), "over-correction: \(input) -> \(out)")
        }
    }
}
