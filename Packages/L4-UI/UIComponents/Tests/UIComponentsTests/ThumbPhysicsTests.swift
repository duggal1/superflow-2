import XCTest
@testable import SuperflowUIComponents

final class ThumbPhysicsTests: XCTestCase {
    func testConvergesWithoutOvershootingAtSixtyAndOneTwentyHertz() {
        for fps in [60.0, 120.0] {
            for target in [-100.0, 278.0] {
                let physics = ThumbPhysics(at: 0)
                physics.target = target
                var last = 0.0
                for frame in 0..<500 {
                    let next = physics.step(1 + Double(frame) / fps)
                    XCTAssertGreaterThanOrEqual(next, min(0, target))
                    XCTAssertLessThanOrEqual(next, max(0, target))
                    XCTAssertLessThanOrEqual(abs(next - target), abs(last - target))
                    last = next
                }
                XCTAssertEqual(physics.x, target, accuracy: 0.02)
                XCTAssertTrue(physics.settled)
            }
        }
    }
}
