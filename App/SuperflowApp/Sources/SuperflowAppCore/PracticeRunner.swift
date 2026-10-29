import Foundation
import SuperflowFeatureOnboarding
import SuperflowKernel
import SuperflowPorts

/// The onboarding sandbox recogniser. It is the only capture path that writes into
/// a text field instead of pasting, and it is driven by the same key the owner
/// chooses in the last step: press starts the take, release ends it.
public actor PracticeRunner: PracticeDictation {
    private let audio: any AudioSource
    private let recognizer: any SpeechRecognizer
    private var profile: String
    private var activeStream: (any RecognitionStream)?
    private var sampleTask: Task<Void, Never>?
    private var committed: [String] = []
    private var partial = ""
    private var ending = false

    public init(audio: any AudioSource, recognizer: any SpeechRecognizer,
                profile: String = ModelProfile.default.id) {
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
            committed = []
            partial = ""
            ending = false
            let sample = Task {
                for await chunk in streams.samples {
                    await recognition.feed(chunk)
                }
            }
            sampleTask = sample

            // The stream stays open across segment rotations. The take ends when
            // the key comes up and `finish()` closes it; the text is assembled
            // once, below.
            for await event in recognition.events {
                switch event {
                case .partial(let text):
                    partial = text
                case .committed(let segment):
                    if !segment.text.isEmpty { committed.append(segment.text) }
                    partial = ""
                case .endpoint:
                    // Segment rotation, not the end of the take. The take ends when
                    // the key comes up and `finish()` closes the stream.
                    break
                case .failure(let message):
                    throw SuperflowError.audioFailure(message)
                }
            }

            activeStream = nil
            sampleTask = nil
            if !partial.isEmpty {
                committed.append(partial)
                partial = ""
            }
            let text = committed.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw SuperflowError.audioFailure("No speech was captured.")
            }
            return text
        } catch {
            await cancel()
            throw error
        }
    }

    /// Stops capture and flushes the recognizer, so the take that was just spoken
    /// is returned by the `transcribe()` call already in flight. Idempotent.
    public func finish() async {
        guard !ending else { return }
        ending = true
        await audio.stop()
        if let sampleTask {
            await sampleTask.value
        }
        sampleTask = nil
        await activeStream?.finish()
    }

    public func cancel() async {
        ending = true
        sampleTask?.cancel()
        sampleTask = nil
        await audio.stop()
        await activeStream?.finish()
        activeStream = nil
        committed = []
        partial = ""
    }
}
