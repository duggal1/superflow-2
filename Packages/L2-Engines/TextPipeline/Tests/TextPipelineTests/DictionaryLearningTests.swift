import Foundation
import SuperflowKernel
import SuperflowPorts
import XCTest
@testable import SuperflowTextPipeline

private actor MemoryLearningStore: LearningRepository {
    var entries: [String: LearningCandidate] = [:]
    func learningCandidates() async throws -> [LearningCandidate] {
        Array(entries.values).sorted { $0.id < $1.id }
    }
    func saveLearningCandidate(_ candidate: LearningCandidate) async throws {
        entries[candidate.id] = candidate
    }
    func deleteLearningCandidate(id: String) async throws { entries.removeValue(forKey: id) }
}

private actor MemoryDictionaryStore: LibraryRepository {
    var entries: [String: LexiconEntry] = [:]
    func lexicon() async throws -> [LexiconEntry] { Array(entries.values) }
    func saveLexicon(_ entry: LexiconEntry) async throws { entries[entry.id] = entry }
    func deleteLexicon(id: String) async throws { entries.removeValue(forKey: id) }
    func shortcuts() async throws -> [ShortcutEntry] { [] }
    func saveShortcut(_ entry: ShortcutEntry) async throws {}
    func deleteShortcut(id: String) async throws {}
}

final class DictionaryLearningTests: XCTestCase {
    func testConsentRequiredBeforeSavingCorrection() async throws {
        let candidates = MemoryLearningStore()
        let lexicon = MemoryDictionaryStore()
        let engine = DictionaryLearningEngine(learning: candidates, lexicon: lexicon)
        let result = try await engine.observe(
            ObservedCorrection(heard: "nextjs", corrected: "Next.js"), consent: false)
        XCTAssertNil(result)
        let persisted = try await candidates.learningCandidates()
        XCTAssertTrue(persisted.isEmpty)
    }

    func testOneEditSuggestsSecondIndependentEditCanPromote() async throws {
        let candidates = MemoryLearningStore()
        let lexicon = MemoryDictionaryStore()
        let engine = DictionaryLearningEngine(learning: candidates, lexicon: lexicon)
        let first = try await engine.observe(
            ObservedCorrection(heard: "nextjs", corrected: "next.js",
                               appBundleID: "com.microsoft.VSCode", anchorID: "one"),
            consent: true, autoPromote: true)
        XCTAssertEqual(first?.state, .suggested)
        XCTAssertEqual(first?.observations, 1)
        let repeatedNotification = try await engine.observe(
            ObservedCorrection(heard: "nextjs", corrected: "next.js",
                               appBundleID: "com.microsoft.VSCode", anchorID: "one"),
            consent: true, autoPromote: true)
        XCTAssertNil(repeatedNotification)

        let second = try await engine.observe(
            ObservedCorrection(heard: "nextjs", corrected: "next.js",
                               appBundleID: "com.microsoft.VSCode", anchorID: "two"),
            consent: true, autoPromote: true)
        XCTAssertEqual(second?.state, .confirmed)
        XCTAssertEqual(second?.observations, 2)
        let learned = try await lexicon.lexicon()
        XCTAssertEqual(learned.count, 1)
        XCTAssertEqual(learned.first?.canonical, "next.js")
        XCTAssertEqual(learned.first?.appScope, "com.microsoft.VSCode")
        XCTAssertEqual(learned.first?.learnedFrom, "edit-correction")

        try await engine.undo(id: try XCTUnwrap(second?.id))
        let afterUndo = try await lexicon.lexicon()
        XCTAssertTrue(afterUndo.isEmpty)
        let after = try await engine.candidates()
        XCTAssertEqual(after.first?.state, .rejected)
    }

    func testSubstantialRewriteIsNotAutoPromoted() async throws {
        let candidates = MemoryLearningStore()
        let lexicon = MemoryDictionaryStore()
        let engine = DictionaryLearningEngine(learning: candidates, lexicon: lexicon)
        for id in ["one", "two"] {
            _ = try await engine.observe(
                ObservedCorrection(heard: "item potency", corrected: "idempotency", anchorID: id),
                consent: true, autoPromote: true)
        }
        let suggested = try await engine.candidates()
        XCTAssertEqual(suggested.first?.state, .suggested)
        XCTAssertTrue(try await lexicon.lexicon().isEmpty)
        try await engine.confirm(id: try XCTUnwrap(suggested.first?.id))
        let learned = try await lexicon.lexicon()
        XCTAssertEqual(learned.first?.canonical, "idempotency")
    }

    func testRejectsWholeSentenceEditsAndSecretLikeInput() async throws {
        let candidates = MemoryLearningStore()
        let lexicon = MemoryDictionaryStore()
        let engine = DictionaryLearningEngine(learning: candidates, lexicon: lexicon)
        for text in [
            "this is a whole sentence that changed",
            "https://example.org/token",
            "person@example.com",
            "secret\nline",
        ] {
            let result = try await engine.observe(
                ObservedCorrection(heard: text, corrected: "private"), consent: true)
            XCTAssertNil(result)
        }
        let stored = try await engine.candidates()
        XCTAssertTrue(stored.isEmpty)
    }

    func testRejectingCandidateCannotRewriteLaterSpeech() async throws {
        let candidates = MemoryLearningStore()
        let lexicon = MemoryDictionaryStore()
        let engine = DictionaryLearningEngine(learning: candidates, lexicon: lexicon)
        let proposed = try await engine.observe(
            ObservedCorrection(heard: "pearl", corrected: "Perl"), consent: true)
        let id = try XCTUnwrap(proposed?.id)
        try await engine.reject(id: id)
        let retry = try await engine.observe(
            ObservedCorrection(heard: "pearl", corrected: "Perl", anchorID: "new"), consent: true)
        XCTAssertNil(retry)
        let learned = try await lexicon.lexicon()
        XCTAssertTrue(learned.isEmpty)
    }
}
