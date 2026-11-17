#!/usr/bin/env swift
// Headless fixture for stealth-debug. By default creates two OFFSCREEN probe
// windows in this process (never ordered front, never raised, never focused):
// one .none, one .readOnly. With --all-none, creates several windows ALL set to
// .none (the app's invariant). With --clean, creates no windows at all. Prints
// its PID so the test can enumerate it. Used only by tools/stealth-debug/test.sh.
// No GUI is shown on the user's screen.

import AppKit
import Foundation

let args = CommandLine.arguments
let clean = args.contains("--clean")
let allNone = args.contains("--all-none")
var windows: [NSWindow] = []

func makeWindow(x: CGFloat, title: String, sharing: NSWindow.SharingType) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: x, y: 10, width: 32, height: 32),
                     styleMask: .borderless, backing: .buffered, defer: false)
    w.sharingType = sharing
    w.isReleasedWhenClosed = false
    w.title = title
    return w
}

if clean {
    windows = []
} else if allNone {
    // Mirrors the app invariant: several owned windows, every one .none.
    windows = [
        makeWindow(x: 10, title: "own-none-1", sharing: .none),
        makeWindow(x: 60, title: "own-none-2", sharing: .none),
        makeWindow(x: 110, title: "own-none-3", sharing: .none),
    ]
} else {
    // Positive control fixture: one .none and one capturable .readOnly window.
    windows = [
        makeWindow(x: 10, title: "probe-none", sharing: .none),
        makeWindow(x: 60, title: "probe-readonly", sharing: .readOnly),
    ]
}

// Let the WindowServer register the windows, then report PID and hold briefly.
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
print("PID=\(getpid())")
fflush(stdout)
RunLoop.current.run(until: Date().addingTimeInterval(8.0))
windows.forEach { $0.close() }
