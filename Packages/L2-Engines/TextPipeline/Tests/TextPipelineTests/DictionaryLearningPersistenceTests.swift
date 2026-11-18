import Foundation
import SuperflowKernel
import SuperflowPorts
import XCTest
@testable import SuperflowTextPipeline

/// A store whose contents survive constructing a second engine over the same
/// instances, so "reload after restart" is exercised at the engine boundary.
/// The DB itself is covered with a real ephemeral SQLite database in the
/// StorageSQLite suite; this suite covers orchestration and state transitions.
private actor PersistentKnowledgeStores {
    var candidateValues: [String: LearningCandidate] = [:]
    var lexiconValues: [String: LexiconEntry] = [:]

    func orderedCandidates() -> [LearningCandidate] {
        candidateValues.values.sorted { ($0.updatedAt, $0.id) < ($1.updatedAt, $1.id) }
    }
}

extension PersistentKnowledgeStores: LearningRepository {
    func learningCandidates() async throws -> [LearningCandidate] { orderedCandidates() }
    func saveLearningCandidate(_ candidate: LearningCandidate) async throws {
        candidateValues[candidate.id] = candidate
    }
    func deleteLearningCandidate(id: String) async throws { candidateValues.removeValue(forKey: id) }
}

extension PersistentKnowledgeStores: LibraryRepository {
    func lexicon() async throws -> [LexiconEntry] { Array(lexiconValues.values) }
    func saveLexicon(_ e: LexiconEntry) async throws { lexiconValues[e.id] = e }
    func deleteLexicon(id: String) async throws { lexiconValues.removeValue(forKey: id) }
    func shortcuts() async throws -> [ShortcutEntry] { [] }
    func saveShortcut(_ e: ShortcutEntry) async throws {}
    func deleteShortcut(id: String) async throws {}
}

final class DictionaryLearningPersistenceTests: XCTestCase {
    func testConfirmPersistsAcrossEngineRestartAndUndoRemovesOnlyLearnedRule() async throws {
        let stores = PersistentKnowledgeStores()
        let first = DictionaryLearningEngine(learning: stores, lexicon: stores)
        let proposed = try await first.observe(
            ObservedCorrection(heard: "item potency", corrected: "idempotency", anchorID: "a1"),
            consent: true)
        let id = try XCTUnwrap(proposed?.id)
        XCTAssertEqual(proposed?.state, .suggested)

        // Fresh engine over the same persisted stores: the candidate must reload.
        let second = DictionaryLearningEngine(learning: stores, lexicon: stores)
        let reloaded = try await second.candidates()
        XCTAssertEqual(reloaded.map(\.id), [id])
        let committed = try await second.confirm(id: id)
        XCTAssertEqual(committed, id)

        let third = DictionaryLearningEngine(learning: stores, lexicon: stores)
        let afterRestart = try await third.candidates()
        XCTAssertEqual(afterRestart.first?.state, .confirmed)
        let rules = try await stores.lexicon()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.learnedFrom, "edit-correction")
        XCTAssertEqual(rules.first?.canonical, "idempotency")

        // Undo through another fresh engine, then observe again: rejected must stick.
        let fourth = DictionaryLearningEngine(learning: stores, lexicon: stores)
        try await fourth.undo(id: id)
        let rulesAfterUndo = try await stores.lexicon()
        XCTAssertTrue(rulesAfterUndo.isEmpty)
        let rejected = try await fourth.candidates()
        XCTAssertEqual(rejected.first?.state, .rejected)

        let fifth = DictionaryLearningEngine(learning: stores, lexicon: stores)
        let retry = try await fifth.observe(
            ObservedCorrection(heard: "item potency", corrected: "idempotency", anchorID: "a2"),
            consent: true)
        XCTAssertNil(retry, "a rejected correction must never rewrite later speech")
    }

    func testRejectRejectsAndConfirmRejectsRejectedCandidate() async throws {
        let stores = PersistentKnowledgeStores()
        let engine = DictionaryLearningEngine(learning: stores, lexicon: stores)
        let candidate = try await engine.observe(
            ObservedCorrection(heard: "pearl", corrected: "Perl", anchorID: "a"), consent: true)
        let id = try XCTUnwrap(candidate?.id)
        try await engine.reject(id: id)
        let rejected = try await engine.candidates()
        XCTAssertEqual(rejected.first?.state, .rejected)

        do {
            _ = try await engine.confirm(id: id)
            XCTFail("confirm must reject a rejected candidate")
        } catch {
            XCTAssertTrue(error is DictionaryLearningError)
        }
        let rules = try await stores.lexicon()
        XCTAssertTrue(rules.isEmpty)
    }

    func testMissingCandidateAndManualRuleConflictsAreHonest() async throws {
        let stores = PersistentKnowledgeStores()
        let engine = DictionaryLearningEngine(learning: stores, lexicon: stores)

        do {
            _ = try await engine.confirm(id: "missing")
            XCTFail("confirm of a missing id must throw")
        } catch {
            guard case .candidateNotFound? = error as? DictionaryLearningError else {
                return XCTFail("expected candidateNotFound, got \(error)")
            }
        }
        do {
            try await engine.undo(id: "missing")
            XCTFail("undo of a missing id must throw")
        } catch {
            guard case .candidateNotFound? = error as? DictionaryLearningError else {
                return XCTFail("expected candidateNotFound, got \(error)")
            }
        }

        let candidate = try await engine.observe(
            ObservedCorrection(heard: "nextjs", corrected: "Next.js", anchorID: "a"), consent: true)
        let id = try XCTUnwrap(candidate?.id)
        // A manually authored rule with the same trigger and a different form.
        try await stores.saveLexicon(LexiconEntry(id: "manual", kind: .term,
                                                  triggers: ["nextjs"], canonical: "Node.js"))
        do {
            _ = try await engine.confirm(id: id)
            XCTFail("a manual rule must not be overwritten")
        } catch {
            guard case .conflictingCorrection? = error as? DictionaryLearningError else {
                return XCTFail("expected conflictingCorrection, got \(error)")
            }
        }
        let rules = try await stores.lexicon()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.id, "manual")
    }

    func testConsentAnchorsSafetyAndAutoPromotionRules() async throws {
        let stores = PersistentKnowledgeStores()
        let engine = DictionaryLearningEngine(learning: stores, lexicon: stores)

        let noConsent = try await engine.observe(
            ObservedCorrection(heard: "a", corrected: "b", anchorID: "no-consent"), consent: false)
        XCTAssertNil(noConsent)
        for (heard, anchor) in [
            ("https://example.com/token", "url"),
            ("person@example.com", "mail"),
            ("secret\nline", "multi"),
            ("this is a whole sentence that changed", "sentence"),
        ] {
            let result = try await engine.observe(
                ObservedCorrection(heard: heard, corrected: "safe", anchorID: anchor), consent: true)
            XCTAssertNil(result)
        }
        let initial = try await engine.candidates()
        XCTAssertTrue(initial.isEmpty)

        // Two independent, high-similarity edits auto-promote; a third copy of
        // the same anchor must not inflate the observation count.
        for anchor in ["one", "one", "two"] {
            _ = try await engine.observe(
                ObservedCorrection(heard: "nextjs", corrected: "next js", anchorID: anchor),
                consent: true, autoPromote: true)
        }
        let candidates = try await engine.candidates()
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.state, .confirmed)
        XCTAssertEqual(candidates.first?.observations, 2)
        let rules = try await stores.lexicon()
        XCTAssertEqual(rules.count, 1)
    }

    func testUnicodeCorrectionsAreAcceptedAndPersist() async throws {
        let stores = PersistentKnowledgeStores()
        let engine = DictionaryLearningEngine(learning: stores, lexicon: stores)
        let candidate = try await engine.observe(
            ObservedCorrection(heard: "café 東京", corrected: "Café 東京", anchorID: "u"), consent: true)
        XCTAssertNotNil(candidate)
        let candidates = try await engine.candidates()
        XCTAssertEqual(candidates.first?.heard, "café 東京")
        _ = try await engine.confirm(id: try XCTUnwrap(candidate?.id))
        let rules = try await stores.lexicon()
        XCTAssertEqual(rules.first?.canonical, "Café 東京")
    }
}
