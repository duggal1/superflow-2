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
        XCTAssertEqual(issued.count, 128)
        XCTAssertEqual(gate.generation, 5 + 128)
        XCTAssertTrue(issued.allSatisfy { !gate.isCurrent($0) })
    }
}
