import Foundation

/// Marker written to `CGEventField.eventSourceUserData` on every event the
/// insertion backend posts. Kept in L0 so the hotkey adapter can recognise the
/// app's own synthetic Cmd+V without importing the insertion adapter.
public enum SyntheticInputMarker {
    /// ASCII "SFPASTE1".
    public static let value: Int64 = 0x5346_5041_5354_4531
}
