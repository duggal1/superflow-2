#!/usr/bin/env swift
// IslandUIDriver.swift — headless probe for the Superflow Island NSPanel.
//
// HARD RULES (from rules.yaml testing.macos_native / headless_always):
//   * Never raise or activate the app. If it must be launched, the SHELL caller
//     uses `open -g -j`; this tool never launches anything itself.
//   * Never move the user's cursor. Never post global keystrokes. The only
//     event posting is `CGEventPostToPid` to the app's OWN pid.
//   * Capture only the target window: `screencapture -x -l <windowid> <path>`.
//   * JSON out, nonzero exit on failure. No secrets, no prod, no files outside
//     the project's .proof/validation directory.
//
// Build once, reuse:  swiftc -O IslandUIDriver.swift -o IslandUIDriver
// Usage:  IslandUIDriver <command> [options]
//   windows  [--pid N | --bundle com.superflow.app]
//   ax       [--pid N | --bundle ...]        Accessibility tree (needs Accessibility perm)
//   frontmost
//   capture  --window ID --out PATH          screencapture -x -l ID PATH
//   postkey  --pid N --code N (--down|--up)  CGEventPostToPid (needs Accessibility perm)

import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

// MARK: - JSON output helpers

func emit(_ obj: [String: Any], exit code: Int = 0) -> Never {
    let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    let s = String(data: data ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
    print(s)
    exit(Int32(code))
}

func ok(_ data: [String: Any] = [:]) -> Never { emit(["status": "ok", "data": data], exit: 0) }
func err(_ reason: String, code: Int = 3) -> Never {
    emit(["status": "error", "reason": reason], exit: code)
}

// MARK: - args

func args() -> [String: String] {
    var d: [String: String] = [:]
    let a = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < a.count {
        let k = a[i]
        if k.hasPrefix("--"), i + 1 < a.count {
            d[String(k.dropFirst(2))] = a[i + 1]
            i += 2
        } else {
            d[k] = "1"
            i += 1
        }
    }
    return d
}

func resolvePID(_ a: [String: String]) -> Int32? {
    if let p = a["pid"], let n = Int32(p) { return n }
    let bundle = a["bundle"] ?? "com.superflow.app"
    return NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == bundle })?.processIdentifier
}

// MARK: - commands

func cmdWindows(_ a: [String: String]) {
    let pid = resolvePID(a)
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else {
        err("CGWindowListCopyWindowInfo returned nil (Screen Recording permission may be missing)")
    }
    let filtered = list.filter { w -> Bool in
        guard let owner = w[kCGWindowOwnerPID as String] as? Int32 else { return false }
        return pid == nil || owner == pid
    }
    var out: [[String: Any]] = []
    for w in filtered {
        var d: [String: Any] = [:]
        d["id"] = w[kCGWindowNumber as String] ?? 0
        d["ownerPID"] = w[kCGWindowOwnerPID as String] ?? 0
        d["name"] = w[kCGWindowName as String] ?? ""
        d["ownerName"] = w[kCGWindowOwnerName as String] ?? ""
        d["layer"] = w[kCGWindowLayer as String] ?? 0
        d["onscreen"] = w[kCGWindowIsOnscreen as String] ?? false
        if let b = w[kCGWindowBounds as String] as? [String: Any] { d["bounds"] = b }
        out.append(d)
    }
    ok(["pid": pid ?? -1, "count": out.count, "windows": out])
}

func cmdAX(_ a: [String: String]) {
    guard let pid = resolvePID(a) else { err("target app not running") }
    guard AXIsProcessTrusted() else { err("Accessibility permission missing for the driver process") }
    let app = AXUIElementCreateApplication(pid)
    var count = 0
    var lines: [String] = []

    func walk(_ el: AXUIElement, _ depth: Int) {
        guard depth < 7, count < 220 else { return }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &title)
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value)
        let r = (role as? String) ?? "?"
        let t = (title as? String) ?? ""
        let v = (value as? String) ?? ""
        lines.append(String(repeating: "  ", count: depth) + "\(r) \(t) \(v)")
        count += 1
        var children: CFTypeRef?
        let rc = AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children)
        if rc == .success, let kids = children as? [AXUIElement] {
            for kid in kids { walk(kid, depth + 1) }
        }
    }
    walk(app, 0)
    ok(["pid": pid, "nodes": count, "tree": lines])
}

func cmdFrontmost() {
    let f = NSWorkspace.shared.frontmostApplication
    ok(["bundle": f?.bundleIdentifier ?? "", "name": f?.localizedName ?? "",
        "pid": f?.processIdentifier ?? -1])
}

func cmdCapture(_ a: [String: String]) {
    guard let id = a["window"], let wid = Int(id) else { err("capture needs --window ID") }
    guard let out = a["out"] else { err("capture needs --out PATH") }
    let allowed = (out as NSString).resolvingSymlinksInPath.hasPrefix("/Users/")
    guard allowed, out.contains(".proof/validation/screens/") else {
        err("out path must be inside .proof/validation/screens/")
    }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    proc.arguments = ["-x", "-l", String(wid), out]
    do {
        try proc.run()
    } catch { err("screencapture failed to launch: \(error)") }
    proc.waitUntilExit()
    guard proc.terminationReason == .exit, proc.terminationStatus == 0 else {
        err("screencapture -x -l \(wid) exited \(proc.terminationStatus) (Screen Recording permission or bad window id)")
    }
    let size = (try? FileManager.default.attributesOfItem(atPath: out)[.size] as? Int) ?? 0
    ok(["path": out, "window": wid, "bytes": size])
}

func cmdPostKey(_ a: [String: String]) {
    guard let pidS = a["pid"], let pid = Int32(pidS) else { err("postkey needs --pid") }
    guard let codeS = a["code"], let code = CGKeyCode(codeS) else { err("postkey needs --code") }
    guard AXIsProcessTrusted() else { err("Accessibility permission missing for CGEventPostToPid") }
    let down = a["down"] != nil || (a["state"] ?? "down") == "down"
    guard let ev = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else {
        err("CGEvent creation failed")
    }
    ev.postToPid(pid)
    ok(["pid": pid, "code": Int(code), "down": down, "postedVia": "CGEvent.postToPid (own pid only)"])
}

// MARK: - dispatch

let a = args()
guard let cmd = Array(CommandLine.arguments.dropFirst()).first else {
    err("no command; use windows|ax|frontmost|capture|postkey")
}
switch cmd {
case "windows": cmdWindows(a)
case "ax": cmdAX(a)
case "frontmost": cmdFrontmost()
case "capture": cmdCapture(a)
case "postkey": cmdPostKey(a)
default: err("unknown command \(cmd)")
}
