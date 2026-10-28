import Foundation
import Observation

/// The pixel waveform's data. A tiny LED matrix mirrored about the centre column:
/// newest level in the centre, older levels spreading outward.
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
        let target: Float = live ? (level < 0.05 ? 0 : level) : 0
        smoothed += (target - smoothed) * (target > smoothed ? 0.6 : 0.25)
        let half = min(Self.halfMax, Int(smoothed * Float(Self.halfMax + 1)))
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
