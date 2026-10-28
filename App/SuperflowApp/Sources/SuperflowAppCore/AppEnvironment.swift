import Foundation
import SuperflowASRFluidAudio
import SuperflowAudioCapture
import SuperflowAudioJournal
import SuperflowDiagnostics
import SuperflowDiarizationFluidAudio
import SuperflowGrammarHarper
import SuperflowHotkeyEngine
import SuperflowInferenceHelperProtocol
import SuperflowKernel
import SuperflowLLMCore
import SuperflowMeetingEngine
import SuperflowModelStore
import SuperflowPermissionsKit
import SuperflowPorts
import SuperflowProjectIndex
import SuperflowRecoveryEngine
import SuperflowSessionEngine
import SuperflowStorageSQLite
import SuperflowSystemAudioCapture
import SuperflowTextCleanup
import SuperflowTextInsertion
import SuperflowTextPipeline

@MainActor
public final class AppEnvironment {
    public let database: SQLiteStore
    public let transcripts: PrivacyRepository
    public let libraryRepository: any LibraryRepository
    public let settingsStore: any SettingsStore
    public let modelProvider: ModelStore
    public let recognizer: FluidAudioRecognizer
    public let diarizer: FluidAudioDiarizer
    public let llamaRuntime: XPCInferenceHelperRuntime
    public let llamaCleaner: LlamaCleaner
    public let microphone: MicrophoneCapture
    public let systemAudio: SystemAudioCapture
    public let journalStore: FileJournalStore
    public let audioArchive: AudioArchiveAdapter
    public let textInserter: SystemTextInserter
    public let sessionEngine: SessionEngine
    public let meetingEngine: MeetingEngine
    public let practiceRunner: PracticeRunner
    public let hotkeySource: HotkeyEngine
    public let permissionGate: SystemPermissionGate
    public let globeKeyProbe: UserDefaultsGlobeKeyProbe
    public let launchAtLogin: LaunchAtLoginService
    public let metrics: MetricsRing
    public let diagnostics: DiagnosticsExporter
    public let supportDirectory: URL
    public let thirdPartyNotices: String
    /// Explicitly selected project scope. Nil means cleanup is filename-only
    /// and no path is ever resolved.
    public private(set) var project: ProjectContext?

    public init(applicationSupportDirectory: URL? = nil,
                fileManager: FileManager = .default) throws {
        let supportDirectory: URL
        if let applicationSupportDirectory {
            supportDirectory = applicationSupportDirectory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            supportDirectory = base.appendingPathComponent("Superflow", isDirectory: true)
        }
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        let databaseURL = supportDirectory.appendingPathComponent("Superflow.sqlite")
        let database = try SQLiteStoreFactory.open(url: databaseURL, fileManager: fileManager)
        let modelProvider = try ModelStore(
            root: supportDirectory.appendingPathComponent("Models", isDirectory: true),
            fileManager: FileManager()
        )
        let metrics = MetricsRing()
        let recognizer = FluidAudioRecognizer(
            modelCacheRoot: supportDirectory.appendingPathComponent("Models/FluidAudio", isDirectory: true),
            fileManager: FileManager()
        )
        let diarizer = FluidAudioDiarizer(
            cacheDirectory: supportDirectory.appendingPathComponent("Models/FluidAudio/Diarization", isDirectory: true)
        )
        let llamaRuntime = XPCInferenceHelperRuntime()
        let llamaCleaner = LlamaCleaner(modelProvider: modelProvider, runtime: llamaRuntime)
        let microphone = MicrophoneCapture()
        let systemAudio = SystemAudioCapture()
        let journalStore = FileJournalStore(
            root: supportDirectory.appendingPathComponent("Journals", isDirectory: true),
            fileManager: FileManager()
        )
        let audioArchive = AudioArchiveAdapter(
            directory: supportDirectory.appendingPathComponent("Audio", isDirectory: true))
        let textInserter = SystemTextInserter()
        let pipeline = TextPipelineBuilder.make(settings: .default)

        self.database = database
        transcripts = PrivacyRepository(base: database)
        libraryRepository = database
        settingsStore = database
        self.modelProvider = modelProvider
        self.recognizer = recognizer
        self.diarizer = diarizer
        self.llamaRuntime = llamaRuntime
        self.llamaCleaner = llamaCleaner
        self.microphone = microphone
        self.systemAudio = systemAudio
        self.journalStore = journalStore
        self.audioArchive = audioArchive
        self.textInserter = textInserter
        self.metrics = metrics
        diagnostics = DiagnosticsExporter(metrics: metrics, databaseURL: databaseURL)
        permissionGate = SystemPermissionGate()
        globeKeyProbe = UserDefaultsGlobeKeyProbe()
        launchAtLogin = LaunchAtLoginService()
        hotkeySource = HotkeyEngine()
        self.supportDirectory = supportDirectory
        thirdPartyNotices = Self.loadThirdPartyNotices()
        practiceRunner = PracticeRunner(audio: MicrophoneCapture(), recognizer: recognizer)
        sessionEngine = SessionEngine(
            audio: microphone,
            recognizer: recognizer,
            pipeline: pipeline,
            repository: transcripts,
            journals: journalStore,
            inserter: textInserter,
            archive: audioArchive,
            metrics: metrics
        )
        meetingEngine = MeetingEngine(
            mic: microphone,
            system: systemAudio,
            recognizer: recognizer,
            diarizer: diarizer,
            pipeline: pipeline,
            repository: transcripts,
            journals: journalStore
        )
    }

    public func makePipeline(settings: AppSettings) async -> TextPipeline {
        let lexicon = (try? await libraryRepository.lexicon()) ?? []
        let shortcuts = (try? await libraryRepository.shortcuts()) ?? []
        let cleanup = CleanupService(
            cleaner: llamaCleaner,
            config: CleanupConfig(
                interactiveDeadlineMs: settings.interactiveDeadlineMs,
                backgroundDeadlineMs: settings.backgroundDeadlineMs,
                workers: settings.cleanupWorkers
            )
        )
        let linter: any HarperLinting
        #if canImport(HarperFFI)
        linter = HarperFFILinter()
        #else
        linter = UnavailableHarperLinter()
        #endif
        let grammar = HarperChecker(linter: linter)
        return TextPipelineBuilder.make(
            settings: settings,
            dependencies: TextPipelineDependencies(
                lexiconEntries: lexicon,
                shortcuts: shortcuts,
                cleaner: cleanup,
                grammarChecker: grammar,
                project: project
            )
        )
    }

    /// Builds a bounded project index off the main actor and applies it to both
    /// engines. Call this only from an explicit project selection or refresh;
    /// cleanup itself never walks the filesystem.
    @discardableResult
    public func selectProject(root: URL, isCoding: Bool) async -> ProjectContext? {
        let context = await Task.detached(priority: .userInitiated) {
            ProjectIndexer().build(root: root, isCoding: isCoding, approvedByUser: true)
        }.value
        project = context
        await sessionEngine.update(project: context)
        await meetingEngine.update(project: context)
        return context
    }

    public func clearProject() async {
        project = nil
        await sessionEngine.update(project: nil)
        await meetingEngine.update(project: nil)
    }

    public func makeRecoveryEngine(settings: AppSettings) async -> RecoveryEngine {
        let pipeline = await makePipeline(settings: settings)
        let project = self.project
        let cleaner: RecoveryCleaner = { text in
            let result = await pipeline.run(text, context: TextContext(settings: settings,
                                                                      project: project))
            return RecoveryCleaned(text: result.text, state: result.draft.cleanupState)
        }
        return RecoveryEngine(repository: transcripts, journals: journalStore, recognizer: recognizer,
                              keepJournals: settings.keepJournals, cleaner: cleaner)
    }

    /// Fn is Superflow's dictation key, and macOS shows Emoji & Symbols for the Globe key until
    /// `AppleFnUsageType` is written. Put that preference in the state the Keyboard pane calls
    /// Do Nothing. The system can keep the old binding until the next login, which is why the
    /// event tap also swallows the lone Fn press.
    public func claimFunctionKey() {
        GlobeKeyOwnership.enforceDoNothing()
    }

    /// Swallowing an event needs an active tap, so Fn suppression depends on Accessibility.
    /// Called before the hotkeys start and again whenever that grant changes.
    public func refreshFunctionKeySuppression() async {
        let canSwallow = await permissionGate.status(.accessibility) == .granted
        await hotkeySource.setFnSuppression(canSwallow)
    }

    public func prepareInstalledCleanupModel(compute: ModelCompute = .gpu) async -> Bool {
        guard await modelProvider.llmModelURL() != nil else { return false }
        do {
            try await llamaCleaner.prepare(compute: compute)
            return true
        } catch {
            metrics.event("cleanup.model.unavailable", ["reason": error.localizedDescription])
            return false
        }
    }

    private static func loadThirdPartyNotices() -> String {
        let names = ["README.md", "S1-mini-NOTICE.txt", "S1-mini-LICENSE.txt", "FluidAudio-LICENSE.txt", "llama.cpp-LICENSE.txt"]
        let directory = Bundle.module.resourceURL?.appendingPathComponent("ThirdPartyNotices", isDirectory: true)
        return names.compactMap { name -> String? in
            guard let directory else { return nil }
            return try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
        }.joined(separator: "\n\n---\n\n")
    }
}
