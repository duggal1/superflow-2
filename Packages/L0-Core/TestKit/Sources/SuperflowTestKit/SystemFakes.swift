import Foundation
import SuperflowKernel
import SuperflowPorts

/// In-memory launch-at-login controller. Tests can force a failure to verify
/// that the settings screen reverts a toggle the system refused.
public actor FakeLaunchAtLogin: LaunchAtLoginController {
    public private(set) var enabled: Bool
    public private(set) var calls: [Bool] = []
    public var failSet = false

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }

    public func isEnabled() async -> Bool { enabled }

    public func setEnabled(_ enabled: Bool) async throws {
        calls.append(enabled)
        if failSet { throw SuperflowError.invalidState("Login item rejected.") }
        self.enabled = enabled
    }

    public func setFailSet(_ value: Bool) { failSet = value }
}

public actor FakeGlobeKeyProbe: GlobeKeyProbe {
    public var action: GlobeKeyAction
    public init(_ action: GlobeKeyAction = .doNothing) {
        self.action = action
    }
    public func set(_ action: GlobeKeyAction) { self.action = action }
    public func currentAction() async -> GlobeKeyAction { action }
}

/// Writes a small deterministic payload so tests can assert that the settings
/// screen really handed the exporter a destination.
public actor FakeDiagnosticsExporter: DiagnosticsExporting {
    public private(set) var urls: [URL] = []
    public var fail = false
    public init() {}

    public func setFail(_ value: Bool) { fail = value }

    public func exportDiagnostics(to url: URL) async throws {
        if fail { throw SuperflowError.storage("Export failed.") }
        urls.append(url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("{\"fixture\":true}".utf8).write(to: url, options: .atomic)
    }
}
