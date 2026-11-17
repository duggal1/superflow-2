import SwiftUI

private struct IslandReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// The reduce-motion flag the Island views read. It honours the system
    /// setting and can be forced on for headless snapshot tests, which cannot
    /// write the system's read-only accessibility key directly.
    var islandReduceMotion: Bool {
        get { self[IslandReduceMotionKey.self] || accessibilityReduceMotion }
        set { self[IslandReduceMotionKey.self] = newValue }
    }
}

public extension View {
    /// Forces the Island's Reduce Motion rendering path. Pass `false` to follow
    /// the system setting; used by headless tests and previews only.
    func islandReduceMotion(_ enabled: Bool) -> some View {
        environment(\.islandReduceMotion, enabled)
    }
}
