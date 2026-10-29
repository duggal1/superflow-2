import SwiftUI

/// One reducer, one phase. Push-to-talk, hands-free, a latched meeting and the
/// meeting panel are four different promises, so the notch says which one is
/// live; an Escape it may regret, the last few dictations and a milestone worth
/// saying out loud are the cards the Island can open.
public enum IslandPhase: Equatable, Sendable {
    case idle
    case hover
    case listening
    case handsFree
    case meeting
    /// The meeting wings clicked open: timer, word count, talk share.
    case meetingPanel
    case processing
    case landed(words: Int)
    case undo(IslandUndo)
    case failed(IslandTranscript)
    case recent(IslandTranscript?)
    /// The last five dictations, opened by clicking an always-on Island.
    case history
    case notice(IslandNotice)
}

public extension IslandPhase {
    enum Kind: Equatable, Sendable { case rest, wings, card }

    var kind: Kind {
        switch self {
        case .idle, .hover: .rest
        case .listening, .handsFree, .meeting, .processing, .landed: .wings
        case .failed, .recent, .history, .undo, .notice, .meetingPanel: .card
        }
    }

    var isRest: Bool { kind == .rest }

    var isBusy: Bool {
        switch self {
        case .listening, .handsFree, .meeting, .meetingPanel, .processing: true
        case .idle, .hover, .landed, .undo, .failed, .recent, .history, .notice: false
        }
    }

    /// A live meeting is not dismissable: clicking outside must not end a
    /// recording. The panel collapses instead.
    var isDismissable: Bool {
        switch self {
        case .failed, .recent, .history, .landed, .undo, .notice, .meetingPanel: true
        case .idle, .hover, .listening, .handsFree, .meeting, .processing: false
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
    /// The window never changes size. Every state is drawn inside this canvas,
    /// top-centred. Tall enough for the history panel; the transparent area
    /// below the silhouette stays click-through through `hitRect`.
    public static let canvas = CGSize(width: 520, height: 360)

    /// Each wing's width, per the design: a held dictation is 56, a latched one
    /// 84, a meeting 116. The flares sit outside the body, so a wide notch on a
    /// narrow canvas could push the silhouette past the window: the wanted width
    /// is clamped to what the canvas has left after the notch and both flares.
    public static let wing: CGFloat = 56
    public static let wingWide: CGFloat = 84
    public static let wingMeeting: CGFloat = 116
    public static let wingInset: CGFloat = 14
    public static let nonNotchGap: CGFloat = 16
    /// The key hints under a live mode. The wings grow by this much while the
    /// shelf is up, so the silhouette never clips a keycap.
    public static let hintShelf: CGFloat = 32
    /// The streaming line is taller than the hint shelf: it holds real type.
    public static let liveShelf: CGFloat = 40

    public static let cardWidth: CGFloat = 480
    public static let cardPad: CGFloat = 20
    public static let cardGap: CGFloat = 12
    public static let cardRowGap: CGFloat = 8
    public static let cardRow: CGFloat = 28
    public static let actionHeight: CGFloat = 24
    public static let actionGap: CGFloat = 8
    public static let transcriptRow: CGFloat = 36
    public static let cardMeta: CGFloat = 16
    public static let restBottom: CGFloat = 12
    /// Cards taller than band + 60 grow by whole rows at this step.
    public static let cardStep: CGFloat = 44

    public static func wingWidth(_ phase: IslandPhase, gap: CGFloat) -> CGFloat {
        let wanted: CGFloat = switch phase {
        case .meeting, .meetingPanel: wingMeeting
        case .handsFree: wingWide
        default: wing
        }
        let flare: CGFloat = 6
        return min(wanted, (canvas.width - gap - 2 * flare) / 2)
    }

    /// band + gap + transcript + gap + meta + bottom padding, on the 4 pt grid.
    public static func cardHeight(_ band: CGFloat, below: CGFloat = 60) -> CGFloat {
        band + below
    }

    public static func box(_ phase: IslandPhase, _ geometry: NotchGeometry,
                           hint: Bool = false, live: Bool = false,
                           prefs: IslandPrefs = IslandPrefs(), historyRows: Int = 5,
                           noSignal: Bool = false) -> IslandBox {
        let gap = geometry.hasNotch ? geometry.notch.width : nonNotchGap
        let wing = wingWidth(phase, gap: gap)

        func wings(_ extra: CGFloat, below: CGFloat = 0, top: CGFloat = 6,
                   bottom: CGFloat = 14) -> IslandBox {
            IslandBox(body: .init(width: min(gap + extra, canvas.width - 2 * top),
                                  height: geometry.band + below),
                      top: top, bottom: bottom, opacity: 1)
        }
        func wide(_ extra: CGFloat, below: CGFloat) -> IslandBox {
            IslandBox(body: .init(width: min(max(gap + extra, 400), canvas.width - 16),
                                  height: geometry.band + below),
                      top: 8, bottom: 18, opacity: 1)
        }
        func card(_ below: CGFloat = 60) -> IslandBox {
            IslandBox(body: .init(width: cardWidth, height: cardHeight(geometry.band, below: below)),
                      top: 12, bottom: 24, opacity: 1)
        }

        switch phase {
        case .idle:
            if geometry.hasNotch {
                return IslandBox(body: .init(width: geometry.notch.width,
                                             height: geometry.band + (prefs.alwaysOn ? 5 : 0)),
                                 top: 0, bottom: restBottom, opacity: 1)
            }
            // "Always show Island" puts a small black pill on a notch-less
            // display instead of hiding the Island entirely.
            return prefs.alwaysOn
                ? IslandBox(body: .init(width: 232, height: geometry.band + 8),
                            top: 6, bottom: 14, opacity: 1)
                : IslandBox(body: .init(width: gap + wing, height: geometry.band - 8),
                            top: 0, bottom: 14, opacity: 0)
        case .hover:
            return prefs.alwaysOn
                ? IslandBox(body: .init(width: max(geometry.notch.width + 8, 232),
                                        height: geometry.band + 28),
                            top: 6, bottom: 14, opacity: 1)
                : IslandBox(body: .init(width: geometry.notch.width + 8,
                                        height: geometry.notch.height + 4),
                            top: 6, bottom: restBottom, opacity: 1)
        case .listening:
            if noSignal && !live { return wings(112, below: hintShelf, top: 8, bottom: 18) }
            if live { return wide(112, below: liveShelf) }
            return wings(2 * wing)
        case .handsFree:
            if live { return wide(168, below: liveShelf) }
            return wings(2 * wing, below: (hint || noSignal) ? hintShelf : 0,
                         top: (hint || noSignal) ? 8 : 6, bottom: (hint || noSignal) ? 18 : 14)
        case .meeting:
            if live { return wide(232, below: liveShelf) }
            return wings(2 * wing, below: hint ? hintShelf : 0,
                         top: hint ? 8 : 6, bottom: hint ? 18 : 14)
        case .processing, .landed:
            return wings(2 * wingWidth(.processing, gap: gap))
        case .meetingPanel:
            return card(live ? 208 : 176)
        case .failed:
            return card(132)
        case .history:
            return card(CGFloat(8 + max(2, min(5, historyRows)) * 40 + 40))
        case .recent:
            return card(88)
        case .undo:
            return card()
        case .notice:
            return card(76)
        }
    }

    /// Interactive region in canvas coordinates (origin top-left). Everything
    /// outside it is click-through.
    public static func hitRect(_ phase: IslandPhase, _ geometry: NotchGeometry,
                               hint: Bool = false, live: Bool = false,
                               prefs: IslandPrefs = IslandPrefs()) -> CGRect {
        if phase == .idle, !geometry.hasNotch, !prefs.alwaysOn { return .zero }
        let size = box(phase, geometry, hint: hint, live: live, prefs: prefs).frameSize
        let slop: CGFloat = phase.isRest ? 0 : 4
        return CGRect(x: (canvas.width - size.width) / 2, y: 0,
                      width: size.width, height: size.height)
            .insetBy(dx: -slop, dy: -slop)
            .intersection(CGRect(origin: .zero, size: canvas))
    }

    public static func contains(_ point: CGPoint, box: IslandBox) -> Bool {
        guard box.opacity > 0 else { return false }
        let frame = CGRect(x: (canvas.width - box.frameSize.width) / 2, y: 0,
                           width: box.frameSize.width, height: box.frameSize.height)
        return NotchShape(top: box.top, bottom: box.bottom).path(in: frame).contains(point)
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
