import AppKit
import Foundation

public struct DictationConflict: Sendable, Equatable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// Apps that install their own fn event tap. Deliberately narrow: only bundle
/// identifiers we can name, and only consulted while fn is Superflow's key. A
/// tap installed later sits ahead of ours, so one of these running silently
/// makes fn look dead even though Superflow's own tap is healthy.
public enum DictationConflictPolicy {
    public static let competingBundleIDs: [String: String] = [
        "com.seewillow.WillowMac": "Willow Voice",
        "com.electron.wispr-flow": "Wispr Flow",
        "com.superduper.superwhisper": "superwhisper",
    ]

    public static func name(forBundleID id: String) -> String? {
        competingBundleIDs[id]
    }

    public static func isCompeting(bundleID: String) -> Bool {
        competingBundleIDs[bundleID] != nil
    }
}

@MainActor
public enum DictationConflictResolver {
    /// Asks known competitors to quit. `terminate()` posts the normal quit
    /// request so they save state and can be reopened; nothing is force-killed.
    public static func terminateKnownCompetitors() -> [DictationConflict] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var closed: [DictationConflict] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier != ownPID,
                  !app.isTerminated,
                  let bundleID = app.bundleIdentifier,
                  let name = DictationConflictPolicy.name(forBundleID: bundleID)
            else { continue }
            if app.terminate() {
                closed.append(DictationConflict(bundleID: bundleID, name: name))
            }
        }
        return closed
    }
}
