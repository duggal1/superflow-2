import SuperflowDesignSystem
import SwiftUI

/// Downloads show progress as a row fill, never as a bar.
public struct ProgressRow<Leading: View, Trailing: View>: View {
    private let title: String
    private let detail: String
    private let progress: Double?
    private let leading: Leading
    private let trailing: Trailing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(title: String, detail: String, progress: Double?,
                @ViewBuilder leading: () -> Leading,
                @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.progress = progress
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Space.sm) {
            leading
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Tok.text)
                Text(detail)
                    .font(Typography.secondary)
                    .monospacedDigit()
                    .foregroundStyle(Tok.text2)
            }
            Spacer(minLength: Space.md)
            trailing
        }
        .padding(.horizontal, Space.md)
        .frame(height: 64)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(Tok.accentSoft)
                    .frame(width: proxy.size.width * (progress ?? 0))
                    .animation(reduceMotion ? nil : Motion.settle, value: progress)
            }
        }
        .background(Tok.surface)
        .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
        .contrastStroke(radius: Radius.card)
        .accessibilityElement(children: .combine)
        .accessibilityValue(progress.map { "\(Int($0 * 100)) percent" } ?? "")
    }
}
