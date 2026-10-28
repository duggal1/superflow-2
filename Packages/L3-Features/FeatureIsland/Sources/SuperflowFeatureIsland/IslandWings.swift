import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// Compact state: what you are talking to on the left of the notch, one signal on
/// the right. Both hug their outer edge and stay centred on the band.
///
/// Each live mode names its own promise in pixels instead of words: the meter
/// for a dictation, a lock for hands-free, the brand disc plus a clock for a
/// meeting. The key hints are a temporary 32 pt shelf under the band, part of
/// the silhouette rather than an overlay, so the shape grows to hold them.
struct WingsContent: View {
    let model: IslandModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phase: IslandPhase { model.phase }

    var body: some View {
        let geometry = model.geometry
        let gap = geometry.hasNotch ? geometry.notch.width : IslandLayout.nonNotchGap
        let wing = (model.box.body.width - gap) / 2

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading
                    .padding(.leading, wing == IslandLayout.wing
                             ? IslandLayout.wingInset : 12)
                    .frame(width: wing, alignment: .leading)

                Color.clear.frame(width: gap)

                trailing
                    .padding(.trailing, IslandLayout.wingInset)
                    .frame(width: wing, alignment: .trailing)
            }
            .frame(height: geometry.band)

            if model.hint, let hints {
                HintShelf(items: hints)
                    .frame(height: model.prefs.liveText ? IslandLayout.liveShelf : IslandLayout.hintShelf)
                    .transition(.opacity)
            } else if model.prefs.liveText && showsLiveShelf {
                LiveLine(live: model.live)
                    .padding(.horizontal, 20)
                    .frame(height: IslandLayout.liveShelf)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.30), value: model.hint)
    }

    private var showsLiveShelf: Bool {
        switch phase {
        case .listening, .handsFree, .meeting: true
        case .idle, .hover, .meetingPanel, .processing, .landed, .failed,
             .recent, .history, .undo, .notice: false
        }
    }

    @ViewBuilder private var leading: some View {
        switch phase {
        case .handsFree:
            HStack(spacing: 8) {
                TargetIcon(bundleID: model.target?.bundleID)
                PixelBitmap(rows: PixelBitmap.lock, develop: 0.12)
            }
            .accessibilityLabel("Hands-free dictation")
        case .meeting:
            HStack(spacing: 8) {
                RecordDisc()
                Text(Self.clock(model.elapsed))
                    .appType(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Tok.text)
                    .contentTransition(.numericText(value: Double(model.elapsed)))
                    .accessibilityLabel("Meeting running for \(Self.spoken(model.elapsed))")
            }
        case .listening, .processing, .landed:
            TargetIcon(bundleID: model.target?.bundleID)
        case .idle, .hover, .meetingPanel, .failed, .recent, .history, .undo, .notice:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch phase {
        case .listening:
            IslandPixelMeter(trail: model.waveform.trail)
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .handsFree:
            // A latched session is wider than a held one: there is no key to
            // release, so the meter has more history to show.
            IslandPixelMeter(trail: model.waveform.trail, columns: 15)
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .meeting:
            IslandPixelBarcode(trail: model.waveform.trail)
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .processing:
            IslandWait()
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .landed:
            PixelBitmap(rows: PixelBitmap.check, develop: 0.16)
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .idle, .hover, .meetingPanel, .failed, .recent, .history, .undo, .notice:
            EmptyView()
        }
    }

    private var hints: [(key: String, label: String)]? {
        switch phase {
        case .handsFree: [(key: "fn / ⏎", label: "Send"), (key: "esc", label: "Cancel")]
        case .meeting: [(key: "⌘ ×2", label: "Save"), (key: "esc", label: "Discard")]
        default: nil
        }
    }

    /// "4:12", or "1:04:12" once a meeting passes the hour. No leading zero on
    /// the minutes: the readout is a duration, not a clock.
    private static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    private static func spoken(_ seconds: Int) -> String {
        let total = max(0, seconds), m = total / 60, s = total % 60
        guard m > 0 else { return "\(s) seconds" }
        return "\(m) minutes \(s) seconds"
    }
}

/// The real icon of the app the text will land in. The microphone stands in only
/// when the target is unknown.
struct TargetIcon: View {
    let bundleID: String?

    var body: some View {
        if let bundleID {
            AppIcon(bundleID: bundleID, size: 20)
        } else {
            Icon(.mic, size: 14, tint: Tok.text2)
                .frame(width: 20, height: 20)
        }
    }
}

/// "fn / ⏎ Send · esc Cancel". One row, centred, never wider than the wings.
struct HintShelf: View {
    let items: [(key: String, label: String)]

    var body: some View {
        HStack(spacing: 20) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    HintKey(label: items[index].key)
                    Text(items[index].label)
                        .appType(.caption)
                        .foregroundStyle(Tok.text2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: IslandLayout.hintShelf)
        .accessibilityHidden(true)
    }
}

/// A keycap at caption scale. The one place in the Island with a fill other
/// than black: the cap has to read as a key, not as a label.
struct HintKey: View {
    let label: String

    var body: some View {
        Text(label)
            .appType(.caption)
            .foregroundStyle(Tok.text)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(Tok.control, in: .rect(cornerRadius: Radius.chip,
                                               style: .continuous))
    }
}
