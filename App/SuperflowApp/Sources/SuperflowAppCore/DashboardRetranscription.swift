import Foundation
import SuperflowKernel
import SuperflowPorts

@MainActor
enum DashboardRetranscription {
    static func transcribe(_ url: URL, environment: AppEnvironment) async throws -> (raw: String, cleaned: String) {
        let settings = await environment.settingsStore.load()
        guard !settings.noTranscriptStorage else { throw SuperflowError.invalidState("Transcript storage is disabled.") }
        try await environment.recognizer.warmUp(profile: settings.asrProfile)
        let stream = try await environment.recognizer.makeStream(profile: settings.asrProfile, source: .mic)
        let collected = Task { () throws -> String in
            var pieces: [String] = []
            for await event in stream.events {
                try Task.checkCancellation()
                switch event {
                case .committed(let segment): pieces.append(segment.text)
                case .failure(let message): throw SuperflowError.audioFailure(message)
                case .partial, .endpoint: break
                }
            }
            return pieces.joined(separator: " ")
        }
        do {
            var reader = try DashboardAudioReader(url: url)
            while let chunk = try reader.next() {
                try Task.checkCancellation()
                await stream.feed(chunk)
            }
            await stream.finish()
            let raw = try await collected.value
            let pipeline = await environment.makePipeline(settings: settings)
            let result = await pipeline.run(raw, context: TextContext(interactive: false, settings: settings))
            return (raw, result.text)
        } catch {
            collected.cancel()
            await stream.finish()
            _ = try? await collected.value
            throw error
        }
    }
}
