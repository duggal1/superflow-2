import SuperflowDesignSystem
import SwiftUI

public struct AppSecureField: View {
    private let label: String
    @Binding private var text: String

    public init(_ label: String, text: Binding<String>) {
        self.label = label
        _text = text
    }

    public var body: some View {
        SecureField(label, text: $text)
            .textFieldStyle(.plain)
            .appType(.body)
            .foregroundStyle(Tok.text)
            .tint(Tok.accent)
            .focusEffectDisabled()
            .padding(.horizontal, Space.sm)
            .frame(height: ControlHeight.large)
            .background(Tok.control, in: .rect(cornerRadius: Radius.field))
            .contrastStroke(radius: Radius.field)
            .accessibilityLabel(label)
            .pixelAudit("AppSecureField")
    }
}
