import AppKit
import ApplicationServices
import Foundation
import Carbon.HIToolbox
import OSLog

public enum PlainClipboard {
    @discardableResult
    public static func copy(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setString(text, forType: .string)
    }
}

public enum InsertionPermission {
    @discardableResult
    public static func requestPrompt() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}

public enum InsertionDiagnostics {
    public static func describe() -> String {
        let front = NSWorkspace.shared.frontmostApplication
        return [
            "axTrusted=\(AXIsProcessTrusted())",
            "bundleID=\(Bundle.main.bundleIdentifier ?? "nil")",
            "bundlePath=\(Bundle.main.bundlePath)",
            "secureInputEnabledGlobally=\(IsSecureEventInputEnabled())",
            "frontmost=\(front?.bundleIdentifier ?? "nil")",
        ].joined(separator: "\n")
    }
}

public enum InsertionSmokeTest {
    public static func run(service: TextInsertionService, text: String = "insertion test 123") {
        NSLog("INSERTION diagnostics:\n%@", InsertionDiagnostics.describe())
        Task {
            try? await Task.sleep(for: .seconds(4))
            let report = await service.insert(text)
            NSLog("INSERTION report: %@", report.summary)
        }
    }
}
