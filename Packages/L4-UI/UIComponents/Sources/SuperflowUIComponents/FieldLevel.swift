import SuperflowDesignSystem
import SwiftUI

public enum FieldLevel {
    case canvas, card, dialog

    public func fill(active: Bool) -> Color {
        switch self {
        case .canvas: active ? Tok.fieldHover : Tok.field
        case .card: active ? Tok.bg : Tok.well
        case .dialog: active ? Tok.controlHover : Tok.control
        }
    }
}
