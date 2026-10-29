import AppKit
import SuperflowFeatureIsland
import SuperflowUIComponents
import SwiftUI

/// The Island's window: borderless, non-activating, above the menu bar, and
/// never draggable. It is created once and never ordered out.
@MainActor
final class IslandPanel: NSPanel {
    /// Only click-opened cards may take focus for their keyboard controls.
    var allowsKey = false
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// By default AppKit pushes a window below the menu bar. That is half of the
    /// floating-badge bug.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: IslandLayout.canvas),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
    }
}

/// Shape-accurate hit testing. Everything outside the shape passes clicks to
/// whatever is underneath: menu bar items, other windows, the desktop.
final class IslandHostingView: NSHostingView<IslandRoot> {
    /// Interactive region in this view's top-left coordinate space.
    var containsPoint: (CGPoint) -> Bool = { _ in false }

    required init(rootView: IslandRoot) {
        super.init(rootView: rootView)
        sizingOptions = []
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        FontSmoothing.applyToCurrentContext()
        super.draw(dirtyRect)
    }

    /// A notch screen reports a top safe-area inset. It would push the content down.
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let y = isFlipped ? local.y : bounds.height - local.y
        return containsPoint(CGPoint(x: local.x, y: y)) ? super.hitTest(point) : nil
    }
}

/// Placement, screens and focus. The window moves only while the Island is idle
/// and therefore invisible, and never with an animation.
@MainActor
public final class IslandController {
    public let model: IslandModel

    private let panel = IslandPanel()
    private let host: IslandHostingView
    private var observers: [NSObjectProtocol] = []
    private var outsideMonitors: [Any] = []
    private var pendingReseat = false
    private var didStart = false

    public init(model: IslandModel) {
        self.model = model
        host = IslandHostingView(rootView: IslandRoot(model: model))
        host.containsPoint = { [unowned model] point in
            guard model.box.opacity > 0 else { return false }
            let slop: CGFloat = model.phase == .idle && model.geometry.hasNotch ? 0 : 4
            return model.hitRect.insetBy(dx: -slop, dy: -slop).contains(point)
        }
        panel.contentView = host
        panel.onCancel = { [unowned model] in model.send(.dismissed) }
        model.placement = { [weak self] in self?.place($0) }
        model.phaseDidChange = { [weak self] in self?.phaseChanged($0) }
    }

    public func start() {
        guard !didStart else { return }
        didStart = true
        place(.home)
        panel.orderFrontRegardless()

        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                               object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            },
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.panel.orderFrontRegardless() }
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            },
        ]
    }

    // MARK: placement

    /// Moves the window. Called only while the Island is idle and invisible.
    private func place(_ target: IslandPlacement) {
        let screen = target == .home
            ? (IslandScreens.home ?? IslandScreens.active)
            : IslandScreens.active
        guard let screen else { return }
        let geometry = NotchGeometry(screen: screen)
        if geometry != model.geometry {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { model.geometry = geometry }
        }
        let size = IslandLayout.canvas
        let x = ((geometry.centerX - size.width / 2) * geometry.scale).rounded() / geometry.scale
        let y = geometry.frame.maxY - size.height
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height),
                       display: false)
        panel.orderFrontRegardless()
    }

    private func screensChanged() {
        guard model.phase == .idle else {
            pendingReseat = true
            return
        }
        place(.home)
    }

    // MARK: phase side effects owned by AppKit

    private func phaseChanged(_ phase: IslandPhase) {
        if phase == .idle, pendingReseat {
            pendingReseat = false
            place(.home)
        }

        let interactiveCard: Bool = switch phase {
        case .recent, .history, .meetingPanel: true
        case .idle, .hover, .listening, .handsFree, .meeting, .processing,
             .landed, .undo, .failed, .notice: false
        }
        if interactiveCard {
            panel.allowsKey = true
            panel.makeKey()
        } else {
            if panel.isKeyWindow { panel.resignKey() }
            panel.allowsKey = false
        }

        // Outside click closes the click-opened card only. The failure card
        // survives outside clicks on purpose: the owner may click into the
        // target field and the transcript must not vanish.
        outsideMonitors.forEach(NSEvent.removeMonitor)
        outsideMonitors = []
        if interactiveCard {
            let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.model.send(.dismissed) }
            }) {
                outsideMonitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                if let self, event.window !== self.panel {
                    MainActor.assumeIsolated { self.model.send(.dismissed) }
                }
                return event
            }) {
                outsideMonitors.append(local)
            }
        }
    }
}
