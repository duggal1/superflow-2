import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI

extension OnboardingViewModel {
    // MARK: models

    public func checkModels() async {
        speechReady = await models.isAvailable(profileID: settings.asrProfile)
        await checkCleanupModel()
    }

    public func checkCleanupModel() async {
        guard let cleanupModels, cleanupWanted else {
            cleanupReady = false
            return
        }
        cleanupReady = await cleanupModels.llmModelURL() != nil
    }

    /// One primary control starts both downloads: speech first, cleanup after.
    public func downloadAll() async {
        await downloadSpeech()
        if cleanupWanted, cleanupModels != nil, !cleanupReady {
            await downloadCleanupModel()
        }
    }

    public func downloadSpeech() async {
        guard !isDownloadingSpeech else { return }
        isDownloadingSpeech = true
        speechError = nil
        speechProgress = 0
        speechTransfer = nil
        let meter = meterTransfer { [weak self] snapshot in self?.speechTransfer = snapshot }
        defer {
            meter.cancel()
            speechTransfer = nil
        }
        let token = UUID()
        speechToken = token
        do {
            try await models.prepare(profileID: settings.asrProfile) { [weak self] value in
                Task { @MainActor in
                    guard let self, self.speechToken == token else { return }
                    self.speechProgress = value
                }
            }
            speechReady = await models.isAvailable(profileID: settings.asrProfile)
            speechToken = UUID()
            speechProgress = nil
            toast.show("\(speechName) is ready.", style: .success)
        } catch {
            speechToken = UUID()
            speechProgress = nil
            speechError = error.localizedDescription
            toast.show("Could not download the speech model. \(error.localizedDescription)",
                       style: .error)
        }
        isDownloadingSpeech = false
    }

    /// Installs the S1-mini GGUF through the same verified manifest as every other
    /// model, then hands off to the composition root so llama.cpp can load it.
    public func downloadCleanupModel() async {
        guard let cleanupModels, !isDownloadingCleanup else { return }
        isDownloadingCleanup = true
        cleanupError = nil
        cleanupProgress = 0
        cleanupTransfer = nil
        let meter = meterTransfer { [weak self] snapshot in self?.cleanupTransfer = snapshot }
        defer {
            meter.cancel()
            cleanupTransfer = nil
        }
        let token = UUID()
        cleanupToken = token
        do {
            _ = try await cleanupModels.ensureLLM { [weak self] value in
                Task { @MainActor in
                    guard let self, self.cleanupToken == token else { return }
                    self.cleanupProgress = value
                }
            }
            cleanupReady = await cleanupModels.llmModelURL() != nil
            cleanupToken = UUID()
            cleanupProgress = nil
            toast.show("S1-mini cleanup is ready.", style: .success)
        } catch {
            cleanupToken = UUID()
            cleanupProgress = nil
            cleanupError = error.localizedDescription
            toast.show("Could not download the cleanup model. \(error.localizedDescription)",
                       style: .error)
        }
        isDownloadingCleanup = false
    }

    /// Polls the shared meter while a transfer runs. The transfer layer reports
    /// on its own queues; the screen only reads the latest reading.
    func meterTransfer(
        _ apply: @escaping @MainActor (TransferSnapshot?) -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            while !Task.isCancelled {
                apply(DownloadTelemetry.shared.snapshot())
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    public func setCleanupWanted(_ wanted: Bool) async {
        cleanupWanted = wanted
        await checkCleanupModel()
    }

    // MARK: practice

    public func startPractice() async {
        guard let practice, practiceReady, !isListening else { return }
        let token = UUID()
        practiceToken = token
        practiceText = ""
        practiceState = .listening
        do {
            let text = try await practice.transcribe()
            guard practiceToken == token else { return }
            practiceText = text
            practiceState = .done
        } catch {
            guard practiceToken == token else { return }
            practiceState = .failed(error.localizedDescription)
        }
    }

    /// Releasing the key ends the take: capture stops, the recognizer flushes, and
    /// `startPractice` returns the text. Harmless when nothing is recording.
    public func finishPractice() async {
        guard isListening else { return }
        await practice?.finish()
    }

    public func cancelPractice() {
        practiceToken = UUID()
        practiceState = .idle
        Task { await practice?.cancel() }
    }

    // MARK: finish

    @discardableResult
    public func finish() async -> Bool {
        guard !isFinishing else { return false }
        isFinishing = true
        defer { isFinishing = false }

        settings.onboardingComplete = true
        settings.dictationKey = dictationKey
        await settingsStore.save(settings)
        onFinish(settings)
        toast.show("Superflow is ready.", style: .success)
        return true
    }
}
