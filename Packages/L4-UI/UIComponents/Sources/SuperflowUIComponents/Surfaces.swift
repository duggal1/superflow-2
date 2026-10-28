import SuperflowDesignSystem
import SwiftUI

/// A card is a fill step and nothing else. No border, no shadow, no nested card.
public struct Card<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = Space.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tok.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
            .contrastStroke(radius: Radius.card)
    }
}

/// Page title in Exposure Italic 28, ending in the pixel full stop.
public struct PageTitle: View {
    private let title: String
    private let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(title)
                    .font(Typography.displayFont(size: TypeScale.displaySSize))
                    .tracking(Typography.displayTracking(size: TypeScale.displaySSize))
                    .foregroundStyle(Tok.text)
                PixelStop(cells: 5, cell: 1.5)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .appType(.body)
                    .foregroundStyle(Tok.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Space.xs)
    }
}

/// The header bar: 52pt, on the canvas, same left/right edge as the content below.
/// The whole bar is a window drag area, so the traffic-light zone moves with it.
public struct PageBar<Leading: View, Trailing: View>: View {
    private let width: CGFloat
    private let leading: Leading
    private let trailing: Trailing

    public init(width: CGFloat = Layout.page,
                @ViewBuilder leading: () -> Leading,
                @ViewBuilder trailing: () -> Trailing) {
        self.width = width
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            leading
            Spacer(minLength: Space.md)
            trailing
        }
        .frame(height: Layout.bar)
        .pageWidth(width)
        .background(WindowDragArea())
    }
}

public extension PageBar where Leading == EmptyView, Trailing == EmptyView {
    init(width: CGFloat = Layout.page) {
        self.init(width: width, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// Scrolling page: Dashboard, Dictionary, Shortcuts, Settings.
///
/// Owns the header bar and the top inset, so a title can never collide with a
/// control again: bar 0...52, then 8pt, so the title starts at y = 60.
public struct Page<Leading: View, Trailing: View, Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let width: CGFloat
    private let leading: Leading
    private let trailing: Trailing
    private let content: Content

    public init(title: String,
                subtitle: String? = nil,
                width: CGFloat = Layout.page,
                @ViewBuilder leading: () -> Leading,
                @ViewBuilder trailing: () -> Trailing,
                @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.leading = leading()
        self.trailing = trailing()
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.sectionGap) {
                PageTitle(title, subtitle: subtitle)
                content
            }
            .pageWidth(width)
            .padding(.bottom, Space.xxl)
        }
        .scrollContentBackground(.hidden)
        // `safeAreaBar` would give the bar the scroll-edge treatment, but the app
        // still targets macOS 15. `safeAreaInset` keeps the bar opaque and the
        // content below it. Logged in DESIGN.md.
        .safeAreaInset(edge: .top, spacing: 0) {
            PageBar(width: width) { leading } trailing: { trailing }
                .background(Tok.bg)
        }
        .scrollEdgeSoft()
        .background(Tok.bg)
    }
}

public extension Page where Leading == EmptyView, Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, width: CGFloat = Layout.page,
         @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, width: width,
                  leading: { EmptyView() }, trailing: { EmptyView() }, content: content)
    }
}

/// Two-pane page: History and Meetings. The panes scroll themselves; the header does not.
public struct SplitPage<Leading: View, Trailing: View, ListPane: View, Detail: View>: View {
    private let title: String
    private let subtitle: String?
    private let leading: Leading
    private let trailing: Trailing
    private let list: ListPane
    private let detail: Detail

    public init(title: String,
                subtitle: String? = nil,
                @ViewBuilder leading: () -> Leading,
                @ViewBuilder trailing: () -> Trailing,
                @ViewBuilder list: () -> ListPane,
                @ViewBuilder detail: () -> Detail) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.trailing = trailing()
        self.list = list()
        self.detail = detail()
    }

    public var body: some View {
        VStack(spacing: 0) {
            PageBar(width: .infinity) { leading } trailing: { trailing }
            PageTitle(title, subtitle: subtitle)
                .pageWidth(.infinity)
                .padding(.bottom, Space.lg)
            HStack(alignment: .top, spacing: 0) {
                list
                    .frame(width: Layout.list)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Tok.bg)
    }
}

public extension View {
    /// Content width and the single left edge. Content is `w` wide, left-aligned,
    /// inset by Layout.pad on both sides.
    func pageWidth(_ w: CGFloat) -> some View {
        padding(.horizontal, Layout.pad)
            .frame(maxWidth: w + 2 * Layout.pad, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Content dissolves under the bar instead of cutting off.
    @ViewBuilder
    func scrollEdgeSoft() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

public struct SectionHeader: View {
    private let title: String
    private let note: String?

    public init(_ title: String, note: String? = nil) {
        self.title = title
        self.note = note
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .appType(.title)
                .foregroundStyle(Tok.text)
            if let note {
                Text(note)
                    .appType(.caption)
                    .foregroundStyle(Tok.text2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

public struct KeyValueRow: View {
    private let label: String
    private let value: String

    public init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Text(label)
                .appType(.body)
                .foregroundStyle(Tok.text2)
            Spacer(minLength: Space.md)
            Text(value)
                .appType(.label)
                .monospacedDigit()
                .foregroundStyle(Tok.text)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }
}
