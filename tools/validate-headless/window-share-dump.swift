#!/usr/bin/env swift
// window-share-dump.swift — dump WindowServer metadata for the target app.
//
// This is one of the "WindowServer sharing-state dump" tools for R17. It uses
// only PUBLIC APIs (CGWindowListCopyWindowInfo). kCGWindowSharingState IS a
// public key in that dictionary: 0 = none (not capturable), 1 = readOnly,
// 2 = readWrite. It is reported per window below. The companion tool
// tools/stealth-debug/main.swift uses CGWindowListCopyWindowInfo(.optionAll)
// and exits nonzero on any capturable window; both agree on the state values.
// The in-app DEBUG invariant and the SCK positive-control verifier are the
// actual stealth proof; this dump is the independent runtime inventory.
//
// Usage:  window-share-dump [--bundle com.superflow.app] [--out PATH] [--self]
//   --self filters by this process's getpid() instead of a bundle identifier.
// JSON out. Read-only. Never launches, focuses, or moves anything.

import Foundation
import CoreGraphics
import AppKit

let a = Array(CommandLine.arguments.dropFirst())
func val(_ key: String) -> String? {
    guard let i = a.firstIndex(of: key), i + 1 < a.count else { return nil }
    return a[i + 1]
}
let bundle = val("--bundle") ?? "com.superflow.app"
let out = val("--out")
let useSelf = a.contains("--self")
let pid: Int32? = useSelf
    ? getpid()
    : NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == bundle })?.processIdentifier

guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                            kCGNullWindowID) as? [[String: Any]] else {
    print("{\"status\":\"error\",\"reason\":\"CGWindowListCopyWindowInfo nil (Screen Recording permission?)\"}")
    exit(3)
}
let rows = list.filter { w in
    guard let owner = w[kCGWindowOwnerPID as String] as? Int32 else { return false }
    return owner == pid
}.map { w -> [String: Any] in
    var d: [String: Any] = [:]
    d["windowID"] = w[kCGWindowNumber as String] ?? 0
    d["ownerPID"] = w[kCGWindowOwnerPID as String] ?? 0
    d["title"] = w[kCGWindowName as String] ?? ""
    d["ownerName"] = w[kCGWindowOwnerName as String] ?? ""
    d["layer"] = w[kCGWindowLayer as String] ?? 0
    d["onscreen"] = w[kCGWindowIsOnscreen as String] ?? false
    let sharing = w[kCGWindowSharingState as String] as? Int ?? -1
    d["sharingState"] = sharing
    d["sharingLabel"] = sharing == 0 ? "none" : sharing == 1 ? "readOnly" : sharing == 2 ? "readWrite" : "unknown(\(sharing))"
    d["sharingAPINote"] = "kCGWindowSharingState: 0=none, 1=readOnly, 2=readWrite. Confirmed by the SCK positive-control verifier."
    if let b = w[kCGWindowBounds as String] as? [String: Any] { d["bounds"] = b }
    return d
}
let payload: [String: Any] = [
    "status": "ok",
    "bundle": bundle,
    "pid": pid ?? -1,
    "running": pid != nil,
    "windowCount": rows.count,
    "leakCount": rows.filter { ($0["sharingState"] as? Int ?? -1) != 0 }.count,
    "windows": rows,
    "note": "Inventory only. Stealth truth requires the SCK positive-control verifier, not this dump."
]
let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
let s = String(data: data ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
if let out {
    try? s.write(toFile: out, atomically: true, encoding: .utf8)
    print("{\"status\":\"ok\",\"written\":\"\(out)\",\"windowCount\":\(rows.count)}")
} else {
    print(s)
}
