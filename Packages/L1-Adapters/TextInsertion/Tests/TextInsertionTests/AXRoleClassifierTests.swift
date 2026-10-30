import XCTest
@testable import SuperflowTextInsertion

final class AXRoleClassifierTests: XCTestCase {
    func testSecureRoleOrSubrole() {
        XCTAssertEqual(AXRoleClassifier.classify(role: "AXTextField", subrole: "AXSecureTextField",
                                                 valueSettable: true, hasEditableAncestor: false), .secure)
        XCTAssertEqual(AXRoleClassifier.classify(role: "AXSecureTextField", subrole: "",
                                                 valueSettable: false, hasEditableAncestor: false), .secure)
    }

    func testEditableRoles() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
            XCTAssertEqual(AXRoleClassifier.classify(role: role, subrole: "", valueSettable: false,
                                                     hasEditableAncestor: false),
                           .editable(role: role), role)
        }
    }

    func testSettableValueAndEditableAncestorAreEditable() {
        XCTAssertEqual(AXRoleClassifier.classify(role: "AXGroup", subrole: "", valueSettable: true,
                                                 hasEditableAncestor: false),
                       .editable(role: "AXGroup"))
        XCTAssertEqual(AXRoleClassifier.classify(role: "AXGroup", subrole: "", valueSettable: false,
                                                 hasEditableAncestor: true),
                       .editable(role: "AXGroup"))
    }

    func testUnambiguousNonEditableControls() {
        for role in ["AXButton", "AXStaticText", "AXMenuItem", "AXImage", "AXToolbar"] {
            XCTAssertEqual(AXRoleClassifier.classify(role: role, subrole: "", valueSettable: false,
                                                     hasEditableAncestor: false),
                           .notEditable(reason: "role-\(role)"), role)
        }
    }

    /// Applications, lists, tables, rows and cells are containers. A real text
    /// field can sit underneath them, so bailing out before the paste attempt
    /// makes dictation silently do nothing in those hosts.
    func testContainersStayUnknownSoPasteIsAttempted() {
        for role in ["AXApplication", "AXList", "AXOutline", "AXTable", "AXRow",
                     "AXCell", "AXColumn"] {
            guard case .unknown = AXRoleClassifier.classify(role: role, subrole: "",
                                                            valueSettable: false,
                                                            hasEditableAncestor: false) else {
                return XCTFail("\(role) should stay unknown so a paste is still attempted")
            }
        }
    }

    /// A slider's AXValue is settable, but it is not a text control. Treating
    /// it as editable would send the AX-first path at a control that cannot
    /// accept text, then paste into whatever handles the chord.
    func testSettableValueDoesNotOverrideAKnownNonEditableRole() {
        for role in ["AXSlider", "AXCheckBox", "AXPopUpButton"] {
            XCTAssertEqual(AXRoleClassifier.classify(role: role, subrole: "", valueSettable: true,
                                                     hasEditableAncestor: false),
                           .notEditable(reason: "role-\(role)"), role)
        }
    }

    /// The editable-ancestor signal still wins for a nested element inside a
    /// real editor, even when its own role is normally non-editable.
    func testEditableAncestorKeepsANestedNonEditableRoleEditable() {
        XCTAssertEqual(AXRoleClassifier.classify(role: "AXStaticText", subrole: "",
                                                 valueSettable: false, hasEditableAncestor: true),
                       .editable(role: "AXStaticText"))
    }

    func testAmbiguousContainersStayUnknown() {
        for role in ["AXWindow", "AXGroup", "AXScrollArea", "AXWebArea", "AXUnknown"] {
            guard case .unknown = AXRoleClassifier.classify(role: role, subrole: "", valueSettable: false,
                                                            hasEditableAncestor: false) else {
                return XCTFail("\(role) should stay unknown so a paste is still attempted")
            }
        }
    }

    func testEmptyRoleIsUnknown() {
        guard case .unknown(let reason) = AXRoleClassifier.classify(role: "", subrole: "", valueSettable: false,
                                                                   hasEditableAncestor: false) else {
            return XCTFail("expected unknown")
        }
        XCTAssertEqual(reason, "role-none")
    }
}
