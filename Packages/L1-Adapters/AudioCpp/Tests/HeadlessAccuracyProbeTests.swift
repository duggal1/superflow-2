import Foundation
import SuperflowAudioCpp
import SuperflowKernel
import Testing

/// Headless acoustic probe. Synthesizes read-aloud technical speech, runs the
/// production streaming recognizer, and writes raw ASR text to disk. No UI,
/// no microphone, no network. Enable with SUPERFLOW_HEADLESS_PROBE=1.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SUPERFLOW_HEADLESS_PROBE"] == "1"))
func headlessASRAccuracyProbe() async throws {
    let output = ProcessInfo.processInfo.environment["SUPERFLOW_DIAG_OUT"]
        ?? "/private/var/folders/ct/cwpf7vpn059fkp932tq9zm4m0000gn/T/opencode/asr-probe.txt"
    let root = AudioCppTestModels.repositoryRoot
    try await AudioCppTestModels.shared.prepareSpeech()
    let recognizer = AudioCppRecognizer(modelCacheRoot: root.appendingPathComponent(".models/audio-cpp"))
    try await recognizer.warmUp(profile: ModelProfile.default.id)

    let work = FileManager.default.temporaryDirectory.appendingPathComponent("superflow-asr-probe-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work) }

    let probes = [
        "The Redis cache invalidation is broken.",
        "Check the Open Telemetry traces before the release.",
        "We deploy to Kubernetes every afternoon.",
        "OAuth two point zero returned a 503 error.",
        "The CI CD pipeline failed on the last commit.",
        "Time to first token matters more than tokens per second.",
        "The intermittent failures are in the Metal GPU path.",
        "Evaluate Metal GPU utilization and model accuracy.",
        "Why did the queue stall during token generation?",
        "Please ensure the dashboard shows the right number.",
    ]

    var report = "model=\(ModelProfile.default.id)\n"
    for (index, phrase) in probes.enumerated() {
        let aiff = work.appendingPathComponent("p\(index).aiff")
        let wav = work.appendingPathComponent("p\(index).wav")
        try run("/usr/bin/say", ["-v", "Alex", "-o", aiff.path, phrase])
        try run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff.path, wav.path])
        let samples = try decodeWav(wav)
        let stream = try await recognizer.makeStream(profile: ModelProfile.default.id, source: .mic)
        let collector = Task {
            var commits: [String] = []
            var partials: [String] = []
            for await event in stream.events {
                switch event {
                case let .committed(segment): commits.append(segment.text)
                case let .partial(text): partials.append(text)
                default: break
                }
            }
            return (commits, partials)
        }
        for start in stride(from: 0, to: samples.count, by: 5_120) {
            let end = min(samples.count, start + 5_120)
            await stream.feed(AudioChunk(samples: Array(samples[start..<end]),
                                         startSample: Int64(start), source: .mic))
        }
        await stream.finish()
        let (commits, partials) = await collector.value
        report += "[\(index)] REF: \(phrase)\n"
        report += "[\(index)] RAW: \(commits.joined(separator: " "))\n"
        report += "[\(index)] PARTIALS: \(partials.count)\n"
    }
    await recognizer.unload()
    try report.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
}

/// Forced-pause probe: does the 600 ms endpoint / chunk cadence mangle words
/// at silence boundaries? Same text, three pause lengths and three feed sizes.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SUPERFLOW_HEADLESS_PROBE"] == "1"))
func headlessBoundaryPauseProbe() async throws {
    let output = ProcessInfo.processInfo.environment["SUPERFLOW_BOUNDARY_OUT"]
        ?? "/private/var/folders/ct/cwpf7vpn059fkp932tq9zm4m0000gn/T/opencode/boundary-probe.txt"
    let root = AudioCppTestModels.repositoryRoot
    try await AudioCppTestModels.shared.prepareSpeech()
    let recognizer = AudioCppRecognizer(modelCacheRoot: root.appendingPathComponent(".models/audio-cpp"))
    try await recognizer.warmUp(profile: ModelProfile.default.id)
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("superflow-boundary-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work) }

    let phrases = [
        ("phrase-pause", "Analyze Open Telemetry [[slnc 900]] but token generation stalled [[slnc 900]] evaluate Metal GPU utilization and model accuracy"),
        ("mid-word-pause", "Time to first to[[slnc 900]]ken matters more than tokens per second"),
        ("no-pause", "Analyze Open Telemetry but token generation stalled evaluate Metal GPU utilization and model accuracy"),
    ]
    var report = ""
    for (label, phrase) in phrases {
        let aiff = work.appendingPathComponent("\(label).aiff")
        let wav = work.appendingPathComponent("\(label).wav")
        try run("/usr/bin/say", ["-v", "Alex", "-o", aiff.path, phrase])
        try run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff.path, wav.path])
        let samples = try decodeWav(wav)
        for cadence in [512, 5_120] {
            let stream = try await recognizer.makeStream(profile: ModelProfile.default.id, source: .mic)
            let collector = Task {
                var commits: [String] = []
                for await event in stream.events { if case let .committed(s) = event { commits.append(s.text) } }
                return commits
            }
            for start in stride(from: 0, to: samples.count, by: cadence) {
                let end = min(samples.count, start + cadence)
                await stream.feed(AudioChunk(samples: Array(samples[start..<end]),
                                             startSample: Int64(start), source: .mic))
            }
            await stream.finish()
            let commits = await collector.value
            report += "\(label) cadence=\(cadence) segments=\(commits.count)\n"
            for (index, commit) in commits.enumerated() { report += "  [\(index)] \(commit)\n" }
        }
    }
    await recognizer.unload()
    try report.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
}

private func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = nil
    process.standardError = nil
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "probe", code: Int(process.terminationStatus), userInfo: nil)
    }
}

private func decodeWav(_ url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    var offset = 12
    while offset + 8 <= data.count {
        let length = data.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))) }
        let end = offset + 8 + length
        guard end <= data.count else { break }
        if String(decoding: data[offset..<offset + 4], as: UTF8.self) == "data" {
            return stride(from: offset + 8, to: end - 1, by: 2).map { index in
                data.withUnsafeBytes { Float(Int16(littleEndian: $0.loadUnaligned(fromByteOffset: index, as: Int16.self))) / 32_768 }
            }
        }
        offset = end + length % 2
    }
    return []
}
