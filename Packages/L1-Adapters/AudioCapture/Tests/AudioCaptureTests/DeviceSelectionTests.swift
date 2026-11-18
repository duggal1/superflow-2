import CoreAudio
import Foundation
import XCTest
@testable import SuperflowAudioCapture

final class DeviceSelectionTests: XCTestCase {
    private func device(
        id: AudioDeviceID,
        uid: String,
        name: String,
        isDefault: Bool = false,
        alive: Bool = true,
        hidden: Bool = false,
        hasInput: Bool = true,
        channels: Int32 = 1,
        rate: Double = 48_000,
        transport: UInt32 = 0
    ) -> InputDeviceDescriptor {
        InputDeviceDescriptor(
            id: id,
            uid: uid,
            name: name,
            isAlive: alive,
            isHidden: hidden,
            isSystemDefault: isDefault,
            hasInputFormat: hasInput,
            inputChannels: channels,
            sampleRate: rate,
            transportType: transport
        )
    }

    private var inputs: [InputDeviceDescriptor] {
        [
            device(id: 1, uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone", isDefault: true),
            device(id: 2, uid: "usb-1", name: "Shure MV7"),
        ]
    }

    // MARK: - Eligibility

    func testRejectsOutputOnlyAndProcessTapDevices() {
        let outputOnly = device(id: 3, uid: "speaker-1", name: "Speakers", hasInput: false, channels: 0)
        let processTap = device(id: 4, uid: "CADefaultDeviceAggregate.123", name: "System Audio")
        let virtual = device(id: 5, uid: "virtual-1", name: "Virtual Cable",
                             transport: InputDeviceDescriptor.virtualTransport)

        XCTAssertTrue(inputs.allSatisfy(\.isEligibleMicrophone))
        XCTAssertFalse(outputOnly.isEligibleMicrophone)
        XCTAssertFalse(processTap.isEligibleMicrophone)
        XCTAssertTrue(processTap.isProcessTapOrVirtual)
        XCTAssertFalse(virtual.isEligibleMicrophone)
        XCTAssertTrue(virtual.isProcessTapOrVirtual)
    }

    func testRejectsDeadHiddenAndInvalidFormatDevices() {
        XCTAssertFalse(device(id: 6, uid: "dead", name: "Dead", alive: false).isEligibleMicrophone)
        XCTAssertFalse(device(id: 7, uid: "hidden", name: "Hidden", hidden: true).isEligibleMicrophone)
        XCTAssertFalse(device(id: 8, uid: "no-rate", name: "No rate", rate: 0).isEligibleMicrophone)
        XCTAssertFalse(device(id: 9, uid: "no-channels", name: "No channels", channels: 0).isEligibleMicrophone)
    }

    // MARK: - Auto and explicit routes

    func testNoChoiceFollowsTheLiveSystemDefault() {
        let route = RouteResolver.resolve(selection: nil, inputs: inputs)
        XCTAssertEqual(route.kind, .automatic)
        XCTAssertEqual(route.uid, "BuiltInMicrophoneDevice")
        XCTAssertNil(route.note)
        XCTAssertEqual(route.displayName, "System default \u{2014} MacBook Pro Microphone")
    }

    func testExplicitChoiceUsesTheDeviceName() {
        let selection = MicrophoneSelection(uid: "usb-1", name: "Shure MV7")
        let route = RouteResolver.resolve(selection: selection, inputs: inputs)
        XCTAssertEqual(route.kind, .explicit)
        XCTAssertEqual(route.uid, "usb-1")
        XCTAssertEqual(route.displayName, "Shure MV7")
    }

    func testMissingChoiceFallsBackAndExplainsWhy() {
        let wanted = MicrophoneSelection(uid: "airpods", name: "AirPods Pro")
        let route = RouteResolver.resolve(selection: wanted, inputs: inputs)
        XCTAssertEqual(route.kind, .fallback)
        XCTAssertEqual(route.uid, "BuiltInMicrophoneDevice")
        XCTAssertEqual(
            route.note,
            "AirPods Pro isn't connected. Using MacBook Pro Microphone."
        )
        let none = RouteResolver.resolve(selection: wanted, inputs: [])
        XCTAssertEqual(none.kind, .fallback)
        XCTAssertEqual(
            none.note,
            "AirPods Pro isn't connected, and there's no other microphone."
        )
    }

    func testVirtualDeviceIsNeverSelectedEvenWhenRequested() {
        let virtual = device(id: 10, uid: "virtual-1", name: "Virtual Cable", isDefault: true,
                             transport: InputDeviceDescriptor.virtualTransport)
        let route = RouteResolver.resolve(
            selection: MicrophoneSelection(uid: "virtual-1", name: "Virtual Cable"),
            inputs: [virtual]
        )
        XCTAssertEqual(route.kind, .fallback)
        XCTAssertNil(route.uid)
        XCTAssertEqual(route.note, "Virtual Cable isn't connected, and there's no other microphone.")
    }

    func testNoInputDeviceIsUnavailable() {
        let route = RouteResolver.resolve(selection: nil, inputs: [])
        XCTAssertEqual(route.kind, .unavailable)
        XCTAssertEqual(route.displayName, "No microphone available")
    }

    // MARK: - Save decisions and persistence

    func testSaveDecisionClearsDefaultAndRefusesUnnamedDevices() {
        XCTAssertEqual(RouteResolver.saveDecision(uid: "default", name: nil, inputs: inputs), .clear)
        XCTAssertEqual(RouteResolver.saveDecision(uid: "   ", name: nil, inputs: inputs), .clear)
        XCTAssertEqual(RouteResolver.saveDecision(uid: "airpods", name: "AirPods", inputs: inputs), .keepCurrent)
        let tap = device(id: 11, uid: "CADefaultDeviceAggregate.x", name: "System Audio")
        XCTAssertEqual(
            RouteResolver.saveDecision(uid: tap.uid, name: tap.name, inputs: inputs + [tap]),
            .keepCurrent
        )
        let decision = RouteResolver.saveDecision(uid: "usb-1", name: "Renamed", inputs: inputs)
        guard case .save(let selection) = decision else {
            return XCTFail("expected a saved selection")
        }
        XCTAssertEqual(selection.uid, "usb-1")
        XCTAssertEqual(selection.name, "Renamed")
    }

    func testSelectionPersistsOnlyTheUIDAndClearsToDefault() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-mic-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileMicrophoneSelectionStore(url: url)

        XCTAssertNil(store.load())
        try store.save(MicrophoneSelection(uid: "usb-1", name: "Shure MV7"))
        XCTAssertEqual(store.load()?.uid, "usb-1")
        XCTAssertEqual(store.load()?.name, "Shure MV7")
        let raw = try Data(contentsOf: url)
        XCTAssertFalse(String(data: raw, encoding: .utf8)?.contains("BuiltInMicrophoneDevice") == true)

        try store.save(nil)
        XCTAssertNil(store.load())
        try store.save(MicrophoneSelection(uid: "  ", name: "blank"))
        XCTAssertNil(store.load(), "a blank UID is the system default")
    }
}
