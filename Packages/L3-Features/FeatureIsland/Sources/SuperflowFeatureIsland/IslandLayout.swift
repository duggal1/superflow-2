import SwiftUI

/// One reducer, one phase, eleven values. Push-to-talk, hands-free and a latched
/// meeting are three different promises, so the notch says which one is live;
/// an Escape it may regret and a milestone worth saying out loud are the two
/// cards the old Island could not draw.
public enum IslandPhase: Equatable, Sendable {
    case idle
    case hover
    case listening
    case handsFree
    case meeting
    case processing
    case landed(words: Int)
    case undo(IslandUndo)
    case failed(IslandTranscript)
    case recent(IslandTranscript?)
    case notice(IslandNotice)
}

public extension IslandPhase {
    enum Kind: Equatable, Sendable { case rest, wings, card }

    var kind: Kind {
        switch self {
        case .idle, .hover: .rest
        case .listening, .handsFree, .meeting, .processing, .landed: .wings
        case .failed, .recent, .undo, .notice: .card
        }
    }

    var isRest: Bool { kind == .rest }

    var isBusy: Bool {
        switch self {
        case .listening, .handsFree, .meeting, .processing: true
        case .idle, .hover, .landed, .undo, .failed, .recent, .notice: false
        }
    }

    var isDismissable: Bool {
        switch self {
        case .failed, .recent, .landed, .undo, .notice: true
        case .idle, .hover, .listening, .handsFree, .meeting, .processing: false
        }
    }

    /// Hands-free and meetings carry a word, so their wings are wide enough for
    /// one. The three plain states keep the narrow wings.
    var isWide: Bool {
        switch self {
        case .handsFree, .meeting: true
        case .idle, .hover, .listening, .processing, .landed, .undo, .failed, .recent, .notice: false
        }
    }
}

public struct IslandBox: Equatable, Sendable {
    /// The black rectangle. Flares are excluded.
    public var body: CGSize
    /// Concave fillet radius at the top corners.
    public var top: CGFloat
    /// Convex corner radius at the bottom.
    public var bottom: CGFloat
    public var opacity: Double

    public init(body: CGSize, top: CGFloat, bottom: CGFloat, opacity: Double) {
        self.body = body
        self.top = top
        self.bottom = bottom
        self.opacity = opacity
    }

    public var frameSize: CGSize {
        .init(width: body.width + 2 * top, height: body.height)
    }
}

public enum IslandLayout {
    /// The window never changes size. Every state is drawn inside this canvas, top-centred.
    public static let canvas = CGSize(width: 520, height: 128)

    public static let wing: CGFloat = 56
    /// Hands-free and meeting spend 24 more points on the name of the mode.
    public static let wingWide: CGFloat = 104
    public static let wingInset: CGFloat = 14
    public static let nonNotchGap: CGFloat = 16

    public static let cardWidth: CGFloat = 480
    public static let cardPad: CGFloat = 20
    public static let cardGap: CGFloat = 12
    public static let cardRowGap: CGFloat = 8
    public static let cardRow: CGFloat = 28
    public static let cardMeta: CGFloat = 16
    public static let restBottom: CGFloat = 12

    public static func wingWidth(_ phase: IslandPhase) -> CGFloat {
        phase.isWide ? wingWide : wing
    }

    /// band + gap + transcript + gap + meta + bottom padding, on the 4 pt grid.
    public static func cardHeight(_ band: CGFloat) -> CGFloat {
        band + cardGap + cardRow + cardRowGap + cardMeta + cardPad
    }

    public static func box(_ phase: IslandPhase, _ geometry: NotchGeometry) -> IslandBox {
        let gap = geometry.hasNotch ? geometry.notch.width : nonNotchGap
        switch phase {
        case .idle:
            return geometry.hasNotch
                ? IslandBox(body: geometry.notch, top: 0, bottom: restBottom, opacity: 1)
                : IslandBox(body: .init(width: gap + wing, height: geometry.band - 8),
                            top: 0, bottom: 14, opacity: 0)
        case .hover:
            return IslandBox(body: .init(width: geometry.notch.width + 8,
                                         height: geometry.notch.height + 4),
                             top: 6, bottom: restBottom, opacity: 1)
        case .listening, .processing, .landed:
            return IslandBox(body: .init(width: gap + 2 * wing, height: geometry.band),
                             top: 6, bottom: 14, opacity: 1)
        case .handsFree, .meeting:
            return IslandBox(body: .init(width: gap + 2 * wingWide, height: geometry.band),
                             top: 6, bottom: 14, opacity: 1)
        case .failed, .recent, .undo, .notice:
            return IslandBox(body: .init(width: cardWidth,
                                         height: cardHeight(geometry.band)),
                             top: 12, bottom: 24, opacity: 1)
        }
    }

    /// Interactive region in canvas coordinates (origin top-left). Everything
    /// outside it is click-through.
    public static func hitRect(_ phase: IslandPhase, _ geometry: NotchGeometry) -> CGRect {
        if phase == .idle, !geometry.hasNotch { return .zero }
        let size = box(phase, geometry).frameSize
        let slop: CGFloat = phase.isRest ? 0 : 4
        return CGRect(x: (canvas.width - size.width) / 2, y: 0,
                      width: size.width, height: size.height)
            .insetBy(dx: -slop, dy: -slop)
            .intersection(CGRect(origin: .zero, size: canvas))
    }

    public static func animation(from a: IslandPhase, to b: IslandPhase,
                                 reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        switch (a.kind, b.kind) {
        case (.rest, .rest): return .snappy(duration: 0.20)
        case (.rest, _): return .smooth(duration: 0.44)
        case (_, .rest): return .smooth(duration: 0.32)
        case (.wings, .wings): return .snappy(duration: 0.20)
        default: return .smooth(duration: 0.38)
        }
    }
}
