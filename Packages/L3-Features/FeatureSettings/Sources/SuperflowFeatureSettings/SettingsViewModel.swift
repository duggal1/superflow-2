import Foundation
import SuperflowContextProfiles
import SuperflowDesignSystem
import SuperflowKernel
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var settings: AppSettings
    @Published public var searchQuery = ""
    @Published public private(set) var saved: AppSettings
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?
    @Published public private(set) var asrReady = false
    @Published public private(set) var cleanupReady = false
    public var cleanupModelInstalled: Bool { cleanupReady }
    @Published public private(set) var diarizationReady = false
    @Published public private(set) var isCheckingModels = false
    @Published public private(set) var isDownloadingASR = false
    @Published public private(set) var isDownloadingCleanup = false
    @Published public private(set) var isDownloadingDiarization = false
    @Published public private(set) var asrProgress: Double?
    /// Measured wire speed for the running transfer, not an estimate.
    @Published public private(set) var asrTransfer: TransferSnapshot?
    @Published public private(set) var cleanupProgress: Double?
    @Published public private(set) var cleanupTransfer: TransferSnapshot?
    @Published public private(set) var diarizationProgress: Double?
    @Published public private(set) var lastDiagnosticsExport: URL?

    public let toast: ToastCenter
    public let thirdPartyNotices: String
    private let store: any SettingsStore
    private let models: (any ModelProvider)?
    private let asrModels: (any ASRModelProvider)?
    private let diarizer: (any SpeakerDiarizer)?
    private let launchAtLogin: (any LaunchAtLoginController)?
    private let diagnostics: (any DiagnosticsExporting)?
    private let onCleanupModelReady: (@MainActor () -> Void)?
    private let onSettingsSaved: (@MainActor (AppSettings) -> Void)?
    private var asrDownloadToken = UUID()
    private var cleanupDownloadToken = UUID()
    private var diarizationDownloadToken = UUID()

    public static let retentionOptions: [Int?] = [nil, 7, 30, 90, 180, 365]

    public init(store: any SettingsStore,
                models: (any ModelProvider)? = nil,
                asrModels: (any ASRModelProvider)? = nil,
                diarizer: (any SpeakerDiarizer)? = nil,
                launchAtLogin: (any LaunchAtLoginController)? = nil,
                diagnostics: (any DiagnosticsExporting)? = nil,
                toast: ToastCenter = ToastCenter(),
                thirdPartyNotices: String = "",
                initial: AppSettings = .default,
                onCleanupModelReady: (@MainActor () -> Void)? = nil,
                onSettingsSaved: (@MainActor (AppSettings) -> Void)? = nil) {
        self.store = store
        self.models = models
        self.asrModels = asrModels ?? models
        self.diarizer = diarizer
        self.launchAtLogin = launchAtLogin
        self.diagnostics = diagnostics
        self.onCleanupModelReady = onCleanupModelReady
        self.toast = toast
        self.thirdPartyNotices = thirdPartyNotices
        self.onSettingsSaved = onSettingsSaved
        self.settings = initial
        self.saved = initial
    }

    // MARK: state

    public var issues: [SettingsIssue] { SettingsValidation.issues(settings) }
    public var isValid: Bool { issues.isEmpty }
    public var hasChanges: Bool { settings != saved }
    public var canSave: Bool { hasChanges && isValid }
    public var launchAtLoginAvailable: Bool { launchAtLogin != nil }
    public var diagnosticsAvailable: Bool { diagnostics != nil }

    public var profile: ModelProfile { ModelProfile.byID(settings.asrProfile) }
    public var profileOptions: [String] {
        ModelProfile.all
            .filter { $0.supportsLiveDictation || $0.id == settings.asrProfile }
            .map(\.id)
    }

    public func profileName(_ id: String) -> String { ModelProfile.byID(id).displayName }

    public func profileStatusLabel(_ id: String) -> String {
        let profile = ModelProfile.byID(id)
        if !profile.streaming { return "Not for dictation" }
        switch profile.status {
        case .verified: return "Verified"
        case .unverified: return "Experimental"
        case .unavailable: return "Unavailable"
        }
    }

    public func profileStatusVariant(_ id: String) -> BadgeVariant {
        let profile = ModelProfile.byID(id)
        if !profile.streaming { return .neutral }
        switch profile.status {
        case .verified: return .green
        case .unverified: return .orange
        case .unavailable: return .neutral
        }
    }

    public static func retentionLabel(for days: Int?) -> String {
        guard let days else { return "Keep forever" }
        return days == 1 ? "After 1 day" : "After \(days) days"
    }

    public func setProfile(_ id: String) {
        guard settings.asrProfile != id else { return }
        let candidate = ModelProfile.byID(id)
        guard candidate.supportsLiveDictation else {
            toast.show("\(candidate.displayName) is batch-only and cannot be used for live dictation.",
                       style: .warning)
            return
        }
        settings.asrProfile = id
        Task { await refreshModelState() }
    }

    // MARK: load and save

    public func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        var loaded = await store.load()
        if let launchAtLogin {
            let actual = await launchAtLogin.isEnabled()
            loaded.launchAtLogin = actual
        }
        settings = loaded
        saved = loaded
        await refreshModelState()
    }

    @discardableResult
    public func save() async -> Bool {
        settings.displayName = settings.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid else {
            toast.show(issues.first?.message ?? "Check the settings above.", style: .warning)
            return false
        }

        if settings.launchAtLogin != saved.launchAtLogin {
            await applyLaunchAtLogin()
        }

        await store.save(settings)
        saved = settings
        onSettingsSaved?(settings)
        toast.show("Settings saved.", style: .success)
        return true
    }

    public func revert() {
        settings = saved
        toast.show("Changes discarded.", style: .info)
    }

    /// Applies a profile to the working copy and offers the previous values
    /// back. Profiles never write to the store on their own; Save still owns
    /// persistence.
    public func applyProfile(_ profile: ContextProfile) {
        let previous = settings
        guard !profile.matches(previous) else { return }
        settings = profile.applying(to: previous)
        toast.show("\(profile.name) profile applied.", style: .info, actionTitle: "Undo") { [weak self] in
            self?.settings = previous
        }
    }

    public func resetToDefaults() {
        var defaults = AppSettings.default
        defaults.onboardingComplete = saved.onboardingComplete
        settings = defaults
        toast.show("Defaults restored. Save to apply.", style: .info)
    }

    private func applyLaunchAtLogin() async {
        guard let launchAtLogin else {
            if settings.launchAtLogin {
                settings.launchAtLogin = false
                toast.show("Launch at login is unavailable in this build.", style: .warning)
            }
            return
        }
        do {
            try await launchAtLogin.setEnabled(settings.launchAtLogin)
        } catch {
            settings.launchAtLogin = saved.launchAtLogin
            toast.show("Could not update launch at login. \(error.localizedDescription)",
                       style: .error)
        }
    }

    // MARK: models

    public func refreshModelState() async {
        isCheckingModels = true
        defer { isCheckingModels = false }
        if let asrModels, profile.supportsLiveDictation {
            asrReady = await asrModels.isAvailable(profileID: settings.asrProfile)
        } else {
            asrReady = false
        }
        cleanupReady = await models?.llmModelURL() != nil
        diarizationReady = await diarizer?.isReady() ?? false
    }

    public func downloadASRModel() async {
        guard let asrModels else {
            toast.show("Model downloads are unavailable in this build.", style: .warning)
            return
        }
        guard profile.supportsLiveDictation else {
            toast.show("\(profile.displayName) is batch-only and cannot be downloaded for live dictation.",
                       style: .warning)
            return
        }
        guard !isDownloadingASR else { return }
        isDownloadingASR = true
        asrProgress = 0
        asrTransfer = nil
        let meter = meterTransfer { [weak self] snapshot in self?.asrTransfer = snapshot }
        defer {
            meter.cancel()
            asrTransfer = nil
        }
        let token = UUID()
        asrDownloadToken = token
        let profileID = settings.asrProfile
        do {
            try await asrModels.prepare(profileID: profileID) { [weak self] value in
                Task { @MainActor in
                    guard let self, self.asrDownloadToken == token else { return }
                    self.asrProgress = value
                }
            }
            asrReady = await asrModels.isAvailable(profileID: profileID)
            asrDownloadToken = UUID()
            asrProgress = nil
            toast.show("\(profileName(profileID)) is ready.", style: .success)
        } catch {
            asrDownloadToken = UUID()
            asrProgress = nil
            toast.show("Could not download the speech model. \(error.localizedDescription)",
                       style: .error)
        }
        isDownloadingASR = false
    }

    public func downloadCleanupModel() async {
        guard let models else {
            toast.show("Model downloads are unavailable in this build.", style: .warning)
            return
        }
        guard !isDownloadingCleanup else { return }
        isDownloadingCleanup = true
        cleanupProgress = 0
        cleanupTransfer = nil
        let meter = meterTransfer { [weak self] snapshot in self?.cleanupTransfer = snapshot }
        defer {
            meter.cancel()
            cleanupTransfer = nil
        }
        let token = UUID()
        cleanupDownloadToken = token
        do {
            _ = try await models.ensureLLM { [weak self] value in
                Task { @MainActor in
                    guard let self, self.cleanupDownloadToken == token else { return }
                    self.cleanupProgress = value
                }
            }
            cleanupReady = await models.llmModelURL() != nil
            if cleanupReady { onCleanupModelReady?() }
            cleanupDownloadToken = UUID()
            cleanupProgress = nil
            toast.show("Cleanup model is ready.", style: .success)
        } catch {
            cleanupDownloadToken = UUID()
            cleanupProgress = nil
            toast.show("Could not download the cleanup model. \(error.localizedDescription)",
                       style: .error)
        }
        isDownloadingCleanup = false
    }

    public func downloadDiarizationModel() async {
        guard let diarizer else {
            toast.show("Meeting speaker separation is unavailable in this build.", style: .warning)
            return
        }
        guard !isDownloadingDiarization else { return }
        isDownloadingDiarization = true
        diarizationProgress = 0
        let token = UUID()
        diarizationDownloadToken = token
        do {
            try await diarizer.prepare { [weak self] value in
                Task { @MainActor in
                    guard let self, self.diarizationDownloadToken == token else { return }
                    self.diarizationProgress = value
                }
            }
            diarizationReady = await diarizer.isReady()
            diarizationDownloadToken = UUID()
            diarizationProgress = nil
            toast.show(diarizationReady ? "Meeting speaker model is ready." : "Meeting speaker model is unavailable.",
                       style: diarizationReady ? .success : .warning)
        } catch {
            diarizationDownloadToken = UUID()
            diarizationProgress = nil
            toast.show("Could not download the meeting speaker model. \(error.localizedDescription)",
                       style: .error)
        }
        isDownloadingDiarization = false
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

    // MARK: diagnostics

    @discardableResult
    public func exportDiagnostics(to url: URL) async -> Bool {
        guard let diagnostics else {
            toast.show("Diagnostics export is unavailable in this build.", style: .warning)
            return false
        }
        do {
            try await diagnostics.exportDiagnostics(to: url)
            lastDiagnosticsExport = url
            toast.show("Diagnostics exported. No transcripts or audio included.", style: .success)
            return true
        } catch {
            toast.show("Could not export diagnostics. \(error.localizedDescription)", style: .error)
            return false
        }
    }
}
