Hover a row, click Play, and the transcript and meta line give way to a pixel waveform of that clip. Pause, scrub, or click **Transcript** to go back. I haven't compiled any of this, and I haven't measured the frame rate on a real display.

**How the waveform stays smooth**
- **Frame rate:** it redraws on every display frame (up to 120 Hz) and does nothing when idle. Each frame is a few fills of two cached paths, so it allocates almost nothing.
- **Playhead:** a scan line at 1 pt, snapped to a device pixel, so it moves about 1.5 device px per frame instead of jumping a column at a time. Cells it passes light up, cut crisp at the line. The cells behind it cool through a dithered trail (white head, then light blue, then blue).
- **Clock:** audio time arrives in about 10 ms buffer steps, so the playhead is dead-reckoned and slewed toward the sample clock. It is also offset by the output device's latency, so the line sits on the sound you hear.
- **Cells:** 4 pt cells with a 2 pt gap. Each column's tip is brighter than its core, as in the Island meter.

## 1. `ClipPlayer` patch (in `AudioPreview.swift`)

```swift
/// The sample clock is what the node RENDERED. This is when you HEAR it.
var outputLatency: TimeInterval { engine.outputNode.presentationLatency }
func prewarm() { if !engine.isRunning { engine.prepare() } }

/// Position in seconds, latency-compensated. Read once per frame. Deliberately not observed.
var time: TimeInterval {
    guard state == .playing, let clip, let nodeTime = node.lastRenderTime,
          let p = node.playerTime(forNodeTime: nodeTime) else { return parked }
    let t = Double(startSample) / clip.sampleRate + Double(p.sampleTime) / p.sampleRate
    return min(clip.duration, max(0, t - outputLatency))
}
```

## 2. `WaveTape.swift`

```swift
import Accelerate
import AVFoundation
import SuperflowDesignSystem
import SwiftUI

enum TapeMetrics {
    static let cell: CGFloat = 4, gap: CGFloat = 2, pitch: CGFloat = 6
    static let half = 3                       // 7 rows
    static let height: CGFloat = 40           // 7 * 6 - 2
}

enum ClipClock {
    /// Tenths, floored: 59.96 s never prints 0:60.0.
    static func format(_ t: TimeInterval) -> String {
        let n = max(0, Int((t * 10).rounded(.down)))
        return String(format: "%d:%02d.%d", n / 600, (n / 10) % 60, n % 10)
    }
}

// MARK: decode (samples only: no spectrogram, so Play starts instantly)

enum RowClipLoader {
    private final class Box { let clip: ClipData; init(_ c: ClipData) { clip = c } }
    private static let cache: NSCache<NSURL, Box> = {
        let c = NSCache<NSURL, Box>(); c.totalCostLimit = 64_000_000; return c
    }()
    static func peek(_ url: URL) -> ClipData? { cache.object(forKey: url as NSURL)?.clip }
    /// Call on hover: by the time you click, the clip is already in memory.
    static func preload(_ url: URL) { if peek(url) == nil { Task { _ = await load(url) } } }

    static func load(_ url: URL) async -> ClipData? {
        if let hit = peek(url) { return hit }
        let clip = await Task.detached(priority: .userInitiated) { decode(url) }.value
        if let clip { cache.setObject(Box(clip), forKey: url as NSURL, cost: clip.samples.count * 4) }
        return clip
    }

    nonisolated private static func decode(_ url: URL) -> ClipData? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              Double(file.length) <= file.processingFormat.sampleRate * 1_200,        // 20 min cap
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let ch = buffer.floatChannelData?[0] else { return nil }
        let samples = Array(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
        let rate = file.processingFormat.sampleRate
        return ClipData(url: url, samples: samples, sampleRate: rate, duration: Double(samples.count) / rate,
                        frames: 0, cells: [])
    }
}

// MARK: peaks -> cached paths

enum TapePeaks {
    /// One half-height (0...3) per column. Max-pooled, dB-mapped so quiet speech still lights a cell.
    static func heights(_ samples: [Float], cols: Int) -> [UInt8] {
        guard cols > 0, !samples.isEmpty else { return [] }
        var out = [UInt8](repeating: 0, count: cols)
        samples.withUnsafeBufferPointer { p in
            for c in 0..<cols {
                let lo = c * p.count / cols, hi = max(lo + 1, (c + 1) * p.count / cols)
                var m: Float = 0
                vDSP_maxmgv(p.baseAddress! + lo, 1, &m, vDSP_Length(hi - lo))
                let v = WaveformEngine.normalized(rms: m, floorDB: -54, ceilDB: -6)
                out[c] = v < 0.04 ? 0 : UInt8(min(3, Int((v * 3.15).rounded(.up))))
            }
        }
        return out
    }
}

/// Built once per (clip, width). Drawing a frame is a handful of fills of these paths, clipped.
final class WavePaths: @unchecked Sendable {
    let width: CGFloat
    let all: Path, core: Path, tips: Path, coreEven: Path, coreOdd: Path

    init(heights: [UInt8]) {
        let pitch = TapeMetrics.pitch, cell = TapeMetrics.cell, mid = TapeMetrics.half
        var all = Path(), core = Path(), tips = Path(), even = Path(), odd = Path()
        for (c, h) in heights.enumerated() {
            let hh = Int(h)
            for r in (mid - hh)...(mid + hh) {
                let rect = CGRect(x: CGFloat(c) * pitch, y: CGFloat(r) * pitch, width: cell, height: cell)
                all.addRect(rect)
                if abs(r - mid) == hh { tips.addRect(rect) }                    // the bright outer cell
                else { core.addRect(rect); if (c + r) % 2 == 0 { even.addRect(rect) } else { odd.addRect(rect) } }
            }
        }
        self.all = all; self.core = core; self.tips = tips; coreEven = even; coreOdd = odd
        width = CGFloat(heights.count) * pitch - TapeMetrics.gap
    }
}

/// Dead-reckons at 1x between audio-clock updates, then slews toward the sample clock.
final class PlayheadSmoother {
    private var value: TimeInterval = 0
    private var lastWall: TimeInterval = 0
    func step(now: TimeInterval, reported: TimeInterval, playing: Bool) -> TimeInterval {
        guard playing, lastWall != 0 else { value = reported; lastWall = playing ? now : 0; return value }
        let dt = min(0.05, now - lastWall); lastWall = now
        value += dt
        let err = reported - value
        if abs(err) > 0.06 { value = reported } else { value += err * 0.12 }
        return value
    }
}

#if DEBUG
/// Prints average fps and the worst frame once a second while playing. Verify 60-120 with this, not by eye.
final class FrameProbe {
    private var last: TimeInterval = 0, mark: TimeInterval = 0, worst: TimeInterval = 0, n = 0
    func tick(_ now: TimeInterval) {
        defer { last = now }
        guard last != 0 else { mark = now; return }
        n += 1; worst = max(worst, now - last)
        if now - mark >= 1 {
            print(String(format: "WaveTape %.1f fps, worst %.1f ms", Double(n) / (now - mark), worst * 1000))
            mark = now; n = 0; worst = 0
        }
    }
}
#endif

// MARK: the tape

private struct PathKey: Hashable { var url: URL?; var cols: Int }

struct WaveTape: View {
    let clip: ClipData?
    let unavailable: Bool
    let player: ClipPlayer
    @Binding var hover: TimeInterval?
    var onTouch: () -> Void = {}

    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var width: CGFloat = 0
    @State private var paths: WavePaths?
    @State private var reveal: CGFloat = 0
    @State private var scrubbing = false
    @State private var smoother = PlayheadSmoother()
    #if DEBUG
    @State private var probe = FrameProbe()
    #endif

    private var cols: Int { max(0, Int((width + TapeMetrics.gap) / TapeMetrics.pitch)) }

    var body: some View {
        let _ = player.moves                                          // redraw after a seek while paused
        let running = player.state == .playing || scrubbing
        let paths = paths, duration = clip?.duration ?? 0, hover = hover, reveal = reveal, scale = scale
        TimelineView(.animation(paused: !running)) { tl in
            let now = tl.date.timeIntervalSinceReferenceDate
            let played = smoother.step(now: now, reported: player.time, playing: player.state == .playing)
            let _ = { #if DEBUG
                if running { probe.tick(now) }
            #endif }()
            Canvas { ctx, size in
                Self.draw(&ctx, size, paths: paths, duration: duration, played: played,
                          hover: hover, reveal: reveal, scale: scale)
            }
        }
        .frame(height: TapeMetrics.height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .overlay { if unavailable { Text("Audio unavailable").appType(.caption).foregroundStyle(Tok.text2) } }
        .contentShape(.rect)
        .gesture(scrub)
        .onContinuousHover { phase in
            switch phase {
            case .active(let p): self.hover = clip == nil ? nil : time(at: p.x)
            case .ended: self.hover = nil
            }
        }
        .task(id: PathKey(url: clip?.url, cols: cols)) { await build() }
        .clickable(clip != nil)
        .accessibilityElement()
        .accessibilityLabel("Recording")
        .accessibilityValue(ClipClock.format(player.time))
        .accessibilityAdjustableAction { d in player.seek(player.time + (d == .increment ? 1 : -1)) }
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard clip != nil else { return }
                if !scrubbing { scrubbing = true; onTouch(); player.beginScrub() }
                player.scrub(to: time(at: g.location.x))               // tape-head grain under the pointer
            }
            .onEnded { _ in
                guard scrubbing else { return }
                scrubbing = false; player.endScrub()
            }
    }

    private func time(at x: CGFloat) -> TimeInterval {
        guard let clip, let w = paths?.width ?? Optional(width), w > 0 else { return 0 }
        return min(max(x / w, 0), 1) * clip.duration
    }

    private func build() async {
        guard let clip, cols > 0 else { paths = nil; reveal = 0; return }
        let samples = clip.samples, n = cols
        let built = await Task.detached(priority: .userInitiated) {
            WavePaths(heights: TapePeaks.heights(samples, cols: n))
        }.value
        guard !Task.isCancelled else { return }
        let first = paths == nil
        paths = built
        guard first else { return }
        guard !reduce else { reveal = 1; return }
        reveal = 0                                                      // the tape rolls out in 14 whole steps
        for k in 1...14 {
            try? await Task.sleep(for: .milliseconds(19))
            if Task.isCancelled { return }
            reveal = CGFloat(k) / 14
        }
    }

    // MARK: drawing. No per-cell work: 7 fills of cached paths.
    nonisolated private static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, paths: WavePaths?,
                                         duration: TimeInterval, played: TimeInterval, hover: TimeInterval?,
                                         reveal: CGFloat, scale: CGFloat) {
        func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        let h = TapeMetrics.height
        guard let p = paths, duration > 0 else {                        // dormant: a dotted midline
            var x: CGFloat = 0
            while x + TapeMetrics.cell <= size.width {
                ctx.fill(Path(CGRect(x: x, y: CGFloat(TapeMetrics.half) * TapeMetrics.pitch,
                                     width: TapeMetrics.cell, height: TapeMetrics.cell)),
                         with: .color(Tok.controlPressed), style: FillStyle(antialiased: false))
                x += TapeMetrics.pitch
            }
            return
        }
        let w = p.width
        let beam = snap(min(w, max(0, CGFloat(played / duration) * w)))
        ctx.drawLayer { l in
            l.clip(to: Path(CGRect(x: 0, y: 0, width: snap(w * reveal), height: h)))
            l.fill(p.all, with: .color(Tok.controlPressed), style: FillStyle(antialiased: false))      // unplayed
            guard beam > 0 else { return }
            let tail = min(8, beam), head = min(4, beam)
            l.drawLayer { s in                                          // played: core blue, tips light blue
                s.clip(to: Path(CGRect(x: 0, y: 0, width: beam - tail, height: h)))
                s.fill(p.core, with: .color(Ramp.blue[3]), style: FillStyle(antialiased: false))
                s.fill(p.tips, with: .color(Ramp.blue[4]), style: FillStyle(antialiased: false))
            }
            l.drawLayer { s in                                          // cooling trail: checker dither, no gradient
                s.clip(to: Path(CGRect(x: beam - tail, y: 0, width: tail, height: h)))
                s.fill(p.coreEven, with: .color(Ramp.blue[4]), style: FillStyle(antialiased: false))
                s.fill(p.coreOdd, with: .color(Ramp.blue[3]), style: FillStyle(antialiased: false))
                s.fill(p.tips, with: .color(Ramp.blue[4]), style: FillStyle(antialiased: false))
            }
            l.drawLayer { s in                                          // head: the newest tips go white
                s.clip(to: Path(CGRect(x: beam - head, y: 0, width: head, height: h)))
                s.fill(p.tips, with: .color(Tok.text), style: FillStyle(antialiased: false))
            }
            l.fill(Path(CGRect(x: min(beam, w - 1), y: 0, width: 1, height: h)),
                   with: .color(Tok.text), style: FillStyle(antialiased: false))                          // the scan line
        }
        if let hv = hover {                                             // ghost line: where a click would land
            let x = snap(min(w - 1, hv / duration * w))
            if abs(x - beam) > 2 {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: h)),
                         with: .color(Tok.text2), style: FillStyle(antialiased: false))
            }
        }
    }
}
```

## 3. `RowPlayer.swift`

```swift
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// Replaces the row's label while the clip plays. Space, arrows, Esc, and the Transcript button all work.
struct PlayerBar: View {
    let entry: DictationEntry
    let vm: RecentViewModel
    @State private var clip: ClipData?
    @State private var failed = false
    @State private var hover: TimeInterval?
    @FocusState private var focused: Bool

    var body: some View {
        let player = vm.audio
        let playing = player.state == .playing
        HStack(spacing: 12) {
            if let id = entry.bundleID { AppIcon(bundleID: id, size: 20) }
            else { Icon(.mic, size: 14, tint: Tok.text2).frame(width: 20, height: 20) }

            WaveTape(clip: clip, unavailable: failed, player: player, hover: $hover, onTouch: { focused = true })
                .frame(maxWidth: .infinity, alignment: .leading)

            PlayerReadout(player: player, hover: hover, total: clip?.duration ?? entry.duration)

            HStack(spacing: 4) {
                BarIconButton(glyph: playing ? .pause : .play, label: playing ? "Pause" : "Play") {
                    focused = true; player.toggle()
                }
                .disabled(clip == nil)
                AppButton("Transcript", glyph: nil, kind: .quiet, height: 24) { vm.stopPlayback() }
            }
            .padding(.trailing, -8)                                     // glyph edge, not the 32 pt target
        }
        .frame(height: 64)
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.space) { player.toggle(); return .handled }
        .onKeyPress(.leftArrow) { player.seek(player.time - 1); return .handled }
        .onKeyPress(.rightArrow) { player.seek(player.time + 1); return .handled }
        .onKeyPress(.escape) { vm.stopPlayback(); return .handled }
        .task(id: entry.id) { await start() }
        .onDisappear { if vm.playingID == entry.id { vm.stopPlayback() } }
    }

    /// The hover preload usually has the clip in memory already, so this is: load, play. No spinner.
    private func start() async {
        focused = true
        guard let url = entry.audio else { failed = true; return }
        let loaded: ClipData? = if let hit = RowClipLoader.peek(url) { hit } else { await RowClipLoader.load(url) }
        guard !Task.isCancelled else { return }
        guard let loaded else { failed = true; return }
        vm.audio.load(loaded)
        clip = loaded
        vm.audio.play()
    }
}

/// Current time in `text` (accent while the pointer is over the tape, because then it is the tooltip),
/// total in `text2`. Tabular, fixed width: nothing walks.
struct PlayerReadout: View {
    let player: ClipPlayer
    let hover: TimeInterval?
    let total: TimeInterval
    var body: some View {
        let _ = player.moves
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: player.state != .playing)) { _ in
            HStack(spacing: 6) {
                Text(ClipClock.format(hover ?? player.time)).foregroundStyle(hover != nil ? Tok.accentText : Tok.text)
                Text(ClipClock.format(total)).foregroundStyle(Tok.text2)
            }
            .appType(.label).monospacedDigit()
        }
        .frame(width: 96, alignment: .trailing)
    }
}
```

## 4. `TranscriptRow` (full replacement)

```swift
// RecentView.swift: replaces TranscriptRow. The old AudioPreview-in-detail is gone; Play lives in the row.
struct TranscriptRow: View {
    enum Variant: Hashable { case cleaned, raw }
    let entry: DictationEntry
    let vm: RecentViewModel
    @State private var hover = false
    @State private var mode: Variant = .cleaned
    @State private var menuOpen = false
    @FocusState private var focused: Bool

    private var playing: Bool { vm.playingID == entry.id }
    private var expanded: Bool { vm.expandedID == entry.id && !playing }
    private var revealed: Bool { hover || focused || menuOpen || expanded }
    private var shown: String { mode == .raw && !entry.raw.isEmpty ? entry.raw : entry.cleaned }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if playing {
                PlayerBar(entry: entry, vm: vm).transition(.opacity)
            } else {
                HStack(spacing: 4) {
                    Button { vm.toggle(entry.id) } label: { label }
                        .buttonStyle(.plain).focused($focused).focusEffectDisabled().clickable()
                    trailing
                }
                .frame(height: 56)
                .transition(.opacity)
            }
            if expanded { detail.transition(.opacity) }
        }
        .padding(.horizontal, 12)
        .background(playing ? Tok.well : hover ? Tok.control : .clear,
                    in: .rect(cornerRadius: Radius.nested, style: .continuous))
        .overlay(alignment: .leading) {
            if expanded || playing { Rectangle().fill(Ramp.blue[4]).frame(width: 2, height: 16) }   // pixel caret
        }
        .onHover { inside in
            hover = inside
            if inside, let u = entry.audio { RowClipLoader.preload(u); vm.audio.prewarm() }           // zero-lag Play
        }
        .animation(hover ? Motion.hoverIn : Motion.hoverOut, value: hover)
        .animation(.smooth(duration: 0.30), value: playing)
        .animation(.smooth(duration: 0.30), value: expanded)
    }

    private var label: some View {
        HStack(spacing: 12) {
            if let id = entry.bundleID { AppIcon(bundleID: id, size: 20) }
            else { Icon(.mic, size: 14, tint: Tok.text2).frame(width: 20, height: 20) }
            VStack(alignment: .leading, spacing: 2) {
                title
                HStack(spacing: 12) {
                    TimelineView(.everyMinute) { ctx in Text(Humanize.when(entry.date, now: ctx.date)) }
                    Text(Humanize.duration(entry.duration))
                    if entry.status == .done { Text(Humanize.words(entry.words)).monospacedDigit() }
                }
                .appType(.caption).foregroundStyle(Tok.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
    }

    @ViewBuilder private var title: some View {
        switch entry.status {
        case .done:
            Text(entry.cleaned.replacingOccurrences(of: "\n", with: " "))
                .appType(.label).foregroundStyle(Tok.text)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading).clipped()
                .modifier(EdgeFade(length: 32))
        case .failed(let why): Text(why).appType(.label).foregroundStyle(Tok.text2)
        case .cancelled: Text("Cancelled. Audio kept.").appType(.label).foregroundStyle(Tok.text2)
        case .retrying:
            HStack(spacing: 8) { RowWait(); Text("Transcribing").appType(.label).foregroundStyle(Tok.text2) }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch entry.status {
        case .done:
            HStack(spacing: 4) {
                if entry.audio != nil { BarIconButton(glyph: .play, label: "Play audio") { vm.play(entry) } }
                else { Color.clear.frame(width: 32, height: 32) }
                CopyButton { vm.copy(shown) }
                ActionMenu(actions: menu, isOpen: $menuOpen)
            }
            .padding(.trailing, -8)
            .opacity(revealed ? 1 : 0)
            .animation(revealed ? Motion.hoverIn : Motion.hoverOut, value: revealed)
        case .failed, .cancelled:
            HStack(spacing: 8) {
                Badge(entry.status == .cancelled ? "Cancelled" : "Failed")
                AppButton("Retry transcript", glyph: nil, kind: .secondary, height: 24) { vm.retry(entry) }
                ActionMenu(actions: menu, isOpen: $menuOpen)
            }
            .padding(.trailing, -8)
        case .retrying:
            Color.clear.frame(width: 32, height: 32)
        }
    }

    private var menu: [ActionMenu.Action] {
        var a: [ActionMenu.Action] = []
        if entry.audio != nil { a.append(.init(title: "Retry transcript", run: { vm.retry(entry) })) }
        a.append(.init(title: "Delete transcript", run: { vm.delete(entry) }))
        if entry.audio != nil { a.append(.init(title: "Extract audio", run: { vm.extractAudio(entry) })) }
        return a
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 16) {
            if entry.status == .done {
                if !entry.raw.isEmpty {
                    Segmented(selection: $mode,
                              items: [.init(value: .cleaned, title: "Cleaned"), .init(value: .raw, title: "Raw")],
                              onCard: true)
                }
                Text(shown).appType(.reading).foregroundStyle(Tok.text)
                    .textSelection(.enabled).frame(maxWidth: 720, alignment: .leading)
            }
        }
        .padding(.leading, 32).padding(.bottom, 16)
    }
}
```

## 5. `RecentViewModel` patch

```swift
// One player for the whole list: one engine, only one row ever plays.
let audio = ClipPlayer()
public private(set) var playingID: UUID?

public func play(_ e: DictationEntry) {
    guard e.audio != nil else { return }
    audio.stop()
    playingID = e.id
}
public func stopPlayback() { audio.stop(); playingID = nil }

// first line of retry(_:) and delete(_:)
if playingID == e.id { stopPlayback() }

// reload(): drop playback if its row left the list
if let p = playingID, !entries.contains(where: { $0.id == p }) { stopPlayback() }
```

Also call `vm.stopPlayback()` from the Dashboard's `onDisappear`, so audio never outlives the page.

## What I couldn't check

- **Frame rate:** drop `FrameProbe` in and read the console while a clip plays. It prints average fps and the worst frame. A Canvas in a `TimelineView` should follow ProMotion, but I haven't proven it here. If the worst frame is over about 8 ms, tell me the number.
- **Latency offset:** `presentationLatency` should line the scan line up with what you hear. On Bluetooth output, check whether it overcorrects.
- **First click:** `RowClipLoader.preload` and `prewarm` on hover make Play near-instant. A click without a hover first, such as keyboard focus, still decodes before it starts. For clips of a few seconds that is imperceptible.
- **Name fix:** the old `clock()` in `AudioPreview.swift` is `private`, so I added `ClipClock`. If the name collides, rename it.
- **Clip length cap:** clips over 20 minutes show "Audio unavailable". Streaming the decode would remove that cap, and I left it out.

This builds on the Island files from the last two rounds. It adds a new motion engine, a pixel-cancel dissolve, a pixel loader for submitting, a cleaner history panel, and a new meeting panel. Nothing here is compiled or measured on a real display, and I still haven't seen your shell view or `IslandHostingView`.

**How the motion works.** The old shell animated the shape with SwiftUI's `.smooth` and `.snappy`, which gave a fixed-length transition. This replaces it with a per-frame spring integrator.
- **The spring:** the silhouette's width, height and corner radii each follow an exact critically damped spring. It is frame-rate independent, it never overshoots, and a retarget mid-flight keeps its velocity, so interrupting a transition never restarts it.
- **The wave:** width leads and height follows slightly later, which gives the liquid feel.
- **Content:** it is laid out once at its final size and revealed by the growing silhouette. Nothing reflows mid-animation, and it runs at the display's refresh rate with zero cost at rest.

## 1. Context, stage IDs and sizes (`IslandScene.swift`, replace `spec`)

```swift
public struct IslandContext: Equatable, Sendable {
    public var prefs = IslandPrefs()
    public var historyRows = 5
    public var noSignal = false
    public init(prefs: IslandPrefs = .init(), historyRows: Int = 5, noSignal: Bool = false) {
        self.prefs = prefs; self.historyRows = historyRows; self.noSignal = noSignal
    }
}

/// Scenes that share a stage morph in place (hold -> latched). A new stage cross-dissolves.
public enum IslandStageID: Hashable, Sendable {
    case rest, listening, processing, landed, cancelled, failed, recent, history
    case meetingWings, meetingPanel, discard, saving
    case note(UUID)
}

public struct MeetingPulse: Equatable, Sendable {
    public var words: Int
    public var wpm: Int
    public var speakers: [SpeakerShare]
    public var current: String?
    public var slices: [Int8]            // speaker index per slice, -1 = silence
    public var slice: Double             // seconds per slice (2 is plenty)
    public var marks: [TimeInterval]     // seconds from the start
    public init(words: Int, wpm: Int, speakers: [SpeakerShare], current: String?,
                slices: [Int8], slice: Double, marks: [TimeInterval]) {
        self.words = words; self.wpm = wpm; self.speakers = speakers; self.current = current
        self.slices = slices; self.slice = slice; self.marks = marks
    }
    public static let empty = MeetingPulse(words: 0, wpm: 0, speakers: [], current: nil, slices: [], slice: 2, marks: [])
}

// IslandActions: add
//     func markMoment()
//     func endMeeting()

extension IslandScene {
    public var stage: IslandStageID {
        switch self {
        case .idle, .hover: .rest
        case .listening: .listening
        case .processing: .processing
        case .landed: .landed
        case .cancelled: .cancelled
        case .failed: .failed
        case .recent: .recent
        case .history: .history
        case .meeting(let m):
            switch m {
            case .recording: .meetingWings
            case .expanded: .meetingPanel
            case .confirmDiscard: .discard
            case .saving: .saving
            }
        case .note(let n): .note(n.id)
        }
    }

    public func spec(notch: CGFloat, band: CGFloat, ctx: IslandContext) -> IslandShapeSpec {
        let live = ctx.prefs.liveText
        func wings(_ extra: CGFloat, below: CGFloat = 0, top: CGFloat = 6, bottom: CGFloat = 14) -> IslandShapeSpec {
            IslandShapeSpec(width: notch + extra, height: band + below, top: top, bottom: bottom)
        }
        func wide(_ extra: CGFloat, below: CGFloat) -> IslandShapeSpec {
            IslandShapeSpec(width: max(notch + extra, 400), height: band + below, top: 8, bottom: 18)
        }
        func card(_ below: CGFloat = 60) -> IslandShapeSpec {
            IslandShapeSpec(width: 480, height: band + below, top: 12, bottom: 24)
        }
        switch self {
        case .idle: return IslandShapeSpec(width: notch, height: band, top: 0, bottom: 8)
        case .hover:
            return ctx.prefs.alwaysOn
                ? IslandShapeSpec(width: max(notch + 8, 232), height: band + 28, top: 6, bottom: 14)
                : IslandShapeSpec(width: notch + 8, height: band + 4, top: 6, bottom: 10)
        case .listening(let mode, let hint):
            let extra: CGFloat = mode == .latched ? 168 : 112
            if ctx.noSignal { return live ? wide(extra, below: 40) : wings(extra, below: 32, top: 8, bottom: 18) }
            if live { return wide(extra, below: 40) }
            return (mode == .latched && hint) ? wings(168, below: 32, top: 8, bottom: 18) : wings(extra)
        case .processing, .landed: return wings(112)
        case .cancelled, .recent: return card()
        case .failed: return card(148)
        case .history: return card(CGFloat(8 + max(2, ctx.historyRows) * 40 + 40))
        case .note: return card(76)
        case .meeting(let m):
            switch m {
            case .recording(let hint):
                if live { return wide(232, below: 40) }
                return hint ? wings(232, below: 32, top: 8, bottom: 18) : wings(232)
            case .expanded: return card(live ? 208 : 176)
            case .confirmDiscard: return card()
            case .saving: return wings(232)
            }
        }
    }
}
```

## 2. The motion engine (`IslandMotion.swift`, new)

This replaces `NotchShape` and your shell's animation code.

```swift
import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

// MARK: spring: exact critically damped solution, so no integration error and no overshoot
struct Spring1 {
    var x: Double, v = 0.0, target: Double
    init(_ x: Double) { self.x = x; target = x }
    mutating func step(_ dt: Double, omega w: Double) {
        let d = x - target, e = exp(-w * dt), c = v + w * d
        x = target + (d + c * dt) * e
        v = (v - w * c * dt) * e
    }
    var settled: Bool { abs(x - target) < 0.004 && abs(v) < 0.02 }
    mutating func land() { x = target; v = 0 }
}

struct IslandOmegas { var w: Double, h: Double, r: Double }   // rad/s. 98% settled in about 5.8 / omega seconds

enum IslandMotion {
    /// Width leads, height follows: that lag is the wave. Tune these numbers, not the system.
    static func omegas(from a: IslandShapeSpec, to b: IslandShapeSpec, band: CGFloat) -> IslandOmegas {
        let small = Double(band) + 40
        let (h0, h1) = (Double(a.height), Double(b.height))
        if h1 <= Double(band) + 8 { return .init(w: 20, h: 18, r: 28) }     // closing, about 0.32 s
        if h0 <= small, h1 > small { return .init(w: 15, h: 12, r: 26) }    // opening, about 0.44 s
        if h0 > small, h1 > small { return .init(w: 18, h: 15, r: 26) }     // card to card, about 0.38 s
        return .init(w: 30, h: 28, r: 34)                                   // wings to wings, about 0.20 s
    }
}

final class IslandKinematics {
    struct Frame { var width: CGFloat, height: CGFloat, top: CGFloat, bottom: CGFloat, settled: Bool }
    private var w = Spring1(0), h = Spring1(0), t = Spring1(0), b = Spring1(0)
    private var om = IslandOmegas(w: 30, h: 28, r: 34)
    private var last: TimeInterval?

    func snap(_ s: IslandShapeSpec) {
        w = Spring1(Double(s.width)); h = Spring1(Double(s.height))
        t = Spring1(Double(s.top)); b = Spring1(Double(s.bottom)); last = nil
    }

    /// Retargets from the CURRENT position and velocity, so interrupting a transition never restarts it.
    func retarget(_ s: IslandShapeSpec, band: CGFloat, instant: Bool) {
        if instant { snap(s); return }
        let from = IslandShapeSpec(width: CGFloat(w.x), height: CGFloat(h.x), top: CGFloat(t.x), bottom: CGFloat(b.x))
        om = IslandMotion.omegas(from: from, to: s, band: band)
        w.target = Double(s.width); h.target = Double(s.height)
        t.target = Double(s.top); b.target = Double(s.bottom); last = nil
    }

    func step(_ now: TimeInterval, scale: CGFloat) -> Frame {
        let dt = last.map { min(1.0 / 20, max(0, now - $0)) } ?? 0
        last = now
        if dt > 0 {
            w.step(dt, omega: om.w); h.step(dt, omega: om.h)
            t.step(dt, omega: om.r); b.step(dt, omega: om.r)
        }
        let done = w.settled && h.settled && t.settled && b.settled
        if done { w.land(); h.land(); t.land(); b.land(); last = nil }
        // whole device pixels: width even so the silhouette centres exactly on the notch
        return Frame(width: Pixel.snapEven(CGFloat(w.x), scale), height: Pixel.snap(CGFloat(h.x), scale),
                     top: CGFloat(t.x), bottom: CGFloat(b.x), settled: done)
    }
}

// MARK: silhouette. True quarter-circle Beziers, cusped concave fillets at the menu bar.
struct IslandSilhouette: Shape {
    var width: CGFloat       // body width. The flares live outside it: total = width + 2 * top
    var height: CGFloat
    var top: CGFloat
    var bottom: CGFloat

    func path(in rect: CGRect) -> Path {
        let k: CGFloat = 0.5522847498
        let t = min(top, height / 2)
        let b = max(0, min(bottom, width / 2, height - t))
        let x0 = rect.midX - (width + 2 * t) / 2, x1 = rect.midX + (width + 2 * t) / 2
        let y0 = rect.minY, y1 = rect.minY + height
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y0))
        p.addLine(to: CGPoint(x: x1, y: y0))
        p.addCurve(to: CGPoint(x: x1 - t, y: y0 + t),                                  // right flare
                   control1: CGPoint(x: x1 - k * t, y: y0), control2: CGPoint(x: x1 - t, y: y0 + t - k * t))
        p.addLine(to: CGPoint(x: x1 - t, y: y1 - b))
        p.addCurve(to: CGPoint(x: x1 - t - b, y: y1),                                  // bottom right
                   control1: CGPoint(x: x1 - t, y: y1 - b + k * b), control2: CGPoint(x: x1 - t - b + k * b, y: y1))
        p.addLine(to: CGPoint(x: x0 + t + b, y: y1))
        p.addCurve(to: CGPoint(x: x0 + t, y: y1 - b),                                  // bottom left
                   control1: CGPoint(x: x0 + t + b - k * b, y: y1), control2: CGPoint(x: x0 + t, y: y1 - b + k * b))
        p.addLine(to: CGPoint(x: x0 + t, y: y0 + t))
        p.addCurve(to: CGPoint(x: x0, y: y0),                                          // left flare
                   control1: CGPoint(x: x0 + t, y: y0 + t - k * t), control2: CGPoint(x: x0 + k * t, y: y0))
        p.closeSubpath()
        return p
    }
}

// MARK: content presence: blur 6 to 0, scale 0.94 to 1, anchored top. Removal is a plain fade.
private struct Presence: ViewModifier {
    let shown: Bool
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).blur(radius: shown ? 0 : 6).scaleEffect(shown ? 1 : 0.94, anchor: .top)
    }
}
extension AnyTransition {
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: AnyTransition.modifier(active: Presence(shown: false), identity: Presence(shown: true))
                .animation(Motion.islandIn),
            removal: AnyTransition.opacity.animation(Motion.islandOut))
    }
}

// MARK: the stage. Put this in your shell where the shape and content used to be.
struct IslandStage: View {
    let model: IslandModel
    @State private var kin = IslandKinematics()
    @State private var running = false
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let target = model.shape
        TimelineView(.animation(paused: !running)) { tl in
            let f = kin.step(tl.date.timeIntervalSinceReferenceDate, scale: scale)
            let _ = park(f.settled)
            let _ = publish(f)
            let shape = IslandSilhouette(width: f.width, height: f.height, top: f.top, bottom: f.bottom)
            ZStack(alignment: .top) {
                shape.fill(Tok.island)
                IslandContent(model: model)
                    .id(model.scene.stage)
                    .transition(reduce ? .opacity : .islandContent)
                    .frame(width: target.width, height: target.height, alignment: .top)   // laid out ONCE, at its final size
                    .frame(width: f.width + 2 * f.top, height: f.height, alignment: .top) // the box that follows the spring
                    .clipShape(shape)                                                      // the growing silhouette reveals it
            }
            .contentShape(shape)
            .onHover { model.hover($0) }
        }
        .frame(width: IslandLayout.canvas.width, height: IslandLayout.canvas.height, alignment: .top)
        .onAppear { kin.snap(target) }
        .onChange(of: target) { _, new in
            kin.retarget(new, band: model.geometry.band, instant: reduce)
            running = true
        }
        .animation(Motion.islandIn, value: model.scene.stage)
    }

    private func park(_ settled: Bool) {
        if settled && running { DispatchQueue.main.async { running = false } }   // zero cost at rest
    }
    /// IslandHostingView.hitTest reads this: the real, current silhouette rect.
    private func publish(_ f: IslandKinematics.Frame) {
        let w = f.width + 2 * f.top, cw = IslandLayout.canvas.width
        model.hitRect = CGRect(x: (cw - w) / 2, y: 0, width: w, height: f.height)
    }
}
```

## 3. Meter v2 (`IslandMeter.swift`, replace the model and both views)

The model is now frame-driven. Attack is about 10 ms, release about 80 ms, and it reacts within one frame of an input sample. The barcode scrolls by device pixel between samples, so it glides at the display rate while the cells stay crisp.

```swift
import SuperflowDesignSystem
import SwiftUI

@MainActor
public final class IslandMeterModel {
    public static let depth = 26
    public private(set) var trail = [Float](repeating: 0, count: IslandMeterModel.depth)   // newest first
    public private(set) var shown: Float = 0                                               // live, per frame
    public private(set) var phase: CGFloat = 0                                             // 0...1 inside the sample slot
    public private(set) var heard = false
    private var target: Float = 0, slotPeak: Float = 0
    private var lastNow: TimeInterval = 0, slotClock: TimeInterval = 0
    private let slot: TimeInterval = 1.0 / 30

    public func ingest(_ level: Float) {
        let v = min(1, max(0, level))
        target = v; slotPeak = max(slotPeak, v)
        if v > 0.06 { heard = true }
    }

    public func reset() {
        trail = [Float](repeating: 0, count: Self.depth)
        shown = 0; target = 0; slotPeak = 0; phase = 0; heard = false; lastNow = 0; slotClock = 0
    }

    /// Called by the views once per display frame. Idempotent inside a frame.
    public func advance(_ now: TimeInterval) {
        guard now != lastNow else { return }
        let dt = lastNow == 0 ? 1.0 / 60 : min(0.05, now - lastNow)
        lastNow = now
        let tau: Float = target > shown ? 0.010 : 0.080
        shown += (target - shown) * (1 - exp(-Float(dt) / tau))
        if shown < 0.005 { shown = 0 }
        slotClock += dt
        while slotClock >= slot {
            slotClock -= slot
            trail.insert(max(shown, slotPeak), at: 0); trail.removeLast()
            slotPeak = 0
        }
        phase = CGFloat(slotClock / slot)
    }
}

func islandHalf(_ v: Float, max m: Int) -> Int {
    v < 0.04 ? 0 : min(m, Int((v * Float(m) * 1.15).rounded(.up)))
}

private func cell(_ ctx: inout GraphicsContext, _ x: CGFloat, _ r: Int, _ tone: Color) {
    ctx.fill(Path(CGRect(x: x, y: CGFloat(r) * 3, width: 2, height: 2)),
             with: .color(tone), style: FillStyle(antialiased: false))
}

/// Dictation: a symmetric envelope radiating from the notch. Centre column is live, older ones are samples.
struct IslandPixelMeter: View {
    let meter: IslandMeterModel
    var columns = 11
    var body: some View {
        let cols = columns
        TimelineView(.animation) { tl in
            let _ = meter.advance(tl.date.timeIntervalSinceReferenceDate)
            let live = meter.shown, trail = meter.trail
            Canvas { ctx, _ in
                let mid = 3
                for c in 0..<cols {
                    let d = abs(c - cols / 2)
                    let h = islandHalf(d == 0 ? live : trail[min(d - 1, trail.count - 1)], max: 3)
                    let x = CGFloat(c) * 3
                    if h == 0 { cell(&ctx, x, mid, Ramp.blue[2]); continue }                // visible silence
                    for r in (mid - h)...(mid + h) {
                        cell(&ctx, x, r, abs(r - mid) == h ? (d == 0 ? Tok.text : Ramp.blue[4]) : Ramp.blue[3])
                    }
                }
            }
        }
        .frame(width: CGFloat(cols) * 3 - 1, height: 20).accessibilityHidden(true)
    }
}

/// Meetings: a scrolling barcode. A live column slides in from the right edge; older ones cool to navy.
struct IslandPixelBarcode: View {
    let meter: IslandMeterModel
    var columns = 24
    @Environment(\.displayScale) private var scale
    var body: some View {
        let cols = columns, scale = scale
        TimelineView(.animation) { tl in
            let _ = meter.advance(tl.date.timeIntervalSinceReferenceDate)
            let live = meter.shown, trail = meter.trail, phase = meter.phase
            Canvas { ctx, _ in
                let mid = 2
                for s in 0...cols {                                                          // s == cols is the live column
                    let age = cols - 1 - s
                    let v: Float = s == cols ? live : trail[min(age, trail.count - 1)]
                    let x = ((CGFloat(s) - phase) * 3 * scale).rounded() / scale             // glides in whole device pixels
                    let h = islandHalf(v, max: 2)
                    if h == 0 { cell(&ctx, x, mid, age > 15 ? Ramp.blue[1] : Ramp.blue[2]); continue }
                    let tone: Color = s == cols ? Tok.text : age < 3 ? Ramp.blue[4] : age < 14 ? Ramp.blue[3] : Ramp.blue[2]
                    for r in (mid - h)...(mid + h) { cell(&ctx, x, r, tone) }
                }
            }
        }
        .frame(width: CGFloat(cols) * 3 - 1, height: 14).accessibilityHidden(true)
    }
}
```

## 4. Pixel FX (`IslandFX.swift`, new)

```swift
import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

/// Cancel. The meter freezes on its last frame, then comes apart: outer cells fall one row and dim, then go,
/// the core follows, and what remains is a dotted line. 14 whole steps over 0.52 s. Plays once.
struct PixelDissolve: View {
    let trail: [Float]
    @State private var born = Date()
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let trail = trail, reduce = reduce
        TimelineView(.animation(paused: done)) { tl in
            let p = reduce ? 1 : min(1, tl.date.timeIntervalSince(born) / 0.52)
            let step = Int((p * 14).rounded(.down))
            let _ = { if p >= 1 && !done { Task { @MainActor in done = true } } }()
            Canvas { ctx, _ in
                let cols = 11, mid = 3
                func fill(_ c: Int, _ r: Int, _ tone: Color) {
                    ctx.fill(Path(CGRect(x: CGFloat(c) * 3, y: CGFloat(r) * 3, width: 2, height: 2)),
                             with: .color(tone), style: FillStyle(antialiased: false))
                }
                for c in 0..<cols {
                    let d = abs(c - cols / 2)
                    let h = islandHalf(trail[min(d, trail.count - 1)], max: 3)
                    if h > 0 {
                        for r in (mid - h)...(mid + h) {
                            let tip = abs(r - mid) == h
                            let die = Int((tip ? 0 : 5.0) + hash(c, r) * 6)                 // tips first, core last, scattered
                            if step < die { fill(c, r, tip ? Ramp.blue[4] : Ramp.blue[3]) }
                            else if step < die + 2 { fill(c, r + 1, Ramp.blue[2]) }         // falls one row, dims, goes
                        }
                    }
                    if h == 0 || step >= 12 { fill(c, mid, step >= 13 ? Ramp.blue[1] : Ramp.blue[2]) }
                }
            }
        }
        .frame(width: 32, height: 20).accessibilityHidden(true)
    }

    private func hash(_ i: Int, _ j: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: i) &* 374761393 &+ UInt32(truncatingIfNeeded: j) &* 668265263
        h = (h ^ (h >> 13)) &* 1274126177; h ^= h >> 16
        return Double(h) / Double(UInt32.max)
    }
}

/// Submitting. One pulse of the meter's own shape sweeps left to right with a white head and a dithered wake.
/// 1.1 s per pass, display-rate. This replaces the three-cell wait mark and stays the one looping mark.
struct PixelSweep: View {
    var columns = 11
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        let cols = columns, reduce = reduce
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let p = reduce ? Double(cols) / 2 : (t.truncatingRemainder(dividingBy: 1.1) / 1.1) * Double(cols + 8) - 4
            Canvas { ctx, _ in
                func fill(_ c: Int, _ r: Int, _ tone: Color) {
                    ctx.fill(Path(CGRect(x: CGFloat(c) * 3, y: CGFloat(r) * 3, width: 2, height: 2)),
                             with: .color(tone), style: FillStyle(antialiased: false))
                }
                for c in 0..<cols {
                    let x = Double(c), behind = x <= p
                    let g = exp(-pow((x - p) / 1.7, 2))
                    let h = Int((2.6 * g).rounded())
                    if h == 0 {
                        fill(c, 3, behind ? Ramp.blue[2] : Ramp.blue[1])
                        if behind, p - x < 4, c % 2 == 0 { fill(c, 2, Ramp.blue[2]); fill(c, 4, Ramp.blue[2]) }   // the wake
                        continue
                    }
                    for r in (3 - h)...(3 + h) {
                        let tip = abs(r - 3) == h, head = abs(x - p) < 0.5
                        fill(c, r, head && tip ? Tok.text : tip ? Ramp.blue[4] : Ramp.blue[3])
                    }
                }
            }
        }
        .frame(width: CGFloat(cols) * 3 - 1, height: 20).accessibilityHidden(true)
    }
}

/// Shown after about 2 s of listening if the microphone never produced a signal.
struct NoSignalShelf: View {
    var body: some View {
        HStack(spacing: 8) {
            Icon(.mic, size: 14, tint: Tok.statusBad)
            Text("No sound yet. Check your microphone.").appType(.caption).foregroundStyle(Tok.text2)
        }
        .frame(maxWidth: .infinity).frame(height: 32)
    }
}
```

## 5. History panel (`IslandHistory.swift`, replace)

The old panel had a close button, per-row copy buttons, a key-hint footer and expandable rows. This one has no buttons per row. Click a line to copy its cleaned text.

- **Quiet columns:** each row shows the app icon, one faded line, and the time.
- **Hover:** hover or selection swaps the time for a copy glyph in the same column, so nothing reflows.
- **Copy:** copying flashes `accentSoft` on the row and draws a pixel check.
- **Closing:** Esc or a click on the notch closes the panel.

```swift
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

struct HistoryPanel: View {
    let model: IslandModel
    @State private var cursor = 0
    @FocusState private var focused: Bool

    var body: some View {
        let g = model.geometry, rows = model.history
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Recent").appType(.label).foregroundStyle(Tok.text)
                    .padding(.leading, IslandLayout.cardPad).frame(maxWidth: .infinity, alignment: .leading)
                if g.hasNotch { Color.clear.frame(width: g.notch.width) }
                HStack(spacing: 6) {
                    Text(model.today.formatted()).monospacedDigit().foregroundStyle(Tok.text)
                    Text("words today").foregroundStyle(Tok.text2)
                }
                .appType(.caption)
                .padding(.trailing, IslandLayout.cardPad).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: g.band)

            VStack(spacing: 0) {
                if rows.isEmpty {
                    Text("Nothing dictated yet.").appType(.reading).foregroundStyle(Tok.text2)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, t in
                        HistoryRow(model: model, transcript: t, selected: i == cursor)
                            .modifier(RowReveal(index: i))
                    }
                }
            }
            .padding(.top, 8).padding(.horizontal, 8)

            HStack {
                Text("Click a line to copy it").appType(.caption).foregroundStyle(Tok.text2)
                Spacer(minLength: 0)
                AppButton("Open History", glyph: nil, kind: .quiet, height: 24) { model.openHistory() }
            }
            .padding(.horizontal, IslandLayout.cardPad).frame(height: 40)
            Spacer(minLength: 0)
        }
        .focusable().focused($focused).focusEffectDisabled()
        .onAppear { focused = true; cursor = 0 }
        .onKeyPress(.upArrow) { cursor = max(0, cursor - 1); return .handled }
        .onKeyPress(.downArrow) { cursor = min(max(0, rows.count - 1), cursor + 1); return .handled }
        .onKeyPress(.return) { if rows.indices.contains(cursor) { model.copy(rows[cursor]) }; return .handled }
        .onKeyPress(.escape) { model.send(.dismissed); return .handled }
    }
}

/// Lives in UIComponents (lint bans a raw Button in feature packages).
struct HistoryRow: View {
    let model: IslandModel
    let transcript: IslandTranscript
    let selected: Bool
    @State private var hover = false

    var body: some View {
        let t = transcript
        let copied = model.copiedID == t.id
        Button { model.copy(t) } label: {
            HStack(spacing: 12) {
                TargetIcon(bundleID: t.bundleID)
                Text(t.text.replacingOccurrences(of: "\n", with: " "))
                    .appType(.label).foregroundStyle(Tok.text)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading).clipped()
                    .modifier(EdgeFade(length: 32))
                ZStack(alignment: .trailing) {                                       // one column: time, copy glyph or check
                    Text(Humanize.when(t.date)).appType(.caption).foregroundStyle(Tok.text2)
                        .opacity(hover || selected || copied ? 0 : 1)
                    Icon(.copy, size: 14, tint: Tok.text2).opacity((hover || selected) && !copied ? 1 : 0)
                    PixelBitmap(rows: PixelBitmap.check, develop: 0.14).opacity(copied ? 1 : 0)
                }
                .frame(width: 64, alignment: .trailing)
            }
            .padding(.horizontal, 12).frame(height: 40)
            .background(copied ? Tok.accentSoft : (selected || hover) ? Tok.control : .clear,
                        in: .rect(cornerRadius: Radius.nested, style: .continuous))
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(Ramp.blue[4]).frame(width: 2, height: 16) }   // pixel caret, not a stroke
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain).focusEffectDisabled().clickable()
        .onHover { hover = $0 }
        .animation(hover ? Motion.hoverIn : Motion.hoverOut, value: hover)
        .animation(.snappy(duration: 0.20), value: copied)
        .accessibilityLabel("Copy: \(t.text)")
    }
}

/// Rows rise 6 pt and fade in, 35 ms apart. Reduce Motion shows them whole.
struct RowReveal: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0).offset(y: shown || reduce ? 0 : 6)
            .onAppear {
                guard !reduce else { return }
                withAnimation(.smooth(duration: 0.30).delay(Double(index) * 0.035)) { shown = true }
            }
    }
}
```

## 6. Meeting intelligence (`IslandMeetingPanel.swift`, replace)

Wings are unchanged: a record disc, the elapsed time, and the scrolling barcode. Click the wings to open the panel, which shows:
- **Clock and pace:** a live clock, the word count, and words per minute.
- **Timeline:** one strip for the whole meeting, a tick per time slice coloured by who spoke, a white head at now, and a dot for each marked moment.
- **Legend:** per-speaker talk share.
- **Actions:** Mark, Discard and End meeting.

The share bar is gone because the legend carries the same percentages.

```swift
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

func speakerTone(_ s: SpeakerShare, index: Int) -> Color {
    if s.isYou { return Ramp.blue[4] }
    switch index % 3 { case 0: return Tok.text2; case 1: return Ramp.blue[2]; default: return Ramp.blue[3] }
}

struct ClockMetric: View {
    let since: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let s = max(0, Int(tl.date.timeIntervalSince(since)))
            Text(s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                           : String(format: "%d:%02d", s / 60, s % 60))
                .appType(.metric).foregroundStyle(Tok.text).contentTransition(.numericText())
        }
        .frame(minWidth: 104, alignment: .leading)
    }
}

/// 110 ticks of 3 x 8 on a 4 pt pitch (440 pt). Each tick is a stretch of the meeting, coloured by who held the floor.
struct MeetingTimeline: View {
    let pulse: MeetingPulse
    var body: some View {
        let slices = pulse.slices, speakers = pulse.speakers, marks = pulse.marks, slice = pulse.slice
        Canvas { ctx, _ in
            let cols = 110, n = slices.count
            func fill(_ r: CGRect, _ c: Color) { ctx.fill(Path(r), with: .color(c), style: FillStyle(antialiased: false)) }
            guard n > 0 else {
                for c in 0..<cols { fill(CGRect(x: CGFloat(c) * 4 + 1, y: 9, width: 1, height: 1), Tok.controlPressed) }
                return
            }
            let group = max(1, Int(ceil(Double(n) / Double(cols))))
            let used = Int(ceil(Double(n) / Double(group)))
            for c in 0..<cols {
                let x = CGFloat(c) * 4
                guard c < used else { fill(CGRect(x: x + 1, y: 9, width: 1, height: 1), Tok.controlPressed); continue }
                var counts: [Int8: Int] = [:]
                for s in slices[(c * group)..<min(n, (c + 1) * group)] { counts[s, default: 0] += 1 }
                let top = counts.max { $0.value < $1.value }?.key ?? -1
                if top < 0 || Int(top) >= speakers.count { fill(CGRect(x: x + 1, y: 9, width: 1, height: 1), Ramp.blue[1]); continue }
                let tone = c == used - 1 ? Tok.text : speakerTone(speakers[Int(top)], index: Int(top))
                fill(CGRect(x: x, y: 6, width: 3, height: 8), tone)
            }
            for m in marks {                                                  // a marked moment: one white dot above the strip
                let c = min(used - 1, max(0, Int(m / (slice * Double(group)))))
                fill(CGRect(x: CGFloat(c) * 4, y: 0, width: 3, height: 3), Tok.text)
            }
        }
        .frame(width: 439, height: 14)
        .animation(.snappy(duration: 0.20), value: pulse.slices.count)
        .accessibilityHidden(true)
    }
}

struct MeetingPanel: View {
    let model: IslandModel
    var body: some View {
        let p = model.pulse
        let total = max(1, p.speakers.reduce(0) { $0 + $1.seconds })
        CardFrame(model: model, trailInset: IslandLayout.cardPad - 8) {
            HStack(spacing: 8) {
                PixelStop(cells: 7, cell: 2)
                Text("Recording").appType(.label).foregroundStyle(Tok.text)
            }
        } trail: {
            BarIconButton(glyph: .close, label: "Collapse") { model.send(.notchClicked) }
        } row: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 24) {
                    ClockMetric(since: model.meetingStart ?? .now)
                    stat(p.words.formatted(), "words")
                    stat(p.wpm == 0 ? "—" : "\(p.wpm)", "per minute")
                    Spacer(minLength: 0)
                    if let c = p.current {
                        HStack(spacing: 6) {
                            Rectangle().fill(Ramp.blue[4]).frame(width: 4, height: 4)
                            Text(c).appType(.caption).foregroundStyle(Tok.text).lineLimit(1)
                        }
                    }
                }
                MeetingTimeline(pulse: p)
                HStack(spacing: 16) {
                    ForEach(Array(p.speakers.prefix(4).enumerated()), id: \.element.id) { i, s in
                        HStack(spacing: 6) {
                            Rectangle().fill(speakerTone(s, index: i)).frame(width: 4, height: 4)
                            Text(s.name).appType(.caption).foregroundStyle(Tok.text2).lineLimit(1)
                            Text("\(Int((s.seconds / total * 100).rounded()))%")
                                .appType(.caption).monospacedDigit().foregroundStyle(Tok.text2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 16)
                if model.prefs.liveText { LiveLine(live: model.live).frame(height: 20) }
                HStack(spacing: 8) {
                    AppButton("Mark", glyph: nil, kind: .secondary, height: 28) { model.mark() }
                    if !p.marks.isEmpty {
                        Text("\(p.marks.count) marked").appType(.caption).monospacedDigit().foregroundStyle(Tok.text2)
                    }
                    Spacer(minLength: 0)
                    AppButton("Discard", glyph: nil, kind: .quiet, height: 24) { model.send(.meetingDiscardAsked) }
                    AppButton("End meeting", glyph: nil, kind: .primary, height: 28) { model.endMeeting() }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).appType(.title).monospacedDigit().foregroundStyle(Tok.text).contentTransition(.numericText())
            Text(label).appType(.caption).foregroundStyle(Tok.text2)
        }
    }
}
```

## 7. Patches to existing views

```swift
// IslandContent.body: three changed cases
case .processing: WingRow(model: model) { TargetIcon(bundleID: model.target?.bundleID) } right: { PixelSweep() }
case .landed(let w):
    WingRow(model: model) { TargetIcon(bundleID: model.target?.bundleID) } right: {
        HStack(spacing: 6) {
            PixelBitmap(rows: PixelBitmap.check, develop: 0.16)
            if w > 0 { Text("+\(w)").appType(.caption).monospacedDigit().foregroundStyle(Tok.text2) }
        }
    }
case .meeting(let m): MeetingView(model: model, state: m)       // unchanged, but see the two edits below

// ListeningView: pass the meter model, add the no-signal shelf
IslandPixelMeter(meter: model.meter, columns: mode == .latched ? 15 : 11)
// shelf slot, in this order:
if model.noSignal { NoSignalShelf().transition(.opacity) }
else if mode == .latched && hint { HintShelf(items: [("⏎ / fn", "Send"), ("esc", "Cancel")]).frame(height: model.prefs.liveText ? 40 : 32) }
else if model.prefs.liveText { LiveLine(live: model.live).padding(.horizontal, 20).frame(height: 40) }

// MeetingView .recording: barcode takes the model; saving uses the sweep
IslandPixelBarcode(meter: model.meter)
case .expanded: MeetingPanel(model: model)
case .saving: WingRow(...) { ... } right: { PixelSweep() }
// MeetingView: make the wings tappable (click opens the panel)
.contentShape(.rect).onTapGesture { model.send(.notchClicked) }     // a raw tap is lint-banned in features: wrap it in a UIComponents helper

// CancelledCard: the band-left becomes the dissolve plus the word
CardFrame(model: model) {
    HStack(spacing: 8) {
        PixelDissolve(trail: model.frozenTrail)
        Text("Cancelled.").appType(.label).foregroundStyle(Tok.text).lineLimit(1)
    }
} trail: { ... } row: { ... }          // trail and row unchanged

// IslandContent.history case is already `HistoryPanel(model:)`
```

## 8. Model patches (`IslandModel.swift`)

```swift
// properties
public private(set) var frozenTrail = [Float](repeating: 0, count: IslandMeterModel.depth)
public private(set) var noSignal = false
@ObservationIgnored public var hitRect = CGRect.zero
@ObservationIgnored private var wasActive = false
@ObservationIgnored private var silenceWatch: Task<Void, Never>?

public var context: IslandContext { IslandContext(prefs: prefs, historyRows: history.count, noSignal: noSignal) }
public var shape: IslandShapeSpec { scene.spec(notch: geometry.notch.width, band: geometry.band, ctx: context) }

// start(): the levels pump now clears the warning the moment sound arrives
Task { [weak self] in
    for await l in levels {
        guard let self else { return }
        meter.ingest(l)
        if noSignal, l > 0.06 { noSignal = false }
    }
},

// send(): capture the frozen frame BEFORE the machine runs and the meter resets
if case .cancelled = event { frozenTrail = meter.trail }

public func notchClicked() {
    recent = feed.lastTranscript(); history = feed.history(limit: 5); today = feed.wordsToday()
    send(.notchClicked)
}
public func mark() {
    actions.markMoment()
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
}
public func endMeeting() { actions.endMeeting(); send(.submitted) }

// replace syncMeter()
private func syncMeter() {
    var active = false, listening = false
    switch scene {
    case .listening: active = true; listening = true
    case .meeting(.recording(_)): active = true
    default: break
    }
    if active && !wasActive {
        meter.reset(); noSignal = false
        silenceWatch?.cancel()
        if listening {                                       // 2 s of nothing at all means the mic is not feeding us
            silenceWatch = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self, case .listening = scene, !meter.heard else { return }
                noSignal = true
            }
        }
    }
    if !active { silenceWatch?.cancel(); noSignal = false }
    wasActive = active
}
```

## 9. Wiring

```swift
// Shell: delete NotchShape and the phase-driven animation. The whole view is now:
IslandStage(model: model)
// IslandHostingView.hitTest: replace the per-state rect with
let r = model.hitRect.insetBy(dx: -4, dy: -4)
if scene is .idle on a notch { r = model.hitRect }      // idle stays exactly the notch, 0 slop

// Panel: .history and .meeting(.expanded) become key like .recent (the keyboard handlers need it)
// Canvas height stays 360. The silhouette never exceeds band + 248.
```

**DESIGN.md changes:**
- §8.18 motion: replace the SwiftUI animation rows with the critically damped springs and their ω table.
- §8.18 wait mark: the three-cell mark becomes the sweep, which is still the only looping mark.
- Add the new `PixelDissolve` to the Island's list of marks.

## What I haven't verified

- **Clipped-content approach:** `IslandStage` lays content out at its final size and clips it to the animating silhouette. If your panel's hosting view applies a second clip, check that the flare corners aren't cut.
- **`TimelineView` pausing:** the pause-at-settle logic is the most likely thing to need a tweak. If the Island ever stops animating, set `running = true` in `onChange`'s caller, and look at `park`.
- **Hit-testing:** `hitRect` is published from inside a render pass. If your host reads it off the main thread, mirror it into an atomic.
- **Spring constants:** the ω values are by-arithmetic, not by-eye. Tune them in `IslandMotion.omegas`, because a ±20% ω change reads as a clear speed change.
- **Barcode glide and frame rate:** I haven't measured the glide at 120 Hz. Reuse the `FrameProbe` from the last round on the stage if you want numbers.
- **`MeetingPulse` data:** `slices`, `wpm` and `marks` need to come from the diarizer and word counter. I wrote the consumer, not the producer.
- **Raw taps:** `onTapGesture` and the `HistoryRow` button both need to move into UIComponents for the lint.