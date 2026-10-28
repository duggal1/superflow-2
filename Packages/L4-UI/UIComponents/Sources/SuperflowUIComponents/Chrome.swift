import AppKit
import SuperflowDesignSystem
import SwiftUI

/// The titlebar must be the canvas, not a lighter band. Traffic lights float on it.
public final class ChromeView: NSView {
    public var configure: (@MainActor (NSWindow) -> Void)?

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            configure?(window)
        }
    }
}

public struct WindowChrome: NSViewRepresentable {
    public enum Kind: Sendable {
        case main, onboarding
    }

    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        let kind = kind
        view.configure = { window in
            window.makeFirstResponder(nil)
            // The system ring is the pass-3 defect: with Full Keyboard Access on,
            // macOS hands the first key view focus when the window opens and the
            // container draws Apple's own ring around itself. Ours is the only
            // ring, and it is drawn for keyboard navigation only (§3).
            window.contentView?.focusRingType = .none
            DispatchQueue.main.async { window.makeFirstResponder(nil) }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            switch kind {
            case .onboarding:
                window.isMovableByWindowBackground = true
                window.backgroundColor = NSColor(Tok.bg)
                window.isOpaque = true
                window.styleMask.remove(.resizable)
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.setContentSize(NSSize(width: Layout.onboardingWidth,
                                             height: Layout.onboardingHeight))
            case .main:
                // The sidebar is native blur over the desktop, so the window itself
                // must be transparent. The detail pane paints Tok.bg edge to edge.
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarSeparatorStyle = .none
                window.isMovableByWindowBackground = false
                window.minSize = NSSize(width: Layout.windowMinWidth,
                                        height: Layout.windowMinHeight)
                // Onboarding removes resizing and pins 640 x 520. Coming back to the
                // main window has to restore both, or the dashboard lands in a
                // fixed-size onboarding window.
                if !window.styleMask.contains(.resizable) {
                    window.styleMask.insert(.resizable)
                    window.standardWindowButton(.zoomButton)?.isHidden = false
                    window.setContentSize(NSSize(width: Layout.windowDefaultWidth,
                                                 height: Layout.windowDefaultHeight))
                    window.center()
                }
            }
        }
        return view
    }

    public func updateNSView(_ view: ChromeView, context: Context) {}
}
