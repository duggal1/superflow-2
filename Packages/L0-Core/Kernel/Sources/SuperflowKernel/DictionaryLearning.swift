import Foundation

/// The only edit information allowed to leave an Accessibility watcher:
/// at most three changed tokens on each side and an app identifier.
public struct ObservedCorrection: Sendable, Equatable {
    public var heard: String
    public var corrected: String
    public var appBundleID: String?

    public init(heard: String, corrected: String, appBundleID: String? = nil) {
        self.heard = heard
        self.corrected = corrected
        self.appBundleID = appBundleID
    }
}

public enum LearningState: String, Codable, Sendable {
    case suggested, confirmed, rejected
}

public struct LearningCandidate: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var heard: String
    public var canonical: String
    public var appScope: String?
    public var confidence: Double
    public var observations: Int
    public var state: LearningState
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, heard: String, canonical: String,
                appScope: String? = nil, confidence: Double, observations: Int = 1,
                state: LearningState = .suggested, createdAt: Date = .now,
                updatedAt: Date = .now) {
        self.id = id
        self.heard = heard
        self.canonical = canonical
        self.appScope = appScope
        self.confidence = min(1, max(0, confidence))
        self.observations = observations
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
