import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextCodeSpeak

final class CodeSpeakTests: XCTestCase {
    private let stage = CodeSpeakStage()

    private func run(_ input: String, protected: Protected = Protected()) async -> String {
        await stage.apply(TranscriptDraft(text: input, protected: protected),
                          context: TextContext()).text
    }

    func testIdentifiers() async {
        let cases: [(String, String)] = [
            ("camel case user profile id", "userProfileId"),
            ("snake case user profile id", "user_profile_id"),
            ("kebab case user profile id", "user-profile-id"),
            ("pascal case user profile id", "UserProfileId"),
            ("constant case user profile id", "USER_PROFILE_ID"),
            ("camel case user id.", "userId."),
            ("snake case http server", "http_server"),
            ("call it camel case get user by id", "call it getUserById"),
            ("snake case id", "id"),
            ("pascal case v two api", "VTwoApi"),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testPathsAndFiles() async {
        let cases: [(String, String)] = [
            ("src slash components slash button dot swift", "src/components/button.swift"),
            ("read the file config dot json", "read the file config.json"),
            ("deploy dot env", "deploy.env"),
            ("open src slash main dot swift.", "open src/main.swift."),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testFlags() async {
        let cases: [(String, String)] = [
            ("run it with dash dash verbose", "run it with --verbose"),
            ("double dash dry", "--dry"),
            ("use dash v", "use -v"),
            ("single dash q now", "-q now"),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testSymbols() async {
        let cases: [(String, String)] = [
            ("open paren foo close paren", "(foo)"),
            ("open paren close paren", "()"),
            ("open paren open paren x close paren close paren", "((x))"),
            ("open paren user id close paren", "(user id)"),
            ("call open bracket x close bracket", "call [x]"),
            ("open brace a close brace", "{a}"),
            ("open angle bracket t close angle bracket", "<t>"),
            ("triple equals", "==="),
            ("double colon", "::"),
            ("fat arrow", "=>"),
        ]
        for (input, expected) in cases {
            let actual = await run(input)
            XCTAssertEqual(actual, expected, "input: \(input)")
        }
    }

    func testBackticksAndCodeBlocks() async {
        let backtick = await run("run backtick npm install backtick now")
        XCTAssertEqual(backtick, "run `npm install` now")
        let block = "code block\nlet x = 1\nend code block"
        let fenced = await run(block)
        XCTAssertEqual(fenced, "```\nlet x = 1\n```")
        let output = CodeSpeakRewriter.rewrite(block, protected: Protected())
        XCTAssertTrue(output.protected.contains("```\nlet x = 1\n```"))
    }

    func testArrowOnlyInCodeContext() async {
        let path = await run("src slash main dot ts arrow app")
        XCTAssertEqual(path, "src/main.ts -> app")
        let camel = await run("userProfile arrow handler")
        XCTAssertEqual(camel, "userProfile -> handler")
        let prose = await run("the arrow points north")
        XCTAssertEqual(prose, "the arrow points north")
    }

    func testOrdinaryEnglishIsLeftAlone() async {
        let corpus = [
            "the camel case study was interesting",
            "snake case for this",
            "this is the camel case of things",
            "a dash and a dot",
            "a dot b",
            "the arrow points north",
            "open parenthesis in the document",
            "close parenthesis at the end",
            "please open the brace and close the brace",
            "let's talk about the kebab case later",
            "we should double check the colon",
            "the backtick is a punctuation mark",
        ]
        for input in corpus {
            let actual = await run(input)
            XCTAssertEqual(actual, input, "input: \(input)")
        }
    }

    func testProtectedSpansAreNotTouched() async {
        let protected = Protected(literals: ["snake case user id"])
        let literal = await run("remember snake case user id", protected: protected)
        XCTAssertEqual(literal, "remember snake case user id")
        let backtick = await run("keep `camel case user id` verbatim")
        XCTAssertEqual(backtick, "keep `camel case user id` verbatim")
    }

    func testCommandIsBoundedToOneClause() async {
        let tooLong = "camel case " + (1...12).map { "word\($0)" }.joined(separator: " ")
        let bounded = await run(tooLong)
        XCTAssertEqual(bounded, tooLong)
        let twoClauses = await run("snake case user id, then camel case post id")
        XCTAssertEqual(twoClauses, "user_id, then postId")
    }

    func testEmptyAndWhitespace() async {
        let empty = await run("")
        XCTAssertEqual(empty, "")
        let whitespace = await run("   \n\t\n")
        XCTAssertEqual(whitespace, "   \n\t\n")
    }

    func testIdempotent() async {
        let inputs = [
            "camel case user profile id",
            "src slash components slash button dot swift",
            "run it with dash dash verbose",
            "open paren foo close paren",
            "run backtick npm install backtick now",
            "snake case user id, then camel case post id",
            "code block\nlet x = 1\nend code block",
            "the camel case study was interesting",
        ]
        for input in inputs {
            let once = await run(input)
            let twice = await run(once)
            XCTAssertEqual(once, twice, "input: \(input)")
        }
    }

    func testExplainNamesEveryRule() async {
        let before = TranscriptDraft(text: "camel case user id, and src slash main dot swift")
        let after = await stage.apply(before, context: TextContext())
        let edits = await stage.explainEdits(before: before, after: after, context: TextContext())
        XCTAssertEqual(edits?.map(\.ruleID), ["identifier.camel", "path"])
        XCTAssertEqual(edits?.first.map(\.kind), .replace)
        let text = after.text as NSString
        XCTAssertEqual(text.substring(with: edits![0].output.nsRange), "userId")
        XCTAssertEqual(text.substring(with: edits![1].output.nsRange), "src/main.swift")
    }

    func testExplainSpansRoundTrip() async {
        let before = TranscriptDraft(text: "snake case user id, and open paren x close paren")
        let after = await stage.apply(before, context: TextContext())
        guard let edits = await stage.explainEdits(before: before, after: after,
                                                   context: TextContext()) else {
            return XCTFail("no explanation")
        }
        let input = before.text as NSString
        let output = after.text as NSString
        XCTAssertEqual(input.substring(with: edits[0].input.nsRange), "snake case user id")
        XCTAssertEqual(output.substring(with: edits[0].output.nsRange), "user_id")
        XCTAssertEqual(output.substring(with: edits[1].output.nsRange), "(")
    }
}
