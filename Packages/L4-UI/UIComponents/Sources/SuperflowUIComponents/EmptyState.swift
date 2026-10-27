import SuperflowDesignSystem
import SwiftUI

/// One component, two densities. No icon, no repeated toolbar button: the full
/// stop is the icon, and the sentence names the next action.
public struct EmptyState: View {
    public enum Density: Sendable {
        case page, pane
    }

    private let title: String
    private let message: String
    private let density: Density

    public init(_ title: String, message: String, density: Density = .page) {
        self.title = title
        self.message = message
        self.density = density
    }

    public var body: some View {
        VStack(spacing: density == .page ? Space.md : Space.sm) {
            PixelStop(cells: 11, cell: density == .page ? 4 : 3)
            Text(title)
                .font(density == .page
                      ? Typography.displayFont(size: TypeScale.displaySSize)
                      : .system(size: 15, weight: .medium))
                .tracking(density == .page ? TypeScale.displaySTracking : 0)
                .foregroundStyle(Tok.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Tok.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.pagePadding)
        .accessibilityElement(children: .combine)
    }
}
