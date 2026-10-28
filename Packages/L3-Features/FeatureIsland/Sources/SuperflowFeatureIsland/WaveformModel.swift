import Foundation
import Observation

/// The pixel waveform's data. A tiny LED matrix mirrored about the centre column:
/// newest level in the centre, older levels spreading outward.
///
/// While the microphone closes the last envelope keeps decaying instead of
/// snapping to silence, and the ticker keeps running through `processing`. That
/// tail is what the Island draws while cleanup runs, so the meter is present for
/// the whole session instead of being replaced by a wait mark the moment fn is
/// released. Silence itself is a dotted line, never a hidden view.
@MainActor @Observable
public final class WaveformModel {
    public static let columns = 11
    public static let rows = 7
    public static let halfMax = 3
    public static let historyCount = 6

    /// Newest first. `history[d]` drives the two columns at distance `d` from the centre.
    public private(set) var history = [Int](repeating: 0, count: historyCount)

    @ObservationIgnored private var smoothed: Float = 0
    @ObservationIgnored private var live = false

    public init() {}

    public func setLive(_ on: Bool) {
        live = on
    }

    /// 30 Hz. Fast attack, slow release, noise gate, quantised to whole cells.
    public func tick(level: Float) {
        let heard = live && level >= 0.05
        let target: Float = heard ? min(1, level) : 0
        // Attack is fast so a word lands within a frame or two; the release is
        // slower while the mic is open (a natural tail) and slightly faster once
        // it closes, so the cleanup meter empties instead of lingering.
        let rate: Float = target > smoothed ? 0.55 : (live ? 0.25 : 0.30)
        smoothed += (target - smoothed) * rate

        let half = smoothed < 0.05
            ? 0
            : min(Self.halfMax, Int((smoothed * Float(Self.halfMax + 1)).rounded()))
        var next = history
        next.removeLast()
        next.insert(half, at: 0)
        if next != history { history = next }
    }

    public func reset() {
        smoothed = 0
        live = false
        history = [Int](repeating: 0, count: Self.historyCount)
    }
}
