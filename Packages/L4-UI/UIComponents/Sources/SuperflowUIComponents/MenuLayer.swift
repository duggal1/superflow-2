import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

/// One overlay at the root of the window owns every dropdown and action menu.
/// No `.popover` (arrow chrome), no system focus ring, no clipping inside scroll
/// views, and it can flip upward near the bottom edge.
@MainActor
@Observable
public final class MenuHost {
    public struct Item: Identifiable, Hashable {
        public let id: Int
        public let title: String
        public var glyph: Glyph?

        public init(id: Int, title: String, glyph: Glyph? = nil) {
            self.id = id
            self.title = title
            self.glyph = glyph
        }
    }

    public struct Presented {
        public let token: UUID
        public var anchor: CGRect
        public let trailing: Bool
        public let items: [Item]
        public let selected: Int?
        public let pick: @MainActor (Int) -> Void

        public init(token: UUID, anchor: CGRect, trailing: Bool, items: [Item],
                    selected: Int?, pick: @escaping @MainActor (Int) -> Void) {
            self.token = token
            self.anchor = anchor
            self.trailing = trailing
            self.items = items
            self.selected = selected
            self.pick = pick
        }
    }

    public private(set) var presented: Presented?
    public var cursor: Int?

    public init() {}

    public func present(_ presented: Presented) {
        cursor = presented.selected ?? presented.items.first?.id
        self.presented = presented
    }

    public func isOpen(_ token: UUID) -> Bool { presented?.token == token }

    public func reanchor(_ token: UUID, _ frame: CGRect) {
        guard presented?.token == token else { return }
        presented?.anchor = frame
    }

    public func dismiss() { presented = nil }

    public func move(_ delta: Int) {
        guard let presented, !presented.items.isEmpty else { return }
        let index = presented.items.firstIndex { $0.id == cursor } ?? 0
        cursor = presented.items[(index + delta + presented.items.count) % presented.items.count].id
    }

    public func commit(_ id: Int? = nil) {
        guard let presented, let target = id ?? cursor else { return }
        self.presented = nil
        presented.pick(target)
    }
}

public struct MenuLayer: View {
    @Environment(MenuHost.self) private var host

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            if let presented = host.presented {
                ZStack {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { host.dismiss() }
                    MenuPanel(presented: presented, canvas: proxy.size)
                }
                .id(presented.token)
                .transition(.opacity)
            }
        }
        .animation(Motion.menuOut, value: host.presented?.token)
    }
}

private struct MenuPanel: View {
    let presented: MenuHost.Presented
    let canvas: CGSize
    @Environment(MenuHost.self) private var host
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var focused: Bool
    @State private var shown = false

    private let row: CGFloat = 32
    private let gap: CGFloat = 2
    private let inset: CGFloat = 6

    var body: some View {
        let width = max(presented.anchor.width, 184)
        let count = CGFloat(presented.items.count)
        let height = count * row + max(count - 1, 0) * gap + inset * 2
        let x = min(max(presented.trailing ? presented.anchor.maxX - width : presented.anchor.minX, 8),
                    max(canvas.width - width - 8, 8))
        let below = presented.anchor.maxY + 6 + height <= canvas.height - 8
        let y = below ? presented.anchor.maxY + 6 : presented.anchor.minY - 6 - height
        let origin = UnitPoint(x: presented.trailing ? 1 : 0, y: below ? 0 : 1)
        let instant = shown || reduceMotion

        VStack(spacing: gap) {
            ForEach(presented.items) { item in
                MenuRow(item: item,
                        isSelected: item.id == presented.selected,
                        isHighlighted: item.id == host.cursor,
                        radius: Radius.card - inset)
                    .onHover { inside in
                        if inside { host.cursor = item.id }
                    }
                    .onTapGesture { host.commit(item.id) }
            }
        }
        .padding(inset)
        .frame(width: width)
        .modifier(PanelSurface(solid: reduceTransparency))
        .scaleEffect(instant ? 1 : 0.96, anchor: origin)
        .offset(y: instant ? 0 : (below ? -4 : 4))
        .opacity(instant ? 1 : 0)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { host.move(1); return .handled }
        .onKeyPress(.upArrow) { host.move(-1); return .handled }
        .onKeyPress(.return) { host.commit(); return .handled }
        .onKeyPress(.escape) { host.dismiss(); return .handled }
        .onAppear {
            focused = true
            withAnimation(Motion.menuIn) { shown = true }
        }
        .padding(.leading, x)
        .padding(.top, max(y, 0))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PanelSurface: ViewModifier {
    let solid: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        if solid {
            content.background(Tok.control, in: shape)
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

private struct MenuRow: View {
    let item: MenuHost.Item
    let isSelected: Bool
    let isHighlighted: Bool
    let radius: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            if let glyph = item.glyph {
                Icon(glyph, size: 14, tint: Tok.text)
                    .frame(width: 20)
            }
            Text(item.title)
                .font(.system(size: 13))
                .foregroundStyle(Tok.text)
                .lineLimit(1)
            Spacer(minLength: Space.md)
            if isSelected {
                Icon(.checkmark, size: 12, weight: .medium, tint: Tok.text)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(isHighlighted ? Tok.wash : .clear,
                    in: .rect(cornerRadius: radius, style: .continuous))
        .contentShape(.rect)
        .animation(Motion.hoverIn, value: isHighlighted)
        .clickable()
    }
}

/// Custom trigger, our panel. The chevron is one size (9) and nothing else.
public struct Dropdown<Value: Hashable>: View {
    public struct Option: Identifiable {
        public let value: Value
        public let title: String
        public var id: Value { value }

        public init(_ title: String, value: Value) {
            self.title = title
            self.value = value
        }
    }

    @Binding private var selection: Value
    private let options: [Option]
    private let label: String
    @Environment(MenuHost.self) private var host
    @State private var token = UUID()
    @State private var frame: CGRect = .zero
    @State private var hover = false

    public init(selection: Binding<Value>, options: [Option], label: String = "Choose") {
        _selection = selection
        self.options = options
        self.label = label
    }

    private var isOpen: Bool { host.isOpen(token) }
    private var selectedIndex: Int? { options.firstIndex { $0.value == selection } }
    private var selectedTitle: String {
        selectedIndex.map { options[$0].title } ?? ""
    }

    public var body: some View {
        Button(action: toggle) {
            HStack(spacing: Space.xs) {
                Text(selectedTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Tok.text)
                    .lineLimit(1)
                Icon(.chevronUpDown, size: 9, weight: .medium, tint: Tok.text2)
            }
            .padding(.horizontal, Space.sm)
            .frame(height: ControlHeight.regular)
            .background(isOpen ? Tok.controlPressed : hover ? Tok.controlHover : Tok.control,
                        in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(hover ? Motion.hoverIn : Motion.hoverOut, value: hover)
        .animation(Motion.hoverIn, value: isOpen)
        .reportFrame($frame)
        .onChange(of: frame) { _, value in host.reanchor(token, value) }
        .clickable()
        .accessibilityLabel(label)
        .accessibilityValue(selectedTitle)
    }

    private func toggle() {
        if isOpen {
            host.dismiss()
            return
        }
        host.present(.init(
            token: token, anchor: frame, trailing: true,
            items: options.enumerated().map { .init(id: $0.offset, title: $0.element.title) },
            selected: selectedIndex,
            pick: { index in selection = options[index].value }))
    }
}

/// The ellipsis menu in page bars.
public struct ActionMenu: View {
    public struct Action: Identifiable {
        public let id = UUID()
        public let title: String
        public var glyph: Glyph?
        public let run: () -> Void

        public init(_ title: String, glyph: Glyph? = nil, run: @escaping () -> Void) {
            self.title = title
            self.glyph = glyph
            self.run = run
        }
    }

    private let actions: [Action]
    private let label: String
    @Environment(MenuHost.self) private var host
    @State private var token = UUID()
    @State private var frame: CGRect = .zero

    public init(actions: [Action], label: String = "More") {
        self.actions = actions
        self.label = label
    }

    public var body: some View {
        BarIconButton(glyph: .more, label: label) {
            if host.isOpen(token) {
                host.dismiss()
                return
            }
            host.present(.init(
                token: token, anchor: frame, trailing: true,
                items: actions.enumerated().map {
                    .init(id: $0.offset, title: $0.element.title, glyph: $0.element.glyph)
                },
                selected: nil,
                pick: { index in actions[index].run() }))
        }
        .reportFrame($frame)
        .onChange(of: frame) { _, value in host.reanchor(token, value) }
    }
}
