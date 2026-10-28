import AppKit
import Observation

/// Whether the owner is navigating with the keyboard or the pointer. The focus
/// ring is drawn for keyboard navigation only, so this is the switch that decides
/// it: opening a window or clicking never counts as navigating.
///
/// The ring itself lives in `FocusStep.swift`, next to the file that owns strokes.
@MainActor
@Observable
public final class InputModality {
    public static let shared = InputModality()

    public private(set) var isKeyboard = false

    @ObservationIgnored private var monitor: Any?

    public init() {}

    public func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Tab (48), space (49) and the arrows (123...126) mean "navigating".
            // Typing does not, so a keystroke in a field never lights a ring.
            let navigating = event.type == .keyDown && [48, 49, 123, 124, 125, 126].contains(Int(event.keyCode))
            if navigating || event.type != .keyDown {
                MainActor.assumeIsolated { self?.isKeyboard = navigating }
            }
            return event
        }
    }
}
