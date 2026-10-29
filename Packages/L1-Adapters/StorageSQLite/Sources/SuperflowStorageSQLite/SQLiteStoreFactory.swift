import Darwin
import Foundation
import OSLog
import SQLite3

public enum SQLiteStoreFactory {
    private static let logger = Logger(subsystem: "com.superflow.app", category: "Storage")

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Superflow/Superflow.sqlite")
    }

    public static func openDefault() throws -> SQLiteStore {
        try open(url: defaultURL())
    }

    public static func open(url: URL, fileManager: FileManager = .default) throws -> SQLiteStore {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
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
