import Dispatch
import Foundation
import XCTest
@testable import SuperflowAudioCapture

final class GenerationGateTests: XCTestCase {
    func testAdvancingInvalidatesEveryEarlierGeneration() {
        let gate = GenerationGate()
        XCTAssertEqual(gate.generation, 0)
        XCTAssertTrue(gate.isCurrent(0))

        let first = gate.advance()
        XCTAssertEqual(first, 1)
        XCTAssertFalse(gate.isCurrent(0))
        XCTAssertTrue(gate.isCurrent(first))

        let second = gate.advance()
        XCTAssertEqual(second, 2)
        XCTAssertFalse(gate.isCurrent(first))
        XCTAssertTrue(gate.isCurrent(second))
    }

    func testConcurrentSwitchesProduceUniqueGenerations() {
        let gate = GenerationGate(start: 5)
        let lock = NSLock()
        var issued: Set<UInt64> = []
        DispatchQueue.concurrentPerform(iterations: 128) { _ in
            let generation = gate.advance()
            lock.lock()
            issued.insert(generation)
            lock.unlock()
        }
        let latest: UInt64 = 5 + 128
        XCTAssertEqual(issued, Set(UInt64(6)...latest), "Every concurrent advance issues exactly one unique generation")
        XCTAssertEqual(gate.generation, latest)
        XCTAssertTrue(gate.isCurrent(latest))
        XCTAssertFalse(gate.isCurrent(5))
        XCTAssertTrue(issued.subtracting([latest]).allSatisfy { !gate.isCurrent($0) })
    }
}
