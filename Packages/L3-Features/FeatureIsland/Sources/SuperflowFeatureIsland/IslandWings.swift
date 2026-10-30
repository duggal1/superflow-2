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
    /// The scene being drawn. The outgoing layer passes the previous phase so a
    /// crossfade cannot repaint the wings with the incoming marks.
    let phase: IslandPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            if phase == .handsFree {
                ZStack {
                    HintShelf(items: hints ?? [])
                        .opacity(model.noSignal ? 0 : (model.hint ? 1 : 0))
                    if model.prefs.liveText {
                        LiveLine(live: model.live)
                            .padding(.horizontal, 20)
                            .opacity(model.noSignal || model.hint ? 0 : 1)
                    }
                    if model.noSignal {
                        NoSignalShelf()
                    }
                }
                // Kept in the tree while the silhouette shrinks, so the shelf is
                // revealed by the moving shape instead of popping out of it.
                .frame(height: model.prefs.liveText ? IslandLayout.liveShelf : IslandLayout.hintShelf)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: model.hint)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: model.noSignal)
                .modifier(Entrance(delay: 0.10, dy: 4))
            } else if model.noSignal {
                NoSignalShelf()
                    .transition(.opacity)
            } else if model.hint, let hints {
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
        .animation(reduceMotion ? nil : .smooth(duration: 0.30), value: model.noSignal)
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
                RollingClock(since: model.sessionStart ?? .now)
                    .modifier(Entrance(dx: -8, dy: 0))
            }
            .accessibilityLabel("Hands-free dictation")
        case .meeting:
            HStack(spacing: 8) {
                RecordDisc()
                RollingClock(since: model.meetingStart ?? model.sessionStart ?? .now)
                    .accessibilityLabel("Meeting running")
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
            IslandPixelMeter(meter: model.meter)
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .handsFree:
            // A latched session is wider than a held one: there is no key to
            // release, so the meter has more history to show.
            IslandPixelMeter(meter: model.meter, columns: 15)
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .meeting:
            IslandPixelBarcode(meter: model.meter)
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .processing:
            PixelSweep()
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .landed(let words):
            HStack(spacing: 6) {
                PixelBitmap(rows: PixelBitmap.check, develop: 0.16)
                if words > 0 {
                    Text("+\(words)")
                        .appType(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Tok.text2)
                }
            }
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
}

/// The real icon of the app the text will land in. The microphone stands in only
/// when the target is unknown.
struct TargetIcon: View {
    let bundleID: String?

    var body: some View {
        if let bundleID {
            AppIcon(bundleID: bundleID, size: 20)
        } else {
            IconView(.mic, size: 14, tint: Tok.text2)
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
