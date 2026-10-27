import CoreGraphics

public enum Space {
    public static let grid: CGFloat = 4
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48
    public static let xxxl: CGFloat = 64

    /// Page padding, card padding, section gap (DESIGN-REBUILD-GUIDE §5.1, R6).
    public static let pagePadding: CGFloat = 32
    public static let contentPadding: CGFloat = 32
    public static let cardPadding: CGFloat = 20
    public static let cardPaddingDense: CGFloat = 16
    public static let sectionGap: CGFloat = 32
    public static let rowHeight: CGFloat = 28
    public static let proseMaxWidth: CGFloat = 720
    public static let pageMaxWidth: CGFloat = 880
}

public enum Radius {
    public static let capsule: CGFloat = 999
    public static let card: CGFloat = 16
    public static let nested: CGFloat = 12
    public static let field: CGFloat = 8
    public static let badge: CGFloat = 8
    public static let chip: CGFloat = 6
    public static let islandCompact: CGFloat = 22
    public static let islandExpanded: CGFloat = 26
    public static let focusRing: CGFloat = 2
    public static let focusOffset: CGFloat = 2
}

public enum ControlHeight {
    public static let small: CGFloat = 24
    public static let regular: CGFloat = 28
    public static let large: CGFloat = 32
    /// This revision drops the 40pt onboarding CTA; the largest control is 32.
    public static let onboardingCTA: CGFloat = 32
}

public enum Layout {
    public static let windowDefaultWidth: CGFloat = 960
    public static let windowDefaultHeight: CGFloat = 620
    public static let windowMinWidth: CGFloat = 880
    public static let windowMinHeight: CGFloat = 560
    public static let sidebarWidth: CGFloat = 220
    public static let sidebarMin: CGFloat = 200
    public static let sidebarMax: CGFloat = 280
    public static let onboardingWidth: CGFloat = 640
    public static let onboardingHeight: CGFloat = 520
    public static let islandDragThreshold: CGFloat = 4
    public static let islandTopInset: CGFloat = 6

    // Pass 2 structure. One left edge, one bar height, one control height.
    /// Sidebar width. The detail pane starts here, and every page insets by `pad`.
    public static let sidebar: CGFloat = 220
    /// Header bar height, and the sidebar's top inset (the traffic-light zone).
    public static let bar: CGFloat = 52
    /// THE left edge: bar, title, subtitle, cards, graph and list rows all start here.
    public static let pad: CGFloat = 32
    /// Wide pages.
    public static let page: CGFloat = 880
    /// Settings.
    public static let narrow: CGFloat = 640
    /// History and Meetings list pane.
    public static let list: CGFloat = 320
    /// Header controls.
    public static let control: CGFloat = 32
}

public enum WindowSpace {
    /// Coordinate space for menu anchoring: the whole window.
    public static let name = "window"
}

public enum Opacity {
    public static let disabled: Double = 0.4
    public static let pressScale: Double = 0.98
}
