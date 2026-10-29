import Darwin
import Foundation
import OSLog
import SQLite3

public enum SQLiteStoreFactory {
    private static let logger = Logger(subsystem: "com.superflow.app", category: "Storage")

    /// Entering WAL mode creates a 32 KiB `-shm` file before SQLite can serve a
    /// single statement. Refusing to open below this margin keeps a nearly full
    /// volume from surfacing as an opaque `SQLite 10: disk I/O error`, which is
    /// exactly what `SQLITE_IOERR_SHMOPEN` looks like from the outside.
    public static let minimumFreeBytes: Int64 = 8 * 1_024 * 1_024

    /// A 64 KiB probe is larger than the `-shm` file, so a successful probe
    /// proves the volume can still hand out the blocks SQLite needs.
    private static let probeBytes = 64 * 1_024

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Superflow/Superflow.sqlite")
    }

    public static func openDefault() throws -> SQLiteStore {
        try open(url: defaultURL())
    }

    public static func open(url: URL, fileManager: FileManager = .default,
                            minimumFreeBytes: Int64 = SQLiteStoreFactory.minimumFreeBytes) throws -> SQLiteStore {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try requireUsableSpace(in: directory, minimumFreeBytes: minimumFreeBytes)
        let lock = try DatabaseOpenLock(path: url.path + ".open-lock")
        defer { lock.release() }
        do {
            if fileManager.fileExists(atPath: url.path) {
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let header = try file.read(upToCount: 16) ?? Data()
                if !header.isEmpty && header != Data("SQLite format 3\0".utf8) {
                    throw SQLiteError(code: SQLITE_NOTADB, message: "database header is invalid")
                }
            }
            let store = try SQLiteStore(path: url.path)
            logger.info("Database opened successfully")
            return store
        } catch {
            logger.error("Database open failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Reported free space can exceed what the volume will actually allocate
    /// (APFS reserves, quotas, snapshots), so the report is only a fast first
    /// gate. The probe is the authoritative check and touches nothing but its
    /// own temporary file.
    static func requireUsableSpace(in directory: URL, minimumFreeBytes: Int64) throws {
        var filesystem = statfs()
        if statfs(directory.path, &filesystem) == 0 {
            let available = Int64(filesystem.f_bavail) * Int64(filesystem.f_bsize)
            if available < minimumFreeBytes {
                throw diskFull(available: available, required: minimumFreeBytes, systemCode: ENOSPC)
            }
        }

        let probe = directory.appendingPathComponent(".superflow-space-probe-\(UUID().uuidString)")
        let descriptor = probe.path.withCString {
            Darwin.open($0, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw spaceProbeFailure(errno, required: minimumFreeBytes)
        }
        defer {
            close(descriptor)
            unlink(probe.path)
        }

        let bytes = [UInt8](repeating: 0, count: probeBytes)
        var offset = 0
        while offset < probeBytes {
            let written = bytes.withUnsafeBytes {
                Darwin.write(descriptor, $0.baseAddress!.advanced(by: offset), probeBytes - offset)
            }
            guard written > 0 else { throw spaceProbeFailure(errno, required: minimumFreeBytes) }
            offset += written
        }
        guard fsync(descriptor) == 0 else {
            throw spaceProbeFailure(errno, required: minimumFreeBytes)
        }
    }

    private static func spaceProbeFailure(_ code: Int32, required: Int64) -> Error {
        switch code {
        case ENOSPC, EDQUOT:
            return diskFull(available: 0, required: required, systemCode: code)
        default:
            return POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    private static func diskFull(available: Int64, required: Int64, systemCode: Int32) -> SQLiteError {
        SQLiteError(code: SQLITE_FULL,
                    message: "the database volume has \(available) bytes available; \(required) are required",
                    systemCode: systemCode)
    }
}

private final class DatabaseOpenLock {
    private let descriptor: Int32

    init(path: String) throws {
        let opened = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard opened >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(opened, LOCK_EX) == 0 else {
            let failure = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(opened)
            throw failure
        }
        descriptor = opened
    }

    func release() {
        // Closing releases the advisory lock even after process termination.
        close(descriptor)
    }
}
