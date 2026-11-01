import AppKit
import Foundation

public protocol FrontmostAppProviding: Sendable {
    func frontmostPID() async -> pid_t?
    func selfPID() async -> pid_t
    func activate(pid: pid_t) async
    /// Used only to keep the Finder exception honest: a desktop paste cannot
    /// land anywhere, so it is the one app that needs a focused text field.
    func bundleIdentifier(pid: pid_t) async -> String?
}

public extension FrontmostAppProviding {
    func bundleIdentifier(pid: pid_t) async -> String? { nil }
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

    public func bundleIdentifier(pid: pid_t) async -> String? {
        await MainActor.run {
            NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
    }
}
