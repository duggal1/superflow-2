import Foundation

/// The Island's input meter, driven by display frames rather than by the audio
/// clock. Attack is about 10 ms, release about 80 ms, so a level shows within
/// one frame of arriving and a word still fades instead of flickering.
///
/// Samples are kept on a 30 Hz slot clock: the trail advances at a fixed rate
/// even at 120 Hz, while `shown` follows every frame and the barcode uses
/// `phase` to glide between slots by whole device pixels.
@MainActor
final class IslandMeterModel {
    static let depth = 26

    /// Newest first. The view reads one entry per column.
    private(set) var trail = [Float](repeating: 0, count: IslandMeterModel.depth)
    /// The level drawn in the live column, updated every frame.
    private(set) var shown: Float = 0
    /// How far the slot clock has advanced inside the current sample, 0...1.
    private(set) var phase: CGFloat = 0
    /// True once any real signal has arrived in this session.
    private(set) var heard = false

    private var target: Float = 0
    private var slotPeak: Float = 0
    private var lastNow: TimeInterval = 0
    private var slotClock: TimeInterval = 0
    private let slot: TimeInterval = 1.0 / 30

    func ingest(_ level: Float) {
        let value = level.isFinite ? min(1, max(0, level)) : 0
        target = value
        slotPeak = max(slotPeak, value)
        if value > 0.06 { heard = true }
    }

    func reset() {
        trail = [Float](repeating: 0, count: Self.depth)
        shown = 0
        target = 0
        slotPeak = 0
        phase = 0
        heard = false
        lastNow = 0
        slotClock = 0
    }

    /// Called by the meter views once per display frame. Idempotent within a
    /// frame, so two visible meters cannot advance the clock twice.
    func advance(_ now: TimeInterval) {
        guard now.isFinite, now > lastNow else { return }
        let dt = lastNow == 0 ? 1.0 / 60 : min(0.05, now - lastNow)
        lastNow = now
        let tau: Float = target > shown ? 0.010 : 0.080
        shown += (target - shown) * (1 - exp(-Float(dt) / tau))
        if shown < 0.005 { shown = 0 }
        slotClock += dt
        while slotClock >= slot {
            slotClock -= slot
            trail.insert(max(shown, slotPeak), at: 0)
            trail.removeLast()
            slotPeak = 0
        }
        phase = CGFloat(slotClock / slot)
    }
}

/// Level -> half-height in cells. Any real signal lights at least one cell.
func islandHalf(_ value: Float, max maximum: Int) -> Int {
    value < 0.04 ? 0 : min(maximum, Int((value * Float(maximum) * 1.15).rounded(.up)))
}
