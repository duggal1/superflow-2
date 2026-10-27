import Foundation
import SuperflowKernel
import SuperflowPorts

/// System audio through a Core Audio process tap (macOS 14.2+) with a
/// ScreenCaptureKit audio-only fallback. Both paths expose the same
/// `AudioSource` port, so MeetingEngine does not know which one is active.
public final class SystemAudioCapture: AudioSource, @unchecked Sendable {
    public let kind: AudioSourceKind = .system

    private let preference: SystemAudioPreference
    private let factory: SystemAudioBackendFactory
    private let lock = NSLock()
    private var backend: (any SystemAudioBackend)?
    private var running = false
    private var lastFailure: String?

    public init(preference: SystemAudioPreference = .automatic) {
        self.preference = preference
        self.factory = .live
    }

    init(preference: SystemAudioPreference, factory: SystemAudioBackendFactory) {
        self.preference = preference
        self.factory = factory
    }

    /// Test seam: build the candidate list from a closure so a test can inject
    /// fakes without spelling out the factory type.
    init(
        preference: SystemAudioPreference,
        candidates: @escaping @Sendable (SystemAudioPreference) -> [any SystemAudioBackend]
    ) {
        self.preference = preference
        self.factory = SystemAudioBackendFactory(candidates: candidates)
    }

    /// The transport currently capturing, or nil while idle. Used by the
    /// meeting notice so the user can tell tap from fallback.
    public var activeBackend: SystemAudioBackendKind? {
        lock.withLock { backend?.kind }
    }

    public var failureDescription: String? {
        lock.withLock { lastFailure }
    }

    public func start() async throws -> AudioStreams {
        let alreadyRunning = lock.withLock { running }
        guard !alreadyRunning else {
            throw SuperflowError.invalidState("system audio already running")
        }

        var failures: [String] = []
        var sawPermissionDenial = false
        for candidate in factory.candidates(preference) {
            do {
                let streams = try await candidate.start()
                lock.withLock {
                    backend = candidate
                    running = true
                    lastFailure = nil
                }
                return streams
            } catch {
                let message = "\(candidate.kind.label): \(Self.describe(error))"
                failures.append(message)
                if Self.isPermissionFailure(error) { sawPermissionDenial = true }
                await candidate.stop()
            }
        }

        let summary = failures.isEmpty
            ? "No system audio backend is available on this system."
            : failures.joined(separator: " · ")
        lock.withLock { lastFailure = summary }
        if sawPermissionDenial {
            throw SuperflowError.permissionDenied(Permission.systemAudio.label)
        }
        throw SuperflowError.audioFailure(summary)
    }

    public func stop() async {
        let active = lock.withLock { () -> (any SystemAudioBackend)? in
            let value = backend
            backend = nil
            running = false
            return value
        }
        await active?.stop()
    }

    private static func isPermissionFailure(_ error: Error) -> Bool {
        if case SystemAudioCaptureFailure.permissionDenied = error { return true }
        if let error = error as? SuperflowError, case .permissionDenied = error { return true }
        return false
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? SystemAudioCaptureFailure { return failure.localizedDescription }
        return error.localizedDescription
    }
}
