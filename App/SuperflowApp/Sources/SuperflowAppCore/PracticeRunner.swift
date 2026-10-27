import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowFeatureOnboarding

public actor PracticeRunner: PracticeDictation {
    private let audio: any AudioSource
    private let recognizer: any SpeechRecognizer
    private var profile: String
    private var activeStream: (any RecognitionStream)?

    public init(audio: any AudioSource, recognizer: any SpeechRecognizer,
                profile: String = ModelProfile.parakeetEOU120M.id) {
        self.audio = audio
        self.recognizer = recognizer
        self.profile = profile
    }

    public func update(profile: String) {
        self.profile = profile
    }

    public func transcribe() async throws -> String {
        let selectedProfile = profile
        if await !recognizer.isReady {
            try await recognizer.warmUp(profile: selectedProfile)
        }

        let streams = try await audio.start()
        do {
            let recognition = try await recognizer.makeStream(profile: selectedProfile, source: .mic)
            activeStream = recognition
            let sampleTask = Task {
                for await chunk in streams.samples {
                    await recognition.feed(chunk)
                }
            }

            var committed: [String] = []
            var partial = ""
            var hasEndpoint = false
            for await event in recognition.events {
                switch event {
                case .partial(let text):
                    partial = text
                case .committed(let segment):
                    if !segment.text.isEmpty { committed.append(segment.text) }
                    partial = ""
                case .endpoint:
                    guard !committed.isEmpty || !partial.isEmpty else { continue }
                    hasEndpoint = true
                    await audio.stop()
                    await sampleTask.value
                    await recognition.finish()
                case .failure(let message):
                    throw SuperflowError.audioFailure(message)
                }
            }

            if !partial.isEmpty { committed.append(partial) }
            activeStream = nil
            if !hasEndpoint, committed.isEmpty {
                throw SuperflowError.audioFailure("No speech was captured.")
            }
            return committed.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            await audio.stop()
            await activeStream?.finish()
            activeStream = nil
            throw error
        }
    }

    public func cancel() async {
        await audio.stop()
        await activeStream?.finish()
        activeStream = nil
    }
}
