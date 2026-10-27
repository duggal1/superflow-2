import Foundation
import SuperflowPorts

/// A port contract violation. TestKit exposes contracts as ordinary throwing
/// functions so the same suite can run inside this package's tests and inside
/// an adapter package's tests without TestKit depending on XCTest.
public struct ContractFailure: Error, CustomStringConvertible, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

public func contractRequire(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw ContractFailure(message()) }
}

/// Collects a bounded prefix of an AsyncStream, cancelling the wait on timeout.
/// Contracts use it so a broken port cannot hang the test process forever.
public enum ContractStream {
    public static func collect<T: Sendable>(_ stream: AsyncStream<T>, limit: Int = 1_000,
                                            timeout: Duration = .seconds(2)) async -> [T] {
        let task = Task { () -> [T] in
            var values: [T] = []
            for await value in stream {
                values.append(value)
                if values.count >= limit { break }
            }
            return values
        }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            task.cancel()
        }
        let values = await task.value
        timer.cancel()
        return values
    }
}

/// Thread-safe progress recorder for `prepare(profileID:progress:)` contracts.
public final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    public init() {}

    public func record(_ value: Double) {
        lock.withLock { storage.append(value) }
    }

    public var values: [Double] {
        lock.withLock { storage }
    }
}

public func contractIsClipboardOnly(_ outcome: InsertionOutcome) -> Bool {
    if case .clipboardOnly = outcome { return true }
    return false
}
