import Foundation

/// Pure role/subrole/settable classification. No AX calls, so it is directly
/// testable without a running app.
public enum AXRoleClassifier {
    public static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
    ]

    /// Controls that unambiguously never accept typed text. Containers are
    /// deliberately absent: Electron, web views, spreadsheet cells and some
    /// native apps report the focused element as the application, window, list,
    /// table, row or cell while a real field sits underneath. Those stay
    /// `.unknown` so the paste attempt decides instead of bailing out early.
    public static let nonEditableRoles: Set<String> = [
        "AXButton", "AXStaticText", "AXMenuItem", "AXMenu", "AXMenuBar", "AXToolbar",
        "AXRadioButton", "AXCheckBox", "AXPopUpButton", "AXSlider", "AXDockItem",
        "AXImage",
    ]

    public static func classify(role: String, subrole: String,
                                valueSettable: Bool, hasEditableAncestor: Bool) -> InsertionFocus {
        if role == "AXSecureTextField" || subrole == "AXSecureTextField" {
            return .secure
        }
        if editableRoles.contains(role) || subrole == "AXSearchField" {
            return .editable(role: role.isEmpty ? subrole : role)
        }
        // Check known non-editable roles before the generic "settable value"
        // signal: a slider, checkbox or pop-up button exposes a settable
        // AXValue but cannot accept text. An editable ancestor still wins for
        // nested elements inside a real editor.
        if nonEditableRoles.contains(role), !hasEditableAncestor {
            return .notEditable(reason: "role-\(role)")
        }
        if valueSettable {
            return .editable(role: role.isEmpty ? "settable-value" : role)
        }
        if hasEditableAncestor {
            return .editable(role: role.isEmpty ? "editable-ancestor" : role)
        }
        return .unknown(reason: "role-\(role.isEmpty ? "none" : role)")
    }
}
