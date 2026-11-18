import XCTest
@testable import SuperflowLLMCore

/// HEX vocabulary-boost ideas ported to a deterministic post-recognition pass.
/// These tests prove recall gains with zero false insertions on no-term clips.
final class VocabularyBoosterTests: XCTestCase {
    private let terms: [VocabularyTerm] = [
        VocabularyTerm("OpenCode"),
        VocabularyTerm("Kubernetes"),
        VocabularyTerm("Scrawl"),
        VocabularyTerm("Abattoir", aliases: ["a bat war"]),
    ]

    func testSplitTermIsJoined() {
        let booster = VocabularyBooster(terms: terms, level: .normal)
        XCTAssertEqual(booster.apply("open code should keep this sentence concise"),
                       "OpenCode should keep this sentence concise")
    }

    func testSoundsLikeMishearingIsCorrected() {
        let booster = VocabularyBooster(terms: terms, level: .normal)
        XCTAssertEqual(booster.apply("please scroll the notes"), "please Scrawl the notes")
    }

    func testOwnerSuppliedSoundsLikeAliasIsUsed() {
        let booster = VocabularyBooster(terms: terms, level: .normal)
        XCTAssertEqual(booster.apply("we visited a bat war yesterday"),
                       "we visited Abattoir yesterday")
    }

    func testNoTermClipIsUnchanged() {
        let booster = VocabularyBooster(terms: terms, level: .strong)
        let ordinary = "please send the report to the team tomorrow morning"
        XCTAssertEqual(booster.apply(ordinary), ordinary)
    }

    func testCommonWordIsNotReplacedEvenAtStrongBoost() {
        let booster = VocabularyBooster(terms: terms, level: .strong)
        XCTAssertEqual(booster.apply("about the report"), "about the report")
    }

    func testPathsAndInflectionsAreSkipped() {
        let booster = VocabularyBooster(terms: terms, level: .normal)
        let path = "open ~/code/opencode/main.swift please"
        XCTAssertEqual(booster.apply(path), path)
        XCTAssertEqual(booster.apply("opencodes are useful"), "opencodes are useful")
    }

    func testOffAndEmptyListAreNoOps() {
        XCTAssertEqual(VocabularyBooster(terms: terms, level: .off).apply("open code"),
                       "open code")
        XCTAssertEqual(VocabularyBooster(terms: [], level: .strong).apply("open code"),
                       "open code")
    }

    func testLongestSpanWins() {
        let booster = VocabularyBooster(terms: terms, level: .normal)
        XCTAssertEqual(booster.apply("the open code review"), "the OpenCode review")
    }
}
