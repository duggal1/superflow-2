/// The public sharing policy for a window, expressed without AppKit so it can
/// be reasoned about and tested headlessly. Mirrors `NSWindow.SharingType`:
/// `.none` is the "not capturable" request; `.readOnly` / `.readWrite` are
/// capturable. The AppKit adapter is the only place this maps to a real flag.
public enum StealthSharingMode: String, Sendable, Equatable, Codable {
    case none
    case readOnly
    case readWrite

    public var isCapturable: Bool { self != .none }
}
