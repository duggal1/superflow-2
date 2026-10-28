import XCTest
@testable import SuperflowKernel

final class WordTimingProjectionTests: XCTestCase {
    func testOnlyMeasuredGapsSetPause() {
        let timings = [WordTiming(word: "first", startMs: 0, endMs: 100),
                       WordTiming(word: "second", startMs: 800, endMs: 900),
                       WordTiming(word: "third", startMs: 950, endMs: 1_100)]
        let words = WordTimingProjection.apply(to: Tokenizer.words("First second third"), timings: timings)
        XCTAssertEqual(words.map(\.pause), [true, false, false])
    }

    func testRepeatedPairsAreAmbiguousAndHaveNoInventedPause() {
        let timings = [WordTiming(word: "hello", startMs: 0, endMs: 100),
                       WordTiming(word: "there", startMs: 900, endMs: 1_000),
                       WordTiming(word: "hello", startMs: 1_100, endMs: 1_200),
                       WordTiming(word: "there", startMs: 1_250, endMs: 1_300)]
        let words = WordTimingProjection.apply(to: Tokenizer.words("hello there"), timings: timings)
        XCTAssertFalse(words.contains(where: \.pause))
    }

    func testMultiwordTimingOnlyMarksItsKnownTrailingBoundary() {
        let timings = [WordTiming(word: "TanStack Query", startMs: 0, endMs: 300),
                       WordTiming(word: "works", startMs: 1_000, endMs: 1_100)]
        let words = WordTimingProjection.apply(to: Tokenizer.words("TanStack Query works"), timings: timings)
        XCTAssertEqual(words.map(\.pause), [false, true, false])
    }

    func testCollapsedRepeatCanUseUniqueSurvivingBoundary() {
        let timings = [WordTiming(word: "I", startMs: 0, endMs: 100),
                       WordTiming(word: "I", startMs: 110, endMs: 200),
                       WordTiming(word: "think", startMs: 1_000, endMs: 1_100)]
        let words = WordTimingProjection.apply(to: Tokenizer.words("I think"), timings: timings)
        XCTAssertEqual(words.map(\.pause), [true, false])
    }

    func testMissingInvalidOrTransformedWordsDoNotInventGaps() {
        let words = Tokenizer.words("hero.tsx works")
        XCTAssertEqual(WordTimingProjection.apply(to: words, timings: []), words)
        XCTAssertEqual(WordTimingProjection.apply(to: words, timings: [
            WordTiming(word: "hero dot t s x", startMs: 0, endMs: 100),
            WordTiming(word: "works", startMs: 1_000, endMs: 1_100)
        ]), words)
        XCTAssertEqual(WordTimingProjection.apply(to: words, timings: [
            WordTiming(word: "hero.tsx", startMs: 500, endMs: 100),
            WordTiming(word: "works", startMs: 1_000, endMs: 1_100)
        ]), words)
    }
}
