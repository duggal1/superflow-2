import Foundation
import OSLog
import SuperflowFeatureSettings
import SuperflowKernel

/// Launch is split in two: `launch()` publishes the window state immediately,
/// and this file owns everything that may take longer than a frame. The window
/// never waits for model loads, retention sweeps, or pipeline construction.
@MainActor
extension AppCoordinator {
    func startModelPreparation(environment: AppEnvironment, log: Logger) {
        Task {
            // ASR owns the GPU first. Both loads specialize Core ML graphs, and
            // overlapping them makes the encoder — the critical path to the
            // first dictation — wait behind cleanup. Cleanup only has to be
            // ready before the first Stop, which is always later than this.
            let started = DispatchTime.now().uptimeNanoseconds
            let ready = await environment.sessionEngine.prewarm()
            log.info("ASR prewarm: \((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000) ms; ready: \(ready)")
            let cleanupStarted = DispatchTime.now().uptimeNanoseconds
            let cleanupReady = await environment.prepareInstalledCleanupModel(compute: settings.cleanupCompute)
            log.info("Cleanup preparation: \((DispatchTime.now().uptimeNanoseconds - cleanupStarted) / 1_000_000) ms; ready: \(cleanupReady)")
        }
    }

    func finishLaunch(environment: AppEnvironment, launchStarted: UInt64, log: Logger) async {
        islandBridge?.setStoresTranscripts(!settings.noTranscriptStorage)
        applyIslandPrefs(settings)
        islandBridge?.start(events: sessionEventRelay.subscribe())
        islandBridge?.startMeetingEvents(meetingEventRelay.subscribe(), engine: environment.meetingEngine)
        startEventRelays()
        menuBarController.observe()
        islandController?.start()
        observePermissionChanges(environment.permissionGate)

        // The key must be live before the model finishes loading. This is a
        // cheap permission/tap setup and never waits for inference.
        await tryStartHotkeys()
        menuBarController.setRecoveryReady(false)

        Task { [weak self] in
            guard let self else { return }
            // Recovery needs the recognizer only when a take was interrupted
            // mid-recording. An ordinary launch must not sit behind a model load:
            // the dictation key works now, and recovery waits for the same
            // serialized warm-up in the background.
            let pending = (try? await environment.database.unfinishedSessions()) ?? []
            guard !pending.isEmpty else {
                self.menuBarController.setRecoveryReady(true)
                log.info("Recovery gate opened after \((DispatchTime.now().uptimeNanoseconds - launchStarted) / 1_000_000) ms; nothing to recover")
                if self.settings.onboardingComplete { _ = await environment.sessionEngine.prewarm() }
                return
            }
            let modelReady = self.settings.onboardingComplete
                ? await environment.sessionEngine.prewarm() : false
            await self.recoverInterruptedSessions(environment: environment)
            self.menuBarController.setRecoveryReady(true)
            log.info("Recovery gate opened after \((DispatchTime.now().uptimeNanoseconds - launchStarted) / 1_000_000) ms; model ready: \(modelReady)")
        }

        Task { [weak self] in
            guard let self else { return }
            await self.performLaunchMaintenance(environment: environment)
        }

        if settings.onboardingComplete {
            // Without Accessibility the OS silently drops every synthetic
            // paste, so a finished dictation looks like nothing happened.
            Task { await self.requestAccessibilityForPaste() }
        }
        if settings.speechEnhancementEnabled {
            modelsModel?.download(ModelsViewModel.enhancementID)
            Task { [weak self] in
                do { try await environment.recognizer.prepareVoiceActivity() }
                catch { self?.menuBarController.publishError("Speech detection: \(error.localizedDescription)") }
            }
        }
    }

    /// Storage maintenance and pipeline construction are invisible to launch.
    /// They update the live engines before the owner has finished their first
    /// sentence, without delaying the dashboard or the dictation key.
    func performLaunchMaintenance(environment: AppEnvironment) async {
        await environment.transcripts.setNoTranscriptStorage(settings.noTranscriptStorage)
        await purgeExpiredTranscripts()
        await sweepAudioArchive()
        scheduleRetentionPurge()
        await environment.practiceRunner.update(profile: settings.asrProfile)
        await refreshPipeline()
        await islandBridge?.refreshLastTranscript()
    }
}
