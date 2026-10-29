import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

struct SystemStatusDialog: View {
    let status: String
    let speech: String
    let cleanupEnabled: Bool
    let needsAttention: Bool
    let fix: () -> Void

    var body: some View {
        DialogFrame(title: "System", confirmTitle: needsAttention ? "Open settings" : "Done",
                    canConfirm: true, showsCancel: needsAttention, onConfirm: {
            if needsAttention { fix() }
        }) {
            VStack(alignment: .leading, spacing: Space.md) {
                row("Status", status)
                row("Speech model", speech)
                row("Cleanup", cleanupEnabled ? "Enabled" : "Off")
                row("Model memory", "Unavailable")
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Text(title).appType(.body).foregroundStyle(Tok.text2)
            Spacer(minLength: Space.md)
            Text(value).appType(.label).foregroundStyle(Tok.text).multilineTextAlignment(.trailing)
        }
    }
}

