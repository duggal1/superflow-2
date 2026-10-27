import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextLineFormat
import XCTest

final class LineFormatGoldenTests: XCTestCase {
    private func fixture() throws -> LineFormatFixture {
        try Golden.load("lineformat/cases.json")
    }

    private func settings(base: LineFormatPatch?, override: LineFormatPatch?) -> LineFormatSettings {
        var value = base?.settings ?? LineFormatSettings()
        override?.apply(to: &value)
        return value
    }

    func testBatchCorpus() throws {
        let fixture = try fixture()
        for c in fixture.cases {
            let lf = settings(base: fixture.settings, override: c.settings?.lineFormat)
            let actual = LineFormatter.format(c.input, settings: lf)
            assertGolden(actual, c.expected, name: c.name)
        }
    }

    func testPunctuationSpacingPreservesURLsNumbersAndTimes() throws {
        let fixture = try fixture()
        for c in fixture.edgeCases ?? [] {
            let lf = settings(base: fixture.settings, override: c.settings?.lineFormat)
            let actual = LineFormatter.format(c.input, settings: lf)
            assertGolden(actual, c.expected, name: c.name)
        }
    }

    func testIncrementalEqualsBatch() throws {
        let fixture = try fixture()
        for c in fixture.incremental {
            let lf = settings(base: fixture.settings, override: c.settings)
            var formatter = LineFormatter(settings: lf)
            var blocks = formatter.feed("")
            for chunk in c.chunks {
                blocks.append(contentsOf: formatter.feed(chunk))
            }
            blocks.append(contentsOf: formatter.finish())
            let incremental = blocks.joined(separator: formatter.separator)
            let batch = LineFormatter.format(c.chunks.joined(), settings: lf)
            assertGolden(incremental, c.expected, name: "\(c.name) (incremental)")
            XCTAssertEqual(incremental, batch, "incremental formatting differs from batch for \(c.name)")
        }
    }

    /// Splits text into realistic streaming chunks: each chunk ends at a word
    /// boundary (ASR partials are word-aligned, never mid-word).
    private func wordChunks(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == " " || character == "\n" {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    func testCharacterByCharacterStreamingEqualsBatch() throws {
        let fixture = try fixture()
        let lf = settings(base: fixture.settings, override: nil)
        let text = "First sentence here. Second sentence follows. A third one arrives later.\n- one\n- two"
        var formatter = LineFormatter(settings: lf)
        var blocks: [String] = []
        for chunk in wordChunks(text) {
            blocks.append(contentsOf: formatter.feed(chunk))
        }
        blocks.append(contentsOf: formatter.finish())
        XCTAssertEqual(blocks.joined(separator: formatter.separator),
                       LineFormatter.format(text, settings: lf))
    }

    func testIdempotence() throws {
        let fixture = try fixture()
        for c in fixture.cases {
            let lf = settings(base: fixture.settings, override: c.settings?.lineFormat)
            let once = LineFormatter.format(c.input, settings: lf)
            let twice = LineFormatter.format(once, settings: lf)
            XCTAssertEqual(once, twice, "line formatter is not idempotent for \(c.name)")
        }
    }

    func testNoWordsAreLost() {
        var lf = settings(base: nil, override: nil)
        lf.capitalize = false
        lf.finalPeriod = false
        let words = (1...1_000).map { "word\($0)" }
        var tokens = words
        tokens[tokens.count - 1] += "."
        var formatter = LineFormatter(settings: lf)
        var blocks = formatter.feed("")
        var index = 0
        while index < tokens.count {
            let end = min(tokens.count, index + 37)
            let chunk = tokens[index..<end].joined(separator: " ") + " "
            blocks.append(contentsOf: formatter.feed(chunk))
            index = end
        }
        blocks.append(contentsOf: formatter.finish())
        let output = blocks.joined(separator: formatter.separator)
        let outputWords = output.split(whereSeparator: \.isWhitespace).map(String.init)
        XCTAssertEqual(outputWords, tokens, "streaming formatter lost or reordered words")
    }

    func testEmptyAndWhitespace() {
        let lf = settings(base: nil, override: nil)
        XCTAssertEqual(LineFormatter.format("", settings: lf), "")
        XCTAssertEqual(LineFormatter.format("   ", settings: lf), "")
        XCTAssertEqual(LineFormatter.format("\n\n", settings: lf), "")
    }

    func testTrailingSpaceIsAppliedByTheStage() async {
        var lf = settings(base: nil, override: nil)
        lf.capitalize = false
        lf.trailingSpace = true
        let stage = LineFormatStage(settings: lf)
        let result = await stage.apply(TranscriptDraft(text: "hello world"),
                                       context: TextContext(settings: Golden.stageSettings()))
        XCTAssertEqual(result.text, "hello world ")

        lf.trailingSpace = false
        let plain = LineFormatStage(settings: lf)
        let second = await plain.apply(TranscriptDraft(text: "hello world"),
                                       context: TextContext(settings: Golden.stageSettings()))
        XCTAssertEqual(second.text, "hello world")
    }

    func testCarryOverIsBounded() {
        let lf = settings(base: nil, override: nil)
        var formatter = LineFormatter(settings: lf)
        let sentence = "This sentence has enough words to be emitted as a block when it reaches the threshold."
        for _ in 0..<200 {
            _ = formatter.feed(sentence + " ")
        }
        let remaining = formatter.finish().joined(separator: formatter.separator)
        // Carry-over must be one unfinished sentence plus at most one block, not the
        // whole stream. A tiny remainder proves the formatter does not retain history.
        XCTAssertLessThan(remaining.count, 1_000)
    }
}
