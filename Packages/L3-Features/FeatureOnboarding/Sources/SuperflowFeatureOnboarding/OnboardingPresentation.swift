import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI

/// Rows the steps reuse. A row never owns state: the model does.
///
/// One shape for both rows: what it is on the left, what it wants on the right.
/// There is no leading glyph, because the title already names the thing and a
/// second symbol for one fact is noise. The trailing column is the only place
/// the state appears, and it is always one control wide.
enum OnboardingPresentation {
    /// Title, one-line reason, trailing control. Never a divider between rows.
    struct PermissionRow: View {
        @ObservedObject var model: OnboardingViewModel
        let permission: Permission
        /// Only the first row that still needs action carries the accent fill.
        var accent: Bool = false

        var body: some View {
            let status = model.status(for: permission)
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(permission.label)
                        .appType(.label)
                        .foregroundStyle(Tok.text)
                    Text(permission.rationale)
                        .appType(.body)
                        .foregroundStyle(Tok.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.md)
                control(status)
            }
            .frame(minHeight: 52)
            .accessibilityElement(children: .contain)
        }

        @ViewBuilder
        private func control(_ status: PermissionStatus) -> some View {
            switch status {
            case .granted:
                Badge("Granted", variant: .green, size: .sm)
            case .denied:
                AppButton("Open Settings", kind: .link, action: open)
            case .notDetermined:
                AppButton("Grant", kind: accent ? .primary : .quiet, action: request)
            }
        }

        private func request() {
            Task { await model.request(permission) }
        }

        private func open() {
            Task { await model.openSystemSettings(permission) }
        }
    }

    /// macOS steals the Globe key when it is not set to Do Nothing, so the row is
    /// detection plus a deep link, never a permission request.
    struct GlobeRow: View {
        @ObservedObject var model: OnboardingViewModel

        var body: some View {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Globe key")
                        .appType(.label)
                        .foregroundStyle(Tok.text)
                    Text(reason)
                        .appType(.body)
                        .foregroundStyle(Tok.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.md)
                control
            }
            .frame(minHeight: 52)
            .accessibilityElement(children: .contain)
        }

        @ViewBuilder
        private var control: some View {
            if model.globeConflict {
                AppButton("Open Keyboard settings", kind: .link, action: open)
            } else if model.globeChecked {
                Badge("Ready", variant: .green, size: .sm)
            }
        }

        private var reason: String {
            guard model.globeChecked else {
                return "Checking the current shortcut."
            }
            if model.globeConflict {
                return "macOS uses it for “\(model.globeAction.label)”."
            }
            return "Set to Do Nothing, so fn is free."
        }

        private func open() {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    }
}
