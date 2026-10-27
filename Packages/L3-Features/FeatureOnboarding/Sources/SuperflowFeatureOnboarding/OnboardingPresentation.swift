import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI

/// Rows the steps reuse. A row never owns state: the model does.
enum OnboardingPresentation {
    /// Title, one-line reason, trailing control. Never a divider between rows.
    struct PermissionRow: View {
        @ObservedObject var model: OnboardingViewModel
        let permission: Permission
        /// Only the first row that still needs action carries the accent fill.
        var accent: Bool = false

        var body: some View {
            let status = model.status(for: permission)
            HStack(spacing: Space.sm) {
                Icon(glyph, size: 14, tint: status.isGranted ? Tok.text2 : Tok.text)
                VStack(alignment: .leading, spacing: 2) {
                    Text(permission.label)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Tok.text)
                    Text(permission.rationale)
                        .font(Typography.secondary)
                        .foregroundStyle(Tok.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.md)
                control(status)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .contain)
        }

        @ViewBuilder
        private func control(_ status: PermissionStatus) -> some View {
            switch status {
            case .granted:
                Icon(.checkmark, size: 12, weight: .medium, tint: Tok.accentText)
                    .accessibilityLabel("Granted")
            case .denied:
                AppButton("Open Settings", kind: .quiet, action: open)
            case .notDetermined:
                AppButton("Grant", kind: accent ? .primary : .quiet, action: request)
            }
        }

        private var glyph: Glyph {
            switch permission {
            case .microphone: .mic
            case .accessibility: .accessibility
            case .inputMonitoring: .keyboard
            case .systemAudio: .speaker
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
            HStack(spacing: Space.sm) {
                Icon(.keyboard, size: 14, tint: model.globeConflict ? Tok.text : Tok.text2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Globe key")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Tok.text)
                    Text(reason)
                        .font(Typography.secondary)
                        .foregroundStyle(Tok.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.md)
                if model.globeConflict {
                    AppButton("Open Keyboard settings", kind: .quiet, action: open)
                } else if model.globeChecked {
                    Icon(.checkmark, size: 12, weight: .medium, tint: Tok.accentText)
                        .accessibilityLabel("Set to Do Nothing")
                }
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .contain)
        }

        private var reason: String {
            guard model.globeChecked else {
                return "Checking the current shortcut."
            }
            if model.globeConflict {
                return "macOS uses it for “\(model.globeAction.label)”."
            }
            return "Set to Do Nothing."
        }

        private func open() {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    }
}
