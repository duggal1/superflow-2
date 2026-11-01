import Foundation
import OSLog
import SuperflowGestureKit
import SuperflowHotkeyEngine
import SuperflowKernel
import SuperflowPorts

/// The input half of the coordinator: install the event tap, run key events through the pure
/// gesture recogniser, and react to permission changes while the app runs. Kept in its own file
/// so `AppCoordinator.swift` stays inside the repository's 400-line source limit.
@MainActor
extension AppCoordinator {
    func tryStartHotkeys() async {
        guard let environment, hotkeyTask == nil, !isStartingHotkeys else { return }
        isStartingHotkeys = true
        defer { isStartingHotkeys = false }
        // `recoveryReady` is not needed to install the tap: `MenuBarController.startDictation`
        // already refuses a session until recovery finishes. Gating the tap on it left fn
        // dead through startup for no safety benefit.
        guard settings.onboardingComplete else { return }
        // Without the tap the fn key silently does nothing, so the status footer has
        // to say why instead of leaving the owner pressing a key that cannot arrive.
        var inputStatus = await environment.permissionGate.status(.inputMonitoring)
        if inputStatus != .granted, !didPromptInputMonitoring {
            didPromptInputMonitoring = true
            inputStatus = await environment.permissionGate.request(.inputMonitoring)
        }
        guard inputStatus == .granted else {
            menuBarController.publishError("Dictation is off. Input Monitoring is not granted.")
            return
        }
        // The chosen key is applied before `start()` builds the taps, so the very
        // first press is already the right one.
        await environment.hotkeySource.setDictationKey(settings.dictationKey)
        // Fn suppression is what keeps macOS from running its Globe action (Show Emoji & Symbols)
        // over dictation. Swallowing an event needs an active tap, so apply it before `start()`
        // creates the taps, otherwise the first tap is built listen-only.
        await environment.refreshFunctionKeySuppression(for: settings.dictationKey)
        do {
            try await environment.hotkeySource.start()
            // The tap is live, so any earlier permission message is stale.
            publishHotkeyStatus(environment: environment)
            let events = environment.hotkeySource.events
            hotkeyTask = Task { [weak self] in
                for await event in events {
                    guard let self else { return }
                    await self.handleKeyEvent(event)
                }
            }
            gestureTimerTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .milliseconds(10))
                    } catch {
                        return
                    }
                    guard let self else { return }
                    self.enqueueGestureActions(
                        self.gesture.tick(atNs: DispatchTime.now().uptimeNanoseconds)
                    )
                }
            }
            startDictationConflictMonitor()
        } catch {
            menuBarController.publishError("Keyboard shortcuts are unavailable. Check Input Monitoring in System Settings.")
        }
    }

    /// Presses can arrive through a listen-only tap while macOS still runs its
    /// Globe action. That is a real degradation, not a ready state.
    private func publishHotkeyStatus(environment: AppEnvironment) {
        if environment.hotkeySource.tapStatus.hasLostSuppression {
            menuBarController.publishError(
                "Keyboard shortcuts are on, but Accessibility is off, so macOS may still open the emoji picker when you press fn.")
        } else {
            menuBarController.publishError("")
        }
    }

    func observePermissionChanges(_ permissions: any PermissionGate) {        guard permissionTask == nil else { return }
        permissionTask = Task { [weak self] in
            let updates = await permissions.updates()
            for await (permission, status) in updates {
                guard let self else { return }
                self.onboardingModel?.updatePermissionStatus(permission, status: status)
                switch permission {
                case .inputMonitoring:
                    if status == .granted {
                        await self.tryStartHotkeys()
                    } else if let environment = self.environment, self.hotkeyTask != nil {
                        await environment.hotkeySource.stop()
                        self.hotkeyTask?.cancel()
                        self.hotkeyTask = nil
                        self.gestureTimerTask?.cancel()
                        self.gestureTimerTask = nil
                        self.conflictTask?.cancel()
                        self.conflictTask = nil
                        self.menuBarController.publishError(
                            "Keyboard shortcuts are unavailable. Check Input Monitoring in System Settings."
                        )
                    }
                case .accessibility:
                    // Gaining or losing Accessibility changes whether the lone Fn press can be
                    // swallowed at all, so re-apply it without needing a relaunch.
                    if self.hotkeyTask != nil {
                        await self.environment?.refreshFunctionKeySuppression(
                            for: self.settings.dictationKey)
                        if let environment = self.environment {
                            self.publishHotkeyStatus(environment: environment)
                        }
                    }
                    if status == .granted {
                        // A dictation may have finished while the grant was missing.
                        // Paste it now rather than asking for the words again.
                        await self.retryPendingPasteIfPossible()
                    }
                default:
                    break
                }
            }
        }
    }

    /// Fn is a global key, so a second dictation app that installs its own tap
    /// after ours wins the event order and Superflow never sees a press. While fn
    /// is the chosen key, ask known competitors to quit and say so once each.
    func startDictationConflictMonitor() {
        // Temporarily disabled so other dictation apps can remain open.
        /*
        guard settings.dictationKey == .fn, conflictTask == nil else { return }
        conflictTask = Task { @MainActor [weak self] in
            var announced = Set<String>()
            while !Task.isCancelled {
                guard let self, self.settings.dictationKey == .fn else { return }
                let closed = DictationConflictResolver.terminateKnownCompetitors()
                let newlyClosed = closed.filter { announced.insert($0.bundleID).inserted }
                if !newlyClosed.isEmpty {
                    let names = newlyClosed.map(\.name).joined(separator: ", ")
                    self.menuBarController.publishError(
                        "\(names) also listens for fn, so Superflow closed it to keep dictation working.")
                }
                do {
                    try await Task.sleep(for: .seconds(20))
                } catch {
                    return
                }
            }
        }
        */
    }

    func handleKeyEvent(_ event: KeyEvent) async {
        if event.kind == .escape {
            guard gesture.state != .idle || gestureIsFinishing
                || menuBarController.sessionState.isActive || menuBarController.meetingState.isActive else { return }
            guard !gestureCancelPending else { return }
            gestureCancelPending = true
            let kind: SessionKind = menuBarController.meetingState.isActive
                || gesture.state == .meetingArmed || gesture.state == .meetingLatched ? .meeting : .dictation
            gestureGeneration &+= 1
            gestureActionTask?.cancel()
            gesture = GestureRecognizer(config: settings.gesture)
            enqueueGestureActions([.cancel(kind, .escape)])
            return
        }
        guard !gestureIsFinishing else { return }
        let actions = gesture.handle(event)
        switch event.kind {
        case .fnDown, .fnUp, .rightCmdDown, .rightCmdUp:
            Logger(subsystem: "com.superflow.app", category: "KeyboardGesture")
                .notice("edge=\(String(describing: event.kind), privacy: .public) state=\(String(describing: self.gesture.state), privacy: .public) actions=\(String(describing: actions), privacy: .public)")
        default:
            break
        }
        enqueueGestureActions(actions)
    }

    private func enqueueGestureActions(_ actions: [GestureAction]) {
        guard !actions.isEmpty else { return }
        let previous = gestureActionTask
        let generation = gestureGeneration
        let terminal = actions.contains { action in
            switch action { case .submit, .cancel: true; default: false }
        }
        if terminal { gestureIsFinishing = true }
        gestureActionTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, generation == self.gestureGeneration else { return }
            defer {
                if terminal, generation == self.gestureGeneration {
                    self.gestureIsFinishing = false
                    self.gestureCancelPending = false
                }
            }
            await self.applyGestureActions(actions)
        }
    }

    func applyGestureActions(_ actions: [GestureAction]) async {
        for action in actions {
            switch action {
            case .startSpeculative(.dictation):
                islandBridge?.holdBegan()
                let started = await menuBarController.startDictation()
                // A refused start (model still loading, no recovery) emits no
                // session event. Say why in the notch: silently retracting looks
                // exactly like a dead fn key.
                if !started, !Task.isCancelled {
                    gesture = GestureRecognizer(config: settings.gesture)
                    islandBridge?.refused(menuBarController.error
                        ?? "The microphone did not open. Hold fn again.")
                }
            case .startSpeculative(.meeting):
                break
            case .holdBegan(let kind):
                if kind == .meeting {
                    await menuBarController.startMeeting()
                    if menuBarController.meetingState.isActive { islandBridge?.meetingBegan() }
                }
            case .beginHandsFree:
                guard gesture.state == .handsFree else { continue }
                // Only promise hands-free once the session is actually open.
                if await menuBarController.beginHandsFreeDictation() {
                    islandBridge?.handsFreeBegan()
                } else if !Task.isCancelled {
                    gesture = GestureRecognizer(config: settings.gesture)
                    islandBridge?.refused(menuBarController.error
                        ?? "The microphone did not open. Hold fn again.")
                }
            case .latchMeeting:
                await menuBarController.beginLatchedMeeting()
                if menuBarController.meetingState.isActive {
                    islandBridge?.meetingBegan()
                } else {
                    gesture = GestureRecognizer(config: settings.gesture)
                    islandBridge?.refused(menuBarController.error
                        ?? "The meeting could not start.")
                }
            case .submit(let kind):
                islandBridge?.holdEnded()
                await menuBarController.stop(kind)
                // Meeting events never reach the Island bridge, so close the
                // notch here once the latched meeting has actually stopped.
                if kind == .meeting { islandBridge?.cancelled() }
            case .cancel(let kind, let reason):
                switch (kind, reason) {
                case (.dictation, .escape):
                    islandBridge?.escaped()
                case (.meeting, .escape):
                    islandBridge?.meetingEscaped()
                default:
                    islandBridge?.cancelled()
                }
                await menuBarController.cancel(kind, cue: reason == .escape)
            }
        }
    }
}
