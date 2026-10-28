import AppKit
import Foundation
import SuperflowKernel
import SuperflowMeetingEngine
import SuperflowPorts
import SuperflowSessionEngine
import SuperflowUIComponents
import SwiftUI

@MainActor
public final class MenuBarController: ObservableObject {
    @Published public private(set) var sessionState: SessionState = .idle
    @Published public private(set) var meetingState: MeetingState = .idle
    @Published public private(set) var error: String?
    @Published public private(set) var recoveryReady = true
    /// True while the fn key is physically down. The dashboard keycap reads it.
    @Published public private(set) var isFnHeld = false

    private let session: SessionEngine?
    private let meeting: MeetingEngine?
    private let hotkeys: (any HotkeySource)?
    private let mainWindow: MainWindowController
    private let sessionEvents: AsyncStream<SessionEvent>?
    private let meetingEvents: AsyncStream<MeetingEvent>?
    private var observations: [Task<Void, Never>] = []

    public init(environment: AppEnvironment?, mainWindow: MainWindowController,
                sessionEvents: AsyncStream<SessionEvent>? = nil,
                meetingEvents: AsyncStream<MeetingEvent>? = nil) {
        session = environment?.sessionEngine
        meeting = environment?.meetingEngine
        hotkeys = environment?.hotkeySource
        self.mainWindow = mainWindow
        self.sessionEvents = sessionEvents
        self.meetingEvents = meetingEvents
    }

    public var dictationTitle: String {
        switch sessionState {
        case .warming: "Cancel Dictation"
        case .recording, .finalizing, .inserting: "Stop Dictation"
        case .idle, .complete, .cancelled, .failed: "Start Dictation"
        }
    }

    public var meetingTitle: String {
        meetingState.isActive ? "Stop Meeting" : "Start Meeting"
    }

    public var canStartDictation: Bool {
        recoveryReady && !sessionState.isActive && !meetingState.isActive && session != nil
    }

    public var canStartMeeting: Bool {
        recoveryReady && !meetingState.isActive && !sessionState.isActive && meeting != nil
    }

    public func setRecoveryReady(_ ready: Bool) {
        recoveryReady = ready
    }

    public func setFnHeld(_ held: Bool) {
        guard isFnHeld != held else { return }
        isFnHeld = held
    }

    public func observe() {
        guard observations.isEmpty else { return }
        if let events = sessionEvents ?? session?.events {
            observations.append(Task { [weak self] in
                for await event in events {
                    guard let self else { return }
                    if case .state(let state) = event { self.sessionState = state }
                }
            })
        }
        if let events = meetingEvents ?? meeting?.events {
            observations.append(Task { [weak self] in
                for await event in events {
                    guard let self else { return }
                    if case .state(let state) = event { self.meetingState = state }
                }
            })
        }
    }

    public func toggleDictation() async {
        guard let session else { return }
        if await session.currentState.isActive {
            await stopDictation()
        } else {
            await startDictation()
        }
    }

    public func toggleMeeting() async {
        if await meeting?.currentState.isActive ?? false {
            await stopMeeting()
        } else {
            await startMeeting()
        }
    }

    public func startDictation(mode: SessionMode = .dictation) async {
        guard let session else { return }
        // A silent return here is why fn looked dead for the first seconds after
        // launch. Say what is happening instead.
        guard recoveryReady else {
            error = "Superflow is still loading the speech model. Hold fn again in a moment."
            return
        }
        let activeMeeting = await meeting?.currentState.isActive ?? false
        guard !activeMeeting else {
            error = "Stop the meeting before starting dictation."
            return
        }
        do {
            _ = try await session.start(mode: mode)
            sessionState = await session.currentState
            await hotkeys?.setActiveTap(true)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func beginHandsFreeDictation() async {
        guard let session else { return }
        // A double-tap lands after the speculative start, but if that start
        // failed there is no session to latch. Start one rather than promise a
        // microphone that is not open.
        var state = await session.currentState
        if !state.isActive {
            await startDictation()
            state = await session.currentState
        }
        guard state.isActive else { return }
        await session.setMode(.handsFree)
        sessionState = await session.currentState
        await hotkeys?.setActiveTap(true)
    }

    /// A latched meeting: the right-⌘ hold threshold, or the second tap. The
    /// speculative start on the first key-down usually created it already, so
    /// this fills the gap instead of starting a second one.
    public func beginLatchedMeeting() async {
        guard let meeting else { return }
        let state = await meeting.currentState
        if state.isActive {
            meetingState = state
            await hotkeys?.setActiveTap(true)
        } else {
            await startMeeting()
        }
    }

    public func stopDictation() async {
        guard let session else { return }
        let state = await session.currentState
        if case .recording = state {
            _ = await session.stop()
        } else if state.isActive {
            await session.cancel()
        }
        sessionState = await session.currentState
        await hotkeys?.setActiveTap(false)
    }

    public func startMeeting() async {
        guard let meeting else { return }
        guard recoveryReady else {
            error = "Superflow is still loading the speech model. Start the meeting in a moment."
            return
        }
        let activeSession = await session?.currentState.isActive ?? false
        guard !activeSession else {
            error = "Stop dictation before starting a meeting."
            return
        }
        do {
            _ = try await meeting.start()
            meetingState = await meeting.currentState
            await hotkeys?.setActiveTap(true)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func stopMeeting() async {
        guard let meeting else { return }
        let state = await meeting.currentState
        if state == .recording {
            _ = await meeting.stop()
        } else if state.isActive {
            await meeting.cancel()
        }
        meetingState = await meeting.currentState
        await hotkeys?.setActiveTap(false)
    }

    /// Cancelling a dictation is silent unless the user did it deliberately, so
    /// only the Escape gesture asks for the cue.
    public func cancel(_ kind: SessionKind, cue: Bool = false) async {
        // Escape is one gesture whether it stops a dictation or a meeting, so it
        // makes the same sound in both cases.
        if cue { Sounds.play(.transcriptionCancel) }
        if kind == .dictation {
            await session?.cancel()
        } else {
            await meeting?.cancel()
        }
        if let session { sessionState = await session.currentState }
        if let meeting { meetingState = await meeting.currentState }
        await hotkeys?.setActiveTap(false)
    }

    public func stopActiveSession() async {
        let activeMeeting = await meeting?.currentState.isActive ?? false
        if activeMeeting {
            await stopMeeting()
        } else {
            await stopDictation()
        }
    }

    public func cancelActiveSession() async {
        let activeMeeting = await meeting?.currentState.isActive ?? false
        if activeMeeting {
            await cancel(.meeting)
        } else {
            await cancel(.dictation)
        }
    }

    public func stop(_ kind: SessionKind) async {
        if kind == .dictation {
            await stopDictation()
        } else {
            await stopMeeting()
        }
    }

    public func showMainWindow(_ section: AppSection? = nil) {
        mainWindow.show(section)
    }

    public func publishError(_ message: String) {
        error = message
    }

    public func quit() async {
        await cancel(.dictation)
        await cancel(.meeting)
        await hotkeys?.stop()
        NSApp.terminate(nil)
    }
}
