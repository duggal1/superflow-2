import Foundation
import SuperflowKernel

public protocol RecognitionStream: Sendable {
    var events: AsyncStream<RecognitionEvent> { get }
    func feed(_ chunk: AudioChunk) async
    /// Flushes, emits the final committed segment, then finishes `events`.
    func finish() async
}

public protocol ASRModelProvider: Sendable {
    func isAvailable(profileID: String) async -> Bool
    func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws
}

public protocol SpeechRecognizer: ASRModelProvider, Sendable {
    var isReady: Bool { get async }
    func warmUp(profile: String) async throws
    func makeStream(profile: String, source: AudioSourceKind) async throws -> any RecognitionStream
}

public extension SpeechRecognizer {
    func isAvailable(profileID: String) async -> Bool {
        await isReady
    }

    func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0)
        try await warmUp(profile: profileID)
        progress(1)
    }
}

public protocol SpeakerDiarizer: Sendable {
    func isReady() async -> Bool
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws
    func beginSession() async
    func feed(_ chunk: AudioChunk) async
    func speaker(atMs: Int) async -> String?
    func finish() async
}

public extension SpeakerDiarizer {
    func isReady() async -> Bool { true }
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {}
    func beginSession() async {}
}
