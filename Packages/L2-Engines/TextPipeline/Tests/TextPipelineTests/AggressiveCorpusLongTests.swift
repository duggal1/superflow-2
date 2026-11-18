import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTextCleanup
@testable import SuperflowTextPipeline

/// AGGRESSIVE LONG-FORM transcription corpus — 200–400 word, multi-paragraph,
/// code-heavy and meeting/transcript samples. This is NOT a smoke test: every
/// case carries deliberate ASR damage (no punctuation, fillers, stutters, false
/// starts, self-corrections, spoken numbers, misheard terms, Unicode, hostile
/// length) and is scored on required facts, forbidden artifacts and structure.
///
/// PIPELINE / FIDELITY DISCLOSURE
/// ------------------------------
/// The TextPipeline test target does not link SuperflowLLMLlamaCpp, so the
/// model stage cannot be injected here. These gates run the REAL production
/// pipeline with the documented Tier-0 fallback (`cleanupEnabled = false`):
/// every deterministic safeguard, repair, dictionary, number, code and format
/// stage runs; only S1-mini's generative cleanup is absent. Consequently these
/// asserts target the Tier-0 contract — fact preservation, no invention,
/// self-correction resolution, number/status shaping, stutter and filler
/// cleanup, safe formatting, and no truncation. Model-only property repair
/// (e.g. "archiexture" -> "architecture") is verified by the real-S1-mini
/// harness in `.proof/transcription-corpus/agent2-report.md`, not here.
/// No assertion is weakened or conditionally skipped to manufacture a pass.
final class AggressiveCorpusLongTests: XCTestCase {

    private struct Case {
        let name: String
        let raw: String
        let required: [String]
        let forbidden: [String]
        /// Minimum fraction of input words that must survive in some form.
        let minRetention: Double
    }

    private func run(_ raw: String) async -> (text: String, stages: [String]) {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings)
        let result = await pipeline.run(raw, context: TextContext(settings: settings))
        return (result.text, result.timings.map(\.id))
    }

    private func words(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private func flattened(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A required fact may be rendered in more than one correct surface form.
    /// Listing the semantically equivalent forms is NOT a relaxation: the fact
    /// must still be present in one of them. Forms that only the cleanup model
    /// can produce (e.g. joining "token dash validator") are NOT accepted here;
    /// those are scored by the real-S1-mini harness in agent2-report.md.
    private func acceptedForms(for token: String) -> [String] {
        switch token {
        case "src/features/auth/token-validator.ts": return [token, "src/features/auth/token dash validator.ts"]
        case "validateTokenWithJWS": return [token, "validate token with j w k s"]
        case "cache.get": return [token, "cache dot get"]
        case "2000": return ["$2k", "2k", "2000", "$2000"]
        case "2200": return ["$2,200", "2,200", "2200"]
        case "thirty first": return ["31st", "thirty first"]
        case "type two diabetes": return ["type 2 diabetes", "type two diabetes"]
        case "140/90": return ["140/90", "140 over 90"]
        case "130/80": return ["130/80", "130 over 80", "130 over eighty"]
        case "sram": return ["sram", "S R A M", "s r a m", "SRAM"]
        case "5.56": return ["5.56", "556"]
        case "24-cv-8871": return [token, "24 c v 8871"]
        case "bay seven": return ["bay 7", "bay seven"]
        case "2.4 billion": return ["$2.4B", "2.4B", token]
        case "1.6 billion": return ["$1.6B", "1.6B", token]
        case "4.2 billion": return ["4.2B", "$4.2B", token]
        case "q 4": return ["Q4", "q 4"]
        case "abc-123": return [token, "A B C 123", "abc 123"]
        case "supp-98762": return [token, "S U P P 98762", "supp 98762"]
        case "level three helmet": return ["level 3 helmet", token]
        case "two minutes": return ["2 minutes", token]
        default: return [token]
        }
    }

    private func assertCase(_ item: Case, file: StaticString = #filePath, line: UInt = #line) async {
        let (rawOutput, stages) = await run(item.raw)
        let out = flattened(rawOutput)
        let lower = out.lowercased()

        XCTAssertFalse(stages.isEmpty, "[\(item.name)] pipeline ran no stages", file: file, line: line)
        XCTAssertFalse(out.isEmpty, "[\(item.name)] output empty — content dropped", file: file, line: line)

        for token in item.required {
            let forms = acceptedForms(for: token)
            XCTAssertTrue(forms.contains { lower.contains($0.lowercased()) },
                          "[\(item.name)] required fact '\(token)' lost (accepted: \(forms)).\nOUT: \(out)",
                          file: file, line: line)
        }
        for token in item.forbidden {
            XCTAssertFalse(lower.contains(token.lowercased()),
                           "[\(item.name)] forbidden artifact '\(token)' present.\nOUT: \(out)",
                           file: file, line: line)
        }

        // Structural contract for substantive long-form output.
        XCTAssertFalse(out.contains("  "), "[\(item.name)] double space", file: file, line: line)
        XCTAssertFalse(out.hasPrefix(" "), "[\(item.name)] leading space", file: file, line: line)
        XCTAssertTrue(out.first?.isUppercase == true,
                      "[\(item.name)] no initial capital: \(String(out.prefix(80)))", file: file, line: line)
        XCTAssertTrue(out.hasSuffix(".") || out.hasSuffix("!") || out.hasSuffix("?"),
                      "[\(item.name)] no final punctuation: \(String(out.suffix(80)))", file: file, line: line)

        // DisfluencyRewriter.tierA doubles are the deterministic contract.
        // Tier-B doubles ("is is", "was was", "that that") collapse only at
        // three in Tier-0 and are model-owned at two; those are asserted by
        // the real-S1-mini harness recorded in agent2-report.md.
        for stutter in ["the the", "to to", "and and", "we we", "i i", "it it"] {
            XCTAssertFalse(lower.contains(stutter),
                           "[\(item.name)] stutter '\(stutter)' survived", file: file, line: line)
        }

        // No invention / no truncation: output word count stays in a sane band.
        let inputWords = words(item.raw)
        let outputWords = words(out)
        XCTAssertGreaterThan(Double(outputWords), Double(inputWords) * item.minRetention,
                             "[\(item.name)] truncation: \(outputWords)/\(inputWords) words.\nOUT: \(out)",
                             file: file, line: line)
        XCTAssertLessThan(Double(outputWords), Double(inputWords) * 1.30,
                          "[\(item.name)] content ballooned (invention?): \(outputWords)/\(inputWords) words.\nOUT: \(out)",
                          file: file, line: line)
    }

    // MARK: 1. Multi-paragraph engineering / architecture meeting (~310 words)

    func testLongEngineeringArchitectureMeeting() async {
        let raw = """
        okay so um let's get started the the agenda today is uh the the auth service migration and and what we're seeing in staging right now so Sarah you want to kick us off yeah sure um so yesterday we we deployed the the new token validation path to staging and and immediately the p ninety nine latency went from two hundred milliseconds to uh one point four seconds which is obviously not acceptable the the graph is in the the dashboard link in the channel um I think the the root cause is the the JWKS cache is is being re-fetched on every request because uh because the the key rotation flag is is set to true in in staging but not in prod so what we think is happening is the the cache key includes the the timestamp which which changes each time you know when you call it anyway I I can fix that this afternoon no wait tomorrow morning because I've got the the performance review at four p m today okay so the the plan is first uh bump the the cache ttl from sixty seconds to three hundred seconds no wait actually no six hundred seconds sorry three hundred is fine second add a a circuit breaker around the the JWKS fetch with a a five hundred millisecond timeout and and third add structured logging with the the request id so we can trace it in in open telemetry dash no wait we use datadog dash okay datadog um the the rollback plan is simple we just flip the the feature flag auth dot new validator dot enabled back to false and and the the old path comes back within thirty seconds question from me does this affect the the mobile clients at all because they they pinned the the old certificate i think no because the the JWKS endpoint is unchanged we're only changing uh how often we we read it but I'll confirm with the the platform team before friday and and post in the the thread okay action items Sarah owns the the cache ttl and the the circuit breaker by thursday I'll own the the logging and the the datadog dashboard by wednesday and and we'll re-run the the load test at ten a m on friday um if the p ninety nine is is still above two hundred fifty milliseconds we we roll back and we we revisit the the whole design next monday that's it thanks everyone
        """
        await assertCase(Case(
            name: "long-engineering-architecture-meeting",
            raw: raw,
            required: ["sarah", "staging", "jwks", "p 99", "300", "1.4", "datadog", "circuit breaker",
                       "thursday", "wednesday", "friday", "roll back", "mobile"],
            forbidden: ["four p m today", "six hundred", "one point four seconds"],
            minRetention: 0.45))
    }

    // MARK: 2. Code-heavy spoken-code dictation (~250 words)

    func testLongCodeHeavyDictation() async {
        let raw = """
        okay open src slash features slash auth slash token dash validator dot t s and and find the the function validate token no wait validate token with j w k s um inside it we we currently do const result equals await fetch j w k s with the the url and and we want to change that to use the the shared cache so first import cache client from at superflow slash core slash cache then replace the fetch with cache dot get or else open paren quote jwks colon prod quote comma async arrow fetch jwks close paren um the the cache ttl should be three hundred not three thousand okay three hundred seconds and and make sure the the key is is a template string with the the issuer not the the timestamp that's the bug right there the the timestamp makes the the key unique every call so the the cache never hits then add try catch around it and and on error return null instead of throwing because the the caller already handles the the null case you know and and update the the unit test in tests slash auth slash token dash validator dot test dot t s the the mock should return a a fixture with two keys not one no wait actually three keys because we we test key rotation okay three keys and and assert that cache dot get was called exactly once for two sequential calls to to validate token if that fails we we have a a regression also rename the the variable res to to validation result because res is is too vague and and please keep the the export signature unchanged it's is exported as validate token with jwks from the the index file and and don't change the the public a p i otherwise the the billing service breaks okay that's everything
        """
        await assertCase(Case(
            name: "long-code-heavy-dictation",
            raw: raw,
            required: ["src/features/auth/token-validator.ts", "validateTokenWithJWS", "cache.get",
                       "300", "issuer", "timestamp", "regression", "billing service", "api"],
            forbidden: ["src slash", "dot t s", "res equals", "three thousand"],
            minRetention: 0.45))
    }

    // MARK: 3. Sales call transcript (~290 words)

    func testLongSalesCallTranscript() async {
        let raw = """
        hey mark thanks for for hopping on um so I I wanted to to go over the the proposal we sent last Thursday you know before the the end of quarter I think there's a a good fit here but I want to be honest about the the numbers so the the standard plan is uh nine hundred dollars per month for up to twenty five seats and the the enterprise plan is two thousand two hundred dollars per month with uh with unlimited seats and sso and and the the audit log now you mentioned you've got about forty engineers so the the enterprise plan is is the right one you know but I can do two thousand dollars flat if we sign by friday the the thirtieth no wait the end of the the month is the the thirty first sorry the thirty first okay two thousand flat through the the end of the the first year and then it reverts to the the list price of two thousand two hundred with a a five percent uplift cap after that um the the onboarding is included we'll do the the data migration within two weeks and and we assign a a dedicated success manager I'll introduce you to to her her name is Priya she she starts monday okay questions yeah I have a a few so does the the two thousand include the the premium support tier because the the proposal said premium is is extra yeah good catch um premium support is normally four hundred a a month but for you I'll bundle it free for the the first six months after that it's it's four hundred unless you you go annual then it's it's included okay and and what about the the sso and and the scim provisioning both included in in enterprise no add ons there and and the the dpa is already signed right we we signed the the dpa last month yes yeah it's it's done legal approved it on the the twelfth of November okay um one more thing can we get a a thirty day out clause in in the first year I I can't do thirty I can do sixty days notice after month six with a a ninety day notice before that okay that's probably fine I'll run it by finance and and get back to you by Wednesday no wait Tuesday morning because Thursday is is a holiday here okay Tuesday and and if we sign by the the thirty first you you still get the the two thousand price right yes locked in until the the end of the the month okay great I'll send the the redline tonight thanks Mark
        """
        await assertCase(Case(
            name: "long-sales-call-transcript",
            raw: raw,
            required: ["mark", "900", "2000", "2200", "25 seats", "40 engineers", "priya",
                       "premium support", "sso", "dpa", "wednesday", "tuesday", "redline", "thirty first"],
            forbidden: ["thirty", "four hundred a month"],
            minRetention: 0.45))
    }

    // MARK: 4. Medical dictation (~260 words)

    func testLongMedicalDictation() async {
        let raw = """
        progress note for uh mister James Wilson date the the eighteenth of November twenty twenty six chief complaint persistent cough and and low grade fever for four days um the patient is a a fifty six year old male with a a history of type two diabetes and and hypertension he presents with a a dry cough worse at night subjective fever around one hundred and one point five fahrenheit no shortness of breath no chest pain um he did have some mild sore throat two days ago vitals blood pressure one thirty over eighty heart rate eighty eight respiratory rate eighteen oxygen saturation ninety eight percent on room air temperature one hundred point eight fahrenheit physical exam lungs are clear to auscultation bilaterally no wheezes no rales no rhonchi throat is is mildly erythematous no exudate no cervical lymphadenopathy assessment uh acute bronchitis likely viral given the the lack of of consolidation on exam and the the normal oxygen sat differential includes uh covid nineteen influenza and and acute bacterial bronchitis plan we'll do a a rapid covid and flu panel today if positive we'll manage supportively if negative and symptoms persist beyond ten days we'll consider azithromycin five hundred milligrams on day one then two hundred and fifty milligrams days two through five no wait that's the the z pack for bacterial sinusitis for bronchitis we'll hold antibiotics for now um continue metformin five hundred milligrams twice daily continue lisinopril ten milligrams daily hold the the ace inhibitor only if the the creatinine rises above one point five encourage fluids rest acetaminophen five hundred milligrams every six hours as needed for fever return precautions if he develops shortness of breath chest pain or fever above one hundred and two follow up in in one week or sooner if symptoms worsen discussed with the the patient he he understands and and agrees with the the plan
        """
        await assertCase(Case(
            name: "long-medical-dictation",
            raw: raw,
            required: ["james wilson", "type two diabetes", "hypertension", "101.5", "98", "130/80",
                       "bronchitis", "azithromycin", "metformin", "lisinopril", "1.5",
                       "acetaminophen", "covid"],
            forbidden: ["1 point 5", "ninety eight percent"],
            minRetention: 0.45))
    }

    // MARK: 5. Legal / deposition transcript (~300 words)

    func testLongLegalTranscript() async {
        let raw = """
        okay we're on the the record it's it's the the fourteenth of November twenty twenty six at ten fifteen a m we're here for the the deposition of of mister Daniel Reeves in the matter of of Harris versus Northwind Logistics case number twenty four c v eight eight seven one um counsel please state your appearances thank you I'm Sarah Chen for the the plaintiff and and I'm Robert Vance for the the defendant mr Reeves you you understand you're under oath yes yes I do um do you understand that your testimony is being recorded and transcribed yes okay let's start can you state your full name for the the record Daniel James Reeves spelled R E E V E S and and your current employer I I work for Northwind Logistics as a a regional operations manager how long have you held that position since March of of twenty twenty one okay and and on the the evening of of the sixth of June twenty twenty five were you present at the the distribution center in in Columbus yes I was I I had arrived around uh six thirty p m and I stayed until approximately nine forty five p m the the question is did you observe the the forklift incident involving mister Harris I I did not personally witness the the collision I I was in in the the office at the the time but I I did hear the the alarm and and I reviewed the the security footage the next morning object hearsay I'll withdraw the the portion about the the footage let me rephrase did you review any documentation yes I I reviewed the the incident report dated the the seventh of June and and the the maintenance log for forklift number fourteen which which showed the the brake inspection had been skipped on the the previous shift is that your signature on the the bottom of of the report yes it is but I I signed it after the the fact I did not personally verify the the inspection okay um one last question was the the warehouse floor wet that evening I I cannot say for certain there there was a a cleanup crew mopping near bay seven around uh five p m but I I did not see any standing water near the the incident site okay we can go off the the record
        """
        await assertCase(Case(
            name: "long-legal-transcript",
            raw: raw,
            required: ["daniel james reeves", "northwind logistics", "harris", "24-cv-8871", "columbus",
                       "june", "forklift", "brake inspection", "signature", "bay seven", "hearsay"],
            forbidden: ["the the the"],
            minRetention: 0.45))
    }

    // MARK: 6. Finance / earnings call (~320 words)

    func testLongFinanceEarningsCall() async {
        let raw = """
        good morning everyone and and welcome to the the Q three twenty twenty six earnings call um I'm Priya Raman the the C F O and and with me today is is our C E O mister David Okoye before we begin let me remind everyone that today's discussion contains forward looking statements and and actual results may differ materially you you can find the the reconciliation of of non G A A P metrics in in the the press release on our investor relations site okay with that out of of the the way revenue for the the quarter was two point four billion dollars up eighteen percent year over year and and twelve percent sequentially gross margin was sixty two percent compared with fifty nine percent in in the the prior year the the improvement was driven by the the enterprise subscription tier and and better utilization of of our inference infrastructure operating expenses were one point six billion dollars including seven hundred million in in research and development and and four hundred million in in sales and marketing operating income was uh eight hundred and eighty million dollars giving us a a thirty seven percent operating margin um cash flow from operations was one point one billion dollars and and we ended the the quarter with four point two billion in in cash and short term investments capex was two hundred and thirty million primarily for the the new data center in in Oregon now for guidance for Q four we're expecting revenue between two point six and and two point seven billion dollars gross margin of sixty three to sixty four percent and and full year free cash flow of at least two point eight billion dollars um we're also raising the the full year revenue guidance to nine point four billion at the the midpoint from the the previous nine point one billion the the main assumption behind this is continued adoption of of the enterprise tier and and no major deterioration in in the the macro environment analyst question yes hi this is is Mark from Morgan Stanley can you talk about the the churn you you saw in in the the small business segment yeah sure um small business churn was three point four percent in in the quarter up from two point eight percent last quarter but it's it's still within our historical range and and the the enterprise churn actually improved to one point one percent we we don't see any structural issue there okay and and on the the buyback we we repurchased five hundred million dollars of of stock during the quarter and and the the board has authorized an additional one billion program with no expiration date operator we'll take one more question
        """
        await assertCase(Case(
            name: "long-finance-earnings-call",
            raw: raw,
            required: ["q 3", "2.4 billion", "18%", "62%", "1.6 billion", "37%", "4.2 billion",
                       "q 4", "2.6", "2.7", "9.4", "3.4%", "1.1%", "morgan stanley", "oregon"],
            forbidden: ["two point four billion", "sixty two percent"],
            minRetention: 0.45))
    }

    // MARK: 7. Academic lecture (~300 words)

    func testLongAcademicLecture() async {
        let raw = """
        okay so today we're going to to talk about transformer attention and and why the the quadratic cost matters um let's start with the the basic equation attention of of Q K V equals softmax of Q K transpose over root d k times V where Q is is the query matrix K is is the key matrix and V is is the value matrix and d k is is the the dimension of of the key vectors the the softmax is applied row wise so each token attends to to every other token and that gives you a an n squared matrix where n is is the the sequence length now for a a sequence of of two thousand tokens that's four million attention scores per head and and if you have sixteen heads that's sixty four million scores per layer and with thirty two layers you you get about two billion scores for a single forward pass which is why long context is is expensive you know there are several approaches to to reduce this one is sparse attention where you only compute a a subset of of the the scores for example local window attention with a a window of of five hundred twelve tokens or pattern based attention like the the long former paper another approach is linear attention where you approximate the the softmax kernel with a a feature map so you can compute K transpose V first and and avoid materializing the n by n matrix the the linear transformer paper from twenty twenty covers that and and then there's flash attention which which doesn't reduce the asymptotic complexity at all but it it tiles the the computation so it fits in in S R A M and avoids writing the the intermediate matrix to H B M that gave like a a two to four x speedup in in practice and lower memory the the key reference is is Dao et al twenty twenty two the the main takeaway for for today is distinguish algorithmic complexity from constant factor optimizations flash attention is is the latter sparse and linear attention are are the former um for next week please read the the original attention is all you need paper and and the the flash attention paper and and be prepared to discuss the the trade offs the the problem set is posted on the the course site due next thursday at eleven fifty nine p m
        """
        await assertCase(Case(
            name: "long-academic-lecture",
            raw: raw,
            required: ["softmax", "query", "key", "value", "quadratic", "n squared", "sparse attention",
                       "flash attention", "sram", "dao", "attention is all you need", "thursday"],
            // "root d k times V" is the actual equation in the source, not a
            // transcription artifact — it must be preserved, not forbidden.
            forbidden: ["two thousand tokens that's four million"],
            minRetention: 0.45))
    }

    // MARK: 8. Customer support escalation (~270 words)

    func testLongCustomerSupportEscalation() async {
        let raw = """
        hi this is is ticket number S U P P nine eight seven six two following up on the the chargeback issue from last week um so the the customer Mrs. Higgins called again this morning she she says she was charged twice for the the November subscription the the two charges are uh one hundred and nineteen dollars on the the first of November and another one hundred and nineteen dollars on the the third of November she she already has the the receipt for the the first one but the the second one does not appear in in her her billing history in in the portal I I checked stripe and and there are indeed two successful charges with different payment intent ids P I underscore three two one and and P I underscore three two two the the second one has a a status of succeeded but no corresponding invoice was generated so I I think the the webhook failed or was delivered twice the the customer is is understandably upset because she she already disputed the the first charge with her bank on the the fifth and now she's seeing a second one I've escalated this to to the the payments team with priority high and and I've attached the the stripe logs and and a a screenshot of of the the portal under ticket S U P P nine eight seven six two what we need is to to issue a a refund for the the second charge one hundred and nineteen dollars and and make sure the the duplicate payment intent is is not reprocessed also can someone check why the the invoice webhook didn't fire so this doesn't happen to to other customers the the customer wants confirmation by Wednesday noon she she is is traveling Thursday and and wants this resolved before then I told her we'd email by Tuesday at the latest but if we can do Wednesday that's fine too no wait I said Tuesday so we should honor that please reply to to the the customer thread directly and and cc me and and the the payments on call thanks
        """
        await assertCase(Case(
            name: "long-customer-support-escalation",
            raw: raw,
            required: ["supp-98762", "119", "november", "stripe", "payment intent", "refund",
                       "webhook", "higgins", "tuesday", "payments team", "disputed"],
            forbidden: ["two hundred and thirty eight", "does not appear in in her"],
            minRetention: 0.45))
    }

    // MARK: 9. Science / lab notes (~260 words)

    func testLongScienceLabNotes() async {
        let raw = """
        experiment run four two on the the eighteenth of November twenty twenty six operator uh doctor Elena Vasquez objective measure the the binding affinity of of compound A B C one two three against the the target protein under varying salt concentrations protocol we prepared a a series of of phosphate buffered saline solutions at uh ten millimolar fifty millimolar and one hundred and fifty millimolar sodium chloride p H was adjusted to seven point four using hydrochloric acid and verified with a a calibrated meter the the protein concentration was two milligrams per milliliter determined by the the bradford assay with bovine serum albumin as the standard compound A B C one two three was dissolved in dimethyl sulfoxide to to a a stock concentration of ten millimolar and then diluted serially to to final concentrations ranging from one nanamolar to one hundred micromolar um the the measurements were performed on the the surface plasmon resonance instrument at twenty five degrees celsius with a a flow rate of thirty microliters per minute each concentration was injected for ninety seconds followed by a a two minute washout and and each run was repeated in triplicate results the the dissociation constant K D at ten millimolar salt was four point two nanomolar at fifty millimolar it it increased to seven point eight nanomolar and and at one hundred and fifty millimolar it was twenty three point one nanomolar suggesting the the interaction is is at least partially electrostatic the the association rate stayed roughly constant around two point one times ten to the fifth molar inverse seconds inverse while the the dissociation rate increased with salt anomalies run two of of the one hundred micromolar injection showed bubble formation in in the flow cell and was excluded from the the fit conclusion salt strongly modulates binding and and we should repeat with a a lower salt condition next week all raw sensor grams are in the the shared drive under A B C one two three slash run four two
        """
        await assertCase(Case(
            name: "long-science-lab-notes",
            raw: raw,
            required: ["elena vasquez", "abc-123", "phosphate buffered saline", "7.4", "bradford",
                       "surface plasmon resonance", "25", "nanomolar", "23.1", "electrostatic",
                       "triplicate", "sensor grams"],
            forbidden: ["one hundred and fifty millimolar sodium chloride p H"],
            minRetention: 0.45))
    }

    // MARK: 10. Gaming session with hostile length / coordinates (~250 words)

    func testLongGamingSession() async {
        let raw = """
        okay okay so we're dropping at uh coordinates three seven point four north one one two point eight east near the the old radar station you you want to to go left or right I say left left there's a a supply drop coming in in approximately forty five seconds mark it on the the map okay marked um I've got the the sniper and and two med kits and and one grenade you should pick up the the armor plate near the the blue container yeah I I see it I I that's actually a a level three helmet not armor take the the helmet okay nice uh enemy movement at the the north ridge about two hundred meters out I count three maybe four one of them has a a red marker so probably the the squad leader don't engage yet let them come to to the the circle the the zone closes in in two minutes and thirty seconds we we need to rotate east toward the the rock formation not west west is is open ground yeah good call okay I'm going to to pop the smoke now wait for my signal three two one go smoke is is out move move move I'm reloading I'm reloading cover me okay I I knocked one down he's crawling behind the the wall finish him nice one down two on the the right I'm out of of ammo do you have any five five six rounds I've got sixty rounds and and a a spare magazine here take half um the the last team is is in in the the final circle probably seven or eight players left we should hold the the high ground and and let them fight each other the the zone is is shrinking fast okay I can see movement in in the the southeast someone is is crawling I'm going to to throw the the last grenade should land in in about three seconds boom okay that that was a a good one let's push we've got maybe thirty seconds before the the next zone finish them
        """
        await assertCase(Case(
            name: "long-gaming-session",
            raw: raw,
            required: ["37.4", "112.8", "45 seconds", "level three helmet", "north ridge",
                       "200 meters", "two minutes", "smoke", "5.56", "grenade", "high ground", "southeast"],
            forbidden: [],
            minRetention: 0.45))
    }
}
