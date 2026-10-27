import XCTest
import SuperflowKernel
@testable import SuperflowTextLineFormat

final class LineFormatTests: XCTestCase {
    private func format(_ s: String, _ tweak: (inout LineFormatSettings) -> Void = { _ in }) -> String {
        var settings = LineFormatSettings()
        tweak(&settings)
        return LineFormatter.format(s, settings: settings)
    }

    func testShortText() {
        XCTAssertEqual(format("hello world"), "Hello world")
    }

    func testFinalPeriod() {
        XCTAssertEqual(format("this is a longer sentence"), "This is a longer sentence.")
        XCTAssertEqual(format("hello there friend"), "Hello there friend")
    }

    func testCapitalizesSentenceAndI() {
        XCTAssertEqual(format("hello. i am here. goodbye"), "Hello. I am here. Goodbye.")
    }

    func testBreaksAtSentenceBoundary() {
        let s1 = "This is the first sentence and it has quite a lot of words in it to reach the threshold easily."
        let s2 = "This is the second sentence which should begin a new block."
        let out = format(s1 + " " + s2)
        XCTAssertTrue(out.contains("\n\n"), out)
        XCTAssertTrue(out.hasPrefix("This is the first"))
    }

    func testLongUnpunctuatedSentenceBreaks() {
        let words = (1...90).map { "word\($0)" }.joined(separator: " ")
        let out = format(words)
        let blocks = out.components(separatedBy: "\n\n")
        XCTAssertGreaterThan(blocks.count, 1)
        for block in blocks { XCTAssertLessThanOrEqual(wordCount(block), 45, block) }
    }

    func testDoesNotSplitAbbreviationsOrDottedTokens() {
        let input = "Dr. Smith uses Next.js and design.md every day at work."
        let out = format(input)
        XCTAssertEqual(out, input)
    }

    func testExistingNewlinesAreHardBoundaries() {
        let out = format("one line\n- list item one\n- list item two")
        XCTAssertEqual(out, "One line\n\n- list item one\n\n- list item two.")
    }

    func testIncrementalEqualsBatch() {
        let chunks = [
            "This is the first sentence and it has quite a lot of words in it to reach the threshold easily. ",
            "This is the second sentence which should begin a new block. ",
            "And a third sentence with no punctuation at the end",
        ]
        let batch = format(chunks.joined())
        var formatter = LineFormatter(settings: LineFormatSettings())
        var incremental: [String] = []
        for chunk in chunks { incremental.append(contentsOf: formatter.feed(chunk)) }
        incremental.append(contentsOf: formatter.finish())
        XCTAssertEqual(incremental.joined(separator: formatter.separator), batch)
    }

    func testIdempotent() {
        for input in ["hello world. this is a test", "one line\n- item", "a b c"] {
            let once = format(input)
            let twice = format(once)
            XCTAssertEqual(once, twice, "input: \(input)")
        }
    }

    func testPunctuationSpacing() {
        XCTAssertEqual(format("hello , world ."), "Hello, world.")
    }

    func testPunctuationSpacingPreservesURLsGroupedNumbersAndTimes() {
        XCTAssertEqual(format("please visit https://example.com/path?q=one,two today"),
                       "Please visit https://example.com/path?q=one,two today.")
        XCTAssertEqual(format("it costs 1,200 dollars"), "It costs 1,200 dollars.")
        XCTAssertEqual(format("meet at 10:30 tomorrow"), "Meet at 10:30 tomorrow.")
    }

    func testLongStreamingInputDoesNotLoseWords() {
        var settings = LineFormatSettings()
        settings.capitalize = false
        settings.finalPeriod = false
        let tokens = (1...1_000).map { "word\($0)" }
        var formatter = LineFormatter(settings: settings)
        var blocks: [String] = []
        for start in stride(from: 0, to: tokens.count, by: 37) {
            let end = min(tokens.count, start + 37)
            blocks.append(contentsOf: formatter.feed(tokens[start..<end].joined(separator: " ") + " "))
        }
        blocks.append(contentsOf: formatter.finish())
        XCTAssertEqual(blocks.joined(separator: formatter.separator).split(whereSeparator: \.isWhitespace).map(String.init),
                       tokens)
    }
}
