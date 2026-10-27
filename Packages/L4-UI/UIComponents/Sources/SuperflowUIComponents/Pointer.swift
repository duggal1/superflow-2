import AppKit
import SuperflowDesignSystem
import SwiftUI

/// The pointer hand, two layers deep: SwiftUI's `pointerStyle`, backed up by an
/// AppKit cursor rect. `pointerStyle` alone was not reliable across the window,
/// and a cursor rect survives scroll views, overlays and window reactivation.
/// Disabled passes false and keeps the arrow.
public extension View {
    func clickable(_ enabled: Bool = true) -> some View {
        pointerStyle(enabled ? .link : nil)
            .overlay {
                if enabled {
                    CursorRect(cursor: .pointingHand)
                        .allowsHitTesting(false)
                }
            }
    }
}

struct CursorRect: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorView {
        CursorView(cursor)
    }

    func updateNSView(_ view: CursorView, context: Context) {
        view.cursor = cursor
        view.window?.invalidateCursorRects(for: view)
    }

    final class CursorView: NSView {
        var cursor: NSCursor

        init(_ cursor: NSCursor) {
            self.cursor = cursor
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("CursorRect is never loaded from a nib")
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: cursor)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            window?.invalidateCursorRects(for: self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }
    }
}

public extension View {
    /// Horizontal drag handle. Open hand at rest, closed hand while dragging.
    func scrubbable(_ active: Bool) -> some View { pointerStyle(active ? .grabActive : .grabIdle) }
}
