import XCTest
@testable import SuperflowKernel

final class SyntheticInputTests: XCTestCase {
    func testMarkerIsStable() {
        XCTAssertEqual(SyntheticInputMarker.value, 0x5346_5041_5354_4531)
        XCTAssertEqual(SyntheticInputMarker.value, SyntheticInputMarker.value)
    }
}
