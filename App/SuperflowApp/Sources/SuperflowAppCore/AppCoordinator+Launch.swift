import Foundation
import OSLog
import SuperflowFeatureSettings
import SuperflowKernel

/// Launch is split in two: `launch()` publishes the window state immediately,
/// and this file owns everything that may take longer than a frame.
@MainActor
extension AppCoordinator {
    func startModelPreparation(environment: AppEnvironment, log: Logger) {
        // ASR is prewarmed first so a second model cannot starve streaming.
        // S1-mini is then prepared eagerly through the same serialized path,
        // so the first dictation never pays a cold load. `prepare()` joins an
        // in-flight warm-up, so concurrent launch/settings/first-key calls
        // cannot double-load the model.
        Task(priority: .utility) {
            let started = DispatchTime.now().uptimeNanoseconds
            let asr = await environment.sessionEngine.prewarm()
            let cleanup = settings.cleanupEnabled
                ? await environment.prepareInstalledCleanupModel()
                : false
            let elapsed = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            log.info("Model preparation: \(elapsed) ms; ASR ready: \(asr); cleanup ready: \(cleanup)")
        }
    }

    func finishLaunch(environment: AppEnvironment, launchStarted: UInt64, log: Logger) async {
        islandBridge?.setStoresTranscripts(!settings.noTranscriptStorage)
        applyIslandPrefs(settings)
        islandBridge?.start(events: sessionEventRelay.subscribe())
        // Honest stealth status is an app-launch concern, not a side effect of
        // starting the bridge's event pump: surfacing it in a one-off bridge
        // (as tests do) must not inject a notice into an unrelated session.
        islandBridge?.announceStealthStatus()
        islandBridge?.startMeetingEvents(meetingEventRelay.subscribe(), engine: environment.meetingEngine)
        startEventRelays()
        menuBarController.observe()
        islandController?.start()
        observePermissionChanges(environment.permissionGate)

        await tryStartHotkeys()
        menuBarController.setRecoveryReady(false)

        Task { [weak self] in
            guard let self else { return }
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
            Task { await self.requestAccessibilityForPaste() }
        }
    }

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
