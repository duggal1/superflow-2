import Foundation
import SuperflowKernel

#if canImport(Darwin)
import Darwin
#endif

public struct RecoveryLockOwner: Codable, Sendable, Equatable {
    public var pid: Int32
    public var host: String
    public var acquiredAt: Date
    public var heartbeatAt: Date
    public var version: Int
    public init(pid: Int32 = getpid(), host: String = ProcessInfo.processInfo.hostName,
                acquiredAt: Date = Date(), heartbeatAt: Date = Date(), version: Int = 1) {
        self.pid = pid
        self.host = host
        self.acquiredAt = acquiredAt
        self.heartbeatAt = heartbeatAt
        self.version = version
    }
}

public enum RecoveryLockError: Error, Sendable, Equatable, LocalizedError {
    case busy(RecoveryLockOwner)
    case exhausted

    public var errorDescription: String? {
        switch self {
        case .busy(let owner): "Recovery is already running under process \(owner.pid)."
        case .exhausted: "A recovery lock could not be acquired after breaking a stale owner."
        }
    }
}

/// Directory-based inter-process lock. Acquisition is a single atomic `mkdir`. A leftover lock is
/// broken only when its recorded PID is dead or its heartbeat is older than `staleAfter`; the old
/// directory is renamed to `.stale-...` as evidence instead of being deleted.
public final class RecoveryLock: @unchecked Sendable {
    private let root: URL
    private let name: String
    private let now: @Sendable () -> Date
    private let pidAlive: @Sendable (Int32) -> Bool
    private let staleAfter: TimeInterval
    /// A lock directory can exist for a few milliseconds before its owner record is written.
    /// Breaking it in that window caused a startup race between concurrent acquirers.
    private let startupGrace: TimeInterval
    private let owner: RecoveryLockOwner
    private let state: AtomicFileStore
    private let monitor = NSLock()
    private var held = false

    public init(root: URL, session: SessionID, owner: RecoveryLockOwner = RecoveryLockOwner(),
                now: @escaping @Sendable () -> Date = { Date() },
                pidAlive: @escaping @Sendable (Int32) -> Bool = { pid in
                    #if canImport(Darwin)
                    return Darwin.kill(pid, 0) == 0
                    #else
                    return pid == getpid()
                    #endif
                },
                staleAfter: TimeInterval = 120,
                startupGrace: TimeInterval = 30) {
        self.root = root
        let safe = session.value.map { ($0.isLetter || $0.isNumber) ? $0 : "_" }
        self.name = "\(String(safe)).lock"
        self.now = now
        self.pidAlive = pidAlive
        self.staleAfter = staleAfter
        self.startupGrace = startupGrace
        self.owner = owner
        self.state = AtomicFileStore(root: root.appendingPathComponent(name, isDirectory: true))
    }

    public var directory: URL { root.appendingPathComponent(name, isDirectory: true) }

    public func acquire() throws { try acquire(attempt: 0) }

    private func acquire(attempt: Int) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        } catch {
            guard attempt < 3, staleReason() != nil else {
                throw RecoveryLockError.busy(ownerFromDisk() ?? owner)
            }
            let stale = root.appendingPathComponent("\(name).stale-\(Int64(now().timeIntervalSince1970 * 1000))-\(UUID().uuidString)")
            // Another process may win the same race; if the rename fails, re-check by retrying.
            try? fm.moveItem(at: directory, to: stale)
            try acquire(attempt: attempt + 1)
            return
        }
        do {
            try state.write(try JSONEncoder().encode(owner), named: "owner.json")
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
        monitor.lock()
        held = true
        monitor.unlock()
    }

    private func staleReason() -> String? {
        guard let current = ownerFromDisk() else {
            // No owner record: either the creator has not written it yet (normal, milliseconds) or
            // a process died between mkdir and write (rare). Only the latter is breakable.
            let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
            let created = attributes?[.creationDate] as? Date ?? now()
            return now().timeIntervalSince(created) > startupGrace ? "owner record missing" : nil
        }
        if !pidAlive(current.pid) { return "owner process \(current.pid) is gone" }
        if now().timeIntervalSince(current.heartbeatAt) > staleAfter { return "heartbeat is stale" }
        return nil
    }

    private func ownerFromDisk() -> RecoveryLockOwner? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("owner.json")) else { return nil }
        return try? JSONDecoder().decode(RecoveryLockOwner.self, from: data)
    }

    /// Refreshes the heartbeat. Cheap enough to call between recovery stages.
    public func touch() {
        guard isHeld else { return }
        var refreshed = owner
        refreshed.heartbeatAt = now()
        _ = try? state.write(try JSONEncoder().encode(refreshed), named: "owner.json")
    }

    public var isHeld: Bool {
        monitor.lock()
        defer { monitor.unlock() }
        return held
    }

    public func release() {
        monitor.lock()
        let wasHeld = held
        held = false
        monitor.unlock()
        guard wasHeld else { return }
        // Never remove a lock that another process has since re-acquired.
        guard let current = ownerFromDisk(), current.pid == owner.pid else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    public func withLock<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        try acquire()
        defer { release() }
        return try await body()
    }

    public static func staleEvidence(root: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return entries.filter { $0.lastPathComponent.contains(".stale-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
