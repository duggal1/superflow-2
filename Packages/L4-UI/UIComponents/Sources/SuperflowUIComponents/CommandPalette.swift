import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

/// One row in the ⌘K command palette. The action is main-actor isolated
/// because every command ultimately mutates UI or engine state.
public struct CommandItem: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let icon: Glyph
    public let shortcut: String?
    public let action: @MainActor () -> Void

    public init(id: String, title: String, subtitle: String? = nil,
                icon: Glyph = .shortcuts, shortcut: String? = nil,
                action: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.shortcut = shortcut
        self.action = action
    }
}

/// Pure filtering and selection logic for the palette. Kept out of the view so
/// arrow-key behavior and query matching are testable without a window.
@MainActor
public final class CommandPaletteModel: ObservableObject {
    public let items: [CommandItem]
    @Published public var query = "" {
        didSet {
            if query != oldValue { selectionIndex = 0 }
        }
    }
    @Published public private(set) var selectionIndex = 0

    public init(items: [CommandItem] = []) {
        self.items = items
    }

    public var filteredItems: [CommandItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return items }
        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(needle)
                || (item.subtitle?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    public var selectedItem: CommandItem? {
        let results = filteredItems
        guard !results.isEmpty else { return nil }
        return results[min(max(0, selectionIndex), results.count - 1)]
    }

    public var isEmpty: Bool { filteredItems.isEmpty }

    public func moveSelection(by delta: Int) {
        let count = filteredItems.count
        guard count > 0 else {
            selectionIndex = 0
            return
        }
        selectionIndex = ((selectionIndex + delta) % count + count) % count
    }

    public func setSelection(_ index: Int) {
        let count = filteredItems.count
        guard count > 0 else {
            selectionIndex = 0
            return
        }
        selectionIndex = min(max(0, index), count - 1)
    }

    /// Runs the highlighted command. Returns false when there is nothing to run.
    @discardableResult
    public func activateSelection() -> Bool {
        guard let item = selectedItem else { return false }
        item.action()
        return true
    }

    public func reset() {
        query = ""
        selectionIndex = 0
    }
}

public struct CommandPalette: View {
    @ObservedObject private var model: CommandPaletteModel
    @Binding private var isPresented: Bool
    private let placeholder: String
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: CommandPaletteModel, isPresented: Binding<Bool>,
                placeholder: String = "Search commands") {
        self.model = model
        _isPresented = isPresented
        self.placeholder = placeholder
    }

    public var body: some View {
        if isPresented {
            ZStack(alignment: .top) {
                Tok.scrim
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .accessibilityHidden(true)

                FloatingPanel {
                    VStack(spacing: Space.xxs) {
                        search
                        results
                        footer
                    }
                    .frame(width: 560)
                }
                .padding(.top, 96)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Command palette")
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    model.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    model.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.return) {
                    runSelected()
                    return .handled
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.99)))
            .onAppear { searchFocused = true }
        }
    }

    private var search: some View {
        HStack(spacing: Space.xs) {
            Icon(.search, size: 14)
            TextField(placeholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(Typography.large)
                .foregroundStyle(Tok.text)
                .focused($searchFocused)
                .accessibilityLabel(placeholder)
        }
        .padding(.horizontal, Space.sm)
        .frame(height: 40)
        .background(Tok.well, in: .rect(cornerRadius: Radius.field, style: .continuous))
    }

    @ViewBuilder
    private var results: some View {
        if model.isEmpty {
            Text("No matching commands.")
                .font(Typography.body)
                .foregroundStyle(Tok.text2)
                .padding(Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(model.filteredItems.enumerated()), id: \.element.id) { index, item in
                        row(item, selected: index == model.selectionIndex, index: index)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }

    private func row(_ item: CommandItem, selected: Bool, index: Int) -> some View {
        Button {
            model.setSelection(index)
            runSelected()
        } label: {
            HStack(spacing: Space.sm) {
                Icon(item.icon, size: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(Typography.body)
                        .foregroundStyle(Tok.text)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(Typography.secondary)
                            .foregroundStyle(Tok.text2)
                    }
                }
                Spacer(minLength: Space.md)
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(Typography.secondary)
                        .foregroundStyle(Tok.text2)
                }
            }
            .padding(.horizontal, Space.sm)
            .frame(height: 40)
            .background(selected ? Tok.controlHover : .clear,
                        in: .rect(cornerRadius: Radius.field, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .clickable()
        .onHover { inside in
            if inside { model.setSelection(index) }
        }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var footer: some View {
        HStack(spacing: Space.sm) {
            Text("↑↓ to move, ↩ to run, esc to close")
                .font(Typography.secondary)
                .foregroundStyle(Tok.text2)
            Spacer(minLength: Space.sm)
        }
        .padding(.horizontal, Space.sm)
        .padding(.top, 2)
    }

    private func runSelected() {
        guard model.activateSelection() else { return }
        close()
    }

    private func close() {
        isPresented = false
        model.reset()
    }
}
