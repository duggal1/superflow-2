import Accelerate
import AVFoundation
import Foundation
import Observation
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// The clip the recognizer heard, as a picture, with a tape head instead of a
/// progress bar. Space plays and pauses, the arrows step a second, once the card
/// has focus.
struct AudioPreview: View {
    let url: URL
    @State private var player = ClipPlayer()
    @State private var clip: ClipData?
    @State private var failed = false
    @State private var hover: TimeInterval?
    @FocusState private var focused: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                SpectroScrubber(clip: clip, unavailable: failed, player: player,
                                hover: $hover, onTouch: { focused = true })
                HStack(spacing: 8) {
                    BarIconButton(glyph: player.state == .playing ? .pause : .play,
                                  label: player.state == .playing ? "Pause" : "Play") {
                        focused = true
                        player.toggle()
                    }
                    .disabled(clip == nil)
                    Readout(player: player, hover: hover, total: clip?.duration ?? 0)
                    Spacer(minLength: 16)
                    // The one non-obvious gesture, revealed only under the pointer.
                    // Always laid out, so showing it never moves the row.
                    Text("Drag to hear")
                        .appType(.caption)
                        .foregroundStyle(Tok.text2)
                        .opacity(hover == nil ? 0 : 1)
                        .animation(.easeOut(duration: 0.15), value: hover == nil)
                }
                .frame(height: 32)
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.space) {
            player.toggle()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            player.seek(player.time - 1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            player.seek(player.time + 1)
            return .handled
        }
        .task(id: url) { await load() }
        .onDisappear { player.stop() }
        .pixelAudit("AudioPreview")
    }

    private func load() async {
        player.stop()
        clip = nil
        failed = false
        guard let loaded = await ClipLoader.load(url) else {
            failed = true
            return
        }
        guard !Task.isCancelled else { return }
        player.load(loaded)
        clip = loaded
    }
}

/// Current time in `text`, total in `text2`, tenths of a second. Under the
/// pointer it shows the hovered time: the readout is the tooltip.
private struct Readout: View {
    let player: ClipPlayer
    let hover: TimeInterval?
    let total: TimeInterval

    var body: some View {
        let _ = player.moves
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: player.state != .playing)) { _ in
            HStack(spacing: 8) {
                Text(clock(hover ?? player.time)).foregroundStyle(Tok.text)
                Text(clock(total)).foregroundStyle(Tok.text2)
            }
            .appType(.label)
            .monospacedDigit()
        }
    }
}

/// Sample-accurate playback over the decoded clip, with 90 ms Hann grains under
/// the pointer while scrubbing. One clock: the player node's own sample time.
@MainActor @Observable
final class ClipPlayer {
    enum State { case idle, playing, paused }

    private(set) var state: State = .idle
    private(set) var duration: TimeInterval = 0
    /// Bumps on every seek and scrub, so a paused scrubber redraws.
    private(set) var moves = 0

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let node = AVAudioPlayerNode()
    @ObservationIgnored private var clip: ClipData?
    @ObservationIgnored private var format: AVAudioFormat?
    @ObservationIgnored private var grainWindow: [Float] = []
    @ObservationIgnored private var startSample = 0
    @ObservationIgnored private var parked: TimeInterval = 0
    /// Invalidates callbacks from a segment that has been replaced.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var scrubbing = false
    @ObservationIgnored private var resumeAfterScrub = false
    @ObservationIgnored private var lastGrain: TimeInterval = -1

    /// Position in seconds. Read once per frame by the views; deliberately not observed.
    var time: TimeInterval {
        guard state == .playing, let clip, let render = node.lastRenderTime,
              let played = node.playerTime(forNodeTime: render) else { return parked }
        return min(clip.duration,
                   Double(startSample) / clip.sampleRate + Double(played.sampleTime) / played.sampleRate)
    }

    func load(_ clip: ClipData) {
        stop()
        self.clip = clip
        duration = clip.duration
        parked = 0
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: clip.sampleRate,
                                   channels: 1,
                                   interleaved: false)!
        self.format = format
        if node.engine == nil { engine.attach(node) }
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        let count = Int(clip.sampleRate * 0.09)
        grainWindow = [Float](repeating: 0, count: count)
        vDSP_hann_window(&grainWindow, vDSP_Length(count), Int32(vDSP_HANN_DENORM))
    }

    func play() {
        guard let clip else { return }
        start(at: parked >= clip.duration - 0.02 ? 0 : parked)
    }

    func pause() {
        guard state == .playing else { return }
        parked = time
        generation += 1
        node.stop()
        state = .paused
        moves += 1
    }

    func toggle() {
        if state == .playing { pause() } else { play() }
    }

    func seek(_ t: TimeInterval) {
        let target = min(max(t, 0), duration)
        if state == .playing {
            start(at: target)
        } else {
            parked = target
            moves += 1
        }
    }

    func stop() {
        generation += 1
        node.stop()
        engine.stop()
        state = .idle
        parked = 0
        scrubbing = false
    }

    // MARK: tape-head scrub

    func beginScrub() {
        resumeAfterScrub = state == .playing
        if state == .playing {
            parked = time
            generation += 1
            node.stop()
            state = .paused
        }
        scrubbing = true
        lastGrain = -1
        guard ensureRunning() else { return }
        node.play()
    }

    func scrub(to t: TimeInterval) {
        guard scrubbing, let clip, let format else { return }
        let target = min(max(t, 0), clip.duration)
        parked = target
        moves += 1
        // 12 ms: more events than that adds nothing audible.
        guard abs(target - lastGrain) > 0.012 else { return }
        lastGrain = target
        let start = Int(target * clip.sampleRate)
        let end = min(start + grainWindow.count, clip.samples.count)
        guard end - start > 64, let buffer = pcmBuffer(start..<end, format) else { return }
        let head = buffer.floatChannelData![0]
        // Hann: no click at either edge of the grain.
        vDSP_vmul(head, 1, grainWindow, 1, head, 1, vDSP_Length(end - start))
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    func endScrub() {
        guard scrubbing else { return }
        scrubbing = false
        if resumeAfterScrub { start(at: parked) }
        // Otherwise the last grain is left to finish on its own: stopping the
        // node here would cut the Hann window and click.
    }

    // MARK: internals

    private func start(at t: TimeInterval) {
        guard let clip, let format, ensureRunning() else { return }
        let from = min(max(Int(t * clip.sampleRate), 0), clip.samples.count - 1)
        guard clip.samples.count - from > 64,
              let buffer = pcmBuffer(from..<clip.samples.count, format) else { return }
        generation += 1
        let generation = self.generation
        node.stop()
        startSample = from
        node.scheduleBuffer(buffer, at: nil, options: [],
                            completionCallbackType: .dataPlayedBack) { [weak self] _ in
            _ = Task { @MainActor in
                guard let self, self.generation == generation, self.state == .playing else { return }
                self.parked = clip.duration
                self.state = .paused
                self.moves += 1
            }
        }
        node.play()
        state = .playing
    }

    private func ensureRunning() -> Bool {
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    private func pcmBuffer(_ range: Range<Int>, _ format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let clip,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(range.count)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(range.count)
        clip.samples.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress! + range.lowerBound,
                                               count: range.count)
        }
        return buffer
    }
}
