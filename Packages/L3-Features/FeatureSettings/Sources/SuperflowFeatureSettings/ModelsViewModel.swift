import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI

@MainActor @Observable
public final class ModelsViewModel {
    public private(set) var items: [ModelItem]
    public private(set) var actionErrors: [String: String] = [:]
    public private(set) var activatingProfile: String?

    private let enhancer: (any SpeechEnhancer)?
    private let enhancementEnabled: @MainActor () -> Bool
    private let models: (any ModelProvider)?
    /// The speech model is installed and read through the same port onboarding and
    /// Settings use (`ASRModelProvider`, the recognizer). `ModelProvider`'s ASR
    /// manifest is empty and its artifacts live in a different directory, so asking
    /// it about the speech profile reported "not installed" for a model the owner
    /// had just downloaded during onboarding, and its Download could never succeed.
    private let asrModels: (any ASRModelProvider)?
    private let asrModelsByRuntime: [ASRRuntime: any ASRModelProvider]
    private let diarizer: (any SpeakerDiarizer)?
    private var asrRuntime: ASRRuntime
    private var asrProfile: String
    private let onActivate: @MainActor (String) async -> Bool
    /// True until the first disk read finishes. A row must not offer Download
    /// before it knows the model is absent, or every visit looks like a re-download.
    public private(set) var isChecking = true
    /// Cleanup is on for every dictation by default, so the S1-mini row reports
    /// `Active` unless the owner turned the setting off. Read through a closure so
    /// the page picks up a Settings change the next time it appears.
    private let cleanupEnabled: @MainActor () -> Bool
    /// A download owns its row until it finishes or is cancelled. Cancelling
    /// invalidates the token, so a late progress callback cannot repaint the row.
    @ObservationIgnored private var tokens: [String: UUID] = [:]
    @ObservationIgnored private var downloadTasks: [String: Task<Void, Never>] = [:]

    public init(models: (any ModelProvider)? = nil,
                asrModels: (any ASRModelProvider)? = nil,
                asrModelsByRuntime: [ASRRuntime: any ASRModelProvider] = [:],
                asrRuntime: ASRRuntime = .audioCpp,
                diarizer: (any SpeakerDiarizer)? = nil,
                asrProfile: String = ModelProfile.nemotron35Streaming.id,
                enhancer: (any SpeechEnhancer)? = nil,
                enhancementEnabled: @escaping @MainActor () -> Bool = { true },
                cleanupEnabled: @escaping @MainActor () -> Bool = { true },
                onActivate: @escaping @MainActor (String) async -> Bool = { _ in false }) {
        self.enhancer = enhancer
        self.enhancementEnabled = enhancementEnabled
        self.models = models
        self.asrModels = asrModels ?? models
        self.asrModelsByRuntime = asrModelsByRuntime
        self.diarizer = diarizer
        self.asrRuntime = asrRuntime
        self.asrProfile = asrProfile
        self.cleanupEnabled = cleanupEnabled
        self.onActivate = onActivate
        self.items = ModelProfile.streamingProfiles.map { profile in
            ModelItem(id: profile.id, kind: .speech, name: profile.displayName,
                      detail: profile.metadataLabel + " · " + profile.licenseName,
                      bytes: profile.artifactBytes)
        } + [
            ModelItem(id: Self.enhancementID, kind: .enhancement, name: "DeepFilterNet 3",
                      detail: "Required for optional microphone noise suppression.",
                      bytes: 0),
            ModelItem(id: Self.cleanupID, kind: .cleanup, name: "S1-mini",
                      detail: "Cleans every dictation: filler words, punctuation, false starts.",
                      bytes: 484_219_808),
            ModelItem(id: Self.meetingsID, kind: .meetings, name: "Speaker separation",
                      detail: "Labels who spoke in meetings.",
                      bytes: 106_675_136),
        ]
        syncActive()
    }

    public static let enhancementID = "deepfilternet3"
    private static let cleanupID = "s1-mini"
    private static let meetingsID = "speaker-separation"

    public var installedCount: Int {
        items.filter { if case .installed = $0.state { true } else { false } }.count
    }
    public var missingCount: Int { items.count - installedCount }
    public var remainingDownloadCount: Int {
        items.filter { needsInstall($0) && !isBusy($0.state) }.count
    }
    public var showsDownloadRemaining: Bool {
        !isChecking && remainingDownloadCount > 0 && !items.contains { isBusy($0.state) }
    }
    /// "2 of 3 installed." — the only subtitle on the page.
    public var subtitle: String { "\(installedCount) of \(items.count) installed." }
    public var activeName: String {
        items.first { $0.kind == .speech && $0.isActive }?.name
            ?? ModelProfile.byID(asrProfile).displayName
    }
    public var selectedASRRuntime: ASRRuntime { asrRuntime }

    /// A catalog entry is not an activated ASR model. The runtime must have
    /// verified local artifacts and the coordinator must persist the change.
    @discardableResult
    public func activate(_ id: String) async -> Bool {
        guard let item = items.first(where: { $0.id == id && $0.kind == .speech }),
              case .installed = item.state,
              ModelProfile.byID(id).supportsLiveDictation,
              item.installedASRRuntimes.contains(.audioCpp) else { return false }
        if item.isActive { return true }
        guard activatingProfile == nil else { return false }
        actionErrors[id] = nil
        activatingProfile = id
        defer { activatingProfile = nil }
        guard await onActivate(id) else {
            actionErrors[id] = "Could not prepare this streaming model. The previous model is still active."
            return false
        }
        await updateASRSelection(runtime: .audioCpp, profile: id)
        return true
    }

    public func matches(_ item: ModelItem, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let profile = item.kind == .speech ? ModelProfile.byID(item.id) : nil
        return [item.name, item.detail, item.kind.title, profile?.vendor ?? "",
                profile?.language ?? "", profile?.formatLabel ?? ""]
            .contains { $0.localizedStandardContains(needle) }
    }

    public func updateASRSelection(runtime: ASRRuntime, profile: String) async {
        guard asrRuntime != runtime || asrProfile != profile else { return }
        asrRuntime = runtime
        asrProfile = profile
        isChecking = true
        await refresh()
    }

    public func refresh() async {
        defer {
            syncActive()
            isChecking = false
        }
        for profile in ModelProfile.streamingProfiles {
            let runtimes = await installedASRRuntimes(profileID: profile.id)
            if let index = items.firstIndex(where: { $0.id == profile.id && $0.kind == .speech }) {
                items[index].installedASRRuntimes = runtimes
                items[index].detail = profile.metadataLabel + " · " + profile.licenseName
                    + (runtimes.isEmpty ? " · audio.cpp" : " · Installed: " +
                        runtimes.map(\.label).joined(separator: ", "))
            }
            set(.installed, for: profile.id, whenIdle: !runtimes.isEmpty)
        }
        let enhancement = await enhancer?.isAvailable() ?? false
        let cleanup = await models?.llmModelURL() != nil
        let meetings = (await diarizer?.isInstalled()) ?? false
        set(.installed, for: Self.enhancementID, whenIdle: enhancement)
        set(.installed, for: Self.cleanupID, whenIdle: cleanup)
        set(.installed, for: Self.meetingsID, whenIdle: meetings)
    }

    /// Only a model the app actually runs is `Active`: the speech profile when it
    /// is on disk, cleanup when it is on disk *and* its setting is on.
    private func syncActive() {
        for i in items.indices {
            let onDisk = isInstalled(items[i].state)
            switch items[i].kind {
            case .speech:
                items[i].isActive = items[i].id == asrProfile
                    && items[i].installedASRRuntimes.contains(asrRuntime)
            case .enhancement: items[i].isActive = onDisk && enhancementEnabled()
            case .cleanup: items[i].isActive = onDisk && cleanupEnabled()
            case .meetings: items[i].isActive = onDisk
            }
        }
    }

    private func set(_ state: DownloadState, for id: String, whenIdle installed: Bool) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        switch items[i].state {
        case .idle, .installed:
            items[i].state = installed ? .installed : .idle
        case .downloading, .verifying, .failed:
            break
        }
        syncActive()
    }

    public func download(_ id: String) {
        guard tokens[id] == nil, let item = items.first(where: { $0.id == id }) else { return }
        let token = UUID()
        tokens[id] = token
        setState(.downloading(0), for: id)
        // All additional families run through the native audio.cpp backend.
        let asrModels = asrModelsByRuntime[.audioCpp] ?? selectedASRModels
        let asrProfile = item.kind == .speech ? item.id : self.asrProfile
        let asrRuntime: ASRRuntime = .audioCpp

        downloadTasks[id] = Task { @MainActor in
            defer {
                // A cancelled old download must not clear a newer retry.
                if tokens[id] == token {
                    tokens[id] = nil
                    downloadTasks[id] = nil
                }
            }
            let report = progressHandler(for: id, token: token)
            do {
                switch item.kind {
                case .speech:
                    guard let asrModels else { setState(.failed("Model support is unavailable."), for: id); return }
                    try await asrModels.prepare(profileID: asrProfile, progress: report)
                case .enhancement:
                    guard let enhancer else { setState(.failed("Noise suppression is unavailable."), for: id); return }
                    try await enhancer.prepare(progress: report)
                case .cleanup:
                    guard let models else { setState(.failed("Model support is unavailable."), for: id); return }
                    _ = try await models.ensureLLM(progress: report)
                case .meetings:
                    guard let diarizer else { setState(.failed("Model support is unavailable."), for: id); return }
                    try await diarizer.prepare(progress: report)
                }
                guard tokens[id] == token else { return }
                setState(.verifying, for: id)
                let installed: Bool
                switch item.kind {
                case .enhancement: installed = await enhancer?.isAvailable() ?? false
                case .speech:
                    installed = await asrModels?.isAvailable(profileID: asrProfile) ?? false
                    if installed,
                       let index = items.firstIndex(where: { $0.id == id }),
                       !items[index].installedASRRuntimes.contains(asrRuntime) {
                        items[index].installedASRRuntimes.append(asrRuntime)
                        items[index].detail = Self.speechDetail(
                            for: asrRuntime, installedIn: items[index].installedASRRuntimes)
                    }
                case .cleanup: installed = await models?.llmModelURL() != nil
                case .meetings: installed = (await diarizer?.isReady()) ?? false
                }
                guard tokens[id] == token else { return }
                setState(installed ? .installed : .failed("The model did not install."), for: id)
            } catch {
                guard tokens[id] == token else { return }
                setState(.failed(error.localizedDescription), for: id)
            }
        }
    }

    public func cancel(_ id: String) {
        tokens[id] = nil
        downloadTasks.removeValue(forKey: id)?.cancel()
        setState(.idle, for: id)
    }

    public func retry(_ id: String) { download(id) }

    @discardableResult
    public func remove(_ id: String) async -> Bool {
        guard let item = items.first(where: { $0.id == id && $0.kind == .speech }),
              case .installed = item.state,
              !item.isActive, id != asrProfile, activatingProfile != id,
              tokens[id] == nil else { return false }
        guard let remover = (asrModelsByRuntime[.audioCpp] ?? asrModels) as? any ASRModelRemoving else {
            actionErrors[id] = "This model provider does not support removal."
            return false
        }
        do {
            try await remover.remove(profileID: id)
            actionErrors[id] = nil
            await refresh()
            return true
        } catch {
            actionErrors[id] = error.localizedDescription
            return false
        }
    }


    private var selectedASRModels: (any ASRModelProvider)? {
        asrModelsByRuntime[asrRuntime] ?? asrModels
    }

    private func installedASRRuntimes(profileID: String) async -> [ASRRuntime] {
        var installed: [ASRRuntime] = []
        for runtime in ASRRuntime.allCases {
            let provider = asrModelsByRuntime[runtime]
                ?? (runtime == asrRuntime ? asrModels : nil)
            guard let provider, await provider.isAvailable(profileID: profileID) else { continue }
            installed.append(runtime)
        }
        return installed
    }

    private func needsInstall(_ item: ModelItem) -> Bool {
        if item.kind == .speech {
            return item.id == asrProfile && !item.installedASRRuntimes.contains(.audioCpp)
        }
        return !isInstalled(item.state)
    }

    private static func speechDetail(for runtime: ASRRuntime,
                                     installedIn runtimes: [ASRRuntime] = []) -> String {
        if runtimes.contains(runtime) {
            switch runtime {
            case .audioCpp: return "Installed for audio.cpp · Metal streaming on this Mac."
            case .sherpaOnnx: return "Installed for sherpa-onnx · Core ML streaming on Apple hardware."
            }
        }
        if let installedElsewhere = runtimes.first {
            return "Installed for \(installedElsewhere.label). Select it in Settings to use these files; \(runtime.label) needs a separate model package."
        }
        return switch runtime {
        case .audioCpp: "audio.cpp · Metal streaming. Model files are required on this Mac."
        case .sherpaOnnx: "sherpa-onnx · Core ML streaming on Apple hardware. ONNX model files are required."
        }
    }

    private static func speechBytes(for runtime: ASRRuntime) -> Int64 {
        runtime == .sherpaOnnx ? 475_274_007 : 930_625_888
    }

    public func downloadAll() {
        for item in items where !isBusy(item.state) && needsInstall(item) {
            download(item.id)
        }
    }

    private func setState(_ state: DownloadState, for id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].state = state
        syncActive()
    }

    private func isInstalled(_ state: DownloadState) -> Bool {
        if case .installed = state { return true }
        return false
    }

    private func isBusy(_ state: DownloadState) -> Bool {
        switch state {
        case .downloading, .verifying: true
        case .idle, .installed, .failed: false
        }
    }

    private func progressHandler(for id: String, token: UUID) -> @Sendable (Double) -> Void {
        { [weak self] value in
            Task { @MainActor in
                guard let self, self.tokens[id] == token else { return }
                self.setState(.downloading(value), for: id)
            }
        }
    }
}
