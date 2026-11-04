import Foundation
import SherpaOnnx
import SherpaOnnxC
import SuperflowKernel
import SuperflowPorts

public actor SherpaOnnxRecognizer: SpeechRecognizer {
    private let models: SherpaOnnxModelStore
    private var engine: SherpaOnnxEngine?
    private var preparing: Task<SherpaOnnxEngine, Error>?

    public init(models: SherpaOnnxModelStore) {
        self.models = models
    }

    public var isReady: Bool { engine != nil }

    public func isPrepared(profile: String) async -> Bool {
        profile == SherpaOnnxModelStore.profileID && engine != nil
    }

    public func isAvailable(profileID: String) async -> Bool {
        guard profileID == SherpaOnnxModelStore.profileID else { return false }
        return await models.isAvailable()
    }

    public func prepare(profileID: String,
                        progress: @escaping @Sendable (Double) -> Void) async throws {
        guard profileID == SherpaOnnxModelStore.profileID else {
            throw SuperflowError.modelUnavailable("sherpa-onnx supports only Nemotron 3.5 Streaming.")
        }
        if engine != nil {
            progress(1)
            return
        }

        let task: Task<SherpaOnnxEngine, Error>
        if let preparing {
            task = preparing
        } else {
            let models = self.models
            task = Task {
                try await models.prepare(progress: progress)
                let directory = await models.modelDirectory()
                return try SherpaOnnxEngine(modelDirectory: directory)
            }
            preparing = task
        }

        do {
            engine = try await task.value
            preparing = nil
            progress(1)
        } catch {
            preparing = nil
            throw error
        }
    }

    public func warmUp(profile: String) async throws {
        guard profile == SherpaOnnxModelStore.profileID else {
            throw SuperflowError.modelUnavailable("sherpa-onnx supports only Nemotron 3.5 Streaming.")
        }
        if engine != nil { return }
        guard await models.isAvailable() else {
            throw SuperflowError.modelUnavailable("Nemotron 3.5 for sherpa-onnx is not downloaded. Get the model in Settings.")
        }
        let directory = await models.modelDirectory()
        engine = try SherpaOnnxEngine(modelDirectory: directory)
    }

    public func makeStream(profile: String, source: AudioSourceKind) async throws -> any RecognitionStream {
        guard profile == SherpaOnnxModelStore.profileID else {
            throw SuperflowError.modelUnavailable("sherpa-onnx supports only Nemotron 3.5 Streaming.")
        }
        guard let engine else {
            throw SuperflowError.invalidState("warmUp(profile:) must succeed before makeStream")
        }
        let streamID = try engine.createStream()
        return SherpaOnnxRecognitionStream(engine: engine, streamID: streamID, source: source)
    }
}

private final class SherpaOnnxEngine: @unchecked Sendable {
    private let lock = NSLock()
    private let recognizer: OpaquePointer
    private var streams: [UUID: OpaquePointer] = [:]

    init(modelDirectory: URL) throws {
        let encoder = modelDirectory.appendingPathComponent("encoder.int8.onnx").path
        let decoder = modelDirectory.appendingPathComponent("decoder.int8.onnx").path
        let joiner = modelDirectory.appendingPathComponent("joiner.int8.onnx").path
        let tokens = modelDirectory.appendingPathComponent("tokens.txt").path
        let transducer = sherpaOnnxOnlineTransducerModelConfig(
            encoder: encoder, decoder: decoder, joiner: joiner)
        let model = sherpaOnnxOnlineModelConfig(
            tokens: tokens, transducer: transducer, numThreads: 4, provider: "coreml")
        var config = sherpaOnnxOnlineRecognizerConfig(
            featConfig: sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80),
            modelConfig: model,
            enableEndpoint: true,
            rule1MinTrailingSilence: 2.4,
            rule2MinTrailingSilence: 0.8,
            rule3MinUtteranceLength: 30,
            decodingMethod: "greedy_search")
        guard let recognizer = withUnsafePointer(to: &config, { SherpaOnnxCreateOnlineRecognizer($0) }) else {
            throw SuperflowError.modelUnavailable("sherpa-onnx could not load Nemotron 3.5.")
        }
        self.recognizer = recognizer
    }

    deinit {
        for stream in streams.values { SherpaOnnxDestroyOnlineStream(stream) }
        SherpaOnnxDestroyOnlineRecognizer(recognizer)
    }

    func createStream() throws -> UUID {
        lock.lock()
        defer { lock.unlock() }
        guard let stream = SherpaOnnxCreateOnlineStream(recognizer) else {
            throw SuperflowError.modelUnavailable("sherpa-onnx could not create an audio stream.")
        }
        SherpaOnnxOnlineStreamSetOption(stream, toCPointer("language"), toCPointer("auto"))
        let id = UUID()
        streams[id] = stream
        return id
    }

    func append(_ samples: [Float], to id: UUID) throws -> (text: String, endpoint: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let stream = streams[id] else {
            throw SuperflowError.invalidState("The sherpa-onnx audio stream is closed.")
        }
        samples.withUnsafeBufferPointer { buffer in
            SherpaOnnxOnlineStreamAcceptWaveform(stream, 16_000, buffer.baseAddress,
                                                 Int32(buffer.count))
        }
        decodeAvailable(stream)
        let text = resultText(stream)
        let endpoint = SherpaOnnxOnlineStreamIsEndpoint(recognizer, stream) != 0
        if endpoint { SherpaOnnxOnlineStreamReset(recognizer, stream) }
        return (text, endpoint)
    }

    func finish(_ id: UUID) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let stream = streams.removeValue(forKey: id) else { return "" }
        defer { SherpaOnnxDestroyOnlineStream(stream) }
        SherpaOnnxOnlineStreamInputFinished(stream)
        decodeAvailable(stream)
        return resultText(stream)
    }

    private func decodeAvailable(_ stream: OpaquePointer) {
        while SherpaOnnxIsOnlineStreamReady(recognizer, stream) != 0 {
            SherpaOnnxDecodeOnlineStream(recognizer, stream)
        }
    }

    private func resultText(_ stream: OpaquePointer) -> String {
        guard let result = SherpaOnnxGetOnlineStreamResult(recognizer, stream) else { return "" }
        defer { SherpaOnnxDestroyOnlineRecognizerResult(result) }
        guard let text = result.pointee.text else { return "" }
        return String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private actor SherpaOnnxRecognitionStream: RecognitionStream {
    nonisolated let events: AsyncStream<RecognitionEvent>

    private let continuation: AsyncStream<RecognitionEvent>.Continuation
    private let engine: SherpaOnnxEngine
    private let streamID: UUID
    private let source: AudioSourceKind
    private var startSample: Int64?
    private var endSample: Int64 = 0
    private var lastText = ""
    private var isFinished = false

    init(engine: SherpaOnnxEngine, streamID: UUID, source: AudioSourceKind) {
        self.engine = engine
        self.streamID = streamID
        self.source = source
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(128))
    }

    func feed(_ chunk: AudioChunk) async {
        guard !isFinished, !chunk.samples.isEmpty else { return }
        guard chunk.source == source else {
            continuation.yield(.failure("Audio source did not match the recognition stream."))
            return
        }
        if startSample == nil { startSample = chunk.startSample }
        endSample = chunk.endSample

        do {
            let result = try engine.append(chunk.samples, to: streamID)
            if result.endpoint {
                emitCommit(text: result.text, end: endSample)
                continuation.yield(.endpoint(endSample))
                startSample = endSample
                lastText = ""
            } else if !result.text.isEmpty, result.text != lastText {
                lastText = result.text
                continuation.yield(.partial(result.text))
            }
        } catch {
            continuation.yield(.failure("sherpa-onnx could not process audio: \(error.localizedDescription)"))
        }
    }

    func finish() async {
        guard !isFinished else { return }
        isFinished = true
        do {
            let text = try engine.finish(streamID)
            emitCommit(text: text, end: max(startSample ?? endSample, endSample))
        } catch {
            continuation.yield(.failure("sherpa-onnx could not finish the audio stream: \(error.localizedDescription)"))
        }
        continuation.finish()
    }

    private func emitCommit(text: String, end: Int64) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        continuation.yield(.committed(RawSegment(
            text: normalized,
            startSample: startSample ?? end,
            endSample: end,
            source: source)))
    }
}
