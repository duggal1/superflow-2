import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

struct OnboardingShell<Content: View>: View {
    let step: Int
    let count: Int
    let primaryTitle: String
    var primaryEnabled = true
    var reveal: CGFloat = 1
    var backAction: (() -> Void)?
    var skipTitle: String?
    var skipAction: (() -> Void)?
    let primaryAction: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func fieldConfig(_ reveal: CGFloat) -> PixelFieldConfig {
        var config = PixelFieldConfig()
        config.cell = 16
        config.cover = 0.42
        config.drift = step < count - 1 ? 120 : 0
        config.reveal = Double(reveal)
        return config
    }

    var body: some View {
        VStack(spacing: 0) {
            // The step scrolls; the footer is pinned. On a 520 pt window the taller
            // steps were pushing the primary button out of view.
            ScrollView {
                content
                    .frame(width: Layout.onboardingColumn, alignment: .topLeading)
                    .padding(.top, Space.xxl)
                    .padding(.bottom, Space.xl)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .frame(width: Layout.onboardingWidth, height: Layout.onboardingHeight)
        .background(Tok.bg)
        .backgroundPreferenceValue(ShellKey.self) { a in
            GeometryReader { geo in
                PixelField(clear: a.clear.map { geo[$0] }, config: fieldConfig(reveal))
            }
        }
        .containerBackground(Tok.bg, for: .window)
        .background(WindowChrome(kind: .onboarding))
        .fontSmoothing()
    }

    private var footer: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                if let backAction {
                    AppButton("Back", kind: .quiet) {
                        Sounds.play(.transcriptionCancel)
                        backAction()
                    }
                    .padding(.leading, -12)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            ProgressDots(step: step, count: count)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if let skipTitle, let skipAction {
                    AppButton(skipTitle, kind: .quiet) {
                        Sounds.play(.clickSoft)
                        skipAction()
                    }
                }
                AppButton(primaryTitle, kind: .primary) {
                    Sounds.play(.clickSoft)
                    primaryAction()
                }
                .disabled(!primaryEnabled)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: Layout.onboardingColumn, height: 64)
        .clearsPixels()
    }
}
