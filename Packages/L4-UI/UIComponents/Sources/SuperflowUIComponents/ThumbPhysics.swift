import Foundation
import Observation

final class ThumbPhysics {
    private(set) var x: Double
    private(set) var velocity = 0.0
    var target: Double
    var omega = 28.0
    private var last: TimeInterval?

    init(at x: Double) { self.x = x; target = x }
    var settled: Bool { abs(x - target) < 0.02 && abs(velocity) < 0.1 }

    func snap(to x: Double) {
        self.x = x; target = x; velocity = 0; last = nil
    }

    func step(_ now: TimeInterval) -> Double {
        let dt = last.map { min(0.05, max(0, now - $0)) } ?? 0
        last = now
        if dt > 0 {
            let distance = x - target
            let decay = exp(-omega * dt)
            let rate = velocity + omega * distance
            x = target + (distance + rate * dt) * decay
            velocity = (velocity - omega * rate * dt) * decay
        }
        if settled { x = target; velocity = 0; last = nil }
        return x
    }
}

@MainActor @Observable
final class SliderFrameClock {
    var running = false
    var revision = 0
    func kick() { revision += 1; running = true }
    func park() {
        guard running else { return }
        let revision = revision
        Task { @MainActor [weak self] in
            guard let self, self.revision == revision else { return }
            self.running = false
        }
    }
}
