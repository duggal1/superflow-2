@preconcurrency import DeepFilterNetCoreML
import Foundation
import SuperflowKernel
import SuperflowPorts

public actor DeepFilterNetEnhancer: SpeechEnhancer {
    private let store: DeepFilterNetModelStore
    private let directory: URL
    private var streamer: DeepFilterNetCoreMLStreamer?
    private var loading: Task<Void, Error>?
    private var resampler = EnhancementResampler()
    private var pending: [Float] = []
    private var inputCount = 0
    private var outputCount = 0

    public init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? base.appendingPathComponent("Superflow/Models/DeepFilterNet3", isDirectory: true)
        store = DeepFilterNetModelStore(directory: self.directory)
    }

    public func isAvailable() async -> Bool { await store.isAvailable() }

    public func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        try await store.ensure { progress($0 * 0.9) }
        try await load()
        progress(1)
    }

    private func load() async throws {
        if let loading { try await loading.value; return }
        guard streamer == nil else { return }
        let task = Task {
            let runtime = try await DeepFilterNetCoreMLStreamer.load(configuration: .init(
                variant: .deepFilterNet3, source: .local(directory), computeUnits: .cpuAndGPU))
            guard runtime.hopSize == 480, runtime.sampleRate == 48_000 else {
                throw SuperflowError.modelUnavailable("Unexpected DeepFilterNet 3 streaming format.")
            }
            for _ in 0..<10 { _ = try runtime.processHop([Float](repeating: 0, count: 480)) }
            runtime.reset()
            streamer = runtime
        }
        loading = task
        defer { loading = nil }
        try await task.value
    }

    public func begin() async throws {
        guard await store.isAvailable() else {
            throw SuperflowError.modelUnavailable("Download DeepFilterNet 3 in Models, or turn off noise suppression in Settings.")
        }
        try await load()
        reset()
    }

    public func process(_ samples: [Float]) throws -> [Float] {
        guard let streamer else { throw SuperflowError.invalidState("DeepFilterNet 3 is not prepared.") }
        inputCount += samples.count
        return try process48(resampler.upsample(samples), streamer: streamer)
    }

    private func process48(_ samples: [Float], streamer: DeepFilterNetCoreMLStreamer) throws -> [Float] {
        pending.append(contentsOf: samples)
        var enhanced: [Float] = []
        var consumed = 0
        while pending.count - consumed >= 480 {
            enhanced.append(contentsOf: try streamer.processHop(Array(pending[consumed..<(consumed + 480)])))
            consumed += 480
        }
        if consumed > 0 { pending.removeFirst(consumed) }
        let output = resampler.downsample(enhanced)
        let limited = Array(output.prefix(max(0, inputCount - outputCount)))
        outputCount += limited.count
        return limited
    }

    public func finish() throws -> [Float] {
        guard let streamer else { return [] }
        defer { reset() }
        // Flush both FIR delays and the model lookahead without counting padding as input.
        var output = try process48(resampler.upsample([Float](repeating: 0, count: 960)), streamer: streamer)
        let remaining = max(0, inputCount - outputCount)
        output.append(contentsOf: resampler.downsample(try streamer.flush()).prefix(remaining))
        return output
    }

    public func reset() {
        streamer?.reset()
        resampler = EnhancementResampler()
        pending.removeAll(keepingCapacity: true)
        inputCount = 0
        outputCount = 0
    }
}
