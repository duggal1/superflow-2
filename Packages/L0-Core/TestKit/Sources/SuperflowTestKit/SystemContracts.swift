import Foundation
import SuperflowKernel
import SuperflowPorts

/// HotkeySource contract: start/stop are idempotent, the event stream preserves
/// order, and the active-tap request is observable without a running tap.
/// `emit` lets the caller drive a fake source; real adapters omit it.
public struct HotkeySourceContract: Sendable {
    private let emit: (@Sendable (KeyEvent) -> Void)?

    public init(emit: (@Sendable (KeyEvent) -> Void)? = nil) {
        self.emit = emit
    }

    public func verify(_ source: any HotkeySource) async throws {
        try await source.start()
        try await source.start()
        await source.setActiveTap(true)
        await source.setActiveTap(false)

        if let emit {
            let stream = source.events
            let events = [
                KeyEvent(kind: .fnDown, timestampNs: 1),
                KeyEvent(kind: .fnUp, timestampNs: 2),
            ]
            for event in events { emit(event) }
            let received = await ContractStream.collect(stream, limit: 2, timeout: .seconds(1))
            try contractRequire(received == events,
                                "hotkey events were dropped or reordered: \(received)")
        }

        await source.stop()
        await source.stop()
    }
}

/// PermissionGate contract: every permission has a status, requests and deep
/// links are forwarded, and the update stream publishes transitions. `change`
/// lets the caller drive a fake gate; real adapters omit it.
public struct PermissionGateContract: Sendable {
    private let change: (@Sendable (Permission, PermissionStatus) async -> Void)?

    public init(change: (@Sendable (Permission, PermissionStatus) async -> Void)? = nil) {
        self.change = change
    }

    public func verify(_ gate: any PermissionGate) async throws {
        for permission in Permission.allCases {
            let status = await gate.status(permission)
            try contractRequire([.granted, .denied, .notDetermined].contains(status),
                                "undefined status \(status) for \(permission)")
        }

        let requested = await gate.request(.microphone)
        try contractRequire([.granted, .denied, .notDetermined].contains(requested),
                            "request returned an undefined status")
        await gate.openSystemSettings(.accessibility)

        if let change {
            let updates = await gate.updates()
            await change(.inputMonitoring, .denied)
            let received = await ContractStream.collect(updates, limit: 1, timeout: .seconds(1))
            try contractRequire(received.first?.0 == .inputMonitoring,
                                "permission update did not identify the changed permission")
            try contractRequire(received.first?.1 == .denied,
                                "permission update did not carry the new status")
        }
    }
}
