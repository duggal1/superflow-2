import AppKit
import CoreGraphics
import CoreFoundation
import Foundation
import SuperflowFeatureIsland
import SuperflowMeetingEngine
import SuperflowSessionEngine
import SwiftUI

@MainActor
public final class IslandPanelController: NSObject, NSWindowDelegate {
    public let model: IslandViewModel

    private let session: SessionEngine
    private let meeting: MeetingEngine
    private let actions: IslandActions
    private let defaults: UserDefaults
    private let panel: NonActivatingIslandPanel
    private let sessionEvents: AsyncStream<SessionEvent>?
    private let meetingEvents: AsyncStream<MeetingEvent>?
    private var sessionTask: Task<Void, Never>?
    private var meetingTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    public init(session: SessionEngine, meeting: MeetingEngine, model: IslandViewModel,
                actions: IslandActions, sessionEvents: AsyncStream<SessionEvent>? = nil,
                meetingEvents: AsyncStream<MeetingEvent>? = nil,
                defaults: UserDefaults = .standard) {
        self.session = session
        self.meeting = meeting
        self.model = model
        self.actions = actions
        self.sessionEvents = sessionEvents
        self.meetingEvents = meetingEvents
        self.defaults = defaults
        panel = NonActivatingIslandPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 280, height: 60)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.title = "Superflow Island"
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: IslandPanelContent(
            model: model,
            actions: actions,
            resetPosition: { [weak self] in self?.resetPosition() },
            movePanel: { [weak self] delta in self?.movePanel(by: delta) }
        ))
        placePanel()
    }

    public func startObserving() {
        guard sessionTask == nil, meetingTask == nil else { return }
        let sessionEvents = self.sessionEvents ?? session.events
        sessionTask = Task { [weak self] in
            for await event in sessionEvents {
                guard let self else { return }
                self.model.handle(event)
                self.refreshPanel()
            }
        }
        let meetingEvents = self.meetingEvents ?? meeting.events
        meetingTask = Task { [weak self] in
            for await event in meetingEvents {
                guard let self else { return }
                self.model.handle(event)
                self.refreshPanel()
            }
        }
    }

    public func resetPosition() {
        if let screen = screenForPanel() {
            defaults.removeObject(forKey: positionKey(for: screen))
        }
        placePanel()
    }

    public func windowDidMove(_ notification: Notification) {
        guard let screen = screenForPanel() else { return }
        defaults.set(NSStringFromPoint(panel.frame.origin), forKey: positionKey(for: screen))
    }

    private func movePanel(by delta: CGSize) {
        let proposed = panel.frame.offsetBy(dx: delta.width, dy: delta.height)
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(proposed) })
                ?? screenForPanel() else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: min(max(proposed.origin.x, visible.minX), max(visible.minX, visible.maxX - proposed.width)),
            y: min(max(proposed.origin.y, visible.minY), max(visible.minY, visible.maxY - proposed.height))
        )
        panel.setFrameOrigin(origin)
    }

    private func refreshPanel() {
        let size = model.isExpanded
            ? NSSize(width: 460, height: 160)
            : NSSize(width: 280, height: 60)
        if panel.frame.size != size {
            var frame = panel.frame
            let oldHeight = frame.height
            frame.size = size
            frame.origin.y += oldHeight - size.height
            panel.setFrame(frame, display: true)
        }

        if model.isVisible {
            if !panel.isVisible {
                placePanel()
                panel.orderFrontRegardless()
            }
            startTicking()
        } else {
            panel.orderOut(nil)
            stopTicking()
        }
    }

    private func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(33))
                } catch {
                    return
                }
                guard let self else { return }
                self.model.tick()
                self.refreshPanel()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func placePanel() {
        guard let screen = screenForPanel() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let key = positionKey(for: screen)
        let saved = defaults.string(forKey: key).map(NSPointFromString)
        let proposed = saved ?? NSPoint(x: visible.midX - size.width / 2,
                                        y: visible.maxY - size.height - 8)
        let origin = NSPoint(
            x: min(max(proposed.x, visible.minX), max(visible.minX, visible.maxX - size.width)),
            y: min(max(proposed.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        )
        panel.setFrameOrigin(origin)
    }

    private func screenForPanel() -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(panel.frame) }
    }

    private func positionKey(for screen: NSScreen) -> String {
        "island.position.\(displayIdentifier(for: screen))"
    }

    private func displayIdentifier(for screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return screen.localizedName
        }
        guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value)) else {
            return String(number.uint32Value)
        }
        return CFUUIDCreateString(nil, unmanaged.takeRetainedValue()) as String
    }
}

@MainActor
private final class NonActivatingIslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct IslandPanelContent: View {
    @ObservedObject var model: IslandViewModel
    let actions: IslandActions
    let resetPosition: () -> Void
    let movePanel: @MainActor @Sendable (CGSize) -> Void

    var body: some View {
        IslandView(model: model, actions: actions, onMove: movePanel)
            .contextMenu {
                Button("Stop", systemImage: "stop.fill", action: actions.stop)
                Button("Cancel", systemImage: "xmark", action: actions.cancel)
                Button("Open App", systemImage: "macwindow", action: actions.openApp)
                Button("Settings", systemImage: "gearshape", action: actions.openSettings)
                Button("Reset Position", systemImage: "arrow.uturn.backward", action: resetPosition)
                Button("Quit Superflow", systemImage: "power", action: actions.quit)
            }
    }
}
