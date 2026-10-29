import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// Replaces the row's label while the clip plays. Space, arrows, Esc, and the
/// Transcript button all work.
struct PlayerBar: View {
    let entry: RecentDictationEntry
    @ObservedObject var model: RecentDictationViewModel
    @State private var clip: ClipData?
    @State private var failed = false
    @State private var hover: TimeInterval?
    @FocusState private var focused: Bool

    private var total: TimeInterval {
        clip?.duration ?? Double(max(0, entry.record.durationMs)) / 1_000
    }

    var body: some View {
        let player = model.audio
        let playing = player.state == .playing
        HStack(spacing: 12) {
            if let id = entry.record.frontmostBundleID { AppIcon(bundleID: id, size: 16) }
            else { Icon(.mic, size: 12, tint: Tok.text2).frame(width: 16, height: 16) }

            WaveTape(clip: clip, unavailable: failed, player: player, hover: $hover,
                     onTouch: { focused = true })
                .frame(maxWidth: .infinity, alignment: .leading)

            PlayerReadout(player: player, hover: hover, total: total)

            HStack(spacing: 4) {
                RowIconButton(glyph: playing ? .pause : .play,
                              label: playing ? "Pause" : "Play") {
                    focused = true
                    player.toggle()
                }
                .disabled(clip == nil)
                AppButton("Transcript", glyph: nil, kind: .quiet, height: 24) { model.stopPlayback() }
            }
            .padding(.trailing, -8)                                     // glyph edge, not the 32 pt target
        }
        .frame(height: 64)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.space) { player.toggle(); return .handled }
        .onKeyPress(.leftArrow) { player.seek(player.time - 1); return .handled }
        .onKeyPress(.rightArrow) { player.seek(player.time + 1); return .handled }
        .onKeyPress(.escape) { model.stopPlayback(); return .handled }
        .task(id: entry.id) { await start() }
        .onDisappear { if model.playingID == entry.id { model.stopPlayback() } }
    }

    /// The hover preload usually has the clip in memory already, so this is:
    /// load, play. No spinner.
    private func start() async {
        focused = true
        guard let url = entry.audio else { failed = true; return }
        let loaded: ClipData?
        if let hit = RowClipLoader.peek(url) {
            loaded = hit
        } else {
            loaded = await RowClipLoader.load(url)
        }
        guard !Task.isCancelled else { return }
        guard let loaded else { failed = true; return }
        model.audio.load(loaded)
        clip = loaded
        model.audio.play()
    }
}

/// Current time in `text` (accent while the pointer is over the tape, because
/// then it is the tooltip), total in `text2`. Tabular, fixed width: nothing walks.
struct PlayerReadout: View {
    let player: ClipPlayer
    let hover: TimeInterval?
    let total: TimeInterval

    var body: some View {
        let _ = player.moves
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: player.state != .playing)) { _ in
            HStack(spacing: 6) {
                Text(ClipClock.format(hover ?? player.time))
                    .foregroundStyle(hover != nil ? Tok.accentText : Tok.text)
                Text(ClipClock.format(total)).foregroundStyle(Tok.text2)
            }
            .appType(.label)
            .monospacedDigit()
        }
        .frame(width: 96, alignment: .trailing)
    }
}
