import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import XCTest

final class SystemContractTests: XCTestCase {
    func testHotkeySourceContractAgainstFake() async throws {
        let source = FakeHotkeySource()
        try await HotkeySourceContract(emit: { source.send($0) }).verify(source)
        let active = await source.activeTap
        XCTAssertFalse(active)
    }

    func testPermissionGateContractAgainstFake() async throws {
        let gate = FakePermissionGate(all: .granted)
        try await PermissionGateContract(change: { permission, status in
            await gate.set(permission, status)
        }).verify(gate)
        let requested = await gate.requested
        XCTAssertEqual(requested, [.microphone])
        let opened = await gate.opened
        XCTAssertEqual(opened, [.accessibility])
    }

    func testPermissionRequestReturnsTheUpdatedStatus() async throws {
        let gate = FakePermissionGate(all: .notDetermined)
        await gate.set(.microphone, .denied)
        let status = await gate.request(.microphone)
        XCTAssertEqual(status, .denied)
    }

    func testHotkeyStopFinishesTheEventStream() async throws {
        let source = FakeHotkeySource()
        let stream = source.events
        await source.stop()
        let received = await ContractStream.collect(stream, limit: 1, timeout: .seconds(1))
        XCTAssertTrue(received.isEmpty)
    }
}
