import SwiftUI

/// Pure state → silhouette geometry. The only thing that decides how wide, tall
/// and round the attached shape is for a given flow state. It reads no screen and
/// has no side effects; every literal comes from `IslandTokens`.
public enum IslandFlowMetrics {
    public static func box(_ state: IslandFlowState,
                           notchWidth: CGFloat,
                           band: CGFloat,
                           hasNotch: Bool,
                           alwaysOn: Bool = false,
                           liveText: Bool = false) -> IslandBox {
        let canvas = IslandTokens.Size.canvas.width
        let flare = IslandTokens.Radius.fillet

        func wings(_ extra: CGFloat) -> IslandBox {
            IslandBox(body: .init(width: min(notchWidth + extra, canvas - 2 * flare),
                                  height: band),
                      top: flare, bottom: IslandTokens.Radius.wingBottom, opacity: 1)
        }

        func card(_ below: CGFloat) -> IslandBox {
            IslandBox(body: .init(width: IslandTokens.Size.cardWidth, height: band + below),
                      top: IslandTokens.Radius.cardTop,
                      bottom: IslandTokens.Radius.cardBottom, opacity: 1)
        }

        switch state {
        case .collapsed:
            if hasNotch {
                return IslandBox(body: .init(width: notchWidth,
                                             height: band + (alwaysOn ? IslandTokens.Space.xs : 0)),
                                 top: 0, bottom: IslandTokens.Size.restBottom, opacity: 1)
            }
            return alwaysOn
                ? IslandBox(body: .init(width: 232, height: band + IslandTokens.Space.sm),
                            top: flare, bottom: IslandTokens.Radius.wingBottom, opacity: 1)
                : IslandBox(body: .init(width: notchWidth + IslandTokens.Space.xxl,
                                        height: band - IslandTokens.Space.sm),
                            top: 0, bottom: IslandTokens.Radius.wingBottom, opacity: 0)

        case .listening:
            if liveText {
                return IslandBox(body: .init(width: min(notchWidth + 168, canvas - 2 * flare),
                                             height: band + 40),
                                 top: 8, bottom: 18, opacity: 1)
            }
            return wings(112)

        case .meetingLive:
            return wings(232)

        case .compose:
            return card(min(296, IslandTokens.Size.canvas.height - band))

        case .error, .permission:
            return card(160)

        case .thinking:
            return card(140)

        case .answer, .meetingEnded:
            return card(208)

        case .undo:
            return card(132)

        case .settings:
            return card(272)

        case .history:
            return card(248)
        }
    }
}
