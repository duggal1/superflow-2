import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Every durable write in the recovery subsystem goes through one primitive: write a temp file in
/// the *same directory*, fsync it, atomically rename it over the destination, fsync the directory.
/// A crash at any of those points leaves either the complete old file or the complete new file.
public enum AtomicWriteStage: String, CaseIterable, Sendable, Equatable {
    case prepare, tempWrite, tempSync, replace, directorySync, committed
}

public enum RecoveryStorageError: Error, Sendable, Equatable, LocalizedError {
    /// A test or diagnostic requested a crash at this exact stage, after that stage completed.
    case injectedCrash(AtomicWriteStage)
    case filesystem(String)

    public var errorDescription: String? {
        switch self {
        case .injectedCrash(let stage): "Simulated process termination at \(stage.rawValue)."
        case .filesystem(let message): "Recovery storage error: \(message)"
        }
    }
}

public struct AtomicWriteResult: Sendable, Equatable {
    public var url: URL
    public var bytes: Int
    public var stage: AtomicWriteStage
    public init(url: URL, bytes: Int, stage: AtomicWriteStage) {
        self.url = url
        self.bytes = bytes
        self.stage = stage
    }
}

/// Deterministic 64-bit FNV-1a. No dependency, no key management, stable across versions and
/// platforms; adequate for detecting torn writes and bit rot, not for adversarial tampering.
public enum RecoveryChecksum {
    public static func fnv1a(_ bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0100_0000_01b3
        }
        return hash
    }

    public static func fnv1a(_ data: Data) -> UInt64 { fnv1a([UInt8](data)) }
}

/// Thin, dependency-free file primitive. `crashAt` injects a kill after the named step so tests can
/// exercise every crash point against real storage; the temp file is intentionally left on disk for
/// the orphan sweep to report, never silently removed.
public struct AtomicFileStore: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public func destination(_ name: String) -> URL { root.appendingPathComponent(name) }

    public func read(_ name: String) throws -> Data? {
        let url = destination(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    @discardableResult
    public func write(_ data: Data, named name: String,
                      crashAt: AtomicWriteStage? = nil) throws -> AtomicWriteResult {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        guard crashAt != .prepare else { throw RecoveryStorageError.injectedCrash(.prepare) }

        let temp = root.appendingPathComponent(".\(name).\(UUID().uuidString).tmp")
        try data.write(to: temp, options: .atomic)
        guard crashAt != .tempWrite else { throw RecoveryStorageError.injectedCrash(.tempWrite) }

        let handle = try FileHandle(forWritingTo: temp)
        try handle.synchronize()
        guard crashAt != .tempSync else {
            try? handle.close()
            throw RecoveryStorageError.injectedCrash(.tempSync)
        }

        // POSIX rename replaces an existing file atomically. Never unlink the old file first:
        // that would leave a window where a reader sees no file at all.
        let destination = self.destination(name)
        let exchanged = Self.rename(temp.path, destination.path)
        try? handle.close()
        guard exchanged else {
            throw RecoveryStorageError.filesystem("rename failed with errno \(Self.lastErrno)")
        }
        guard crashAt != .replace else { throw RecoveryStorageError.injectedCrash(.replace) }

        Self.syncDirectory(root)
        guard crashAt != .directorySync else { throw RecoveryStorageError.injectedCrash(.directorySync) }
        return AtomicWriteResult(url: destination, bytes: data.count, stage: .committed)
    }

    public func remove(_ name: String) throws {
        let url = destination(name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Moves crash leftovers into `Quarantine/` instead of deleting them: no user-visible data is
    /// ever destroyed by recovery. Returns the URLs that were moved.
    @discardableResult
    public func quarantineTemps() throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        let quarantine = root.appendingPathComponent("Quarantine", isDirectory: true)
        let entries = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var moved: [URL] = []
        for entry in entries where entry.lastPathComponent.hasSuffix(".tmp") {
            try fm.createDirectory(at: quarantine, withIntermediateDirectories: true)
            let target = quarantine.appendingPathComponent("\(UUID().uuidString)-\(entry.lastPathComponent)")
            try fm.moveItem(at: entry, to: target)
            moved.append(target)
        }
        return moved
    }

    /// Move a corrupt record aside for user inspection; never delete it.
    @discardableResult
    public func quarantine(named name: String) throws -> URL? {
        let url = destination(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let quarantine = root.appendingPathComponent("Quarantine", isDirectory: true)
        try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
        let target = quarantine.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    private static var lastErrno: Int32 {
        #if canImport(Darwin)
        return errno
        #else
        return -1
        #endif
    }

    private static func rename(_ from: String, _ to: String) -> Bool {
        #if canImport(Darwin)
        return from.withCString { src in to.withCString { dst in Darwin.rename(src, dst) == 0 } }
        #else
        return (try? FileManager.default.moveItem(atPath: from, toPath: to)) != nil
        #endif
    }

    private static func syncDirectory(_ url: URL) {
        #if canImport(Darwin)
        let fd = url.path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY) }
        guard fd >= 0 else { return }
        _ = Darwin.fsync(fd)
        _ = Darwin.close(fd)
        #endif
    }
}
