import AppKit
import SwiftUI

/// Type roles. Two weights only: **350 for text you read, 500 for text you scan**.
///
/// Light text on a dark background reads heavier than it measures, so the reading
/// roles sit between Light (-0.4) and Regular (0) on `NSFont`'s weight scale
/// instead of at Regular. Medium roles stay on SwiftUI's own font so
/// `.monospacedDigit()` is guaranteed to tabularise; the 350 roles are measured
/// for it in `DesignSystemTests`.
///
/// Tracking is per role, never per view.
public enum AppType: Sendable, CaseIterable {
    /// 12 / 350 — meta lines, badges of text, field labels.
    case caption
    /// 13 / 350 — reading rows and secondary copy.
    case body
    /// 13 / 500 — titles and labels you scan.
    case label
    /// 15 / 350 — transcript and page prose.
    case reading
    /// 15 / 500 — section and page titles.
    case title
    /// 28 / 500, tabular — the one big number on a card.
    case metric

    public var size: CGFloat {
        switch self {
        case .caption: 12
        case .body, .label: 13
        case .reading, .title: 15
        case .metric: 28
        }
    }

    public var tracking: CGFloat {
        switch self {
        case .caption: 0
        case .body, .label: -0.1
        case .reading, .title: -0.2
        case .metric: -0.6
        }
    }

    public var isMedium: Bool {
        switch self {
        case .label, .title, .metric: true
        case .caption, .body, .reading: false
        }
    }

    /// Halfway between Light and Regular. One constant to revert on.
    public static let readingWeight = NSFont.Weight(rawValue: -0.2)

    public var font: Font {
        guard !isMedium else { return .system(size: size, weight: .medium) }
        return Font(NSFont.systemFont(ofSize: size, weight: Self.readingWeight) as CTFont)
    }
}

public extension View {
    func appType(_ role: AppType) -> some View {
        font(role.font).tracking(role.tracking)
    }
}
