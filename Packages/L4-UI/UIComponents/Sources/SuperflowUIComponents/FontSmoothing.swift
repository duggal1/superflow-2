import AppKit
import SwiftUI

/// SwiftUI has no font-smoothing modifier, and macOS drops subpixel smoothing
/// for layer-backed text unless the drawing context asks for it. This attaches
/// to the hosting window and turns on glyph smoothing, antialiasing and subpixel
/// positioning for the backing store every subview shares.
public struct FontSmoothing: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView { SmoothingView() }
    public func updateNSView(_ nsView: NSView, context: Context) {}
    public static func applyToCurrentContext() {
        guard let context = NSGraphicsContext.current else { return }
        let cg = context.cgContext
        cg.setShouldSmoothFonts(true)
        cg.setAllowsFontSmoothing(true)
        cg.setAllowsAntialiasing(true)
        cg.setShouldAntialias(true)
        cg.setAllowsFontSubpixelPositioning(true)
        cg.setAllowsFontSubpixelQuantization(true)
    }

}

final class SmoothingView: NSView {
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.allowsEdgeAntialiasing = true
        enable()
    }

    override func draw(_ dirtyRect: NSRect) {
        enable()
        super.draw(dirtyRect)
    }

    private func enable() {
        FontSmoothing.applyToCurrentContext()
    }
}

public extension View {
    /// Opts this view's window into smoothed glyph rendering.
    func fontSmoothing() -> some View {
        background(alignment: .topLeading) {
            FontSmoothing()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}
