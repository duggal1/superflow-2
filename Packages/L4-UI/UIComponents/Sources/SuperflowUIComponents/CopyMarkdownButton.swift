import AppKit
import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

public struct CopyMarkdownButton: View {
    enum Phase { case idle, copied, failed }
    private let enabled: Bool
    private let action: @MainActor () async -> Bool

    public init(enabled: Bool, action: @escaping @MainActor () async -> Bool) {
        self.enabled = enabled
        self.action = action
    }
    @State private var phase: Phase = .idle
    @State private var reset: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var label: String {
        switch phase {
        case .idle: "Copy as Markdown"
        case .copied: "Copied"
        case .failed: "Couldn't copy"
        }
    }

    public var body: some View {
        Button(action: copy) {
            HStack(spacing: Space.xs) {
                IconView(phase == .copied ? .checkmark : .copy, size: 14, tint: Tok.onAccent)
                ZStack(alignment: .leading) {
                    Text("Copy as Markdown").hidden()
                    Text(label).id(label).transition(.opacity)
                }
            }
        }
        .buttonStyle(CopyMarkdownStyle())
        .disabled(!enabled)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: phase)
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .help("Copy transcript as Markdown (⇧⌘C)")
        .onDisappear { reset?.cancel() }
    }

    private func copy() {
        reset?.cancel()
        reset = Task {
            phase = await action() ? .copied : .failed
            AccessibilityNotification.Announcement(label).post()
            do { try await Task.sleep(for: .milliseconds(1600)) } catch { return }
            phase = .idle
        }
    }
}

private struct CopyMarkdownStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appType(.label)
            .foregroundStyle(Tok.onAccent)
            .padding(.horizontal, Space.sm)
            .frame(height: ControlHeight.regular)
            .background(configuration.isPressed ? Tok.accentPressed : hover ? Tok.accentBlue500 : Tok.accent,
                        in: .rect(cornerRadius: Radius.field))
            .opacity(enabled ? 1 : 0.4)
            .keyboardFocusRing(radius: Radius.field)
            .onHover { hover = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hover)
    }
}
