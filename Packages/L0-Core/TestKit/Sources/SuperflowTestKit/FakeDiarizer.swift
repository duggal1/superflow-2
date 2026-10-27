import Foundation
import SuperflowKernel
import SuperflowPorts

/// Deterministic diarizer fake. One speaker per session, assigned by the first
/// fed sample so tests can assert labels without a model.
public actor FakeSpeakerDiarizer: SpeakerDiarizer {
    public private(set) var ready: Bool
    public private(set) var prepared = false
    public private(set) var beganSession = false
    public private(set) var fedChunks = 0
    public private(set) var finished = 0
    public var label: String
    public var failPrepare: Bool

    public init(ready: Bool = true, label: String = "speaker-1", failPrepare: Bool = false) {
        self.ready = ready
        self.label = label
        self.failPrepare = failPrepare
    }

    public func setReady(_ value: Bool) { ready = value }

    public func isReady() async -> Bool { ready }

    public func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0)
        if failPrepare { throw SuperflowError.modelUnavailable("diarizer") }
        prepared = true
        ready = true
        progress(1)
    }

    public func beginSession() async {
        beganSession = true
        fedChunks = 0
    }

    public func feed(_ chunk: AudioChunk) async {
        fedChunks += 1
    }

    public func speaker(atMs: Int) async -> String? {
        fedChunks > 0 ? label : nil
    }

    public func finish() async {
        finished += 1
    }
}
