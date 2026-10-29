import AppKit
import SuperflowDesignSystem
import SwiftUI

@MainActor
public enum MenuMetrics {
    public static let row: CGFloat = 32
    public static let inset: CGFloat = 4
    public static let gap: CGFloat = 8

    public static func height(_ items: [MenuItem]) -> CGFloat {
        inset * 2 + CGFloat(items.count) * row + CGFloat(items.filter(\.gapBefore).count) * gap
    }

    public static func offsets(_ items: [MenuItem]) -> [CGFloat] {
        var y = inset
        return items.map { item in
            if item.gapBefore { y += gap }
            defer { y += row }
            return y
        }
    }

    public static func width(_ items: [MenuItem], minWidth: CGFloat) -> CGFloat {
        let font = Typography.nsUIFont(AppType.label.size, weight: AppType.label.weight)
        let text = items.map { ($0.title as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return max(minWidth, ceil(text) + 96)
    }

    public static func index(at y: CGFloat, _ items: [MenuItem]) -> Int? {
        offsets(items).enumerated().first { y >= $0.element && y < $0.element + row }?.offset
    }

    public static func placement(anchor: CGRect, size: CGSize, bounds: CGSize,
                                 origin: CGPoint) -> (point: CGPoint, flipped: Bool) {
        let left = origin.x + 8
        let right = max(left, origin.x + bounds.width - size.width - 8)
        let x = min(max(anchor.maxX - size.width, left), right)
        let below = anchor.maxY + 6
        let flipped = below + size.height > origin.y + bounds.height - 8
        let y = max(origin.y + 8, flipped ? anchor.minY - 6 - size.height : below)
        return (CGPoint(x: x - origin.x, y: y - origin.y), flipped)
    }
}
