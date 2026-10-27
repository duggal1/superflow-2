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
            }
        }
        return view
    }

    public func updateNSView(_ view: ChromeView, context: Context) {}
}
