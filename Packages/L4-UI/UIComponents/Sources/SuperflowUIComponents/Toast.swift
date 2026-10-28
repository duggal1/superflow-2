import Foundation
import SuperflowDesignSystem
import SwiftUI

public enum ToastStyle: String, Sendable, CaseIterable {
    case info, success, warning, error

    public var defaultDuration: Double {
        switch self {
        case .error: 6
        case .warning: 5
        case .info, .success: 4
        }
    }
}

public struct ToastMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public var style: ToastStyle
    public var actionTitle: String?
    public var duration: Double

    public init(id: UUID = UUID(), text: String, style: ToastStyle = .info,
                actionTitle: String? = nil, duration: Double? = nil) {
        self.id = id
        self.text = text
        self.style = style
        self.actionTitle = actionTitle
        self.duration = duration ?? (actionTitle == nil ? style.defaultDuration : 6)
    }
}

/// Bounded queue: one visible toast, everything else waits in order. Pure value
/// logic so the behavior is testable without a running app.
public struct ToastQueue: Sendable, Equatable {
    public private(set) var current: ToastMessage?
    public private(set) var pending: [ToastMessage]
    public let capacity: Int

    public init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
        pending = []
    }

    public mutating func enqueue(_ message: ToastMessage) {
        if current == nil {
            current = message
            return
        }
        pending.append(message)
        if pending.count > capacity { pending.removeFirst(pending.count - capacity) }
    }

    @discardableResult
    public mutating func dismiss() -> ToastMessage? {
        let finished = current
        current = pending.isEmpty ? nil : pending.removeFirst()
        return finished
    }

    @discardableResult
    public mutating func dismiss(id: UUID) -> ToastMessage? {
        if current?.id == id { return dismiss() }
        pending.removeAll { $0.id == id }
        return nil
    }

    public mutating func removeAll() {
        current = nil
        pending.removeAll()
    }
}

@MainActor
public final class ToastCenter: ObservableObject {
    @Published public private(set) var current: ToastMessage?
    private var queue = ToastQueue()
    private var dismissal: Task<Void, Never>?

    public init() {}

    public func show(_ text: String, style: ToastStyle = .info,
                     actionTitle: String? = nil,
                     action: (() -> Void)? = nil) {
        let message = ToastMessage(text: text, style: style, actionTitle: actionTitle)
        actions[message.id] = action
        queue.enqueue(message)
        publish()
    }

    public func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        if let finished = queue.dismiss() {
            actions[finished.id] = nil
        }
        publish()
    }

    private var actions: [UUID: () -> Void] = [:]

    /// Test seam: dismissed messages must not retain their action closure.
    var pendingActionCount: Int { actions.count }

    public func performAction() {
        guard let message = current, let action = actions[message.id] else {
            dismiss()
            return
        }
        action()
        actions[message.id] = nil
        dismiss()
    }

    private func publish() {
        current = queue.current
        dismissal?.cancel()
        dismissal = nil
        guard let message = current else { return }
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(message.duration))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}

public struct ToastView: View {
    public let message: ToastMessage
    public let onAction: () -> Void
    public let onDismiss: () -> Void

    public init(_ message: ToastMessage, onAction: @escaping () -> Void,
                onDismiss: @escaping () -> Void) {
        self.message = message
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        GlassGroup(spacing: Space.xs) {
            GlassCapsule {
                HStack(spacing: Space.sm) {
                    Text(message.text)
                        .appType(.body)
                        .foregroundStyle(Tok.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let title = message.actionTitle {
                        Button(title, action: onAction)
                            .buttonStyle(.app(.quiet))
                    }
                    IconButton(.close, label: "Dismiss", size: 12, action: onDismiss)
                }
                .padding(.horizontal, Space.md)
                .frame(height: 40)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.text)
    }
}

public extension View {
    /// Float a feature's toasts above its content.
    func toast(_ center: ToastCenter) -> some View {
        overlay { ToastHost(center: center) }
    }
}

public struct ToastHost: View {
    @ObservedObject private var center: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(center: ToastCenter) {
        self.center = center
    }

    public var body: some View {
        VStack {
            Spacer()
            if let message = center.current {
                ToastView(message, onAction: { center.performAction() },
                          onDismiss: { center.dismiss() })
                    .padding(.bottom, Space.lg)
                    .transition(reduceMotion ? .opacity : .offset(y: 8).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : Motion.settle, value: center.current)
        .allowsHitTesting(center.current != nil)
    }
}
