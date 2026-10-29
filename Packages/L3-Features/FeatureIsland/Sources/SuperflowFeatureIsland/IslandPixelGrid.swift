import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

struct IslandPixelGrid {
    let scale: CGFloat

    func length(_ value: CGFloat) -> CGFloat {
        Pixel.snap(value * IslandVisual.artworkScale, scale)
    }

    func rect(_ rect: CGRect) -> CGRect {
        let x = length(rect.minX)
        let y = length(rect.minY)
        return CGRect(x: x, y: y, width: length(rect.maxX) - x, height: length(rect.maxY) - y)
    }
}
