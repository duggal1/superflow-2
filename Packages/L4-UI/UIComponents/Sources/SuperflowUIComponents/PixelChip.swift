import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

public struct PixelChip: View {
    private let text: String
    private let mono: Bool
    private let lit: Bool

    public init(_ text: String, mono: Bool = true, lit: Bool = false) {
        self.text = text
        self.mono = mono
        self.lit = lit
    }

    public var body: some View {
        Text(text)
            .font(mono ? .system(size: 12, design: .monospaced) : AppType.body.font)
            .foregroundStyle(Tok.text).lineLimit(1)
            .padding(.horizontal, 10).frame(height: 28)
            .background(NotchedRect().fill(lit ? Tok.controlHover : Tok.control,
                                           style: FillStyle(antialiased: false)))
    }
}

public struct TermChip: View {
    private enum Focus { case term, delete }
    private let text: String
    private let disabled: Bool
    private let onOpen: () -> Void
    private let onDelete: () -> Void
    @State private var hover = false
    @FocusState private var focus: Focus?

    public init(_ text: String, disabled: Bool = false,
                onOpen: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.text = text
        self.disabled = disabled
        self.onOpen = onOpen
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) { PixelChip(text, mono: false, lit: hover).opacity(disabled ? 0.5 : 1) }
                .buttonStyle(.plain).focusEffectDisabled().clickable().focusStep()
                .focused($focus, equals: .term).onDeleteCommand(perform: onDelete)
            if hover || focus != nil {
                Button(action: onDelete) {
                    IconView(.close, size: 9, tint: Tok.text2).frame(width: 20, height: 28)
                }
                .buttonStyle(.plain).focusEffectDisabled().clickable().focusStep()
                .focused($focus, equals: .delete)
                .accessibilityLabel("Delete \(text)")
            }
        }
        .onHover { hover = $0 }
    }
}

public struct FlowLayout: SwiftUI.Layout {
    private let spacing: CGFloat
    public init(spacing: CGFloat = 8) { self.spacing = spacing }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
