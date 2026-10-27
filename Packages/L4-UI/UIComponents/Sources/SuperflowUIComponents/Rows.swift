import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

/// A feature-facing row that is wholly clickable. Features never build a raw
/// Button, so the pointer cursor and hover state come from here.
public struct RowButton<Content: View>: View {
    private let label: String
    private let height: CGFloat?
    private let radius: CGFloat
    private let selected: Bool
    private let enabled: Bool
    private let hoverFill: Color
    private let action: () -> Void
    private let content: Content
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init(_ label: String, height: CGFloat? = nil, radius: CGFloat = Radius.nested,
                selected: Bool = false, enabled: Bool = true,
                hoverFill: Color = Tok.surface,
                action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.label = label
        self.height = height
        self.radius = radius
        self.selected = selected
        self.enabled = enabled
        self.hoverFill = hoverFill
        self.action = action
        self.content = content()
    }

    public var body: some View {
        Button(action: action) {
            content
                .frame(height: height)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fill, in: .rect(cornerRadius: radius, style: .continuous))
                .contentShape(.rect(cornerRadius: radius))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : Opacity.disabled)
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : (hover ? Motion.hoverIn : Motion.hoverOut), value: hover)
        .clickable(enabled && isEnabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fill: Color {
        if selected { return Tok.control }
        return hover ? hoverFill : .clear
    }
}

/// One settings row: a clear label on the left, one control column on the right.
/// There is no `help` parameter, so help text cannot come back. Every control
/// column is 280 wide, which is what makes every slider track share one edge.
public struct SettingRow<Control: View>: View {
    /// The shared control column. Matches TimingSlider's fixed width.
    public static var controlWidth: CGFloat { 280 }

    private let title: String
    private let filter: String
    private let control: Control

    public init(_ title: String, filter: String = "", @ViewBuilder control: () -> Control) {
        self.title = title
        self.filter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        self.control = control()
    }

    private var visible: Bool {
        filter.isEmpty || title.localizedCaseInsensitiveContains(filter)
    }

    public var body: some View {
        if visible {
            HStack(spacing: Space.lg) {
                Text(title)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Tok.text)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                control
                    .frame(width: Self.controlWidth, height: 44, alignment: .trailing)
            }
            .accessibilityElement(children: .contain)
        }
    }
}

/// The only switch in the app. Features wrap their state in this instead of
/// reaching for a raw Toggle.
public struct SettingToggle: View {
    private let label: String
    @Binding private var isOn: Bool
    private let enabled: Bool

    public init(_ label: String, isOn: Binding<Bool>, enabled: Bool = true) {
        self.label = label
        _isOn = isOn
        self.enabled = enabled
    }

    public var body: some View {
        AppToggle(label, isOn: $isOn, enabled: enabled)
    }
}

/// Trigger → result. Dictionary and Shortcuts share the skeleton.
public struct EntryRow: View {
    private let trigger: String
    private let result: String
    private let badge: String?
    private let badgeVariant: BadgeVariant
    private let isDisabled: Bool
    private let onOpen: () -> Void
    private let onDelete: () -> Void

    public init(trigger: String, result: String, badge: String? = nil,
                badgeVariant: BadgeVariant = .neutral, isDisabled: Bool = false,
                onOpen: @escaping () -> Void,
                onDelete: @escaping () -> Void) {
        self.trigger = trigger
        self.result = result
        self.badge = badge
        self.badgeVariant = badgeVariant
        self.isDisabled = isDisabled
        self.onOpen = onOpen
        self.onDelete = onDelete
    }

    public var body: some View {
        RowButton("\(trigger), becomes \(result)", height: 36) {
            onOpen()
        } content: {
            HStack(spacing: Space.md) {
                Text(trigger)
                    .font(Typography.body)
                    .foregroundStyle(Tok.text2)
                    .frame(width: 200, alignment: .leading)
                    .lineLimit(1)
                Icon(.arrow, size: 12, tint: Tok.text2)
                Text(result)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(isDisabled ? Tok.text2 : Tok.text)
                    .lineLimit(1)
                Spacer(minLength: Space.md)
                if let badge {
                    Badge(badge, variant: badgeVariant)
                }
            }
            .padding(.horizontal, Space.sm)
        }
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
