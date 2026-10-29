import AppKit
import SuperflowDesignSystem
import SwiftUI

/// Semantic icons backed by Hugeicons or native SF Symbols.
public enum Icon: String, CaseIterable, Sendable {
    // Sidebar.
    case dashboard = "square.grid.2x2"
    case history = "clock.arrow.trianglehead.counterclockwise.rotate.90"
    case dictionary = "character.book.closed"
    case shortcuts = "command"
    case meetings = "person.2.wave.2"
    case settings = "gearshape"
    case models = "brain"

    // Actions and state
    case search = "magnifyingglass"
    case add = "plus"
    case minus = "minus"
    case more = "ellipsis"
    case copy = "doc.on.doc"
    case delete = "trash"
    case refresh = "arrow.clockwise"
    case importIn = "arrow.down.to.line"
    case exportOut = "square.and.arrow.up"
    case rename = "pencil"
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
    case cleanup = "text.badge.checkmark"
    case folder = "folder"
    case sun = "sun.max"
    case moon = "moon"

    // Dashboard metrics (pass 3).
    case words = "text.word.spacing"
    case timeSaved = "hourglass"
    case speed = "gauge.with.needle"
    case streak = "flame"

    // Settings rows (pass 3). Bare symbols only, never an enclosing variant.
    case person = "person.crop.circle"
    case appearance = "circle.lefthalf.filled"
    case liveText = "captions.bubble"
    case power = "power"
    case capsuleShape = "capsule.inset.filled"
    case handTap = "hand.tap"
    case eyeSlash = "lock.doc"
    case diagnostics = "stethoscope"
    case licenses = "doc.plaintext"
    case number = "textformat.123"
    case textSize = "capslock"
    case textAppend = "text.append"
    case space = "space"
    case paragraph = "paragraphsign"
    case blocks = "text.alignleft"
    case code = "curlybraces"
    case chart = "chart.bar.xaxis"
    case settingMeeting = "record.circle"
    case settingWorkers = "person.3"
    case settingCompute = "speedometer"
    case settingClock = "clock.badge.xmark"
    case speechModel = "waveform.badge.mic"
    case noiseSuppression = "ear.badge.waveform"
    case doubleTap = "cursorarrow.click.2"
    case speakerSeparation = "waveform.and.person.filled"
    case keepAudio = "recordingtape"
    case typingSpeed = "character.cursor.ibeam"
    case interactiveDeadline = "bolt"
    case backgroundDeadline = "moon.zzz"
}

public extension Icon {
    static var calendar: Icon { .streak }
    static var timer: Icon { .timeSaved }
    static var clock: Icon { .history }
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
public struct IconView: View {
    public let glyph: Icon
    public var size: CGFloat
    public var weight: IconWeight
    public var tint: Color?
    public var selected: Bool

    public init(_ glyph: Icon, size: CGFloat = 14, weight: IconWeight = .regular,
                tint: Color? = nil, selected: Bool = false) {
        self.glyph = glyph
        self.size = size
        self.weight = weight
        self.tint = tint
        self.selected = selected
    }

    public var body: some View {
        Image(systemName: glyph.symbolName)
            .symbolVariant(selected ? .fill : .none)
            .contentTransition(.symbolEffect(.replace))
            .font(.system(size: size, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint ?? Tok.text2)
            .frame(width: size == 14 || size == 15 ? 20 : size,
                   height: size == 14 || size == 15 ? 20 : size)
            .accessibilityHidden(true)
    }
}

#if DEBUG
/// Call once at launch. A missing name fails loudly instead of rendering nothing.
public func validateGlyphs() {
    for glyph in Icon.allCases {
        assert(NSImage(systemSymbolName: glyph.symbolName, accessibilityDescription: nil) != nil,
               "Missing SF Symbol: \(glyph.symbolName)")
    }
}
#endif
