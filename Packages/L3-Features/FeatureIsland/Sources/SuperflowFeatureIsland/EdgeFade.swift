import SwiftUI

/// The transcript preview never ends in a hard clip or an ellipsis: the last
/// 32 pt of the line dissolves into the black. This is an alpha mask on text,
/// not a gradient fill, which is why it is the one allowed `LinearGradient`.
public struct EdgeFade: ViewModifier {
    private let length: CGFloat

    public init(length: CGFloat = 32) {
        self.length = length
    }

    public func body(content: Content) -> some View {
        content.mask {
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear],
                               startPoint: .leading,
                               endPoint: .trailing)
                    .frame(width: length)
            }
        }
    }
}

/// The oldest words dissolve on the left, so a streaming line can keep the newest
/// text hard against the right edge without a hard cut at its start.
public struct EdgeFadeLeading: ViewModifier {
    private let length: CGFloat

    public init(length: CGFloat = 32) {
        self.length = length
    }

    public func body(content: Content) -> some View {
        content.mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black],
                               startPoint: .leading,
                               endPoint: .trailing)
                    .frame(width: length)
                Rectangle()
            }
        }
    }
}

/// A truncated multi-line transcript dissolves at the bottom instead of ending
/// mid-line. The mask is the last 20 points, never more than the block itself.
public struct EdgeFadeBottom: ViewModifier {
    private let length: CGFloat

    public init(length: CGFloat = 20) {
        self.length = length
    }

    public func body(content: Content) -> some View {
        content.mask {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear],
                               startPoint: .top,
                               endPoint: .bottom)
                    .frame(height: length)
            }
        }
    }
}
