import Foundation
import SQLite3

/// Full integrity verification and non-destructive quarantine.
///
/// The store already runs `PRAGMA quick_check` on every open and the factory
/// checks the file header, but a logically corrupt database (valid header,
/// damaged pages) was previously reported and then left in place. This adds a
/// full `integrity_check` and a quarantine step that *moves* the database and
/// its WAL sidecars aside instead of deleting or overwriting anything: a user
/// keeps the damaged file for recovery and never loses it silently.
public enum DatabaseIntegrity {
    public enum CheckResult: Sendable, Equatable {
        case healthy
        case corrupted([String])
        case unreadable(String)
    }

    public struct Report: Sendable, Equatable {
        public let databaseURL: URL
        public let check: CheckResult
        /// Set only when corruption was found and the file was moved aside.
        public let quarantineURL: URL?
    }

    public enum IntegrityError: Error, LocalizedError, Equatable {
        case corruptedDatabaseQuarantined(String)

        public var errorDescription: String? {
            switch self {
            case .corruptedDatabaseQuarantined(let path):
                "The database failed its integrity check and was moved to \(path) for recovery. No data was deleted."
            }
        }
    }

    private static let quarantineDirectoryName = ".superflow-quarantine"
    private static let sidecars = ["-wal", "-shm"]

    /// Runs `PRAGMA integrity_check` on a staged copy. Working on a copy keeps
    /// the check read-only with respect to the live database and avoids WAL
    /// read-only locking problems: the staged file gets a fresh shared-memory
    /// file of its own. A missing database is healthy (there is nothing to
    /// corrupt yet), so first launch can still create one.
    public static func check(databaseAt url: URL,
                             fileManager: FileManager = .default) -> CheckResult {
        guard fileManager.fileExists(atPath: url.path) else { return .healthy }
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("superflow-integrity-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: staging) }
            let staged = staging.appendingPathComponent(url.lastPathComponent)
            try fileManager.copyItem(at: url, to: staged)
            for suffix in sidecars {
                let original = URL(fileURLWithPath: url.path + suffix)
                if fileManager.fileExists(atPath: original.path) {
                    try fileManager.copyItem(at: original,
                                             to: URL(fileURLWithPath: staged.path + suffix))
                }
            }
            // The staged file is a throwaway copy, so a writable handle here
            // cannot touch the live database. This also lets SQLite rebuild a
            // WAL shared-memory file if one was not carried over.
            let connection = try SQLiteConnection(path: staged.path)
            let statement = try connection.prepare("PRAGMA integrity_check")
            var problems: [String] = []
            while try statement.step() {
                let line = statement.text(0) ?? "unknown integrity error"
                if line.lowercased() != "ok" { problems.append(line) }
            }
            return problems.isEmpty ? .healthy : .corrupted(problems)
        } catch {
            return .unreadable(String(describing: error))
        }
    }

    /// Moves the database and any WAL sidecars into a hidden, timestamped
    /// quarantine folder beside the database. Nothing is deleted; the returned
    /// URL is where the original bytes now live.
    public static func quarantine(databaseAt url: URL,
                                  fileManager: FileManager = .default) throws -> URL {
        let root = url.deletingLastPathComponent()
            .appendingPathComponent(quarantineDirectoryName, isDirectory: true)
        let stamp = "\(url.deletingPathExtension().lastPathComponent)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        let destination = root.appendingPathComponent(stamp, isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let candidates = [url] + sidecars.map { URL(fileURLWithPath: url.path + $0) }
        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            try fileManager.moveItem(at: candidate,
                                     to: destination.appendingPathComponent(candidate.lastPathComponent))
        }
        return destination
    }

    /// Checks, and when corrupt, quarantines before returning. Recommended for
    /// launch paths that open the store: call this before `SQLiteStoreFactory`
    /// opens the live database so the moved file is not open during the move.
    @discardableResult
    public static func verifyAndQuarantineIfCorrupted(
        databaseAt url: URL,
        fileManager: FileManager = .default
    ) throws -> Report {
        let result = check(databaseAt: url, fileManager: fileManager)
        guard case .corrupted = result else {
            return Report(databaseURL: url, check: result, quarantineURL: nil)
        }
        let destination = try quarantine(databaseAt: url, fileManager: fileManager)
        return Report(databaseURL: url, check: result, quarantineURL: destination)
    }
}
