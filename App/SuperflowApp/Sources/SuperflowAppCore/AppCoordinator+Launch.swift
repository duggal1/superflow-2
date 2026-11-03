import Foundation
import OSLog
import SuperflowFeatureSettings
import SuperflowKernel

/// Launch is split in two: `launch()` publishes the window state immediately,
/// and this file owns everything that may take longer than a frame.
@MainActor
extension AppCoordinator {
    func startModelPreparation(environment: AppEnvironment, log: Logger) {
        Task { [weak self] in
            guard let self else { return }

            let asrStarted = DispatchTime.now().uptimeNanoseconds
            let asrReady = await environment.sessionEngine.prewarm()
            log.info("ASR prewarm: \((DispatchTime.now().uptimeNanoseconds - asrStarted) / 1_000_000) ms; ready: \(asrReady)")

            if self.settings.speechEnhancementEnabled {
                self.modelsModel?.download(ModelsViewModel.enhancementID)
            }

            let cleanupStarted = DispatchTime.now().uptimeNanoseconds
            let ready = await environment.prepareInstalledCleanupModel(compute: self.settings.cleanupCompute)
            let cleanupMs = (DispatchTime.now().uptimeNanoseconds - cleanupStarted) / 1_000_000
            log.info("Cleanup preparation: \(cleanupMs) ms; ready: \(ready)")
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
