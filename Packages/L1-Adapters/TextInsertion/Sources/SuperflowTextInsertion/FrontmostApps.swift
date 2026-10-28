import AppKit
import Foundation

public protocol FrontmostAppProviding: Sendable {
    func frontmostPID() async -> pid_t?
    func selfPID() async -> pid_t
    func activate(pid: pid_t) async
}

public struct WorkspaceFrontmostApps: FrontmostAppProviding {
    public init() {}

    public func frontmostPID() async -> pid_t? {
        await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    }

    public func selfPID() async -> pid_t {
        ProcessInfo.processInfo.processIdentifier
    }

    public func activate(pid: pid_t) async {
        await MainActor.run {
            _ = NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }
}
