import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

/// 640 x 520, content column 480, footer 64. The pixel field is the backdrop and
/// dissolves around every block marked `.clearsPixels()`.
struct OnboardingShell<Content: View>: View {
    let step: Int
    let count: Int
    let primaryTitle: String
    var primaryEnabled = true
    var skipTitle: String?
    var reveal: CGFloat = 1
    var collapse: CGFloat = 0
    var backAction: (() -> Void)?
    var skipAction: (() -> Void)?
    let primaryAction: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: 480, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, Space.xxxl + Space.xs)
                .padding(.horizontal, Space.lg)
                .clearsPixels()
            footer
        }
        .frame(width: Layout.onboardingWidth, height: Layout.onboardingHeight)
        .backgroundPreferenceValue(PixelClearKey.self) { anchors in
            GeometryReader { proxy in
                ZStack {
                    Tok.bg
                    PixelField(clear: anchors.map { proxy[$0] }, config: field)
                }
            }
        }
        .background(WindowChrome(kind: .onboarding))
    }

    /// The step index is the only progress value; the field is driven from it.
    private var field: PixelFieldConfig {
        var config = PixelFieldConfig()
        config.cell = 16
        config.cover = 0.42
        config.drift = step < count - 1 ? 120 : 0
        config.reveal = Double(reveal)
        config.collapse = Double(collapse)
        return config
    }

    private var footer: some View {
        ZStack {
            ProgressDots(step: step, count: count)
            HStack(spacing: Space.xs) {
                if let backAction {
                    AppButton("Back", kind: .quiet, action: backAction)
                }
                Spacer(minLength: Space.md)
                if let skipTitle, let skipAction {
                    AppButton(skipTitle, kind: .quiet, action: skipAction)
                }
                AppButton(primaryTitle, kind: .primary, height: ControlHeight.large,
                          enabled: primaryEnabled, action: primaryAction)
            }
        }
        .padding(.horizontal, Space.lg)
        .frame(height: 64)
        .clearsPixels()
    }
}
