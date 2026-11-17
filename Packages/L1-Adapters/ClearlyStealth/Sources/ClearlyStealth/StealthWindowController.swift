import AppKit
import ClearlyStealthCore

public extension StealthSharingMode {
    /// The single public AppKit mechanism this whole feature relies on.
    var nsSharingType: NSWindow.SharingType {
        switch self {
        case .none: return .none
        case .readOnly: return .readOnly
        case .readWrite: return .readWrite
        }
    }
}

/// Retroactive conformance so the pure `WindowGuardCore` can operate on real
/// AppKit windows. The only mapping between our enum and `NSWindow.sharingType`.
extension NSWindow: WindowSharingControllable {
    public var sharingMode: StealthSharingMode {
        get {
            switch sharingType {
            case .none: return .none
            case .readOnly: return .readOnly
            case .readWrite: return .readWrite
            @unknown default: return .readOnly  // unknown == treat as capturable
            }
        }
        set { sharingType = newValue.nsSharingType }
    }
}

/// Applies the Island's window policy. `sharingType = .none` is set BEFORE the
/// first `orderFront` so the panel is never capturable, even for one frame.
/// This controller never orders a window front — the owner does that.
@MainActor
public enum StealthWindowController {
    public static func configureIslandPanel(_ panel: NSPanel) {
        panel.title = ""
        panel.isExcludedFromWindowsMenu = true
        // The only public mechanism. Set before first orderFront.
        panel.sharingType = .none
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    public static func apply(_ mode: StealthSharingMode, to window: NSWindow) {
        window.sharingType = mode.nsSharingType
    }
}
