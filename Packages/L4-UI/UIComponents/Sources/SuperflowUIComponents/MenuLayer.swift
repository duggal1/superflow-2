import Observation
import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

@MainActor
public struct MenuItem: Identifiable {
    public enum Role { case normal, destructive }
    public let id = UUID()
    public var title: String
    public var glyph: Glyph?
    public var leading: AnyView?
    public var role: Role
    public var enabled: Bool
    public var checked: Bool
    public var gapBefore: Bool
    public var run: () -> Void

    public init(_ title: String, glyph: Glyph? = nil, leading: AnyView? = nil,
                role: Role = .normal, enabled: Bool = true, checked: Bool = false,
                gapBefore: Bool = false, run: @escaping () -> Void) {
        self.title = title
        self.glyph = glyph
        self.leading = leading
        self.role = role
        self.enabled = enabled
        self.checked = checked
        self.gapBefore = gapBefore
        self.run = run
    }
}

@MainActor @Observable
public final class MenuHost {
    public struct Presented {
        public let token = UUID()
        public var owner: UUID
        public var items: [MenuItem]
        public var anchor: CGRect
    }

    public private(set) var presented: Presented?
    public private(set) var cursor: Int?
    public var openID: UUID? { presented?.owner }
    public init() {}

    public func present(owner: UUID, items: [MenuItem], anchor: CGRect) {
        guard !items.isEmpty else { return }
        cursor = items.firstIndex { $0.checked && $0.enabled }
        presented = Presented(owner: owner, items: items, anchor: anchor)
    }

    public func reanchor(owner: UUID, frame: CGRect) {
        guard presented?.owner == owner else { return }
        presented?.anchor = frame
    }

    public func dismiss() {
        withAnimation(.easeOut(duration: 0.12)) { presented = nil; cursor = nil }
    }

    public func hover(_ index: Int?) {
        guard let index, let p = presented, p.items.indices.contains(index), p.items[index].enabled else {
            cursor = nil
            return
        }
        cursor = index
    }

    public func move(_ delta: Int) {
        guard let p = presented, !p.items.isEmpty else { return }
        var index = cursor ?? (delta > 0 ? -1 : p.items.count)
        for _ in p.items.indices {
            index = (index + delta + p.items.count) % p.items.count
            if p.items[index].enabled { cursor = index; return }
        }
    }

    public func commit(_ index: Int? = nil) {
        guard let p = presented, let index = index ?? cursor,
              p.items.indices.contains(index), p.items[index].enabled else { return }
        let action = p.items[index].run
        dismiss()
        action()
    }
}

public struct MenuLayer: View {
    @Environment(MenuHost.self) private var host
    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .named(WindowSpace.name)).origin
            ZStack(alignment: .topLeading) {
                if let p = host.presented {
                    Color.clear.contentShape(.rect).onTapGesture { host.dismiss() }
                    MenuPanel(presented: p, bounds: geometry.size, origin: origin)
                        .id(p.token)
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .allowsHitTesting(host.presented != nil)
    }
}
