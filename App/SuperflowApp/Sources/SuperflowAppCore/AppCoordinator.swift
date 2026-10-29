import AppKit
import Foundation
import OSLog
import SuperflowDesignSystem
import SuperflowFeatureDashboard
import SuperflowFeatureDictionary
import SuperflowFeatureHistory
import SuperflowFeatureIsland
import SuperflowFeatureMeetings
import SuperflowFeatureOnboarding
import SuperflowFeatureSettings
import SuperflowFeatureShortcuts
import SuperflowGestureKit
import SuperflowKernel
import SuperflowMeetingEngine
import SuperflowPorts
import SuperflowRecoveryEngine
import SuperflowSessionEngine
import SuperflowStorageSQLite
import SuperflowUIComponents
import SwiftUI
@MainActor
public final class AppCoordinator: ObservableObject {
    @Published public private(set) var settings = AppSettings.default
    @Published public private(set) var isLoaded = false
    @Published public private(set) var startupError: String? = nil
    @Published public private(set) var recoveryNotice: String?
    @Published public private(set) var recoveredTranscript: String?
    @Published public internal(set) var isCommandPalettePresented = false

    public let environment: AppEnvironment?
    public let themeStore: ThemeStore
    public let mainWindowController: MainWindowController
    public let menuBarController: MenuBarController
    public let islandController: IslandController?
    let islandBridge: IslandBridge?

    public lazy var commandPaletteModel = AppCommandPalette.make(
        onSelectSection: { [weak self] in self?.mainWindowController.show($0) },
        onToggleDictation: { [weak self] in
            guard let self else { return }
            Task { await self.menuBarController.toggleDictation() }
        },
        onToggleMeeting: { [weak self] in
            guard let self else { return }
            Task { await self.menuBarController.toggleMeeting() }
        },
        onQuit: { [weak self] in
            guard let self else { return }
            Task { await self.menuBarController.quit() }
        }
    )

    private var didLaunch = false
    // Shared with `AppCoordinator+Input.swift`, which owns the hotkey and permission wiring.
    var gesture = GestureRecognizer()
    var hotkeyTask: Task<Void, Never>?
    var gestureTimerTask: Task<Void, Never>?
    private var sessionRelayTask: Task<Void, Never>?
    private var meetingRelayTask: Task<Void, Never>?
    private var retentionTask: Task<Void, Never>?
    var permissionTask: Task<Void, Never>?
    private let sessionEventRelay = EngineEventRelay<SessionEvent>()
    private let meetingEventRelay = EngineEventRelay<MeetingEvent>()

    public lazy var dashboardModel: DashboardViewModel? = {
        guard let environment else { return nil }
        return DashboardViewModel(repository: environment.transcripts, settings: settings)
    }()

    public lazy var historyModel: HistoryViewModel? = makeHistoryModel()

    public lazy var dictionaryModel: DictionaryViewModel? = {
        guard let environment else { return nil }
        return DictionaryViewModel(repository: environment.libraryRepository) { [weak self] in
            Task { await self?.refreshPipeline() }
        }
    }()

    public lazy var shortcutsModel: ShortcutsViewModel? = {
        guard let environment else { return nil }
        return ShortcutsViewModel(repository: environment.libraryRepository) { [weak self] in
            Task { await self?.refreshPipeline() }
        }
    }()

    public lazy var meetingsModel: MeetingsViewModel? = {
        guard let environment else { return nil }
        return MeetingsViewModel(engine: environment.meetingEngine,
                                 repository: environment.transcripts,
                                 inserter: environment.textInserter,
                                 events: meetingEventRelay.subscribe())
    }()

    public lazy var modelsModel: ModelsViewModel? = {
        guard let environment else { return nil }
        return ModelsViewModel(models: environment.modelProvider,
                               asrModels: environment.recognizer,
                               diarizer: environment.diarizer,
                               asrProfile: settings.asrProfile,
                               enhancer: environment.speechEnhancer,
                               enhancementEnabled: { [weak self] in self?.settings.speechEnhancementEnabled ?? true },
                               cleanupEnabled: { [weak self] in self?.settings.cleanupEnabled ?? true })
    }()

    public lazy var settingsModel: SettingsViewModel? = {
        guard let environment else { return nil }
        return SettingsViewModel(
            store: environment.settingsStore,
            models: environment.modelProvider,
            asrModels: environment.recognizer,
            diarizer: environment.diarizer,
            enhancer: environment.speechEnhancer,
            launchAtLogin: environment.launchAtLogin,
            diagnostics: environment.diagnostics,
            thirdPartyNotices: environment.thirdPartyNotices,
            initial: settings,
            onCleanupModelReady: { [weak self] in
                Task { @MainActor in await self?.prepareCleanupModel() }
            }
        ) { [weak self] updated in
            Task { await self?.applySettings(updated) }
        }
    }()

    public lazy var onboardingModel: OnboardingViewModel? = {
        guard let environment else { return nil }
        return OnboardingViewModel(
            permissions: environment.permissionGate,
            globe: environment.globeKeyProbe,
            models: environment.recognizer,
            cleanupModels: environment.modelProvider,
            settingsStore: environment.settingsStore,
            practice: environment.practiceRunner,
            initial: settings
        ) { [weak self] updated in
            Task { await self?.completeOnboarding(updated) }
        }
    }()

    public init(applicationSupportDirectory: URL? = nil) {
        let mainWindow = MainWindowController()
        let environment: AppEnvironment?
        let startupError: String?
        do {
            environment = try AppEnvironment(applicationSupportDirectory: applicationSupportDirectory)
            startupError = nil
        } catch {
            environment = nil
            if let storage = error as? SQLiteError, storage.isDiskFull {
                startupError = """
                Superflow needs free disk space before it can open your library. \
                Free some space, then choose Try again. Your existing transcripts are untouched.
                """
            } else {
                startupError = "Superflow could not open its local database. \(error.localizedDescription)"
            }
        }
        self.environment = environment
        self.startupError = startupError
        themeStore = ThemeStore()
        mainWindowController = mainWindow

        let menu = MenuBarController(
            environment: environment,
            mainWindow: mainWindow,
            sessionEvents: sessionEventRelay.subscribe(),
            meetingEvents: meetingEventRelay.subscribe()
        )
        menuBarController = menu
        if let environment {
            let bridge = IslandBridge(transcripts: environment.transcripts)
            let islandModel = IslandModel(feed: bridge.feed, geometry: Self.initialGeometry())
            islandBridge = bridge
            islandController = IslandController(model: islandModel)
            configureIslandActions(islandModel, environment: environment)
        } else {
            islandBridge = nil
            islandController = nil
        }
    }

    /// The Island starts at the notch display, or wherever the pointer is if the
    /// Mac has no notch. `IslandController` re-seats it on every display change.
    private static func initialGeometry() -> NotchGeometry {
        if let screen = IslandScreens.home ?? IslandScreens.active {
            return NotchGeometry(screen: screen)
        }
        return NotchGeometry(frame: .zero, safeTop: 0, leftWidth: nil, rightWidth: nil, scale: 2)
    }
    public func launch() async {
        guard !didLaunch else { return }
        let launchStarted = DispatchTime.now().uptimeNanoseconds
        let launchLog = Logger(subsystem: "com.superflow.app", category: "ModelWarmup")
        didLaunch = true
        StaleDefaults.removeIslandLegacy()
        guard let environment else {
            isLoaded = true
            return
        }

        settings = await environment.settingsStore.load()
        // Onboarding is asked once. If the stored row lost the flag (fresh database,
        // quarantined file, a write that never landed) but the owner already finished,
        // restore it instead of sending them through setup again.
        if settings.onboardingComplete {
            OnboardingCheckpoint.markComplete()
        } else if OnboardingCheckpoint.isComplete() {
            settings.onboardingComplete = true
            await environment.settingsStore.save(settings)
        }
        // Fn is Superflow's dictation key only while it owns dictation, so put the Globe
        // binding in the Do Nothing state first. A different key leaves the Globe alone.
        if settings.dictationKey == .fn { environment.claimFunctionKey() }
        themeStore.mode = settings.theme
        islandBridge?.setStoresTranscripts(!settings.noTranscriptStorage)
        applyIslandPrefs(settings)
        await environment.transcripts.setNoTranscriptStorage(settings.noTranscriptStorage)
        await purgeExpiredTranscripts()
        await sweepAudioArchive()
        scheduleRetentionPurge()
        await environment.practiceRunner.update(profile: settings.asrProfile)
        gesture.update(config: settings.gesture)
        await refreshPipeline()
        islandBridge?.start(events: sessionEventRelay.subscribe())
        islandBridge?.startMeetingEvents(meetingEventRelay.subscribe(), engine: environment.meetingEngine)
        startEventRelays()
        menuBarController.observe()
        islandController?.start()
        Task { await islandBridge?.refreshLastTranscript() }
        observePermissionChanges(environment.permissionGate)
        menuBarController.setRecoveryReady(false)
        let shouldWarmModels = settings.onboardingComplete
        // Fn has to be live before the model loads. Installing the tap needs no model,
        // and doing it after the warm-up meant the key did nothing for the whole load
        // while the status read "Warming up".
        Task { [weak self] in
            guard let self else { return }
            await self.tryStartHotkeys()
            // Order matters: `RecoveryEngine` calls `makeStream`, which requires a
            // prepared profile, so the model load has to finish first. The hotkeys are
            // already installed, so a press in this window is answered instead of lost.
            let modelReady = shouldWarmModels ? await environment.sessionEngine.warmUp() : false
            await self.recoverInterruptedSessions(environment: environment)
            self.menuBarController.setRecoveryReady(true)
            launchLog.info("Recovery gate opened after \((DispatchTime.now().uptimeNanoseconds - launchStarted) / 1_000_000) ms; model ready: \(modelReady)")
        }
        Task {
            let started = DispatchTime.now().uptimeNanoseconds
            let ready = await environment.prepareInstalledCleanupModel(compute: settings.cleanupCompute)
            launchLog.info("Cleanup preparation: \((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000) ms; ready: \(ready)")
        }
        if settings.speechEnhancementEnabled {
            modelsModel?.download(ModelsViewModel.enhancementID)
            Task { [weak self] in
                do { try await environment.recognizer.prepareVoiceActivity() }
                catch { self?.menuBarController.publishError("Speech detection: \(error.localizedDescription)") }
            }
        }
        isLoaded = true
        launchLog.info("UI initialization: \((DispatchTime.now().uptimeNanoseconds - launchStarted) / 1_000_000) ms")
    }

    public func copyRecoveredTranscript() {
        guard let recoveredTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recoveredTranscript, forType: .string)
        recoveryNotice = "Recovered transcript copied to the clipboard."
    }

    public func refreshPipeline() async {
        guard let environment else { return }
        let pipeline = await environment.makePipeline(settings: settings)
        await environment.sessionEngine.update(pipeline: pipeline, settings: settings)
        await environment.meetingEngine.update(pipeline: pipeline, settings: settings)
    }

    public func applySettings(_ updated: AppSettings) async {
        let enhancementTurnedOn = !settings.speechEnhancementEnabled && updated.speechEnhancementEnabled
        let retentionChanged = settings.retentionDays != updated.retentionDays
        let cleanupComputeChanged = settings.cleanupCompute != updated.cleanupCompute
        settings = updated
        themeStore.mode = updated.theme
        islandBridge?.setStoresTranscripts(!updated.noTranscriptStorage)
        applyIslandPrefs(updated)
        guard let environment else { return }
        if retentionChanged { await purgeExpiredTranscripts() }
        await environment.transcripts.setNoTranscriptStorage(updated.noTranscriptStorage)
        await environment.practiceRunner.update(profile: updated.asrProfile)
        // A key change has to reach the live tap even when it is already running.
        await environment.hotkeySource.setDictationKey(updated.dictationKey)
        await environment.refreshFunctionKeySuppression(for: updated.dictationKey)
        gesture.update(config: updated.gesture)
        dashboardModel?.update(settings: updated)
        await refreshPipeline()
        await tryStartHotkeys()
        // The cleanup model is already resident at this point, so switching
        // CPU/GPU has to re-place its weights rather than wait for a relaunch.
        if cleanupComputeChanged { await prepareCleanupModel() }
        if enhancementTurnedOn {
            modelsModel?.download(ModelsViewModel.enhancementID)
            Task { [weak self] in
                do { try await environment.recognizer.prepareVoiceActivity() }
                catch { self?.menuBarController.publishError("Speech detection: \(error.localizedDescription)") }
            }
        }
        if updated.onboardingComplete, await !environment.recognizer.isReady {
            Task { _ = await environment.sessionEngine.warmUp() }
        }
    }

    public func completeOnboarding(_ updated: AppSettings) async {
        OnboardingCheckpoint.markComplete()
        await applySettings(updated)
        mainWindowController.show(.dashboard)
    }

    /// The two Island switches are mirrored, not stored, in the model. Settings
    /// pushes them on load and on every save, so the notch and the window agree.
    private func applyIslandPrefs(_ settings: AppSettings) {
        islandController?.model.configure(
            IslandPrefs(alwaysOn: settings.islandAlwaysOn, liveText: settings.islandLiveText)
        )
    }

    private func prepareCleanupModel() async {
        guard let environment else { return }
        _ = await environment.prepareInstalledCleanupModel(compute: settings.cleanupCompute)
    }

    private func recoverInterruptedSessions(environment: AppEnvironment) async {
        let engine = await environment.makeRecoveryEngine(settings: settings)
        let report = await engine.recover()
        if report.hasRecoveredText {
            recoveredTranscript = report.recoveredTranscripts.map(\.text).joined(separator: "\n\n")
            let count = report.recoveredTranscripts.count
            recoveryNotice = "Recovered text from \(count) interrupted session\(count == 1 ? "" : "s")."
        } else if report.failed > 0 {
            recoveryNotice = "An interrupted session could not be recovered. Its audio journal was kept for retry."
        }
    }

    private func scheduleRetentionPurge() {
        retentionTask?.cancel()
        retentionTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(24 * 60 * 60))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.purgeExpiredTranscripts()
                await self?.sweepAudioArchive()
            }
        }
    }

    /// Removes clips past the retention setting, then clears the two columns for
    /// any row whose file is gone. Runs at launch and once a day.
    private func sweepAudioArchive() async {
        guard let environment, settings.keepAudio else { return }
        await environment.audioArchive.sweep(olderThanDays: settings.audioRetentionDays)
        guard settings.audioRetentionDays != nil else { return }
        guard let ids = try? await environment.database.sessionsWithAudio() else { return }
        for id in ids {
            let url = AudioArchiveLocation.url(for: id)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? await environment.database.clearAudio(session: id)
            }
        }
    }

    private func purgeExpiredTranscripts(now: Date = Date()) async {
        guard let environment, let retentionDays = settings.retentionDays, retentionDays > 0,
              let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now) else { return }
        do {
            let removed = try await environment.transcripts.purge(olderThan: cutoff)
            environment.metrics.event("storage.retention.purge", ["sessions": String(removed)])
        } catch {
            environment.metrics.event("storage.retention.purge.failed", [:])
        }
    }

    private func startEventRelays() {
        guard let environment else { return }
        if sessionRelayTask == nil {
            let events = environment.sessionEngine.events
            sessionRelayTask = Task { [weak self] in
                for await event in events {
                    guard let self else { return }
                    self.sessionEventRelay.publish(event)
                }
            }
        }
        if meetingRelayTask == nil {
            let events = environment.meetingEngine.events
            meetingRelayTask = Task { [weak self] in
                for await event in events {
                    guard let self else { return }
                    self.meetingEventRelay.publish(event)
                }
            }
        }
    }

}
