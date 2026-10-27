import AppKit
import SuperflowKernel
import SwiftUI

@MainActor
public final class ThemeStore {
    public var mode: ThemeMode {
        didSet {
            apply()
            onChange?(mode)
        }
    }

    public var onChange: ((ThemeMode) -> Void)?

    public init(mode: ThemeMode = .system) {
        self.mode = mode
    }

    public var preferredColorScheme: ColorScheme? {
        switch mode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    public func apply() {
        switch mode {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
