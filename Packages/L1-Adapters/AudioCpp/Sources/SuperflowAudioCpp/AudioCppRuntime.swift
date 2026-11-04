import CAudioCpp
import Foundation
import SuperflowKernel
import SuperflowPorts

private final class NativeHandle {
    enum Kind { case registry, model, session }
    let pointer: OpaquePointer
    let kind: Kind
    init(_ pointer: OpaquePointer, kind: Kind) {
        self.pointer = pointer
        self.kind = kind
    }
    deinit {
        switch kind {
        case .registry: audiocpp_registry_free(pointer)
        case .model: audiocpp_model_free(pointer)
        case .session: audiocpp_session_free(pointer)
        }
    }
}

actor AudioCppRuntime {
    private struct Slot {
        let handle: NativeHandle
        let source: AudioSourceKind
        let continuation: AsyncStream<RecognitionEvent>.Continuation
        var text = ""
        var start: Int64?
        var end: Int64 = 0
        var silenceSamples = 0
    }
    private struct SpeakerTurn {
        let start: Int64
        let end: Int64
        let label: String
    }
    private let asset: AudioCppAsset
    private let modelURL: URL
    private var registry: NativeHandle?
    private var model: NativeHandle?
    private var slots: [UUID: Slot] = [:]
    private var idle: [NativeHandle] = []
    private var turns: [SpeakerTurn] = []
    private var installation: Task<Void, Error>?
    private var generation: UInt64 = 0

    init(asset: AudioCppAsset, root: URL) {
        self.asset = asset
        modelURL = root.appendingPathComponent(asset.fileName)
    }

    var isReady: Bool { model != nil && (!idle.isEmpty || !slots.isEmpty) }
    func hasActiveStreams() -> Bool { !slots.isEmpty }
    func isInstalled() -> Bool { model != nil || (try? asset.verified(modelURL)) == true }
    /// Delete only this profile's verified GGUF, never shared diarization
    /// weights or another model's files. An active session or download vetoes
    /// removal; the UI refuses deleting the currently selected speech model.
    func removeInstalledModel() throws {
        guard asset.isSpeech else {
            throw SuperflowError.invalidState("Speaker separation is not a speech model")
        }
        guard slots.isEmpty, installation == nil else {
            throw SuperflowError.invalidState("Model is in use or downloading")
        }
        idle.removeAll()
        model = nil
        guard FileManager.default.fileExists(atPath: modelURL.path) else { return }
        try FileManager.default.removeItem(at: modelURL)
        let receipt = modelURL.appendingPathExtension("verified.json")
        if FileManager.default.fileExists(atPath: receipt.path) {
            try FileManager.default.removeItem(at: receipt)
        }
    }


    func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0)
        let startedGeneration = generation
        if !isInstalled() {
            let pending: Task<Void, Error>
            if let installation {
                pending = installation
            } else {
                let asset = asset
                let url = modelURL
                pending = Task { try await asset.install(at: url, progress: progress) }
                installation = pending
            }
            do {
                try await withTaskCancellationHandler {
                    try await pending.value
                } onCancel: {
                    pending.cancel()
                }
                try Task.checkCancellation()
                if generation == startedGeneration { installation = nil }
            } catch {
                if generation == startedGeneration { installation = nil }
                throw error
            }
        }
        guard generation == startedGeneration else { throw CancellationError() }
        try prime()
        progress(1)
    }

    func load() throws {
        guard model == nil else { return }
        guard isInstalled() else {
            throw SuperflowError.modelUnavailable("Download the audio.cpp model in Settings")
        }
        if registry == nil {
            var pointer: OpaquePointer?
            try Self.check(audiocpp_registry_create(nil, &pointer))
            guard let pointer else { throw SuperflowError.modelUnavailable("audio.cpp registry allocation failed") }
            registry = NativeHandle(pointer, kind: .registry)
        }
        let registryPointer = registry?.pointer
        let modelPath = modelURL.path
        let loaded = try asset.family.withCString { family in
            try modelPath.withCString { path in
                var loaded: OpaquePointer?
                var config = audiocpp_model_config(family_hint: family, config_id: nil,
                                                   weight_id: nil, model_spec_override: nil)
                try Self.check(audiocpp_model_load(registryPointer, path, &config, nil, &loaded))
                return loaded
            }
        }
        guard let loaded else { throw SuperflowError.modelUnavailable("audio.cpp model allocation failed") }
        model = NativeHandle(loaded, kind: .model)
        guard audiocpp_model_supports(model?.pointer, asset.task, "streaming") != 0 else {
            model = nil
            throw SuperflowError.modelUnavailable("The audio.cpp model does not support streaming")
        }
    }

    func prime() throws {
        try load()
        if idle.isEmpty && slots.isEmpty {
            let stream = try start(source: asset.isSpeech ? .mic : .system)
            close(id: stream.id)
            guard !idle.isEmpty else { throw SuperflowError.modelUnavailable("audio.cpp session preparation failed") }
        }
    }

    private func createSession() throws -> NativeHandle {
        let modelPointer = model?.pointer
        let task = asset.task
        let options = audiocpp_options_create()
        defer { audiocpp_options_free(options) }
        if asset == .speakers {
            guard let options else { throw SuperflowError.modelUnavailable("audio.cpp options allocation failed") }
            try Self.check(audiocpp_options_set(options, "nemotron_3_diar.latency_profile", "ultra_low"))
        }
        let backendName = AudioCppBackend.select()
        let session = try backendName.withCString { backend in
            var session: OpaquePointer?
            var config = audiocpp_backend_config(backend: backend, device: 0, threads: 4)
            try Self.check(audiocpp_session_create(modelPointer, task, "streaming", &config, options, &session))
            return session
        }
        guard let session else { throw SuperflowError.modelUnavailable("audio.cpp session allocation failed") }
        return NativeHandle(session, kind: .session)
    }

    /// Nemotron uses token lookahead. Qwen emits native partial deltas after
    /// bounded decoding windows; its upstream default is 30 seconds, which
    /// would make a dictation UI appear frozen. Keep the option family-specific.
    private func configureRequest(_ request: OpaquePointer) throws {
        if asset.isNemotron {
            try Self.check(audiocpp_request_set_option(request, "language", "en-US"))
            try Self.check(audiocpp_request_set_option(request, "lookahead_tokens", "3"))
        } else if asset == .qwenASR06B {
            try Self.check(audiocpp_request_set_option(request, "audio_chunk_duration_sec", "3"))
        }
    }

    func start(source: AudioSourceKind) throws -> AudioCppStream {
        guard slots.count < 2 else { throw SuperflowError.invalidState("audio.cpp has two active speech streams") }
        try load()
        let owner: NativeHandle
        if let cached = idle.popLast() { owner = cached }
        else { owner = try createSession() }
        guard let request = audiocpp_request_create() else {
            throw SuperflowError.modelUnavailable("audio.cpp request allocation failed")
        }
        defer { audiocpp_request_free(request) }
        try Self.check(audiocpp_request_set_audio(request, nil, 0, Int32(sampleRate), 1))
        try configureRequest(request)
        try Self.check(audiocpp_stream_start(owner.pointer, request))
        let id = UUID()
        let (events, continuation) = AsyncStream<RecognitionEvent>.makeStream(bufferingPolicy: .bufferingNewest(32))
        continuation.onTermination = { [weak self] _ in
            Task { await self?.cancel(id: id) }
        }
        slots[id] = Slot(handle: owner, source: source, continuation: continuation)
        return AudioCppStream(events: events, runtime: self, id: id)
    }

    func feed(_ chunk: AudioChunk, id: UUID) {
        guard var slot = slots[id] else { return }
        let streamStart = slot.start ?? chunk.startSample
        slot.start = streamStart
        slot.end = chunk.endSample
        let handle = slot.handle.pointer
        do {
            let event = try chunk.samples.withUnsafeBufferPointer { samples in
                var event: OpaquePointer?
                try Self.check(audiocpp_stream_push(handle, samples.baseAddress, samples.count,
                                                    Int32(sampleRate), 1, chunk.startSample - streamStart, &event))
                return event
            }
            if let event {
                consume(audiocpp_event_as_result(event), slot: &slot)
                audiocpp_event_free(event)
            }
            while true {
                var next: OpaquePointer?
                try Self.check(audiocpp_stream_next_event(slot.handle.pointer, &next))
                guard let next else { break }
                consume(audiocpp_event_as_result(next), slot: &slot)
                audiocpp_event_free(next)
            }
            if asset.isSpeech {
                let sum = chunk.samples.reduce(Float.zero) { $0 + $1 * $1 }
                let speech = !chunk.samples.isEmpty && (sum / Float(chunk.samples.count)).squareRoot() >= 0.0025
                slot.silenceSamples = speech ? 0 : slot.silenceSamples + chunk.samples.count
                let capped = slot.end - (slot.start ?? slot.end) >= Int64(sampleRate * 120)
                if capped || (!slot.text.isEmpty && slot.silenceSamples >= sampleRate * 3 / 5) {
                    try finalizeSpeech(&slot)
                    emit(.endpoint(slot.end), to: slot)
                    try Self.check(audiocpp_stream_reset(slot.handle.pointer))
                    guard let request = audiocpp_request_create() else {
                        throw SuperflowError.modelUnavailable("audio.cpp request allocation failed")
                    }
                    defer { audiocpp_request_free(request) }
                    try Self.check(audiocpp_request_set_audio(request, nil, 0, Int32(sampleRate), 1))
                    try configureRequest(request)
                    try Self.check(audiocpp_stream_start(slot.handle.pointer, request))
                    slot.text = ""
                    slot.start = nil
                    slot.silenceSamples = 0
                }
            }
            slots[id] = slot
        } catch {
            emit(.failure("audio.cpp streaming inference failed"), to: slot)
            close(id: id)
        }
    }

    func finish(id: UUID) {
        guard var slot = slots[id] else { return }
        defer { close(id: id) }
        do {
            if asset.isSpeech {
                try finalizeSpeech(&slot)
            } else {
                var result: OpaquePointer?
                defer { audiocpp_result_free(result) }
                try Self.check(audiocpp_stream_finish(slot.handle.pointer, &result))
                collectSpeakers(result)
            }
        } catch {
            emit(.failure("audio.cpp could not finalize the transcript"), to: slot)
        }
    }

    private func finalizeSpeech(_ slot: inout Slot) throws {
        guard slot.start != nil else { return }
        var result: OpaquePointer?
        defer { audiocpp_result_free(result) }
        try Self.check(audiocpp_stream_finish(slot.handle.pointer, &result))
        var text: UnsafePointer<CChar>?
        if audiocpp_result_text(result, &text, nil) == AUDIOCPP_OK, let text {
            let final = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
            if !final.isEmpty {
                emit(.committed(RawSegment(text: final,
                    startSample: slot.start ?? 0, endSample: slot.end, source: slot.source)), to: slot)
            }
        }
    }

    func speaker(atMs: Int) -> String? {
        let sample = Int64(atMs) * Int64(sampleRate) / 1_000
        return turns.last { $0.start <= sample && sample < $0.end }?.label
    }
    func resetSpeakers() { turns.removeAll(keepingCapacity: true) }
    func unload() {
        generation &+= 1
        for id in Array(slots.keys) { close(id: id) }
        installation?.cancel()
        installation = nil
        idle.removeAll()
        model = nil
    }
    func cancel(id: UUID) { close(id: id) }
    private func close(id: UUID) {
        guard let slot = slots.removeValue(forKey: id) else { return }
        slot.continuation.finish()
        if idle.count < 2, audiocpp_stream_reset(slot.handle.pointer) == AUDIOCPP_OK {
            idle.append(slot.handle)
        }
    }
    private func consume(_ result: OpaquePointer?, slot: inout Slot) {
        collectSpeakers(result)
        var text: UnsafePointer<CChar>?
        if audiocpp_result_text(result, &text, nil) == AUDIOCPP_OK, let text, asset.isSpeech {
            slot.text += String(cString: text)
            emit(.partial(slot.text), to: slot)
        }
    }
    private func collectSpeakers(_ result: OpaquePointer?) {
        guard asset == .speakers else { return }
        for index in 0..<audiocpp_result_speaker_turn_count(result) {
            var start: Int64 = 0
            var end: Int64 = 0
            var label: UnsafePointer<CChar>?
            if audiocpp_result_speaker_turn(result, index, &start, &end, &label, nil, nil) == AUDIOCPP_OK,
               let label {
                let native = String(cString: label)
                guard native.hasPrefix("speaker_"), let index = Int(native.dropFirst(8)),
                      (0..<8).contains(index) else { continue }
                turns.append(SpeakerTurn(start: start, end: end, label: "remote-\(index + 1)"))
            }
        }
    }
    private func emit(_ event: RecognitionEvent, to slot: Slot) {
        if case .dropped(.committed) = slot.continuation.yield(event) {
            slot.continuation.yield(.failure("Transcript processing fell behind; recover this recording from its saved audio"))
            slot.continuation.finish()
        }
    }
    private nonisolated static func check(_ status: audiocpp_status) throws {
        guard status == AUDIOCPP_OK else {
            throw SuperflowError.modelUnavailable("audio.cpp: " + String(cString: audiocpp_status_string(status)))
        }
    }
}

struct AudioCppStream: RecognitionStream {
    let events: AsyncStream<RecognitionEvent>
    let runtime: AudioCppRuntime
    let id: UUID
    func feed(_ chunk: AudioChunk) async { await runtime.feed(chunk, id: id) }
    func finish() async { await runtime.finish(id: id) }
}
