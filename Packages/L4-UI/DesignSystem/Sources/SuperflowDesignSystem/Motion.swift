import SwiftUI

public enum Motion {
    /// Entry is faster than the return.
    public static let hoverIn: Animation = .easeOut(duration: 0.10)
    public static let hoverOut: Animation = .easeOut(duration: 0.22)
    public static let settle: Animation = .timingCurve(0.23, 1, 0.32, 1, duration: 0.28)
    public static let enter: Animation = .timingCurve(0.22, 1, 0.36, 1, duration: 0.78)
    public static let stagger: Double = 0.07
    public static let smallSpring: Animation = .snappy
    public static let largeSpring: Animation = .smooth

    // Pass 2 structure.
    /// Sidebar pill and tab thumb.
    public static let slide: Animation = .smooth(duration: 0.30)
    /// Route and tab content.
    public static let fade: Animation = .easeOut(duration: 0.18)
    public static let menuIn: Animation = .smooth(duration: 0.20)
    public static let menuOut: Animation = .easeOut(duration: 0.12)

    // Pass 4: the Island. Content enters after the shape has started to open.
    public static let islandIn = Animation.smooth(duration: 0.30).delay(0.10)
    public static let islandOut = Animation.easeOut(duration: 0.10)

    public static func entrance(index: Int) -> Animation {
        enter.delay(Double(index) * stagger)
    }

    public static func settle(delay: Double = 0) -> Animation {
        settle.delay(delay)
    }

    public static func staggerDelay(index: Int) -> Double {
        Double(index) * stagger
    }
}

/// Entrance stagger for onboarding and the Dashboard's first appearance only.
public struct Reveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    let index: Int
    @State private var shown = false

    public init(index: Int) {
        self.index = index
    }

    public func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 8)
            .blur(radius: shown || reduce ? 0 : 4)
            .onAppear {
                guard !reduce else { return }
                withAnimation(Motion.enter.delay(Double(index) * Motion.stagger)) { shown = true }
            }
    }
}

public extension View {
    func reveal(_ index: Int) -> some View { modifier(Reveal(index: index)) }
}
