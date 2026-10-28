import AVFoundation
import Darwin
import Foundation
import SuperflowASRFluidAudio
import SuperflowAudioCapture
import SuperflowAudioJournal
import SuperflowKernel
import SuperflowPorts
import SuperflowTextPipeline

@main
enum Superflowctl {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("superflowctl: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else { throw UsageError() }
        switch command {
        case "benchmark":
            try await RealModelBenchmark(arguments: arguments.dropFirst()).run()
        case "bench":
            try await RealModelSpeedBench(arguments: arguments.dropFirst()).run()
        case "transcribe":
            guard arguments.count == 2 else { throw UsageError() }
            try await transcribe(fileURL: URL(fileURLWithPath: arguments[1]).standardizedFileURL,
                                 profileID: ModelProfile.parakeetEOU120M.id)
        case "campaign":
            try await Campaign(arguments: arguments.dropFirst()).run()
        case "live":
            guard arguments.count <= 2 else { throw UsageError() }
            try await live(profileID: arguments.dropFirst().first ?? ModelProfile.parakeetEOU120M.id)
        case "help", "--help", "-h":
            print(UsageError.message)
        default:
            throw UsageError()
        }
    }

    private static func transcribe(fileURL: URL, profileID: String) async throws {
        let recognizer = FluidAudioRecognizer()
        try await prepare(recognizer, profileID: profileID)
        var reader = try AudioFileChunkReader(url: fileURL)
        let pipeline = makeTier0Pipeline()
        let journals = FileJournalStore()
        let session = SessionID()
        let writer = try await journals.openWriter(session: session, source: .mic)
        let stream: any RecognitionStream
        do {
            stream = try await recognizer.makeStream(profile: profileID, source: .mic)
        } catch {
            _ = await writer.close()
            await journals.delete(session: session)
            throw error
        }
        let printer = TranscriptPrinter(pipeline: pipeline)
        let events = Task { await printer.consume(stream.events) }

        do {
            while let chunk = try reader.next() {
                await writer.append(chunk)
                await stream.feed(chunk)
            }
            await stream.finish()
            await events.value
            let summary = await writer.close()
            await journals.delete(session: session)
            if summary.degraded {
                FileHandle.standardError.write(Data("Journal stopped after low disk space or an I/O error.\n".utf8))
            }
        } catch {
            await stream.finish()
            _ = await writer.close()
            await journals.delete(session: session)
            throw error
        }
    }

    private static func live(profileID: String) async throws {
        let recognizer = FluidAudioRecognizer()
        try await prepare(recognizer, profileID: profileID)
        let microphone = MicrophoneCapture()
        let journals = FileJournalStore()
        let session = SessionID()
        let writer = try await journals.openWriter(session: session, source: .mic)
        let recognition: any RecognitionStream
        do {
            recognition = try await recognizer.makeStream(profile: profileID, source: .mic)
        } catch {
            _ = await writer.close()
            await journals.delete(session: session)
            throw error
        }
        let streams: AudioStreams
        do {
            streams = try await microphone.start()
        } catch {
            await recognition.finish()
            _ = await writer.close()
            await journals.delete(session: session)
            throw error
        }
        let pipeline = makeTier0Pipeline()
        let printer = TranscriptPrinter(pipeline: pipeline)
        let outputTask = Task { await printer.consume(recognition.events) }
        let feedTask = Task {
            for await chunk in streams.samples {
                await writer.append(chunk)
                await recognition.feed(chunk)
            }
        }
        let audioEventsTask = Task {
            for await event in streams.events {
                switch event {
                case .routeChanged:
                    FileHandle.standardError.write(Data("Microphone route changed.\n".utf8))
                case .failed(let message):
                    FileHandle.standardError.write(Data("Microphone error: \(message)\n".utf8))
                case .permissionRevoked:
                    FileHandle.standardError.write(Data("Microphone permission was revoked.\n".utf8))
                case .stopped:
                    break
                }
            }
        }

        await waitForInterrupt()
        await microphone.stop()
        await feedTask.value
        await recognition.finish()
        await outputTask.value
        audioEventsTask.cancel()
        _ = await writer.close()
        await journals.delete(session: session)
    }

    private static func prepare(_ recognizer: FluidAudioRecognizer, profileID: String) async throws {
        guard FluidAudioCatalog.supports(profileID) else {
            throw SuperflowError.modelUnavailable("Unsupported ASR profile \(profileID)")
        }
        try await recognizer.prepare(profileID: profileID) { progress in
            let percent = Int(progress * 100)
            FileHandle.standardError.write(Data("Preparing ASR model: \(percent)%\r".utf8))
        }
        FileHandle.standardError.write(Data("\n".utf8))
    }

    private static func makeTier0Pipeline() -> TextPipeline {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        return TextPipelineBuilder.make(settings: settings)
    }

    private static func waitForInterrupt() async {
        await withCheckedContinuation { continuation in
            signal(SIGINT, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            source.setEventHandler {
                source.cancel()
                continuation.resume()
            }
            source.resume()
        }
    }
}

private actor TranscriptPrinter {
    private let pipeline: TextPipeline

    init(pipeline: TextPipeline) { self.pipeline = pipeline }

    func consume(_ events: AsyncStream<RecognitionEvent>) async {
        for await event in events {
            switch event {
            case .committed(let segment):
                let result = await pipeline.run(segment.text,
                                                context: TextContext(source: segment.source, interactive: false))
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                FileHandle.standardOutput.write(Data((text + "\n").utf8))
            case .failure(let message):
                FileHandle.standardError.write(Data("ASR error: \(message)\n".utf8))
            case .partial, .endpoint:
                break
            }
        }
    }
}

private struct UsageError: Error, LocalizedError {
    static let message = "Usage: superflowctl benchmark <audio-file> <profile-id> <model-cache-root> <pace-factor> [journal-root] | transcribe <audio-file> | live [profile-id]"
    var errorDescription: String? { Self.message }
}
