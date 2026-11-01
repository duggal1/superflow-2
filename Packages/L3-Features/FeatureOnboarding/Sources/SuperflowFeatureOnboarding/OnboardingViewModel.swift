import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI

/// Drives the four-step onboarding. Nothing here blocks the app: every step can be
/// skipped, and the app degrades instead of refusing to start.
@MainActor
public final class OnboardingViewModel: ObservableObject {
    @Published public  var step: OnboardingStep = .welcome
    @Published public  var statuses: [Permission: PermissionStatus] = [:]
    @Published public  var globeAction: GlobeKeyAction = .unknown
    @Published public  var isRefreshingPermissions = false

    @Published public  var speechReady = false
    @Published public  var speechSkipped = false
    @Published public  var speechProgress: Double?
    /// Measured wire speed for the running transfer, not an estimate.
    @Published public  var speechTransfer: TransferSnapshot?
    @Published public  var speechError: String?
    @Published public  var isDownloadingSpeech = false

    @Published public  var cleanupReady = false
    @Published public  var cleanupProgress: Double?
    @Published public  var cleanupTransfer: TransferSnapshot?
    @Published public  var cleanupError: String?
    @Published public  var isDownloadingCleanup = false
    /// Cleanup is on for every dictation by default; the row still carries its own
    /// switch so the owner can decline the download.
    @Published public var cleanupWanted = true

    @Published public  var permissionsSkipped = false
    @Published public  var practiceState: PracticeState = .idle
    @Published public var practiceText = ""
    @Published public  var isFinishing = false
    /// The key that starts a dictation. Written straight into `settings` on finish,
    /// so the app and the sandbox cannot disagree about the gesture.
    @Published public var dictationKey: DictationKey = .fn

    public let toast: ToastCenter

    /// Meetings ask for system audio lazily, on the first meeting, never here.
    public static let requiredPermissions: [Permission] = [.microphone, .accessibility, .inputMonitoring]

    let permissions: any PermissionGate
    let globe: any GlobeKeyProbe
    let models: any ASRModelProvider
    let cleanupModels: (any ModelProvider)?
    let settingsStore: any SettingsStore
    let practice: (any PracticeDictation)?
    let onFinish: @MainActor (AppSettings) -> Void

    var settings: AppSettings
    var speechToken = UUID()
    var cleanupToken = UUID()
    var practiceToken = UUID()

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
        self.dictationKey = initial.dictationKey
        // Setup always installs the streaming Nemotron 3.5 profile. Dictation has
        // no batch path, and the owner asked for this to be the forced default.
        self.settings.asrProfile = ModelProfile.default.id
        self.onFinish = onFinish
    }

    // MARK: step state

    public var speechName: String { ModelProfile.byID(settings.asrProfile).displayName }
    public var cleanupAvailable: Bool { cleanupModels != nil }
    public var isListening: Bool { practiceState == .listening }
    public var globeConflict: Bool { globeAction.isConflict }
    public var globeChecked: Bool { globeAction != .unknown }

    /// The done step promises the exact key the owner picked, not always fn.
    public var subtitle: String? {
        step == .done
            ? "Hold \(dictationKey.label) anywhere to dictate."
            : step.subtitle
    }

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
        case .welcome, .key, .done:
            true
        case .permissions:
            permissionsGranted
        case .models:
            needsDownload ? !isDownloadingSpeech : true
        }
    }

    public var canAdvance: Bool {
        switch step {
        case .welcome, .key, .done:
            true
        case .permissions:
            permissionsGranted
        case .models:
            speechReady || speechSkipped
        }
    }

    public var speechTotalBytes: Int64? { speechTransfer?.totalBytes(estimatedFrom: speechProgress) }
    public var cleanupTotalBytes: Int64? { cleanupTransfer?.totalBytes(estimatedFrom: cleanupProgress) }

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
        return "Cleans every dictation. On by default."
    }

    public func status(for permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    // MARK: lifecycle

    public func load() async {
        settings = await settingsStore.load()
        dictationKey = settings.dictationKey
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

    func didEnter(_ step: OnboardingStep) async {
        switch step {
        case .permissions:
            await refreshPermissions()
            await refreshGlobeAction()
        case .models:
            await checkModels()
        case .key, .done:
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

}
