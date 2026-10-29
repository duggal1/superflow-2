import AppKit
import SwiftUI

/// Shared sans-serif roles.
public enum AppType: Sendable, CaseIterable {
    /// 12 / 400 — meta lines, badges of text, field labels.
    case caption
    /// 13 / 400 — reading rows and secondary copy.
    case body
    /// 13 / 400 — titles and labels you scan.
    case label
    /// 15 / 400 — transcript and page prose.
    case reading
    /// 15 / 400 — section and page titles.
    case title
    /// 28 / 400, tabular — the one big number on a card.
    case metric

    public var size: CGFloat {
        switch self {
        case .caption: 12
        case .body, .label: 13
        case .reading, .title: 15
        case .metric: 28
        }
    }

    public var tracking: CGFloat { 0 }

    public var weight: CGFloat {
        switch self {
        case .caption, .body, .reading: AppFont.textWeight
        case .label, .title, .metric: AppFont.emphasisWeight
        }
    }

    public var font: Font { Typography.ui(size, weight: weight) }

}

public enum AppTypeScope: Sendable {
    case standard, island
}

private struct AppTypeScopeKey: EnvironmentKey {
    static let defaultValue = AppTypeScope.standard
}

public extension EnvironmentValues {
    var appTypeScope: AppTypeScope {
        get { self[AppTypeScopeKey.self] }
        set { self[AppTypeScopeKey.self] = newValue }
    }
}

public extension AppType {
    func size(in scope: AppTypeScope) -> CGFloat {
        guard scope == .island else { return size }
        return switch self {
        case .caption: 12
        case .body, .label: 13
        case .reading, .title: 14
        case .metric: 24
        }
    }

    func tracking(in scope: AppTypeScope) -> CGFloat {
        guard scope == .island else { return tracking }
        return switch self {
        case .caption: -0.2
        case .body, .label: -0.3
        case .reading, .title: -0.4
        case .metric: -0.6
        }
    }

    func weight(in scope: AppTypeScope) -> CGFloat {
        scope == .island ? 400 : weight
    }
}

private struct AppTypeModifier: ViewModifier {
    let role: AppType
    @Environment(\.appTypeScope) private var scope

    func body(content: Content) -> some View {
        content
            .font(scope == .island
                  ? Typography.font(name: AppFont.islandName, size: role.size(in: scope), weight: role.weight(in: scope))
                  : Typography.ui(role.size(in: scope), weight: role.weight(in: scope)))
            .tracking(role.tracking(in: scope))
    }
}

public extension View {
    func appType(_ role: AppType) -> some View {
        modifier(AppTypeModifier(role: role))
    }
}
