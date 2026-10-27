import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextGrammarGate
import SuperflowTextLineFormat
import SuperflowMeetingEngine
import SuperflowTextNumbers
import SuperflowTextCleanup
import SuperflowTestKit
import SuperflowTextPipeline
import XCTest

/// Temporary calibration helper. Run with `SUPERFLOW_GOLDEN_DUMP=1 swift test --filter CalibrationDump`
/// to print the current behaviour for candidate corpus entries before freezing goldens.
final class CalibrationDump: XCTestCase {
    private func dump(_ title: String, _ input: String, _ output: String) {
        let escapedInput = input.replacingOccurrences(of: "\n", with: "\\n")
        let escaped = output.replacingOccurrences(of: "\n", with: "\\n")
        print("DUMP|\(title)|\(escapedInput)|=>|\(escaped)")
    }

    func testDumpNumbers() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_GOLDEN_DUMP"] == "1" else {
            throw XCTSkip("calibration only")
        }
        var settings = AppSettings.default
        settings.commandsEnabled = false
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        settings.lineFormat.capitalize = false
        settings.lineFormat.finalPeriod = false
        let pipeline = TextPipelineBuilder.make(settings: settings)

        let inputs = [
            "two hundred dollars",
            "fifty percent",
            "twenty twenty four",
            "january fifth",
            "the third of march",
            "three point five",
            "one thousand two hundred",
            "two million five hundred thousand",
            "two hundred thousand",
            "five million",
            "a hundred dollars",
            "twenty five degrees",
            "the nineteen eighties",
            "chapter twelve",
            "room four oh one",
            "call me at five five five one two three four",
            "my number is 1234567890",
            "zip 94107",
            "it costs 1000000 dollars",
            "twenty-first century",
            "ten thirty",
            "seven thirty pm",
            "nine am",
            "one and a half million",
            "two point five million",
            "three quarters",
            "two thirds",
            "ninety nine bottles",
            "one hundred and five",
            "fifteen minutes",
            "twelve thousand three hundred and forty five",
            "ten dollars and fifty cents",
            "february twenty second twenty twenty six",
            "the twenty first of june",
            "five dollars",
            "one dollar",
            "zero",
            "seven",
            "ten",
            "eleven",
            "one hundred",
            "one thousand",
            "one million",
            "one billion",
            "two trillion",
            "minus five",
            "negative three",
            "plus two",
            "forty two percent",
            "twelve point five percent",
            "one hundred percent",
            "version two point zero",
            "error 404",
            "the 2nd",
            "twelve o'clock",
            "one oh five",
            "nineteen ninety nine",
            "two thousand and one",
            "twenty ten",
            "twenty oh five",
            "five hundred thousand dollars",
            "three hundred and twenty five thousand",
            "one point two three",
            "zero point five",
            "point five",
            "ten thousand",
            "one hundred thousand",
            "nine hundred ninety nine",
            "one thousand one",
            "twenty one",
            "thirty",
            "forty five",
            "one hundred and twenty three",
            "two hundred and fifty thousand",
            "one million two hundred thousand",
            "five foot ten",
            "six feet two",
            "one hundred and eighty pounds",
            "seventy two degrees fahrenheit",
            "twelve inches",
            "three gigabytes",
            "two hundred milliseconds",
            "fifty basis points",
            "fourteen days",
            "twenty four hours",
            "three weeks",
            "two years",
            "one decade",
            "half an hour",
            "a couple of days",
            "two or three",
            "one to five",
            "five to ten",
            "between twenty and thirty",
            "over one hundred",
            "under fifty",
            "about a thousand",
            "roughly two million",
            "up to ten thousand",
        ]
        for input in inputs {
            let result = await pipeline.run(input, context: TextContext(settings: settings))
            dump("numbers", input, result.text)
        }
    }

    func testDumpLineFormat() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_GOLDEN_DUMP"] == "1" else {
            throw XCTSkip("calibration only")
        }
        let long = (1...40).map { "word\($0)" }.joined(separator: " ") + "."
        var defaults = LineFormatSettings()
        defaults.capitalize = false
        defaults.finalPeriod = false
        var cases: [(String, LineFormatSettings, String)] = [
            ("short", defaults, "hello there"),
            ("one sentence", defaults, "the quick brown fox jumps over the lazy dog."),
            ("two sentences", defaults, "First sentence here. Second sentence follows."),
            ("hard newline", defaults, "first line\nsecond line"),
            ("blank line", defaults, "first paragraph\n\nsecond paragraph"),
            ("long sentence", defaults, long),
            ("clause split", defaults,
             "This is a very long sentence that keeps going and going with many words in it, and it has a comma in the middle somewhere so that the formatter can split at a clause boundary when it needs to do so for readability."),
            ("abbreviation", defaults, "Dr. Smith went to Washington. He arrived at 5 p.m. and left."),
            ("decimal", defaults, "The value is 3.14 today. Next we test 2.71 tomorrow."),
            ("url", defaults, "Visit https://example.com/page. Then come back."),
            ("ellipsis", defaults, "Wait... what happened? Nobody knows."),
            ("existing list", defaults, "- one\n- two\n- three"),
            ("trailing spaces", defaults, "hello   world  "),
            ("punctuation spacing", defaults, "hello , world . next"),
            ("paragraph style", defaults, "First sentence here. Second sentence follows. Third sentence ends."),
        ]
        var single = defaults
        single.breakStyle = .newline
        cases.append(("single newline style", single, "First sentence here. Second sentence follows. Third sentence ends."))
        var caps = defaults
        caps.capitalize = true
        cases.append(("capitalize", caps, "hello world. next sentence."))
        var period = defaults
        period.finalPeriod = true
        cases.append(("final period", period, "hello world this is a test"))
        var trailing = defaults
        trailing.trailingSpace = true
        cases.append(("trailing space", trailing, "hello world"))
        var tight = defaults
        tight.minWords = 5
        tight.preferredMax = 8
        tight.hardMax = 10
        cases.append(("tight", tight, long))

        for (name, settings, input) in cases {
            dump("lineformat-\(name)", input, LineFormatter.format(input, settings: settings))
        }

        // Incremental == batch across chunk boundaries.
        let chunks = ["The quick brown fox ", "jumps over the lazy dog. ", "Then it runs away. ",
                      "A second paragraph starts here. ", "And it ends."]
        var formatter = LineFormatter(settings: defaults)
        var blocks = formatter.feed("")
        for chunk in chunks { blocks.append(contentsOf: formatter.feed(chunk)) }
        blocks.append(contentsOf: formatter.finish())
        dump("lineformat-incremental", chunks.joined(), blocks.joined(separator: formatter.separator))
        dump("lineformat-batch", chunks.joined(), LineFormatter.format(chunks.joined(), settings: defaults))
    }

    func testDumpLexiconAndShortcuts() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_GOLDEN_DUMP"] == "1" else {
            throw XCTSkip("calibration only")
        }
        var settings = AppSettings.default
        settings.commandsEnabled = false
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        settings.lineFormat.capitalize = false
        settings.lineFormat.finalPeriod = false
        let lexicon = [
            LexiconEntry(kind: .correction, triggers: ["super flow", "superflow"], canonical: "Superflow"),
            LexiconEntry(kind: .term, triggers: ["cube control", "kube control"], canonical: "kubectl"),
            LexiconEntry(kind: .term, triggers: ["next js", "next.js"], canonical: "Next.js"),
            LexiconEntry(kind: .correction, triggers: ["jason"], canonical: "JSON"),
        ]
        let shortcuts = [
            ShortcutEntry(trigger: "sign off", content: "# Notes\n\n- one\n- two"),
            ShortcutEntry(trigger: "my email", content: "dev@example.com"),
            ShortcutEntry(trigger: "standup", content: "Daily standup notes", match: .inline),
        ]
        let pipeline = TextPipelineBuilder.make(
            settings: settings,
            dependencies: TextPipelineDependencies(lexiconEntries: lexicon, shortcuts: shortcuts))

        let inputs = [
            "super flow",
            "I use super flow every day",
            "Super Flow is great",
            "superflow",
            "kube control apply",
            "cube control get pods",
            "next js app",
            "next.js app",
            "jason file",
            "json file",
            "JASON",
            "super flow and jason",
            "sign off",
            "Sign off.",
            "sign  off",
            "please sign off now",
            "my email",
            "email my email to me",
            "standup",
            "for the standup tomorrow",
            "superflow.com",
            "https://superflow.com",
            "dev@superflow.com",
            "kubectl",
            "super flowed",
            "the super flow",
        ]
        for input in inputs {
            let result = await pipeline.run(input, context: TextContext(settings: settings))
            dump("lexicon-shortcuts", input, result.text)
        }
    }

    func testDumpGrammarGate() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_GOLDEN_DUMP"] == "1" else {
            throw XCTSkip("calibration only")
        }
        let text = "I recieve teh message and it are fine. I have have seen it."
        let ns = text as NSString
        func range(_ find: String) -> NSRange { ns.range(of: find) }
        let lints = [
            GrammarLint(utf16Start: range("recieve").location, utf16Length: range("recieve").length,
                        kind: "spelling", suggestion: "receive"),
            GrammarLint(utf16Start: range("teh").location, utf16Length: range("teh").length,
                        kind: "spelling", suggestion: "the"),
            GrammarLint(utf16Start: range("are").location, utf16Length: range("are").length,
                        kind: "agreement", suggestion: "is"),
            GrammarLint(utf16Start: range("have have").location, utf16Length: range("have have").length,
                        kind: "repeatedWords", suggestion: "have"),
        ]
        let policy = GrammarGatePolicy(maxEditRatio: 0.5)
        let edits = GrammarGateStage.acceptedEdits(lints, in: text, policy: policy, protected: Protected())
        dump("grammar", text, GrammarGateStage.apply(edits, to: text))
        for edit in edits { print("EDIT|\(edit.range)|\(edit.replacement)") }
        let protectedText = "I recieve the superflow message."
        let pns = protectedText as NSString
        let plints = [GrammarLint(utf16Start: pns.range(of: "recieve").location,
                                  utf16Length: pns.range(of: "recieve").length,
                                  kind: "spelling", suggestion: "receive")]
        let pedits = GrammarGateStage.acceptedEdits(plints, in: protectedText, policy: policy,
                                                    protected: Protected(literals: ["superflow"]))
        dump("grammar-protected", protectedText, GrammarGateStage.apply(pedits, to: protectedText))
    }
}

extension CalibrationDump {
    func testDumpStagesDirect() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_GOLDEN_DUMP"] == "1" else {
            throw XCTSkip("calibration only")
        }
        var settings = AppSettings.default
        settings.commandsEnabled = false
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        let inputs = ["one thousand two hundred", "my number is 1234567890", "it costs 1000000 dollars",
                      "twenty-first century", "one hundred and eighty pounds", "two trillion",
                      "the nineteen eighties", "five to ten", "ten thirty", "seven thirty pm",
                      "https://example.com/page.", "10:30", "1,200", "version 1.2.3"]
        for input in inputs {
            let numbers = NumbersStage.transform(input, protected: Protected(), settings: settings)
            dump("numbers-direct", input, numbers)
        }
        var lf = LineFormatSettings()
        lf.capitalize = false
        lf.finalPeriod = false
        var noPunct = lf
        noPunct.fixPunctuationSpacing = false
        for input in ["https://example.com/page.", "1,200", "10:30"] {
            dump("lf-punct", input, LineFormatter.format(input, settings: lf))
            dump("lf-nopunct", input, LineFormatter.format(input, settings: noPunct))
        }
        var full = settings
        full.numberStyle = .full
        dump("numbers-full", "two hundred thousand", NumbersStage.transform("two hundred thousand", protected: Protected(), settings: full))
        dump("numbers-full", "one thousand", NumbersStage.transform("one thousand", protected: Protected(), settings: full))
    }
}

extension CalibrationDump {
    func testDumpMoreNumbers() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_GOLDEN_DUMP"] == "1" else {
            throw XCTSkip("calibration only")
        }
        var settings = AppSettings.default
        let inputs = ["one thousand two hundred fifty dollars", "two million dollars",
                      "two million five hundred thousand dollars", "one hundred and five dollars",
                      "two hundred and fifty thousand dollars", "fifty cents", "twenty five cents",
                      "a hundred percent", "twenty twenty six", "january twenty second",
                      "the first of january", "one half", "two and a half", "three point one four",
                      "one thousand two hundred and fifty", "ten thousand and five",
                      "twenty five thousand", "one hundred and one", "one hundred one",
                      "a thousand", "a million", "one hundred million", "two billion five hundred million",
                      "nine ninety nine", "five five five", "one two three four five six"]
        for input in inputs {
            dump("numbers-more", input, NumbersStage.transform(input, protected: Protected(), settings: settings))
        }
        let protected = Protected(literals: ["twenty five"])
        dump("numbers-protected", "twenty five apples", NumbersStage.transform("twenty five apples", protected: protected, settings: settings))
        var noSpell = settings
        noSpell.spellOutSmallNumbers = false
        dump("numbers-nospell", "seven apples", NumbersStage.transform("seven apples", protected: Protected(), settings: noSpell))
    }
}

extension CalibrationDump {
    func testDumpLineFormatEdges() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_GOLDEN_DUMP"] == "1" else {
            throw XCTSkip("calibration only")
        }
        var lf = LineFormatSettings()
        lf.capitalize = false
        lf.finalPeriod = false
        let words = (1...60).map { "word\($0)" }
        var longWithComma = words
        longWithComma[39] += ","
        let long = longWithComma.joined(separator: " ") + "."
        dump("lf-edge-long", long, LineFormatter.format(long, settings: lf))
        var period = lf
        period.finalPeriod = true
        for input in ["one two three", "one two three four", "hello world this is a test"] {
            dump("lf-edge-period", input, LineFormatter.format(input, settings: period))
        }
        var single = lf
        single.breakStyle = .newline
        dump("lf-edge-list-single", "- one\n- two\n- three", LineFormatter.format("- one\n- two\n- three", settings: single))
        dump("lf-edge-list-paragraph", "- one\n- two\n- three", LineFormatter.format("- one\n- two\n- three", settings: lf))
        var tight = lf
        tight.minWords = 25
        tight.preferredMax = 35
        tight.hardMax = 45
        let sixty = (1...60).map { "word\($0)" }.joined(separator: " ") + "."
        dump("lf-edge-sixty", sixty, LineFormatter.format(sixty, settings: tight))
        let chunks = ["alpha beta gamma ", "delta epsilon. ", "zeta eta theta iota. ",
                      "kappa lambda mu. ", "nu xi omicron pi rho sigma tau."]
        var formatter = LineFormatter(settings: lf)
        var blocks = formatter.feed("")
        for chunk in chunks { blocks.append(contentsOf: formatter.feed(chunk)) }
        blocks.append(contentsOf: formatter.finish())
        dump("lf-edge-inc", chunks.joined(), blocks.joined(separator: formatter.separator))
        dump("lf-edge-batch", chunks.joined(), LineFormatter.format(chunks.joined(), settings: lf))
        var idem = lf
        idem.capitalize = true
        idem.finalPeriod = true
        let once = LineFormatter.format("hello   world , next sentence . and more words here", settings: idem)
        dump("lf-edge-idem-once", once, LineFormatter.format(once, settings: idem))
        dump("lf-edge-idem-twice", once, LineFormatter.format(LineFormatter.format(once, settings: idem), settings: idem))
    }
}

extension CalibrationDump {
    func testDumpMeetingAndCleanup() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_GOLDEN_DUMP"] == "1" else {
            throw XCTSkip("calibration only")
        }
        let iso = ISO8601DateFormatter()
        let doc = MeetingDocument(
            sessionID: SessionID("11111111-2222-3333-4444-555555555555"),
            title: "Weekly design review",
            startedAt: iso.date(from: "2026-03-04T09:30:00Z")!,
            endedAt: iso.date(from: "2026-03-04T10:15:00Z")!,
            durationMs: 2_700_000,
            speakers: [MeetingSpeaker(id: "self", name: "You", isSelf: true),
                       MeetingSpeaker(id: "s2", name: "Priya", isSelf: false)],
            turns: [
                MeetingTurn(index: 0, speakerID: "self", speakerName: "You", startMs: 0, endMs: 4_000,
                            text: "Let us review the open questions.", rawText: "let us review the open questions",
                            source: .mic),
                MeetingTurn(index: 1, speakerID: "s2", speakerName: "Priya", startMs: 65_000, endMs: 70_000,
                            text: "The island should not steal focus.", rawText: "the island should not steal focus",
                            source: .system),
                MeetingTurn(index: 2, speakerID: "self", speakerName: "You", startMs: 125_000, endMs: 126_000,
                            text: "System audio was lost for 5 s.", rawText: "System audio was lost for 5 s.",
                            source: .system, isGap: true),
            ]
        )
        print("MEETMD-BEGIN")
        print(MeetingExport.markdown(doc))
        print("MEETMD-END")
        let data = try MeetingExport.jsonData(doc)
        print("MEETJSON-BEGIN")
        print(String(decoding: data, as: UTF8.self))
        print("MEETJSON-END")

        var settings = AppSettings.default
        settings.cleanupEnabled = true
        let cases: [(String, FakeTextCleaner.Behavior, String)] = [
            ("identity", .identity, "the quick brown fox jumps over the lazy dog"),
            ("upper", .upper, "the quick brown fox"),
            ("fail", .fail, "the quick brown fox jumps over the lazy dog"),
            ("truncate", .truncate, "one two three four five six seven eight nine ten"),
            ("dropLast", .dropLast, "one two three four five six seven eight nine ten"),
            ("echoPrefix", .echoPrefix("Sure thing "), "the quick brown fox jumps over the lazy dog"),
            ("slow", .slow(ms: 2000), "the quick brown fox jumps over the lazy dog"),
        ]
        for (name, behavior, input) in cases {
            let service = CleanupService(cleaner: FakeTextCleaner(behavior),
                                         config: CleanupConfig(interactiveDeadlineMs: 50))
            let outcome = await service.clean(input, context: TextContext(settings: settings))
            dump("cleanup-\(name)", input, "state=\(outcome.state.rawValue)|chunks=\(outcome.chunks.count)|text=\(outcome.text)")
        }
        let notReady = CleanupService(cleaner: NotReadyCleaner())
        let nr = await notReady.clean("hello world", context: TextContext(settings: settings))
        dump("cleanup-notReady", "hello world", "state=\(nr.state.rawValue)|text=\(nr.text)")
        var disabled = settings
        disabled.cleanupEnabled = false
        let off = await CleanupService(cleaner: FakeTextCleaner(.identity)).clean("hello world", context: TextContext(settings: disabled))
        dump("cleanup-disabled", "hello world", "state=\(off.state.rawValue)|text=\(off.text)")
        let empty = await CleanupService(cleaner: FakeTextCleaner(.identity)).clean("  ", context: TextContext(settings: settings))
        dump("cleanup-empty", "  ", "state=\(empty.state.rawValue)|text=\(empty.text)")
    }
}

extension CalibrationDump {
    func testDumpPipeline() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_GOLDEN_DUMP"] == "1" else {
            throw XCTSkip("calibration only")
        }
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        let lexicon = [LexiconEntry(kind: .correction, triggers: ["super flow"], canonical: "Superflow")]
        let shortcuts = [ShortcutEntry(trigger: "sign off", content: "# Notes\n\n- one\n- two")]
        let pipeline = Golden.makePipeline(settings: settings, lexicon: lexicon, shortcuts: shortcuts)
        print("STAGES|\(pipeline.stageIDs)")
        for input in ["hello world", "hello world this is a test", "two hundred dollars",
                      "super flow", "sign off", "hello, new line world",
                      "hello. new paragraph world", "the quick brown fox jumps over the lazy dog",
                      "I recieve teh report and it are fine", "  ", ""] {
            let result = await pipeline.run(input, context: TextContext(settings: settings))
            dump("pipeline", input, result.text)
            print("PIPE-DIAG|\(input)|\(result.shortCircuitedBy ?? "none")|\(result.draft.diagnostics.map(\.message))")
        }
        var cleanupSettings = settings
        cleanupSettings.cleanupEnabled = true
        let cleaner = CleanupService(cleaner: FakeTextCleaner(.upper))
        let withCleanup = Golden.makePipeline(settings: cleanupSettings, cleaner: cleaner)
        let cleaned = await withCleanup.run("the quick brown fox jumps over the lazy dog",
                                            context: TextContext(settings: cleanupSettings))
        dump("pipeline-cleanup", "the quick brown fox jumps over the lazy dog", cleaned.text)
    }
}
