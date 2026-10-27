import SwiftUI

public struct ShellAnchors: Sendable { public var clear: [Anchor<CGRect>] = []; public var bloom: Anchor<CGRect>? }

public struct ShellKey: PreferenceKey {
    public static let defaultValue = ShellAnchors()
    public static func reduce(value: inout ShellAnchors, nextValue: () -> ShellAnchors) {
        let n = nextValue()
        value.clear += n.clear
        if let b = n.bloom { value.bloom = b }
    }
}

public extension View {
    func clearsPixels() -> some View { anchorPreference(key: ShellKey.self, value: .bounds) { ShellAnchors(clear: [$0]) } }
    func bloomSource() -> some View { anchorPreference(key: ShellKey.self, value: .bounds) { ShellAnchors(bloom: $0) } }
}
