import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

struct MenuPanel: View {
    let presented: MenuHost.Presented
    let bounds: CGSize
    let origin: CGPoint
    @Environment(MenuHost.self) private var host
    @Environment(\.accessibilityReduceMotion) private var reduce
    @FocusState private var focused: Bool
    @State private var shown = false

    var body: some View {
        let items = presented.items
        let width = min(MenuMetrics.width(items, minWidth: presented.anchor.width), max(1, bounds.width - 16))
        let height = min(MenuMetrics.height(items), max(1, bounds.height - 16))
        let offsets = MenuMetrics.offsets(items)
        let place = MenuMetrics.placement(anchor: presented.anchor,
            size: CGSize(width: width, height: height), bounds: bounds, origin: origin)
        ScrollViewReader { scroll in
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                        .fill(Tok.controlPressed)
                        .frame(width: width - 8, height: MenuMetrics.row)
                        .offset(x: 4, y: host.cursor.flatMap { offsets.indices.contains($0) ? offsets[$0] : nil } ?? 4)
                        .opacity(host.cursor == nil ? 0 : 1)
                        .animation(reduce ? nil : .smooth(duration: 0.18), value: host.cursor)
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if item.gapBefore { Color.clear.frame(height: MenuMetrics.gap) }
                            Button { host.commit(index) } label: { MenuRow(item: item) }
                                .buttonStyle(.plain)
                                .disabled(!item.enabled)
                                .focusEffectDisabled()
                                .clickable(item.enabled)
                                .onHover { inside in host.hover(inside ? index : nil) }
                                .id(index)
                                .accessibilityLabel(item.title)
                                .accessibilityAddTraits(item.checked ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, MenuMetrics.inset)
                }
                .frame(width: width, height: MenuMetrics.height(items), alignment: .topLeading)
            }
            .onChange(of: host.cursor) { _, index in
                if let index { scroll.scrollTo(index) }
            }
        }
        .frame(width: width, height: height)
        .background(Tok.controlHover, in: .rect(cornerRadius: Radius.nested, style: .continuous))
        .modifier(ContrastStroke(radius: Radius.nested))
        .clipShape(.rect(cornerRadius: Radius.nested))
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.downArrow) { host.move(1); return .handled }
        .onKeyPress(.upArrow) { host.move(-1); return .handled }
        .onKeyPress(.return) { host.commit(); return .handled }
        .onKeyPress(.escape) { host.dismiss(); return .handled }
        .scaleEffect(shown || reduce ? 1 : 0.96, anchor: place.flipped ? .bottomTrailing : .topTrailing)
        .offset(y: shown || reduce ? 0 : (place.flipped ? 4 : -4))
        .opacity(shown || reduce ? 1 : 0)
        .offset(x: place.point.x, y: place.point.y)
        .onAppear {
            focused = true
            withAnimation(reduce ? nil : .smooth(duration: 0.20)) { shown = true }
        }
    }
}

private struct MenuRow: View {
    let item: MenuItem
    var body: some View {
        let tone = item.role == .destructive ? Tok.statusBad : Tok.text
        HStack(spacing: 8) {
            ZStack {
                if let leading = item.leading { leading }
                else if let glyph = item.glyph { Icon(glyph, size: 14, tint: tone) }
            }
            .frame(width: 20, height: 20)
            Text(item.title).appType(.label).foregroundStyle(tone).lineLimit(1)
            Spacer(minLength: 16)
            if item.checked {
                Icon(.checkmark, size: 12, tint: Tok.accentText).frame(width: 20, height: 20)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: MenuMetrics.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .opacity(item.enabled ? 1 : Opacity.disabled)
    }
}
