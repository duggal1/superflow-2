import CoreGraphics
import SuperflowKernel
import XCTest
@testable import SuperflowTextInsertion

final class PasteEventPosterTests: XCTestCase {
    func testEventsCarryCommandFlagsAndTheMarker() throws {
        let source = CGEventSource(stateID: .privateState)
        let down = try XCTUnwrap(CGEventPastePoster.makeEvent(keyCode: 9, down: true, source: source))
        let up = try XCTUnwrap(CGEventPastePoster.makeEvent(keyCode: 9, down: false, source: source))
        XCTAssertEqual(down.flags, .maskCommand)
        XCTAssertEqual(up.flags, .maskCommand)
        XCTAssertEqual(down.getIntegerValueField(.eventSourceUserData), SyntheticInputMarker.value)
        XCTAssertEqual(up.getIntegerValueField(.eventSourceUserData), SyntheticInputMarker.value)
    }

    func testSyntheticDetection() throws {
        let source = CGEventSource(stateID: .privateState)
        let marked = try XCTUnwrap(CGEventPastePoster.makeEvent(keyCode: 9, down: true, source: source))
        XCTAssertTrue(SyntheticInput.isSynthetic(marked))

        let plain = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true))
        XCTAssertFalse(SyntheticInput.isSynthetic(plain))

        plain.setIntegerValueField(.eventSourceUserData, value: 1234)
        XCTAssertFalse(SyntheticInput.isSynthetic(plain))
    }

    func testMarkerMatchesKernelContract() {
        XCTAssertEqual(SyntheticInputMarker.value, 0x5346_5041_5354_4531)
    }
}
