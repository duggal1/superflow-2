import AppKit
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI

// MARK: - Sidebar

/// Full height, flush left, 220 wide, native blur. The first row starts at y = 52
/// so it never meets the traffic lights. One fixed icon column, one colour for
/// icon and text, one neutral capsule that slides between rows.
struct MainSidebar: View {
    @Binding var selection: AppSection
    let status: EngineStatus
    let onStatus: () -> Void
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            WindowDragArea()
                .frame(height: Layout.bar)

            VStack(spacing: 2) {
                ForEach(AppSection.allCases) { section in
                    SidebarRow(section: section,
                               isSelected: selection == section,
                               pill: pill) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, Space.sm)

            Spacer(minLength: 0)

            SidebarStatus(status: status, action: onStatus)
                .padding(.horizontal, Space.sm)
                .padding(.bottom, Space.md)
        }
        .frame(width: Layout.sidebar)
        .frame(maxHeight: .infinity)
        .background { SidebarBackdrop() }
        .animation(reduceMotion ? nil : Motion.slide, value: selection)
    }
}

private struct SidebarRow: View {
    let section: AppSection
    let isSelected: Bool
    let pill: Namespace.ID
    let action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconView(section.icon, size: 15, tint: Tok.text,
                         selected: isSelected)
                    .frame(width: 20, height: 20)
                Text(section.title)
                    .appType(.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Tok.text)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Tok.washStrong)
                        .matchedGeometryEffect(id: "pill", in: pill)
                } else if hover {
                    Capsule().fill(Tok.wash)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : (hover ? Motion.hoverIn : Motion.hoverOut), value: hover)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isSelected)
        .focusStep(Capsule())
        .clickable()
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("sidebar.\(section.rawValue)")
    }
}

/// One implementation with onboarding: the sidebar footer is a `StatusNote`.
/// The only chrome the footer gets is a wash on hover — no plate, no stroke, no
/// fill at rest, so the mark sits directly on the sidebar blur.
private struct SidebarStatus: View {
    let status: EngineStatus
    let action: () -> Void

    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            StatusNote(text: status.label, level: status.level, working: status.isWorking, compact: true)
                .frame(maxWidth: 184)
                .background(hover ? Tok.wash : .clear,
                            in: .rect(cornerRadius: Radius.nested, style: .continuous))
                .contentShape(.rect(cornerRadius: Radius.nested, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : (hover ? Motion.hoverIn : Motion.hoverOut),
                   value: hover)
        .focusStep(.rect(cornerRadius: Radius.nested, style: .continuous))
        .clickable()
        .help(status.label)
        .accessibilityLabel("Engine status: \(status.label)")
    }
}

/// `NSVisualEffectView` adapts to dark and light by itself. It needs the window to
/// be non-opaque to see the desktop, which `WindowChrome(.main)` guarantees.
private struct SidebarBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - Status vocabulary

enum EngineFix {
    case settings, microphone, keyboardAccess
}

enum EngineStatus {
    case ready, listening, noMicrophone, noKeyboardAccess

    var label: String {
        switch self {
        case .ready: "Ready"
        case .listening: "Listening"
        case .noMicrophone: "No microphone access"
        case .noKeyboardAccess: "Input Monitoring off"
        }
    }

    var tone: DotTone {
        switch self {
        case .ready: .green
        case .listening: .orange
        case .noMicrophone, .noKeyboardAccess: .rose
        }
    }

    var level: DotLevel {
        switch self {
        case .ready: .success
        case .listening: .warning
        case .noMicrophone, .noKeyboardAccess: .error
        }
    }

    var fix: EngineFix {
        switch self {
        case .noMicrophone: .microphone
        case .noKeyboardAccess: .keyboardAccess
        case .ready, .listening: .settings
        }
    }

    var isWorking: Bool {
        switch self {
        case .listening: true
        case .ready, .noMicrophone, .noKeyboardAccess: false
        }
    }
}
