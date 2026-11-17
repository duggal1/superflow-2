#!/usr/bin/env swift
// Clearly stealth: WindowServer sharing-state dump.
//
// Lists every window owned by a PID using only the public
// CGWindowListCopyWindowInfo(.optionAll). Prints window number, name, bounds,
// layer and kCGWindowSharingState. Exits NONZERO if any window is capturable
// (sharing state != kCGWindowSharingStateNone), i.e. a hiding leak.
//
// Usage:  swift tools/stealth-debug/main.swift --pid <PID> [--json]
//         swift tools/stealth-debug/main.swift --pid <PID> --json

import CoreGraphics
import Foundation

private let sharingNone = 0  // kCGWindowSharingStateNone

struct WindowRow {
    let number: Int
    let name: String
    let bounds: String
    let layer: Int
    let state: Int

    var stateLabel: String {
        switch state {
        case 0: return "none"
        case 1: return "readOnly"
        case 2: return "readWrite"
        default: return "unknown(\(state))"
        }
    }
    var isLeak: Bool { state != sharingNone }
}

private func parseArgs() -> (pid: Int32, json: Bool)? {
    let args = Array(CommandLine.arguments.dropFirst())
    var pid: Int32?
    var json = false
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--pid":
            i += 1
            guard i < args.count, let value = Int32(args[i]) else { return nil }
            pid = value
        case "--json":
            json = true
        default:
            return nil
        }
        i += 1
    }
    guard let pid else { return nil }
    return (pid, json)
}

private func listRows(pid: Int32) -> [WindowRow] {
    guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return list.compactMap { entry in
        guard let owner = entry[kCGWindowOwnerPID as String] as? Int32, owner == pid else { return nil }
        let number = entry[kCGWindowNumber as String] as? Int ?? -1
        let layer = entry[kCGWindowLayer as String] as? Int ?? -1
        let state = entry[kCGWindowSharingState as String] as? Int ?? -1
        let name = entry[kCGWindowName as String] as? String ?? ""
        let bounds: String
        if let b = entry[kCGWindowBounds as String] as? [String: Any] {
            let x = (b["X"] as? NSNumber)?.doubleValue ?? 0
            let y = (b["Y"] as? NSNumber)?.doubleValue ?? 0
            let w = (b["Width"] as? NSNumber)?.doubleValue ?? 0
            let h = (b["Height"] as? NSNumber)?.doubleValue ?? 0
            bounds = "\(Int(x)),\(Int(y)),\(Int(w)),\(Int(h))"
        } else {
            bounds = "?"
        }
        return WindowRow(number: number, name: name, bounds: bounds, layer: layer, state: state)
    }
    .sorted { $0.number < $1.number }
}

private func jsonEscape(_ s: String) -> String {
    var out = ""
    for ch in s.unicodeScalars {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        default: out.unicodeScalars.append(ch)
        }
    }
    return out
}

guard let (pid, json) = parseArgs() else {
    FileHandle.standardError.write(
        "usage: stealth-debug --pid <PID> [--json]\n".data(using: .utf8)!)
    exit(2)
}

let rows = listRows(pid: pid)
let leaks = rows.filter(\.isLeak)

if json {
    let windows = rows.map { r in
        "{\"number\":\(r.number),\"name\":\"\(jsonEscape(r.name))\",\"bounds\":\"\(r.bounds)\",\"layer\":\(r.layer),\"sharingState\":\(r.state),\"sharingLabel\":\"\(r.stateLabel)\",\"leak\":\(r.isLeak)}"
    }.joined(separator: ",")
    print("{\"pid\":\(pid),\"windowCount\":\(rows.count),\"leakCount\":\(leaks.count),\"ok\":\(leaks.isEmpty),\"windows\":[\(windows)]}")
} else {
    print("PID \(pid): \(rows.count) window(s)")
    print(String(format: "%-10@ %-7@ %-12@ %-20@ %@",
                 "NUMBER" as NSString, "LAYER" as NSString,
                 "SHARING" as NSString, "BOUNDS" as NSString, "NAME" as NSString))
    for r in rows {
        print(String(format: "%-10d %-7d %-12@ %-20@ %@",
                     r.number, r.layer,
                     r.stateLabel as NSString, r.bounds as NSString, r.name as NSString))
    }
    if leaks.isEmpty {
        print("RESULT: OK — no capturable windows")
    } else {
        print("RESULT: LEAK — \(leaks.count) capturable window(s): \(leaks.map(\.number))")
    }
}

exit(leaks.isEmpty ? 0 : 1)
