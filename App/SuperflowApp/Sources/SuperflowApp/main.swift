import AppKit
import SwiftUI
import SuperflowAppCore
import SuperflowDesignSystem
import SuperflowIcons

/// Orders the main window front and activates the app on launch. Swapping the activation policy
/// away from `.accessory` was necessary but not sufficient: SwiftUI presented the window behind
/// other apps, so it looked like nothing had launched at all.
final class SuperflowAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Fail loudly at launch instead of rendering nothing when a symbol name or the
        // bundled display face is missing.
        validateGlyphs()
        validateDisplayFont()
        #endif
        activate()
        // The scene materialises slightly after didFinishLaunching on a cold start, so order the
        // window front a few times instead of racing it once.
        for delay in [0.1, 0.4, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.activate()
            }
        }
    }

    /// `NSApp.activate(ignoringOtherApps:)` is deprecated and is frequently ignored for an app
    /// launched in the background; `NSRunningApplication` still brings it and its windows forward.
    private func activate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows,
                                                       .activateIgnoringOtherApps])
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        // Restored window state can come back minimised or hidden, which reports as "no window"
        // and looks like the app never launched. Force it back onto the current Space.
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}

@main
struct SuperflowApplication: App {
    @NSApplicationDelegateAdaptor(SuperflowAppDelegate.self) private var appDelegate
    @StateObject private var coordinator: AppCoordinator

    init() {
        // Do NOT force `.accessory` here. A menu-bar-only activation policy makes SwiftUI skip
        // presenting the main `Window` scene, which left the app with no visible UI and made
        // first-run onboarding (and its permission prompts) impossible to reach. The app starts
        // as a regular app so the window appears; MainWindowController.didClose() downgrades to
        // `.accessory` once the user closes it, and show() upgrades again.
        _coordinator = StateObject(wrappedValue: AppCoordinator())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(coordinator: coordinator)
        } label: {
            BrandMarkView(size: 12, tint: .primary)
                .fixedSize()
                .accessibilityLabel("Superflow")
        }
        .menuBarExtraStyle(.menu)

        // The main window is presented on launch. Suppressing it left the app with no visible
        // UI at all until the menu-bar icon was clicked, so first-run onboarding (and the
        // permission prompts inside it) was unreachable and macOS never registered Superflow
        // in Privacy & Security. Closing the window still drops back to menu-bar only.
        Window("Superflow", id: "main") {
            MainWindowRootView(coordinator: coordinator)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: Layout.windowDefaultWidth, height: Layout.windowDefaultHeight)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
    }

    @CommandsBuilder
    var commands: some Commands {
        // The shell draws its own sidebar, so the system SidebarCommands have
        // nothing to toggle. This is the one owner of the shortcut.
        CommandGroup(replacing: .sidebar) {
            Button("Toggle Sidebar") {
                coordinator.mainWindowController.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) {
                    coordinator.mainWindowController.show(section)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        CommandGroup(after: .windowList) {
            Button("Search Commands…") {
                coordinator.showCommandPalette()
            }
            .keyboardShortcut("k", modifiers: .command)
        }
    }
}
