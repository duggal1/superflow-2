import AppKit
import Foundation
import Observation
import SwiftUI

public enum IslandPlacement: Sendable { case home, active }

@MainActor @Observable
public final class IslandModel {
    public private(set) var phase: IslandPhase = .idle
    public private(set) var copied = false
    public var geometry: NotchGeometry
    public private(set) var target: IslandTarget?
    public let waveform = WaveformModel()

    @ObservationIgnored public var feed: any IslandFeed
    @ObservationIgnored public var placement: (IslandPlacement) -> Void = { _ in }
    @ObservationIgnored public var phaseDidChange: (IslandPhase) -> Void = { _ in }
    @ObservationIgnored private var latestLevel: Float = 0
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var consumers: [Task<Void, Never>] = []

    public init(feed: any IslandFeed, geometry: NotchGeometry) {
        self.feed = feed
        self.geometry = geometry
        consumers = [
            Task { [weak self] in
                guard let events = self?.feed.events else { return }
                for await event in events { self?.send(event) }
            },
            Task { [weak self] in
                guard let levels = self?.feed.levels else { return }
                for await level in levels { self?.latestLevel = level }
            },
        ]
    }

    deinit {
        consumers.forEach { $0.cancel() }
        timer?.cancel()
        hoverTask?.cancel()
        ticker?.cancel()
    }

    // MARK: input

    public func send(_ event: IslandEvent) {
        if case .holdBegan(let target) = event {
            self.target = target
            hoverTask?.cancel()
        }
        go(IslandReducer.reduce(phase, event))
    }

    /// Pointer over the notch. 120 ms dwell, so sweeping across to a menu item does not flicker.
    public func hoverChanged(_ inside: Bool) {
        switch phase {
        case .idle where inside && geometry.hasNotch:
            hoverTask?.cancel()
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self?.go(.hover)
            }
        case .idle:
            hoverTask?.cancel()
        case .hover where !inside:
            go(.idle)
        case .failed:
            if inside {
                timer?.cancel()
            } else {
                scheduleFailureTimeout(ms: 4_000)
            }
        case .hover, .listening, .processing, .landed, .recent:
            break
        }
    }

    /// Click on the notch. The owner can always reach the last dictation.
    public func openRecent() {
        guard phase.isRest, geometry.hasNotch else { return }
        hoverTask?.cancel()
        go(.recent(feed.lastTranscript()))
    }

    public func copy(_ transcript: IslandTranscript) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript.text, forType: .string)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        copied = true
        after(900) { [weak self] in self?.send(.dismissed) }
    }

    // MARK: transitions

    private func go(_ next: IslandPhase) {
        guard next != phase else { return }
        let prev = phase
        timer?.cancel()
        copied = false

        // Move the window only while it is invisible, never animated.
        if prev == .idle, next != .hover {
            placement(next.kind == .card ? .home : .active)
        } else if prev == .hover, next.kind == .wings {
            placement(.active)
        }

        // The meter only runs while the microphone is live. A new session starts
        // from silence, so the first frame can never show the last session's peak.
        if next == .listening {
            waveform.reset()
            waveform.setLive(true)
            startTicker()
        } else {
            waveform.setLive(false)
            stopTicker()
        }

        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(IslandLayout.animation(from: prev, to: next, reduceMotion: reduce)) {
            phase = next
        }

        sideEffects(next)
        phaseDidChange(next)

        switch next {
        case .landed:
            after(900) { [weak self] in self?.go(.idle) }
        case .failed:
            if feed.storesTranscripts { scheduleFailureTimeout(ms: 12_000) }
        case .idle where !prev.isRest:
            after(420) { [weak self] in self?.placement(.home) }
        case .idle, .hover, .listening, .processing, .recent:
            break
        }
    }

    private func scheduleFailureTimeout(ms: Int) {
        guard feed.storesTranscripts else { return }
        after(ms) { [weak self] in self?.go(.idle) }
    }

    private func after(_ ms: Int, _ body: @escaping @MainActor () -> Void) {
        timer?.cancel()
        timer = Task {
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled else { return }
            body()
        }
    }

    // MARK: waveform clock

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.waveform.tick(level: self.latestLevel)
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: side effects

    private func sideEffects(_ phase: IslandPhase) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch phase {
        case .listening: performer.perform(.alignment, performanceTime: .default)
        case .landed: performer.perform(.levelChange, performanceTime: .default)
        case .failed: performer.perform(.generic, performanceTime: .default)
        case .idle, .hover, .processing, .recent: break
        }

        let line: String? = switch phase {
        case .listening: "Listening"
        case .landed: "Pasted"
        case .failed: "Couldn't paste. Transcript ready to copy."
        case .idle, .hover, .processing, .recent: nil
        }
        if let line {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: line,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ]
            )
        }
    }
}
