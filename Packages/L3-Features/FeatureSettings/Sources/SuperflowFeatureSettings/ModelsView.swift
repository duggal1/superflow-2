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

public struct VendorMark: View {
    public init() {}
    public var body: some View {
        NVIDIAIcon(size: 20, tint: Tok.text)
    }
}

@MainActor @Observable
public final class ModelsViewModel {
    public var items: [ModelItem] = [
        ModelItem(id: "parakeet", kind: .speech, name: "Parakeet",
                  detail: "Streaming speech recognition for English. Runs on this Mac.",
                  bytes: 150_000_000, state: .idle, isActive: true),
        ModelItem(id: "cleanup", kind: .cleanup, name: "S1-mini",
                  detail: "Removes filler words and fixes punctuation. Optional.",
                  bytes: 80_000_000, state: .idle, isActive: false),
        ModelItem(id: "diarization", kind: .meetings, name: "Speaker separation",
                  detail: "Labels who spoke in meetings. Optional.",
                  bytes: 120_000_000, state: .idle, isActive: false),
    ]

    public var installedCount: Int { items.filter { if case .installed = $0.state { true } else { false } }.count }
    public var subtitle: String { "\(installedCount) of \(items.count) installed." }
    public var missingCount: Int { items.count - installedCount }

    public init() {}

    public func download(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = .downloading(0)
        Task { @MainActor in
            for i in 1...5 {
                try? await Task.sleep(for: .milliseconds(200))
                if let idx = items.firstIndex(where: { $0.id == id }) {
                    items[idx].state = .downloading(Double(i) / 5.0)
                }
            }
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].state = .installed
                if items[idx].kind == .speech { items[idx].isActive = true }
            }
        }
    }

    public func cancel(_ id: String) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].state = .idle
        }
    }

    public func retry(_ id: String) { download(id) }

    public func activate(_ id: String) {
        for i in items.indices where items[i].kind == .speech {
            items[i].isActive = (items[i].id == id)
        }
    }

    public func downloadAll() {
        for item in items where {
            if case .idle = item.state { true } else { false }
        }() {
            download(item.id)
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
            if vm.missingCount > 0 { AppButton("Download all", kind: .primary) { vm.downloadAll() } }
        } content: {
            ForEach(ModelKind.allCases) { kind in
                let items = vm.items.filter { $0.kind == kind }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(kind.title)
                        VStack(spacing: 8) { ForEach(items) { ModelCard(item: $0, vm: vm) } }
                    }
                }
            }
        }
    }
}

struct ModelCard: View {
    let item: ModelItem
    let vm: ModelsViewModel

    var body: some View {
        DownloadCard(title: item.name, detail: item.detail, state: item.state, totalBytes: item.bytes) {
            VendorMark()
        } trailing: {
            HStack(spacing: 12) {
                switch item.state {
                case .idle:
                    Text(item.bytes, format: .byteCount(style: .file)).font(.system(size: 12)).monospacedDigit().foregroundStyle(Tok.text2)
                    AppButton("Download", kind: .secondary) { vm.download(item.id) }
                case .downloading, .verifying:
                    AppButton("Cancel", kind: .quiet) { vm.cancel(item.id) }
                case .installed:
                    if item.isActive {
                        Badge("Active", variant: .green, size: .sm)
                    } else if item.kind == .speech {
                        AppButton("Use", kind: .secondary) { vm.activate(item.id) }
                    } else {
                        Badge("Installed", variant: .neutral, size: .sm)
                    }
                case .failed:
                    Badge("Failed", variant: .danger, size: .sm)
                    AppButton("Retry", kind: .secondary) { vm.retry(item.id) }
                }
            }
        }
    }
}
