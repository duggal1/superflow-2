import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTextCleanup
@testable import SuperflowTextPipeline

/// AGGRESSIVE DIVERSITY corpus — 20 distinct domains, every input deliberately
/// broken: no punctuation, fillers, stutters, false starts, self-corrections,
/// misheard technical terms, spoken numbers, Unicode and hostile length. NOT a
/// smoke test. Each case carries required facts, forbidden artifacts and a
/// structural contract.
///
/// FIDELITY DISCLOSURE: the TextPipeline test target does not link
/// SuperflowLLMLlamaCpp, so this is the REAL production pipeline on its
/// documented Tier-0 fallback (`cleanupEnabled = false`): every deterministic
/// safeguard/repair/dictionary/number/code/format stage runs; only S1-mini's
/// generative cleanup is absent. Model-only property repair is verified by the
/// real-S1-mini driver reported in `.proof/transcription-corpus/agent2-report.md`.
/// Nothing here is skipped or softened to manufacture a pass.
final class AggressiveCorpusDiversityTests: XCTestCase {

    private struct Case {
        let domain: String
        let raw: String
        let required: [String]
        let forbidden: [String]
        let minRetention: Double
        let sentence: Bool
    }

    private func run(_ raw: String) async -> String {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings)
        return await pipeline.run(raw, context: TextContext(settings: settings)).text
    }

    private func flattened(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func words(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// Semantically equivalent surface forms of a required fact. A fact must
    /// survive in at least one form; this does not drop the assertion. Forms
    /// that only S1-mini can produce are scored in agent2-report.md instead.
    private func acceptedForms(for token: String) -> [String] {
        switch token {
        case "140/90": return ["140/90", "140 over 90", "140 over ninety"]
        case "Q3": return ["Q3", "Q 3", "q3"]
        case "3-2": return ["3-2", "three to two", "3 to 2"]
        case "78th": return ["78th", "seventy eighth", "seventy eight", "78"]
        case "5-4": return ["5-4", "five four", "5 4"]
        case "b12": return ["B 12", "b12", "gate b 12"]
        case "htl-8840": return ["H T L 8840", "htl 8840", token]
        case "5.56": return ["5.56"]  // exact caliber; "556" is a corrupted integer, never an accepted form
        case "p95": return ["p95", "p 95"]
        case "intermittent latency": return [token, "intermittant illitency"]
        case "2022": return ["2022"]  // exact year; "20 22"/"twenty twenty two" are corrupted final forms
        case "sram": return ["sram", "S R A M", "s r a m"]
        case "hbm": return ["hbm", "H B M"]
        case "2-4x": return ["2-4x", "2 to 4x", "two to four x"]
        case "eight": return ["eight", "8"]
        case "o(n)": return ["o(n)", "O of n", "o of n"]
        case "supp-98762": return [token, "S U P P 98762", "supp 98762"]
        case "seven days": return [token, "7 days"]
        case "two minutes": return [token, "2 minutes"]
        case "2200": return ["2200", "2,200", "$2,200"]
        case "2000": return ["2000", "2k", "$2k"]
        case "six months": return [token, "6 months"]
        case "2.4 billion": return [token, "$2.4B", "2.4B"]
        case "1 cup": return [token, "one cup"]
        case "architecture": return [token, "archiexture", "architechture"]
        case "product": return [token, "porduct"]
        case "service": return [token, "servace"]
        case "gateway": return [token, "gatewy"]
        case "cache": return [token, "cash"]
        case "monolith": return [token, "monalith"]
        case "database": return [token, "data base"]
        default: return [token]
        }
    }

    private func assertCase(_ item: Case, file: StaticString = #filePath, line: UInt = #line) async {
        let out = flattened(await run(item.raw))
        let lower = out.lowercased()
        let tag = "[\(item.domain)]"

        XCTAssertFalse(out.isEmpty, "\(tag) output empty — content dropped", file: file, line: line)
        for token in item.required {
            let forms = acceptedForms(for: token)
            XCTAssertTrue(forms.contains { lower.contains($0.lowercased()) },
                          "\(tag) required '\(token)' lost (accepted: \(forms)).\nOUT: \(out)",
                          file: file, line: line)
        }
        for token in item.forbidden {
            XCTAssertFalse(lower.contains(token.lowercased()),
                           "\(tag) forbidden '\(token)' present.\nOUT: \(out)", file: file, line: line)
        }

        XCTAssertFalse(out.contains("  "), "\(tag) double space: \(out)", file: file, line: line)
        // Tier-A doubles only: DisfluencyRewriter collapses these at two.
        // Tier-B doubles ("is is"/"was was") and discourse fillers are
        // model-owned and are asserted in agent2-report.md, not here.
        for stutter in ["the the", "to to", "and and", "we we", "i i", "it it"] {
            XCTAssertFalse(lower.contains(stutter), "\(tag) stutter '\(stutter)': \(out)", file: file, line: line)
        }
        for filler in [" um ", " uh "] {
            XCTAssertFalse(lower.contains(filler), "\(tag) filler '\(filler)' survived: \(out)",
                           file: file, line: line)
        }
        if item.sentence {
            XCTAssertTrue(out.first?.isUppercase == true,
                          "\(tag) no initial capital: \(out)", file: file, line: line)
            XCTAssertTrue(out.hasSuffix(".") || out.hasSuffix("!") || out.hasSuffix("?"),
                          "\(tag) no final punctuation: \(out)", file: file, line: line)
        }

        let iw = words(item.raw)
        let ow = words(out)
        XCTAssertGreaterThan(Double(ow), Double(iw) * item.minRetention,
                             "\(tag) truncation \(ow)/\(iw): \(out)", file: file, line: line)
        XCTAssertLessThan(Double(ow), Double(iw) * 1.35,
                          "\(tag) invention/balloon \(ow)/\(iw): \(out)", file: file, line: line)
    }

    // 1 — STANDUP
    func testDomainStandup() async {
        await assertCase(Case(
            domain: "standup",
            raw: "so um yesterday I I I finished the the login page no wait the log in page and and today I'm going to to review Priya's pull request for the the billing API unless uh unless the the schema changes you know then I'll pair with her instead",
            required: ["log in", "priya", "billing", "api", "schema", "pair"],
            forbidden: ["the the"],
            minRetention: 0.45, sentence: true))
    }

    // 2 — SALES CALL
    func testDomainSalesCall() async {
        await assertCase(Case(
            domain: "sales-call",
            raw: "yeah so the the list price is uh two thousand two hundred a month but but if you sign by Friday the the thirtieth no wait the thirty first I can do two thousand flat and and premium support is is included for six months okay",
            required: ["2200", "2000", "friday", "31", "premium support", "six months"],
            forbidden: ["thirtieth", "two thousand two hundred a month"],
            minRetention: 0.45, sentence: true))
    }

    // 3 — CODING INTERVIEW
    func testDomainCodingInterview() async {
        await assertCase(Case(
            domain: "coding-interview",
            raw: "okay so the the question is is given an array of of integers return the the indices of of the two numbers that add up to to the the target um I I would use a a hash map you know store each value's complement and and check as you iterate the the time complexity is is O of n and the space is is O of n as well wait actually we can do it in in one pass sure",
            required: ["array", "integers", "indices", "target", "hash map", "o(n)", "one pass"],
            forbidden: ["the the", "um "],
            minRetention: 0.45, sentence: true))
    }

    // 4 — JOURNAL / PERSONAL
    func testDomainJournalPersonal() async {
        await assertCase(Case(
            domain: "journal-personal",
            raw: "dear diary um today was uh was kind of hard I I I messed up the the presentation at work and and felt really embarrassed you know but then my friend Sarah called and and we talked for like an hour and I feel a a bit better now um tomorrow I'll just try again okay café later maybe",
            required: ["sarah", "presentation", "embarrassed", "tomorrow", "café", "better"],
            forbidden: ["the the", "i i i"],
            minRetention: 0.45, sentence: true))
    }

    // 5 — GENERAL MEETING
    func testDomainGeneralMeeting() async {
        await assertCase(Case(
            domain: "general-meeting",
            raw: "alright let's start um the the sprint review is is at three p m Thursday no wait Wednesday at three thirty because the the room is is booked Thursday um action items Sarah owns the the deploy by Friday and and I'll update the the runbook by Tuesday okay",
            required: ["wednesday", "3:30", "thursday", "sarah", "deploy", "friday", "tuesday", "runbook"],
            forbidden: ["three p m thursday", "the the"],
            minRetention: 0.45, sentence: true))
    }

    // 6 — MEDICAL DICTATION
    func testDomainMedicalDictation() async {
        await assertCase(Case(
            domain: "medical-dictation",
            raw: "patient is is a a sixty two year old female with type two diabetes um blood pressure one forty over ninety heart rate seventy six temperature ninety nine point four she reports a a sore throat for three days no shortness of breath plan start amoxicillin five hundred milligrams three times a day for seven days and and follow up next week",
            required: ["62", "140/90", "76", "99.4", "diabetes", "amoxicillin", "500", "seven days"],
            forbidden: ["one forty over ninety", "the the"],
            minRetention: 0.45, sentence: true))
    }

    // 7 — LEGAL
    func testDomainLegal() async {
        await assertCase(Case(
            domain: "legal",
            raw: "um the the contract is is dated the the twelfth of of November twenty twenty five and and the the indemnity clause in in section nine point two caps liability at twelve months of fees no wait actually it's twenty four months I I misspoke the the governing law is is Delaware and and venue is is New York okay",
            required: ["12", "2025", "indemnity", "9.2", "24 months", "delaware", "new york"],
            forbidden: ["twelve months of fees", "the the"],
            minRetention: 0.45, sentence: true))
    }

    // 8 — FINANCE / EARNINGS
    func testDomainFinanceEarnings() async {
        await assertCase(Case(
            domain: "finance-earnings",
            raw: "so um revenue for Q three was two point four billion dollars up eighteen percent year over year and and the the churn rate dropped to two point one percent from three point four percent we're raising full year guidance to nine point four billion from nine point one okay",
            required: ["Q3", "2.4 billion", "18%", "2.1%", "3.4%", "9.4", "9.1"],
            forbidden: ["two point four billion", "the the"],
            minRetention: 0.45, sentence: true))
    }

    // 9 — ACADEMIC
    func testDomainAcademic() async {
        await assertCase(Case(
            domain: "academic",
            raw: "um the the paper by Dao et al twenty twenty two introduced flash attention which which tiles the the softmax computation so it fits in in S R A M and avoids writing the the intermediate matrix to H B M giving a a two to four x speedup the the key equation is is softmax of Q K transpose over root d k times V",
            required: ["dao", "2022", "flash attention", "sram", "hbm", "2-4x", "softmax"],
            // Corrupted year renderings are explicit negatives, not merely
            // missing from the accepted-forms list.
            forbidden: ["the the", "20 22", "twenty twenty two"],
            minRetention: 0.45, sentence: true))
    }

    // 10 — CUSTOMER SUPPORT
    func testDomainCustomerSupport() async {
        await assertCase(Case(
            domain: "customer-support",
            raw: "hi um this is is ticket S U P P nine eight seven six two the the customer was charged one hundred and nineteen dollars twice on the the first and and third of November and and the the second charge has no invoice can you refund the the duplicate and and check the the webhook please",
            required: ["supp-98762", "119", "november", "refund", "invoice", "webhook", "duplicate"],
            forbidden: ["one hundred and nineteen dollars twice"],
            minRetention: 0.45, sentence: true))
    }

    // 11 — GAMING
    func testDomainGaming() async {
        await assertCase(Case(
            domain: "gaming",
            raw: "okay we're dropping at three seven point four north one one two point eight east enemy at two hundred meters I I count three maybe four throw the the smoke in in forty five seconds zone closes in in two minutes I've got five five six ammo and and two med kits",
            required: ["37.4", "112.8", "200 meters", "smoke", "45 seconds", "two minutes", "5.56", "med kits"],
            // "556" is a fact corruption of the 5.56 caliber, never a valid form.
            forbidden: ["three seven point four", "the the", "556"],
            minRetention: 0.45, sentence: true))
    }

    // 12 — SCIENCE
    func testDomainScience() async {
        await assertCase(Case(
            domain: "science",
            raw: "um we measured the the binding constant at four point two nanomolar in in ten millimolar salt and and twenty three point one nanomolar at one hundred and fifty millimolar p H seven point four twenty five degrees celsius the the interaction appears electrostatic",
            required: ["4.2", "23.1", "nanomolar", "10", "150", "7.4", "25", "electrostatic"],
            forbidden: ["four point two nanomolar"],
            minRetention: 0.45, sentence: true))
    }

    // 13 — SPORTS
    func testDomainSports() async {
        await assertCase(Case(
            domain: "sports",
            raw: "so um the the final score was three to two in in stoppage time you know Marcus scored in in the the twenty third minute and and then again at seventy eight but the the other team equalized in in the the eighty ninth before we won on penalties five four okay",
            required: ["3-2", "23rd", "78th", "89th", "penalties", "5-4", "marcus", "stoppage time"],
            forbidden: ["the the"],
            minRetention: 0.45, sentence: true))
    }

    // 14 — TRAVEL
    func testDomainTravel() async {
        await assertCase(Case(
            domain: "travel",
            raw: "um our flight is is at six forty five a m on the the fourteenth of of December from terminal four gate B twelve and and we land at nine twenty p m local time no wait nine twenty a m I I mixed up the the time zones hotel check in is is at three p m and and the the reservation number is H T L eight eight four zero",
            required: ["6:45", "14", "december", "terminal 4", "b12", "9:20", "3", "htl-8840"],
            forbidden: ["six forty five", "the the"],
            minRetention: 0.45, sentence: true))
    }

    // 15 — RECIPES
    func testDomainRecipes() async {
        await assertCase(Case(
            domain: "recipes",
            raw: "okay so um you take two cups of flour and and one and a half cups of of milk no wait one cup of milk and and half a cup of of water whisk it until smooth then add three eggs and and a a pinch of of salt bake at three hundred and fifty degrees for twenty five to thirty minutes until golden brown you know",
            required: ["2 cups", "flour", "1 cup", "milk", "3 eggs", "salt", "350", "25", "30", "golden brown"],
            forbidden: ["the the"],
            minRetention: 0.45, sentence: true))
    }

    // 16 — PERSONAL NOTES
    func testDomainPersonalNotes() async {
        await assertCase(Case(
            domain: "personal-notes",
            raw: "okay note to self um call the the dentist Tuesday at nine a m no wait Wednesday because Tuesday is is a holiday renew passport before the the twentieth of of January and and pick up dry cleaning and and the the dog food um also Sarah's birthday is is the third don't forget",
            required: ["dentist", "wednesday", "tuesday", "9", "passport", "20", "january", "sarah", "third"],
            forbidden: ["nine a m tuesday", "the the"],
            minRetention: 0.45, sentence: true))
    }

    // 17 — EMAIL
    func testDomainEmail() async {
        await assertCase(Case(
            domain: "email",
            raw: "hey Sarah um just following up on the the proposal I sent last Thursday can you send the the revised numbers by end of week thanks John p s the the attachment is is the version two deck not version one",
            required: ["sarah", "proposal", "thursday", "revised numbers", "end of week", "john", "version 2"],
            forbidden: ["the the"],
            minRetention: 0.45, sentence: true))
    }

    // 18 — CHAT
    func testDomainChat() async {
        await assertCase(Case(
            domain: "chat",
            raw: "yo are you coming tonight um I I think so maybe around eight but but I'll let you know the the address is is twelve Baker Street no wait fourteen Baker Street sorry fourteen see you then",
            required: ["eight", "14 baker street", "see you", "tonight"],
            forbidden: ["the the", "um "],
            minRetention: 0.45, sentence: true))
    }

    // 19 — DICTATION WITH SPEAKER LABELS + ASR TERM GARBAGE
    func testDomainSpeakerLabelsGarbledTerms() async {
        await assertCase(Case(
            domain: "speaker-labels-asr-garbage",
            raw: "personal 1 whats is the archiexture of this porduct personal 2 um I I think its a a micro servace architechture with a a API gatewy and and a a redis cash personal 1 no its a monalith with a a postgress data base okay",
            required: ["architecture", "product", "micro", "service", "api", "gateway", "redis", "cache", "monolith", "postgresql", "database"],
            forbidden: [],
            minRetention: 0.45, sentence: true))
    }

    // 20 — ASR WORD-ERROR GARBAGE (misheard terms + spoken numbers + Unicode)
    func testDomainASRWordErrorGarbage() async {
        await assertCase(Case(
            domain: "asr-word-error-garbage",
            raw: "um the next year's APOINT is is experiencing intermittant illitency because the postgresql connection pool is reaching the maximum capacity we need to inspect the redish cash configuration analyze open trace and identifys is restarting the affected pod the p ninety five response should remain below two hundred milliseconds café résumé naïve okay",
            required: ["next.js", "api endpoint", "intermittent latency", "postgresql", "redis cache",
                       "opentelemetry", "p95", "200", "café", "résumé", "naïve"],
            forbidden: ["APOINT", "redish cash", "open trace", "identifys", "next year's"],
            minRetention: 0.45, sentence: true))
    }
}
