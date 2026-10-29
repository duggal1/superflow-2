import AppKit
import SuperflowDesignSystem
import SwiftUI

/// Semantic icons backed by Hugeicons or native SF Symbols.
public enum Glyph: String, CaseIterable, Sendable {
    // Sidebar.
    case dashboard = "circle.grid.3x3"
    case history = "clock"
    case dictionary = "textformat.abc"
    case shortcuts = "command"
    case meetings = "person.2.wave.2"
    case settings = "switch.2"
    case models = "square.stack.3d.up"

    // Actions and state
    case search = "magnifyingglass"
    case add = "plus"
    case minus = "minus"
    case more = "ellipsis"
    case copy = "doc.on.doc"
    case delete = "trash"
    case refresh = "arrow.clockwise"
    case importIn = "arrow.down.to.line"
    case exportOut = "arrow.up.to.line"
    case checkmark = "checkmark"
    case chevronUpDown = "chevron.up.chevron.down"
    case chevronRight = "chevron.right"
    case chevronDown = "chevron.down"
    case chevronLeft = "chevron.left"
    case arrow = "arrow.right"
    case close = "xmark"
    case stop = "stop"
    case play = "play.fill"
    case pause = "pause.fill"
    case undo = "arrow.uturn.backward"
    case download = "arrow.down"
    case arrowUp = "arrow.up"
    case externalLink = "arrow.up.right"
    case sidebar = "sidebar.left"
    case alert = "exclamationmark.triangle"
    case info = "info"
    case lock = "lock"

    // Subjects
    case mic = "mic"
    case accessibility = "accessibility"
    case keyboard = "keyboard"
    case speaker = "speaker.wave.2"
    case waveform = "waveform"
    case cleanup = "textformat"
    case folder = "folder"
    case sun = "sun.max"
    case moon = "moon"

    // Dashboard metrics (pass 3).
    case words = "text.word.spacing"
    case timeSaved = "timer"
    case speed = "speedometer"
    case streak = "calendar"

    // Settings rows (pass 3). Bare symbols only, never an enclosing variant.
    case person = "person"
    case appearance = "circle.lefthalf.filled"
    case liveText = "captions.bubble"
    case power = "power"
    case capsuleShape = "capsule"
    case handTap = "hand.tap"
    case eyeSlash = "eye.slash"
    case diagnostics = "doc.text.magnifyingglass"
    case licenses = "doc.text"
    case number = "number"
    case textSize = "textformat.size.larger"
    case textAppend = "text.append"
    case space = "space"
    case paragraph = "paragraphsign"
    case blocks = "text.alignleft"
    case code = "chevron.left.forwardslash.chevron.right"
    case chart = "chart.bar"
}

public extension Glyph {
    static var calendar: Glyph { .streak }
    static var timer: Glyph { .timeSaved }
    static var clock: Glyph { .history }
}

public enum IconWeight: Sendable {
    case regular, medium

    public var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        }
    }
}

/// A bare symbol. It carries no meaning on its own, so it is hidden from
/// VoiceOver; the control around it owns the accessibility label.
///
/// Rendering is `.monochrome` so a parent's `foregroundStyle` reaches the glyph.
/// Hierarchical rendering made the sidebar icons dim and two-tone. Sizes are
/// exactly 14 (rows), 16 (bar), 12 (buttons) and 9 (dropdown chevron).
public struct Icon: View {
    public let glyph: Glyph
    public var size: CGFloat
    public var weight: IconWeight
    public var tint: Color?

    public init(_ glyph: Glyph, size: CGFloat = 14, weight: IconWeight = .regular,
                tint: Color? = nil) {
        self.glyph = glyph
        self.size = size
        self.weight = weight
        self.tint = tint
    }

    public var body: some View {
        Group {
            if let image = HugeIcon.image(for: glyph) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: glyph.symbolName)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
            .font(.system(size: size, weight: weight.fontWeight))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint ?? Tok.text2)
            .accessibilityHidden(true)
    }
}

#if DEBUG
/// Call once at launch. A missing name fails loudly instead of rendering nothing.
public func validateGlyphs() {
    for glyph in Glyph.allCases {
        assert(NSImage(systemSymbolName: glyph.symbolName, accessibilityDescription: nil) != nil,
               "Missing SF Symbol: \(glyph.symbolName)")
    }
}
#endif
