import Foundation
import Observation

/// The pixel meter's data. One trail of levels, newest first, one entry per
/// 33 ms frame.
///
/// The dictation meter reads the trail symmetrically from its centre column; the
/// meeting barcode reads the same trail as a scrolling strip, so both meters are
/// the same measurement at two different lengths. Silence is a value (0), never
/// a hidden view: the views draw an unlit column as a blue dot on the midline.
@MainActor @Observable
public final class WaveformModel {
    public static let columns = 11
    public static let barcodeColumns = 24
    public static let rows = 7
    public static let halfMax = 3

    /// Anything quieter than this is silence. Four percent, not five: a word at
    /// the edge of the gate must still light one cell.
    public static let silence: Float = 0.04
    /// Fast attack, slower release. A syllable lands within a frame; a tail
    /// decays over roughly half a second instead of snapping to zero.
    public static let attack: Float = 0.6
    public static let release: Float = 0.25

    public static let depth = barcodeColumns

    /// Newest first. `trail[0]` is the level measured this frame.
    public private(set) var trail = [Float](repeating: 0, count: depth)

    @ObservationIgnored private var shown: Float = 0
    @ObservationIgnored private var live = false

    public init() {}

    /// The microphone is open. When it closes the trail keeps decaying, so the
    /// last envelope drains instead of vanishing.
    public func setLive(_ on: Bool) {
        live = on
    }

    /// One 33 ms frame. `level` is 0...1, already mapped from dBFS.
    public func tick(level: Float) {
        let heard = live ? min(1, max(0, level)) : 0
        let target = heard < Self.silence ? 0 : heard
        shown += (target - shown) * (target > shown ? Self.attack : Self.release)
        if shown < 0.01 { shown = 0 }
        // Idle silence costs nothing: the trail is already all zero, so leave it.
        guard shown != 0 || trail.contains(where: { $0 != 0 }) else { return }
        trail.removeLast()
        trail.insert(shown, at: 0)
    }

    public func reset() {
        shown = 0
        live = false
        trail = [Float](repeating: 0, count: Self.depth)
    }

    /// Level to half-height in cells. Any signal above the gate lights at least
    /// one cell; the 1.15 gain puts a normal speaking voice near the top.
    public static func cells(_ level: Float, max m: Int) -> Int {
        guard level >= silence else { return 0 }
        return min(m, Int((level * Float(m) * 1.15).rounded(.up)))
    }
}
