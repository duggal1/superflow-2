import Foundation
import SuperflowAudioCpp
import SuperflowKernel

actor AudioCppTestModels {
    static let shared = AudioCppTestModels()
    static let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../..", isDirectory: true).standardizedFileURL
    private static let cacheRoot = repositoryRoot.appendingPathComponent(".models/audio-cpp", isDirectory: true)

    private var speechPreparation: Task<Void, Error>?
    private var speakerPreparation: Task<Void, Error>?

    func prepareSpeech() async throws {
        let preparation: Task<Void, Error>
        if let speechPreparation {
            preparation = speechPreparation
        } else {
            let cacheRoot = Self.cacheRoot
            preparation = Task {
                let recognizer = AudioCppRecognizer(modelCacheRoot: cacheRoot)
                try await recognizer.prepare(profileID: ModelProfile.default.id) { _ in }
                await recognizer.unload()
            }
            speechPreparation = preparation
        }
        try await preparation.value
    }

    func prepareSpeakers() async throws {
        let preparation: Task<Void, Error>
        if let speakerPreparation {
            preparation = speakerPreparation
        } else {
            let cacheRoot = Self.cacheRoot
            preparation = Task {
                let diarizer = AudioCppDiarizer(cacheDirectory: cacheRoot)
                try await diarizer.prepare { _ in }
                await diarizer.unload()
            }
            speakerPreparation = preparation
        }
        try await preparation.value
    }
}
