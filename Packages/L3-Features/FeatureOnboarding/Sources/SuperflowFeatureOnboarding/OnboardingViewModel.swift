import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI

/// Drives the four-step onboarding. Nothing here blocks the app: every step can be
/// skipped, and the app degrades instead of refusing to start.
@MainActor
public final class OnboardingViewModel: ObservableObject {
    @Published public private(set) var step: OnboardingStep = .welcome
    @Published public private(set) var statuses: [Permission: PermissionStatus] = [:]
    @Published public private(set) var globeAction: GlobeKeyAction = .unknown
    @Published public private(set) var isRefreshingPermissions = false

    @Published public private(set) var speechReady = false
    @Published public private(set) var speechSkipped = false
    @Published public private(set) var speechProgress: Double?
    /// Measured wire speed for the running transfer, not an estimate.
    @Published public private(set) var speechTransfer: TransferSnapshot?
    @Published public private(set) var speechError: String?
    @Published public private(set) var isDownloadingSpeech = false

    @Published public private(set) var cleanupReady = false
    @Published public private(set) var cleanupProgress: Double?
    @Published public private(set) var cleanupTransfer: TransferSnapshot?
    @Published public private(set) var cleanupError: String?
    @Published public private(set) var isDownloadingCleanup = false
    /// The cleanup model is optional, so the row carries its own switch.
    @Published public var cleanupWanted = true

    @Published public private(set) var permissionsSkipped = false
    @Published public private(set) var practiceState: PracticeState = .idle
    @Published public var practiceText = ""
    @Published public private(set) var isFinishing = false

    public let toast: ToastCenter

    /// Meetings ask for system audio lazily, on the first meeting, never here.
    public static let requiredPermissions: [Permission] = [.microphone, .accessibility, .inputMonitoring]

    private let permissions: any PermissionGate
    private let globe: any GlobeKeyProbe
    private let models: any ASRModelProvider
    private let cleanupModels: (any ModelProvider)?
    private let settingsStore: any SettingsStore
    private let practice: (any PracticeDictation)?
    private let onFinish: @MainActor (AppSettings) -> Void

    private var settings: AppSettings
    private var speechToken = UUID()
    private var cleanupToken = UUID()
    private var practiceToken = UUID()

    public init(permissions: any PermissionGate,
                globe: any GlobeKeyProbe = UnknownGlobeKeyProbe(),
                models: any ASRModelProvider,
                cleanupModels: (any ModelProvider)? = nil,
                settingsStore: any SettingsStore,
                practice: (any PracticeDictation)? = nil,
                toast: ToastCenter = ToastCenter(),
                initial: AppSettings = .default,
                onFinish: @escaping @MainActor (AppSettings) -> Void = { _ in }) {
        self.permissions = permissions
        self.globe = globe
        self.models = models
        self.cleanupModels = cleanupModels
        self.settingsStore = settingsStore
        self.practice = practice
        self.toast = toast
        self.settings = initial
        self.onFinish = onFinish
    }

    // MARK: step state

    public var speechName: String { ModelProfile.byID(settings.asrProfile).displayName }
    public var cleanupAvailable: Bool { cleanupModels != nil }
    public var isListening: Bool { practiceState == .listening }
    public var globeConflict: Bool { globeAction.isConflict }
    public var globeChecked: Bool { globeAction != .unknown }

    public var grantedCount: Int {
        Self.requiredPermissions.filter { statuses[$0]?.isGranted == true }.count
    }

    public var permissionsGranted: Bool {
        Self.requiredPermissions.allSatisfy { statuses[$0]?.isGranted == true }
    }

    /// The sandbox field appears only when it can actually work.
    public var practiceReady: Bool {
        practice != nil && speechReady && status(for: .microphone).isGranted
    }

    public var needsDownload: Bool {
        !speechReady && !speechSkipped
    }

    /// The same footer button downloads first, then continues.
    public var primaryTitle: String {
        step == .models && needsDownload ? "Download" : step.primaryTitle
    }

    public var primaryEnabled: Bool {
        switch step {
        case .welcome, .done:
            true
        case .permissions:
            permissionsGranted
        case .models:
            needsDownload ? !isDownloadingSpeech : true
        }
    }

    public var canAdvance: Bool {
        switch step {
        case .welcome, .done:
            true
        case .permissions:
            permissionsGranted
        case .models:
            speechReady || speechSkipped
        }
    }

    public var speechTotalBytes: Int64? { speechTransfer?.totalBytes }
    public var cleanupTotalBytes: Int64? { cleanupTransfer?.totalBytes }

    public var speechDetail: String {
        if speechReady { return "Ready" }
        if let speechProgress {
            return TransferText.progress(speechProgress, transfer: speechTransfer)
        }
        if speechError != nil { return "Download failed" }
        return "Streaming speech recognition for English. Runs on this Mac."
    }

    public var cleanupDetail: String {
        if cleanupReady { return "Ready" }
        if let cleanupProgress {
            return TransferText.progress(cleanupProgress, transfer: cleanupTransfer)
        }
        if cleanupError != nil { return "Download failed" }
        return "Removes filler words and fixes punctuation. Optional."
    }

    public func status(for permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    // MARK: lifecycle

    public func load() async {
        settings = await settingsStore.load()
        await refreshPermissions()
        await refreshGlobeAction()
        await checkModels()
    }

    public func advance() async {
        guard canAdvance, let next = step.next else { return }
        step = next
        await didEnter(next)
    }

    public func back() {
        guard let previous = step.previous else { return }
        step = previous
    }

    /// "Set up later" is always available. Nothing blocks on a permission or a model.
    public func skipCurrent() async {
        if step == .permissions { permissionsSkipped = true }
        if step == .models {
            speechSkipped = true
            if !cleanupReady { cleanupWanted = false }
        }
        guard let next = step.next else { return }
        step = next
        await didEnter(next)
    }

    /// Runs the step's primary control: download on the models step, then move on.
    public func performPrimaryAction() async {
        if step == .models, needsDownload {
            await downloadAll()
            return
        }
        if step == .done {
            await finish()
            return
        }
        await advance()
    }

    private func didEnter(_ step: OnboardingStep) async {
        switch step {
        case .permissions:
            await refreshPermissions()
            await refreshGlobeAction()
        case .models:
            await checkModels()
        case .done:
            await checkModels()
        case .welcome:
            break
        }
    }

    // MARK: permissions

    public func refreshPermissions() async {
        isRefreshingPermissions = true
        defer { isRefreshingPermissions = false }
        var fresh: [Permission: PermissionStatus] = [:]
        for permission in Permission.allCases {
            fresh[permission] = await permissions.status(permission)
        }
        statuses = fresh
    }

    public func request(_ permission: Permission) async {
        let result = await permissions.request(permission)
        statuses[permission] = result
    }

    public func updatePermissionStatus(_ permission: Permission, status: PermissionStatus) {
        statuses[permission] = status
    }

    public func openSystemSettings(_ permission: Permission) async {
        await permissions.openSystemSettings(permission)
    }

    // MARK: globe key

    public func refreshGlobeAction() async {
        globeAction = await globe.currentAction()
    }

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
    private func meterTransfer(
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
        await settingsStore.save(settings)
        onFinish(settings)
        toast.show("Superflow is ready.", style: .success)
        return true
    }
}
