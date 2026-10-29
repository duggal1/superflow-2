import Darwin
import Foundation

/// Held for the lifetime of the process; the kernel releases it on force quit.
public final class ApplicationInstanceLock {
    private let descriptor: Int32

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let opened = Darwin.open(directory.appendingPathComponent(".instance-lock").path,
                                 O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard opened >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            let failure = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(opened)
            throw failure
        }
        descriptor = opened
    }

    deinit { close(descriptor) }
}
