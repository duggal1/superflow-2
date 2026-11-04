import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI

public enum ModelKind: String, CaseIterable, Identifiable, Sendable {
    case speech, enhancement, cleanup, meetings
    public var id: Self { self }
    public var title: String {
        switch self {
        case .speech: "Speech"
        case .enhancement: "Noise suppression"
        case .cleanup: "Cleanup"
        case .meetings: "Meetings"
        }
    }
}

public struct ModelItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: ModelKind
    public let name: String
    public var detail: String
    public let bytes: Int64
    public var installedASRRuntimes: [ASRRuntime]
    /// Populated only from a real same-corpus, same-device benchmark run.
    public var benchmark: ASRBenchmarkResult?
    public var state: DownloadState
    public var isActive: Bool

    public init(id: String, kind: ModelKind, name: String, detail: String, bytes: Int64,
                installedASRRuntimes: [ASRRuntime] = [],
                benchmark: ASRBenchmarkResult? = nil,
                state: DownloadState = .idle, isActive: Bool = false) {
        self.id = id; self.kind = kind; self.name = name; self.detail = detail
        self.bytes = bytes; self.installedASRRuntimes = installedASRRuntimes
        self.benchmark = benchmark
        self.state = state; self.isActive = isActive
    }
}

/// The vendor mark, wrapped once so the asset name lives in one place.
/// The mark on a Models row, at the same 24 pt as onboarding. Speech and cleanup
/// are the two vendor artifacts (the NVIDIA eye, the S1-mini plate); the meetings
/// row is audio.cpp's diarizer, so it carries a glyph rather than a vendor image.
public struct ModelMark: View {
    public let kind: ModelKind
    public let profileID: String?
    public init(kind: ModelKind, profileID: String? = nil) {
        self.kind = kind
        self.profileID = profileID
    }

    @ViewBuilder public var body: some View {
        switch kind {
        case .speech:
            if profileID == nil || profileID == ModelProfile.nemotron35Streaming.id {
                NVIDIAIcon(width: 24)
            } else {
                IconView(.speechModel, size: 18)
            }
        case .enhancement: IconView(.noiseSuppression, size: 14)
        case .cleanup: S1MiniMark(size: 24)
        case .meetings: IconView(.speakerSeparation, size: 14)
        }
    }
}

/// The Models page reads the same catalog and download ports as Settings and
/// onboarding. There is no second download path: every row's state comes from
/// `ModelProvider` and `SpeakerDiarizer`.
private enum CatalogFilter: Hashable { case all, installed, available }

public struct ModelsView: View {
    @Bindable var vm: ModelsViewModel
    @State private var query = ""
    @State private var searchFocus = false
    @State private var filter: CatalogFilter = .all

    private var filteredItems: [ModelItem] {
        vm.items.filter { item in
            guard vm.matches(item, query: query) else { return false }
            switch filter {
            case .all: return true
            case .installed:
                if case .installed = item.state { return true }
                return false
            case .available:
                if case .idle = item.state { return true }
                return false
            }
        }
    }

    public init(vm: ModelsViewModel) { self.vm = vm }

    public var body: some View {
        Page(title: "Models", subtitle: vm.subtitle) {
            EmptyView()
        } trailing: {
            if vm.showsDownloadRemaining {
                AppButton("Install remaining (\(vm.remainingDownloadCount))", kind: .primary) { vm.downloadAll() }
            }
        } content: {
            HStack(spacing: 12) {
                SearchField(text: $query, prompt: "Search models", isFocused: $searchFocus)
                Segmented(selection: $filter, items: [
                    .init("All", value: .all),
                    .init("Installed", value: .installed),
                    .init("Available", value: .available),
                ])
            }
            if filteredItems.isEmpty {
                EmptyState("No matching models.", message: "Change the search or model filter.")
            } else {
                ModelPipeline(noise: vm.items.contains { $0.kind == .enhancement && $0.isActive },
                              speech: vm.items.contains { $0.kind == .speech && $0.isActive },
                              cleanup: vm.items.contains { $0.kind == .cleanup && $0.isActive })
                ForEach([false, true], id: \.self) { meetings in
                    let order: [ModelKind] = meetings ? [.meetings] : [.enhancement, .speech, .cleanup]
                    let items = order.flatMap { kind in filteredItems.filter { $0.kind == kind } }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(meetings ? "Meetings" : "Dictation",
                                          note: "\(items.filter { if case .installed = $0.state { true } else { false } }.count) of \(items.count) installed")
                            VStack(spacing: 8) {
                                ForEach(items) { ModelCard(item: $0, vm: vm) }
                            }
                        }
                    }
                }
            }
        }
        .task { await vm.refresh() }
        .searchShortcut($searchFocus)
    }
}

struct ModelCard: View {
    let item: ModelItem
    let vm: ModelsViewModel

    var body: some View {
        DownloadCard(title: item.name, detail: item.detail, state: item.state,
                     totalBytes: item.bytes > 0 ? item.bytes : nil) {
            ModelMark(kind: item.kind, profileID: item.kind == .speech ? item.id : nil)
        } trailing: {
            HStack(spacing: 12) {
                if item.kind == .speech {
                    Text(item.benchmark.map { String(format: "%.0f/100", $0.intelligenceScore) }
                         ?? "Not benchmarked")
                        .appType(.caption)
                        .foregroundStyle(Tok.text2)
                        .accessibilityLabel("Speech recognition benchmark")
                }
                switch item.state {
                case .idle where vm.isChecking:
                    // The disk has not answered yet. Offering Download here made a
                    // freshly installed model look like it needed downloading again.
                    Text(item.bytes > 0 ? item.bytes.formatted(.byteCount(style: .file)) : "Size unknown")
                        .appType(.caption).monospacedDigit().foregroundStyle(Tok.text2)
                case .idle:
                    Text(item.bytes > 0 ? item.bytes.formatted(.byteCount(style: .file)) : "Size unknown")
                        .appType(.caption).monospacedDigit().foregroundStyle(Tok.text2)
                    AppButton("Install model", kind: .secondary) { vm.download(item.id) }
                case .downloading, .verifying:
                    AppButton("Cancel", kind: .quiet) { vm.cancel(item.id) }
                case .installed:
                    if item.isActive {
                        PixelBadge("Active", kind: .active)
                    } else if item.kind == .speech {
                        let runtimes = item.installedASRRuntimes.map(\.label).joined(separator: ", ")
                        PixelBadge("Installed · \(runtimes)", kind: .installed)
                        if item.installedASRRuntimes.contains(.audioCpp) {
                            AppButton("Use model", kind: .secondary) {
                                Task { await vm.activate(item.id) }
                            }
                        } else {
                            AppButton("Install for audio.cpp", kind: .secondary) {
                                vm.download(item.id)
                            }
                        }
                    } else {
                        PixelBadge("Installed", kind: .installed)
                    }
                case .failed:
                    PixelBadge("Failed", kind: .failed)
                    AppButton("Retry", kind: .secondary) { vm.retry(item.id) }
                }
            }
        }
    }
}
