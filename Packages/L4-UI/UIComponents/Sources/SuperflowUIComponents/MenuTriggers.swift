import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

public struct MenuTrigger<Label: View>: View {
    private let items: () -> [MenuItem]
    private let isOpen: Binding<Bool>?
    private let label: (Bool) -> Label
    @Environment(MenuHost.self) private var host
    @State private var owner = UUID()
    @State private var frame = CGRect.zero

    public init(items: @escaping () -> [MenuItem], isOpen: Binding<Bool>? = nil,
                @ViewBuilder label: @escaping (Bool) -> Label) {
        self.items = items
        self.isOpen = isOpen
        self.label = label
    }

    public var body: some View {
        let open = host.openID == owner
        Button {
            if open { host.dismiss() }
            else { host.present(owner: owner, items: items(), anchor: frame) }
        } label: { label(open) }
        .buttonStyle(.plain).focusEffectDisabled().clickable().focusStep()
        .reportFrame($frame)
        .onChange(of: frame) { _, next in host.reanchor(owner: owner, frame: next) }
        .onChange(of: open) { _, next in isOpen?.wrappedValue = next }
        .onDisappear {
            if host.openID == owner { host.dismiss() }
            isOpen?.wrappedValue = false
        }
    }
}

struct RowIconFace: View {
    let glyph: Icon
    var open = false
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        IconView(glyph, size: 12, tint: hover || open ? Tok.text : Tok.text2)
            .frame(width: 28, height: 28)
            .background(open ? Tok.controlPressed : hover ? Tok.controlHover : .clear,
                        in: .rect(cornerRadius: Radius.field))
            .contentShape(.rect(cornerRadius: Radius.field))
            .onHover { hover = $0 }
            .animation(reduce ? nil : (hover ? Motion.hoverIn : Motion.hoverOut), value: hover)
    }
}

public struct RowIconButton: View {
    private let glyph: Icon
    private let label: String
    private let action: () -> Void
    public init(glyph: Icon, label: String, action: @escaping () -> Void) {
        self.glyph = glyph; self.label = label; self.action = action
    }
    public var body: some View {
        Button(action: action) { RowIconFace(glyph: glyph) }
            .buttonStyle(.plain).focusEffectDisabled().clickable().focusStep()
            .accessibilityLabel(label)
    }
}

public struct RowCopyButton: View {
    private let action: () -> Void
    @State private var done = false
    @State private var copyCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduce
    public init(action: @escaping () -> Void) { self.action = action }
    public var body: some View {
        RowIconButton(glyph: done ? .checkmark : .copy, label: done ? "Copied" : "Copy transcript") {
            action(); done = true; copyCount += 1
        }
        .animation(reduce ? nil : .snappy(duration: 0.20), value: done)
        .task(id: copyCount) {
            guard copyCount > 0 else { return }
            do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
            done = false
        }
    }
}

public struct ActionMenu: View {
    private let items: [MenuItem]
    private let isOpen: Binding<Bool>?
    public init(items: [MenuItem], isOpen: Binding<Bool>? = nil) {
        self.items = items; self.isOpen = isOpen
    }
    public var body: some View {
        MenuTrigger(items: { items }, isOpen: isOpen) { open in
            RowIconFace(glyph: .more, open: open)
        }
        .accessibilityLabel("More")
    }
}

public struct NativeActionMenu: View {
    private let items: [MenuItem]

    public init(items: [MenuItem]) { self.items = items }

    private var groups: [[MenuItem]] {
        items.reduce(into: [[MenuItem]]()) { groups, item in
            if groups.isEmpty || item.gapBefore { groups.append([]) }
            groups[groups.count - 1].append(item)
        }
    }

    public var body: some View {
        Menu {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group) { item in
                        Button(role: item.role == .destructive ? .destructive : nil, action: item.run) {
                            if let icon = item.glyph {
                                Label(item.title, systemImage: icon.symbolName)
                            } else {
                                Text(item.title)
                            }
                        }
                        .disabled(!item.enabled)
                    }
                }
            }
        } label: {
            IconView(.more, size: 14).frame(width: 32, height: 32)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Meeting actions")
    }
}

public struct Dropdown<Value: Hashable>: View {
    public struct Option {
        public let value: Value
        public let title: String
        public let leading: (() -> AnyView)?
        public init(value: Value, title: String, leading: (() -> AnyView)? = nil) {
            self.value = value; self.title = title; self.leading = leading
        }
    }
    @Binding private var selection: Value
    private let options: [Option]
    private let label: String
    public init(selection: Binding<Value>, options: [Option], label: String = "Choose") {
        _selection = selection; self.options = options; self.label = label
    }
    public var body: some View {
        let current = options.first { $0.value == selection }
        MenuTrigger(items: {
            options.map { option in
                MenuItem(option.title, leading: option.leading?(), checked: option.value == selection) {
                    selection = option.value
                }
            }
        }) { open in
            DropdownFace(title: current?.title ?? "", leading: current?.leading?(), open: open)
        }
        .accessibilityLabel(label)
        .accessibilityValue(current?.title ?? "")
    }
}

private struct DropdownFace: View {
    let title: String
    let leading: AnyView?
    let open: Bool
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        HStack(spacing: 8) {
            if let leading { leading.frame(width: 20, height: 20) }
            Text(title).appType(.body).foregroundStyle(Tok.text).lineLimit(1).fixedSize()
            IconView(.chevronUpDown, size: 9, tint: Tok.text2)
        }
        .padding(.horizontal, 12).frame(height: 28)
        .background(open ? Tok.controlPressed : hover ? Tok.controlHover : Tok.control, in: .capsule)
        .contentShape(.capsule)
        .onHover { hover = $0 }
        .animation(reduce ? nil : (hover ? Motion.hoverIn : Motion.hoverOut), value: hover)
    }
}
