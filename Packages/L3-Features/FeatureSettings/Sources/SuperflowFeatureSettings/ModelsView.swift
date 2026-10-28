import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI

public enum ModelKind: String, CaseIterable, Identifiable, Sendable {
    case speech, cleanup, meetings
    public var id: Self { self }
    public var title: String {
        switch self {
        case .speech: "Speech"
        case .cleanup: "Cleanup"
        case .meetings: "Meetings"
        }
    }
}

public struct ModelItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: ModelKind
    public let name: String
    public let detail: String
    public let bytes: Int64
    public var state: DownloadState
    public var isActive: Bool

    public init(id: String, kind: ModelKind, name: String, detail: String, bytes: Int64,
                state: DownloadState = .idle, isActive: Bool = false) {
        self.id = id; self.kind = kind; self.name = name; self.detail = detail
        self.bytes = bytes; self.state = state; self.isActive = isActive
    }
}

/// The vendor mark, wrapped once so the asset name lives in one place.
/// The mark on a Models row, at the same 24 pt as onboarding. Speech and cleanup
/// are the two vendor artifacts (the NVIDIA eye, the S1-mini plate); the meetings
/// row is FluidAudio's diarizer, so it carries a glyph rather than a vendor image.
public struct ModelMark: View {
    public let kind: ModelKind
    public init(kind: ModelKind) { self.kind = kind }

    @ViewBuilder public var body: some View {
        switch kind {
        case .speech: NVIDIAIcon(size: 24)
        case .cleanup: S1MiniMark(size: 24)
        case .meetings: Icon(.meetings, size: 14, tint: Tok.text2)
        }
    }
}

/// The Models page reads the same catalog and download ports as Settings and
/// onboarding. There is no second download path: every row's state comes from
/// `ModelProvider` and `SpeakerDiarizer`.
@MainActor @Observable
public final class ModelsViewModel {
    public private(set) var items: [ModelItem]

    private let models: (any ModelProvider)?
    private let diarizer: (any SpeakerDiarizer)?
    private let asrProfile: String
    /// Cleanup is on for every dictation by default, so the S1-mini row reports
    /// `Active` unless the owner turned the setting off. Read through a closure so
    /// the page picks up a Settings change the next time it appears.
    private let cleanupEnabled: @MainActor () -> Bool
    /// A download owns its row until it finishes or is cancelled. Cancelling
    /// invalidates the token, so a late progress callback cannot repaint the row.
    @ObservationIgnored private var tokens: [String: UUID] = [:]

    public init(models: (any ModelProvider)? = nil,
                diarizer: (any SpeakerDiarizer)? = nil,
                asrProfile: String = ModelProfile.nemotron35Streaming.id,
                cleanupEnabled: @escaping @MainActor () -> Bool = { true }) {
        self.models = models
        self.diarizer = diarizer
        self.asrProfile = asrProfile
        self.cleanupEnabled = cleanupEnabled
        self.items = [
            ModelItem(id: asrProfile, kind: .speech,
                      name: ModelProfile.byID(asrProfile).displayName,
                      detail: "Streaming speech recognition for English. Runs on this Mac.",
                      bytes: 620_000_000),
            ModelItem(id: Self.cleanupID, kind: .cleanup, name: "S1-mini",
                      detail: "Cleans every dictation: filler words, punctuation, false starts.",
                      bytes: 484_219_808),
            ModelItem(id: Self.meetingsID, kind: .meetings, name: "Speaker separation",
                      detail: "Labels who spoke in meetings.",
                      bytes: 120_000_000),
        ]
        syncActive()
    }

    private static let cleanupID = "s1-mini"
    private static let meetingsID = "speaker-separation"

    public var installedCount: Int {
        items.filter { if case .installed = $0.state { true } else { false } }.count
    }
    public var missingCount: Int { items.count - installedCount }
    /// "2 of 3 installed." — the only subtitle on the page.
    public var subtitle: String { "\(installedCount) of \(items.count) installed." }
    public var activeName: String {
        items.first { $0.kind == .speech }?.name
            ?? ModelProfile.nemotron35Streaming.displayName
    }

    public func refresh() async {
        defer { syncActive() }
        guard let models else { return }
        let speech = await models.isAvailable(profileID: asrProfile)
        let cleanup = await models.llmModelURL() != nil
        let meetings = (await diarizer?.isReady()) ?? false
        set(.installed, for: asrProfile, whenIdle: speech)
        set(.installed, for: Self.cleanupID, whenIdle: cleanup)
        set(.installed, for: Self.meetingsID, whenIdle: meetings)
    }

    /// Only a model the app actually runs is `Active`: the speech profile when it
    /// is on disk, cleanup when it is on disk *and* its setting is on.
    private func syncActive() {
        for i in items.indices {
            let onDisk = isInstalled(items[i].state)
            switch items[i].kind {
            case .speech: items[i].isActive = onDisk
            case .cleanup: items[i].isActive = onDisk && cleanupEnabled()
            case .meetings: items[i].isActive = false
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
        guard let item = items.first(where: { $0.id == id }) else { return }
        let token = UUID()
        tokens[id] = token
        setState(.downloading(0), for: id)

        Task { @MainActor in
            let report = progressHandler(for: id, token: token)
            do {
                switch item.kind {
                case .speech:
                    guard let models else { setState(.failed("Model support is unavailable."), for: id); return }
                    try await models.prepare(profileID: asrProfile, progress: report)
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
                case .speech: installed = await models?.isAvailable(profileID: asrProfile) ?? false
                case .cleanup: installed = await models?.llmModelURL() != nil
                case .meetings: installed = (await diarizer?.isReady()) ?? false
                }
                guard tokens[id] == token else { return }
                setState(installed ? .installed : .failed("The model did not install."), for: id)
                tokens[id] = nil
            } catch {
                guard tokens[id] == token else { return }
                setState(.failed(error.localizedDescription), for: id)
                tokens[id] = nil
            }
        }
    }

    public func cancel(_ id: String) {
        tokens[id] = nil
        setState(.idle, for: id)
    }

    public func retry(_ id: String) { download(id) }

    public func downloadAll() {
        for item in items where !isBusy(item.state) && !isInstalled(item.state) {
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

public struct ModelsView: View {
    @Bindable var vm: ModelsViewModel

    public init(vm: ModelsViewModel) { self.vm = vm }

    public var body: some View {
        Page(title: "Models", subtitle: vm.subtitle) {
            EmptyView()
        } trailing: {
            if vm.missingCount > 0 {
                AppButton("Download all", kind: .primary) { vm.downloadAll() }
            }
        } content: {
            if vm.items.isEmpty {
                EmptyState("No models.", message: "Reinstall Superflow to restore them.")
            } else {
                ForEach(ModelKind.allCases) { kind in
                    let items = vm.items.filter { $0.kind == kind }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(kind.title)
                            VStack(spacing: 8) {
                                ForEach(items) { ModelCard(item: $0, vm: vm) }
                            }
                        }
                    }
                }
            }
        }
        .task { await vm.refresh() }
    }
}

struct ModelCard: View {
    let item: ModelItem
    let vm: ModelsViewModel

    var body: some View {
        DownloadCard(title: item.name, detail: item.detail, state: item.state,
                     totalBytes: item.bytes) {
            ModelMark(kind: item.kind)
        } trailing: {
            HStack(spacing: 12) {
                switch item.state {
                case .idle:
                    Text(item.bytes, format: .byteCount(style: .file))
                        .appType(.caption).monospacedDigit().foregroundStyle(Tok.text2)
                    AppButton("Download", kind: .secondary) { vm.download(item.id) }
                case .downloading, .verifying:
                    AppButton("Cancel", kind: .quiet) { vm.cancel(item.id) }
                case .installed:
                    if item.isActive {
                        Badge("Active", variant: .green, size: .sm)
                    } else {
                        Badge("Installed", variant: .neutral, size: .sm)
                    }
                case .failed:
                    Badge("Failed", variant: .rose, size: .sm)
                    AppButton("Retry", kind: .secondary) { vm.retry(item.id) }
                }
            }
        }
    }
}
