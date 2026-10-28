import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

/// Scope, then search with the menu slot and Add, in the page body. Title to
/// toggle and search row to list are 32; the toggle and the search row are 16
/// apart, so they read as one group.
public struct ListControls<Scope: Hashable>: View {
    @Binding private var scope: Scope
    private let scopes: [Segmented<Scope>.Item]
    @Binding private var query: String
    private let prompt: String
    @Binding private var searchFocus: Bool
    private let addTitle: String
    private let menu: [ActionMenu.Action]
    private let onAdd: () -> Void

    public init(scope: Binding<Scope>, scopes: [Segmented<Scope>.Item],
                query: Binding<String>, prompt: String,
                searchFocus: Binding<Bool>, addTitle: String,
                menu: [ActionMenu.Action], onAdd: @escaping () -> Void) {
        _scope = scope
        self.scopes = scopes
        _query = query
        self.prompt = prompt
        _searchFocus = searchFocus
        self.addTitle = addTitle
        self.menu = menu
        self.onAdd = onAdd
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if scopes.count > 1 {
                Segmented(selection: $scope, items: scopes)
            }
            HStack(spacing: 12) {
                SearchField(text: $query, prompt: prompt, isFocused: $searchFocus)
                Spacer(minLength: 16)
                ActionMenu(actions: menu)
                AppButton(addTitle, glyph: .add, kind: .primary, height: ControlHeight.regular, action: onAdd)
            }
        }
    }
}

public enum EntryScope: Hashable, Sendable {
    case personal, shared

    public static var items: [Segmented<EntryScope>.Item] {
        [
            .init("Personal", value: .personal),
            .init("Shared", value: .shared),
        ]
    }
}

/// A command shortcut that is invisible but real. Features never declare a
/// raw Button, so keyboard shortcuts come from here.
public struct HiddenShortcut: View {
    private let title: String
    private let key: KeyEquivalent
    private let modifiers: EventModifiers
    private let action: () -> Void

    public init(_ title: String, key: KeyEquivalent, modifiers: EventModifiers = .command,
                action: @escaping () -> Void) {
        self.title = title
        self.key = key
        self.modifiers = modifiers
        self.action = action
    }

    public var body: some View {
        Button(title, action: action)
            .keyboardShortcut(key, modifiers: modifiers)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
