/// Identity of a capture-listed window, without ScreenCaptureKit types.
public struct WindowIdentity: Sendable, Equatable {
    public let pid: Int32
    public let bundleIdentifier: String?

    public init(pid: Int32, bundleIdentifier: String?) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
    }
}

/// Decides what the screen reader's `SCContentFilter(display:excludingWindows:)`
/// must drop so OCR can never read the Island back, independent of whatever
/// `sharingType` happens to do on this macOS build.
public enum ScreenCaptureExclusion {
    /// Exclude the Island and every other window owned by the same process.
    /// This matches the existing `ScreenReader` policy (all own windows are
    /// excluded) and is deliberately stronger than excluding only the Island.
    public static func shouldExclude(_ window: WindowIdentity, island: WindowIdentity) -> Bool {
        if window.pid == island.pid { return true }
        if let bundle = window.bundleIdentifier, let islandBundle = island.bundleIdentifier,
           bundle == islandBundle {
            return true
        }
        return false
    }
}
