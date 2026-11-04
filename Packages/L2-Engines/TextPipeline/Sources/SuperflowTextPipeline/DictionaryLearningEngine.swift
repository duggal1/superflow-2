import Foundation
import SuperflowKernel
import SuperflowPorts

public enum DictionaryLearningError: Error, Sendable {
    case candidateNotFound
    case rejected
    case conflictingCorrection
}

/// Separates observed edits from active replacement rules. It never monitors
/// input itself, never sends data to a server, and only receives short phrases
/// explicitly admitted by the opt-in Accessibility watcher.
public actor DictionaryLearningEngine {
    private let learning: any LearningRepository
    private let lexicon: any LibraryRepository
    private var seenAnchors = Set<String>()
    private var anchorOrder: [String] = []

    public init(learning: any LearningRepository, lexicon: any LibraryRepository) {
        self.learning = learning
        self.lexicon = lexicon
    }

    public func candidates() async throws -> [LearningCandidate] {
        try await learning.learningCandidates()
    }

    /// One AX edit can produce many notifications. Count an insertion at most
    /// once, and reject sentence rewrites, URLs, secrets and multi-line content.
    @discardableResult
    public func observe(_ observation: ObservedCorrection, consent: Bool,
                        autoPromote: Bool = false) async throws -> LearningCandidate? {
        guard consent, !seenAnchors.contains(observation.anchorID) else { return nil }
        let heard = observation.heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = observation.corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.safePhrase(heard, maxLength: 80),
              Self.safePhrase(corrected, maxLength: 200),
              heard != corrected else { return nil }
        rememberAnchor(observation.anchorID)
        let app = observation.appBundleID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundle = app.flatMap { !$0.isEmpty && $0.count <= 200 ? $0 : nil }
        let similarity = Self.editSimilarity(heard, corrected)
        let existing = try await learning.learningCandidates().first {
            $0.heard.caseInsensitiveCompare(heard) == .orderedSame
                && $0.canonical == corrected && $0.appScope == bundle
        }
        var candidate = existing ?? LearningCandidate(
            heard: heard, canonical: corrected, appScope: bundle, confidence: similarity)
        guard candidate.state != .rejected else { return nil }
        if existing != nil { candidate.observations += 1 }
        candidate.confidence = similarity
        candidate.updatedAt = .now
        try await learning.saveLearningCandidate(candidate)

        if autoPromote && candidate.observations >= 2 && similarity >= 0.85 {
            try await confirm(id: candidate.id)
            candidate.state = .confirmed
        }
        return candidate
    }

    /// Returns the committed rule's ID only after SQLite has accepted it.
    @discardableResult
    public func confirm(id: String) async throws -> String {
        guard var candidate = try await learning.learningCandidates().first(where: { $0.id == id }) else {
            throw DictionaryLearningError.candidateNotFound
        }
        guard candidate.state != .rejected else { throw DictionaryLearningError.rejected }
        let entries = try await lexicon.lexicon()
        if let conflict = entries.first(where: {
            $0.appScope == candidate.appScope
                && $0.triggers.contains(where: {
                    $0.compare(candidate.heard, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                })
        }) {
            guard conflict.canonical == candidate.canonical,
                  conflict.id == candidate.id else {
                throw DictionaryLearningError.conflictingCorrection
            }
        }
        let rule = LexiconEntry(
            id: candidate.id, kind: .correction, triggers: [candidate.heard],
            canonical: candidate.canonical, enabled: true, source: .user,
            appScope: candidate.appScope, heardForms: [candidate.heard],
            learnedFrom: "edit-correction", confidence: candidate.confidence,
            confirmationCount: candidate.observations, hitCount: 0,
            createdAt: candidate.createdAt, updatedAt: .now)
        try await lexicon.saveLexicon(rule)
        candidate.state = .confirmed
        candidate.updatedAt = .now
        try await learning.saveLearningCandidate(candidate)
        return rule.id
    }

    public func reject(id: String) async throws {
        guard var candidate = try await learning.learningCandidates().first(where: { $0.id == id }) else {
            throw DictionaryLearningError.candidateNotFound
        }
        if candidate.state == .confirmed { try await undo(id: id); return }
        candidate.state = .rejected
        candidate.updatedAt = .now
        try await learning.saveLearningCandidate(candidate)
    }

    /// Never delete a manually authored rule, even if IDs collide.
    public func undo(id: String) async throws {
        guard var candidate = try await learning.learningCandidates().first(where: { $0.id == id }) else {
            throw DictionaryLearningError.candidateNotFound
        }
        let existing = try await lexicon.lexicon()
        if let active = existing.first(where: { $0.id == id }) {
            guard active.learnedFrom == "edit-correction" else {
                throw DictionaryLearningError.conflictingCorrection
            }
            try await lexicon.deleteLexicon(id: id)
        }
        candidate.state = .rejected
        candidate.updatedAt = .now
        try await learning.saveLearningCandidate(candidate)
    }

    private func rememberAnchor(_ anchor: String) {
        guard !anchor.isEmpty else { return }
        seenAnchors.insert(anchor)
        anchorOrder.append(anchor)
        if anchorOrder.count > 256 {
            seenAnchors.remove(anchorOrder.removeFirst())
        }
    }

    private static func safePhrase(_ text: String, maxLength: Int) -> Bool {
        guard !text.isEmpty, text.count <= maxLength,
              text.split(whereSeparator: \.isWhitespace).count <= 3,
              text.rangeOfCharacter(from: .controlCharacters) == nil,
              !text.contains("://"), !text.contains("@"), !text.contains("/") else { return false }
        return true
    }

    /// This measures normalized edit distance, not model confidence or a
    /// probability of correctness. Never show it as a calibrated ASR score.
    static func editSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(lhs.lowercased())
        let b = Array(rhs.lowercased())
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(0...b.count)
        for i in a.indices {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for j in b.indices {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1,
                                     previous[j] + (a[i] == b[j] ? 0 : 1))
            }
            previous = current
        }
        return max(0, 1 - Double(previous[b.count]) / Double(max(a.count, b.count)))
    }
}
