public protocol SpeechEnhancer: Sendable {
    /// Load + warm the model. Call at launch, never at record time.
    func prepare() async throws
    /// Start a streaming enhancement session.
    func begin() async throws
    /// 16 kHz mono Float32 in, 16 kHz mono Float32 out. Output lags input by a few
    /// tens of ms; total output after `finish()` equals total input.
    func process(_ samples: [Float]) async throws -> [Float]
    /// Drain whatever is still inside the model, then reset for the next session.
    func finish() async throws -> [Float]
    func reset() async
}

public extension SpeechEnhancer {
    func begin() async throws {}
}
