import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

/// Borderless badge: a tinted fill and coloured text. No edge, no inset shade.
public struct Badge: View {
    public enum Size: Sendable {
        case lg, md, sm

        public var font: CGFloat {
            switch self {
            case .lg: 13
            case .md: 12
            case .sm: 10
            }
        }

        public var horizontalPadding: CGFloat {
            self == .lg ? 8 : 6
        }

        public var height: CGFloat {
            switch self {
            case .lg: 24
            case .md: 20
            case .sm: 18
            }
        }
    }

    @Environment(\.colorScheme) private var scheme
    private let text: String
    private let variant: BadgeVariant
    private let size: Size

    public init(_ text: String, variant: BadgeVariant = .neutral, size: Size = .md) {
        self.text = text
        self.variant = variant
        self.size = size
    }

    public var body: some View {
        Text(text)
            .font(Typography.ui(size.font))
            .foregroundStyle(variant.textColor(dark: scheme == .dark))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, size.horizontalPadding)
            .frame(minHeight: size.height)
            .background(variant.fill(dark: scheme == .dark),
                        in: .rect(cornerRadius: Radius.field, style: .continuous))
            .accessibilityLabel(text)
    }
}

public struct DotView: View {
    public let tone: DotTone
    public var size: CGFloat

    public init(_ tone: DotTone, size: CGFloat = 6) {
        self.tone = tone
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A physical key. Depth is a fill step, not a shadow: the lip is a second surface.
public struct KeyCap: View {
    private let label: String
    private let down: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ label: String, down: Bool = false) {
        self.label = label
        self.down = down
    }

    public var body: some View {
        Text(label)
            .font(Typography.bodyMedium)
            .foregroundStyle(Tok.keycapText)
            .frame(minWidth: 28, minHeight: 28)
            .padding(.horizontal, Space.sm)
            .background(Tok.controlHover,
                        in: .rect(cornerRadius: Radius.field, style: .continuous))
            .offset(y: down ? 2 : 0)
            .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: down)
            .background {
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .fill(Tok.control)
                    .offset(y: 2)
            }
            .padding(.bottom, 2)
            .accessibilityLabel(label)
    }
}

/// One number, its label and its note. Exactly one bare symbol, left of the label:
/// icon plus label plus value is already three signals, so there is no dot or box.
public struct Metric: View {
    private let glyph: Glyph?
    private let label: String
    private let value: String
    private let note: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ label: String, value: String, note: String, glyph: Glyph? = nil) {
        self.label = label
        self.value = value
        self.note = note
        self.glyph = glyph
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let glyph {
                    Icon(glyph, size: 14, tint: Tok.text2)
                        .frame(width: 16, height: 16)
                }
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Tok.text2)
            }
            Text(value)
                .font(.system(size: 28, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Tok.text)
                .contentTransition(reduceMotion ? .identity : .numericText())
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(Tok.text2)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Step progress without a bar: the active capsule widens and carries the accent,
/// the trail behind it is the same blue one step quieter, and what is still ahead
/// is a neutral surface step. Sizes stay on the 4pt grid (16 / 4, gap 8, height 4).
public struct ProgressDots: View {
    private let step: Int
    private let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(step: Int, count: Int) {
        self.step = step
        self.count = count
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(color(index))
                    .frame(width: index == step ? 16 : 4, height: 4)
            }
        }
        .animation(reduceMotion ? nil : Motion.settle, value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \(step + 1) of \(count)")
    }

    /// Current, reached, ahead. The 45% tint is the trail fading out, not a text
    /// hierarchy: it is the only two-step tint in the app and it belongs to progress.
    private func color(_ index: Int) -> Color {
        if index == step { return Tok.accent }
        return index < step ? Tok.accent.opacity(0.45) : Tok.controlHover
    }
}

/// Uses a status dot and a sentence. The Island and menu bar inherit this.
public struct NoticeBanner: View {
    private let text: String
    private let tone: DotTone
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(_ text: String, tone: DotTone = .orange,
                actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.tone = tone
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            DotView(tone)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
            Text(text)
                .font(Typography.secondary)
                .foregroundStyle(Tok.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.xs)
            if let actionTitle, let action {
                AppButton(actionTitle, kind: .quiet, height: ControlHeight.small, action: action)
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .background(Tok.control, in: .rect(cornerRadius: Radius.nested, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

public struct ProgressBar: View {
    public let value: Double
    public var height: CGFloat
    public var tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(value: Double, height: CGFloat = 4, tint: Color = Tok.accent) {
        self.value = min(1, max(0, value))
        self.height = height
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Tok.well)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * value))
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : Motion.settle, value: value)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

public enum DotLevel: Sendable {
    case info, warning, success, error
    public var tone: DotTone {
        switch self {
        case .info: .blue
        case .warning: .orange
        case .success: .green
        case .error: .rose
        }
    }
}

public struct Dot: View {
    public let level: DotLevel
    public var size: CGFloat = 6
    public init(level: DotLevel, size: CGFloat = 6) {
        self.level = level
        self.size = size
    }
    public var body: some View {
        DotView(level.tone, size: size)
    }
}

public struct StatusNote: View {
    public let text: String
    public var level: DotLevel = .warning
    public init(text: String, level: DotLevel = .warning) {
        self.text = text
        self.level = level
    }
    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Dot(level: level).frame(width: 6, height: 6)
            Text(text).font(.system(size: 13)).foregroundStyle(Tok.text2).frame(height: 16)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(Tok.surface, in: .rect(cornerRadius: Radius.nested, style: .continuous))
        .modifier(ContrastStroke(radius: Radius.nested))
    }
}
