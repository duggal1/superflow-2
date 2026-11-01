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
    /// One start at a time. A double-tap can arrive while the speculative start
    /// is still inside its model or microphone wait; both callers share it
    /// instead of racing into "session already active".
    private var startTask: Task<Bool, Never>?

    public convenience init(environment: AppEnvironment?, mainWindow: MainWindowController,
                            sessionEvents: AsyncStream<SessionEvent>? = nil,
                            meetingEvents: AsyncStream<MeetingEvent>? = nil) {
        self.init(session: environment?.sessionEngine,
                  meeting: environment?.meetingEngine,
                  hotkeys: environment?.hotkeySource,
                  mainWindow: mainWindow,
                  sessionEvents: sessionEvents,
                  meetingEvents: meetingEvents)
    }

    init(session: SessionEngine?, meeting: MeetingEngine?,
         hotkeys: (any HotkeySource)?, mainWindow: MainWindowController,
         sessionEvents: AsyncStream<SessionEvent>? = nil,
         meetingEvents: AsyncStream<MeetingEvent>? = nil) {
        self.session = session
        self.meeting = meeting
        self.hotkeys = hotkeys
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

    @discardableResult
    public func startDictation(mode: SessionMode = .dictation) async -> Bool {
        guard session != nil else { return false }
        if let startTask {
            let result = await startTask.value
            if result, mode == .handsFree { await session?.setMode(.handsFree) }
            return result
        }
        let task = Task { @MainActor [weak self] in
            await self?.performStartDictation(mode: mode) ?? false
        }
        startTask = task
        let result = await task.value
        startTask = nil
        return result
    }

    private func performStartDictation(mode: SessionMode) async -> Bool {
        guard let session else { return false }
        // The launch prewarm is silent, but an explicit warm-up (onboarding or a
        // settings change) can still hold `.warming`. Wait for that same load
        // instead of refusing the key; a refused fn press is indistinguishable
        // from a dead shortcut.
        var state = await session.currentState
        if state == .warming {
            let deadline = ContinuousClock.now + .seconds(120)
            while state == .warming, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
                state = await session.currentState
            }
            if state == .warming {
                error = "Superflow is still getting ready. Hold fn again in a moment."
                return false
            }
        }
        let activeMeeting = await meeting?.currentState.isActive ?? false
        guard !activeMeeting else {
            error = "Stop the meeting before starting dictation."
            return false
        }
        do {
            _ = try await session.start(mode: mode)
            sessionState = await session.currentState
            await hotkeys?.setActiveTap(true)
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func beginHandsFreeDictation() async -> Bool {
        guard let session else { return false }
        var state = await session.currentState
        // An explicit warm-up owns `.warming` without a session yet. Wait for it
        // to finish, then start. A cold speculative start also passes through
        // `.warming`; the same wait lands on its recording state.
        if state == .warming {
            let deadline = ContinuousClock.now + .seconds(120)
            while state == .warming, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(25))
                state = await session.currentState
            }
        }
        if !state.isActive {
            // A double-tap lands after the speculative start, but if that start
            // failed there is no session to latch. Start one rather than promise
            // a microphone that is not open. This shares any in-flight start.
            guard await startDictation(mode: .handsFree) else { return false }
        } else if case .recording = state {
            await session.setMode(.handsFree)
        } else {
            // `.warming` from the speculative start, or `.finalizing` from an
            // edge case: wait for the recording state before promising hands-free.
            let deadline = ContinuousClock.now + .seconds(120)
            while ContinuousClock.now < deadline {
                state = await session.currentState
                if case .recording = state { break }
                if !state.isActive { break }
                try? await Task.sleep(for: .milliseconds(25))
            }
            guard case .recording = state else { return false }
            await session.setMode(.handsFree)
        }
        sessionState = await session.currentState
        await hotkeys?.setActiveTap(true)
        return true
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
            if await session.currentSession != nil { await session.cancel() }
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
            if let session, await session.currentSession != nil { await session.cancel() }
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
