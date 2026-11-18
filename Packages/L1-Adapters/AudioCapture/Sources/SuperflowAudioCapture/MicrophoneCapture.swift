import AVFoundation
import CoreAudio
import Dispatch
import Foundation
import SuperflowKernel
import SuperflowPorts

/// Explicit Core Audio input capture. Conversion and stream delivery run on this
/// actor; the IOProc only copies into a preallocated SPSC ring.
///
/// Launch calls `prepare()` to build the delivery streams without opening the
/// microphone. The first key-down calls `start()`, which opens the selected
/// device; `stop()` closes it again so the mic is never left live while idle.
public actor MicrophoneCapture: AudioSource {
    public nonisolated let kind: AudioSourceKind = .mic

    private let gate = GenerationGate()
    private let selectionStore: (any MicrophoneSelectionStore)?
    private var selection: MicrophoneSelection?
    private var lifecycle = CaptureLifecycle()
    private var watchdog: CaptureWatchdog?
    private var healthContinuations: [AsyncStream<CaptureHealth>.Continuation] = []
    private var lastPublishedHealth = CaptureHealth()
    private var lastDropped = 0
    private var generation: UInt64 = 0
    /// A saved device that will not open falls back to the system default for
    /// this capture without changing the persisted choice.
    private var usedFallback = false

    private var stream: HALInputStream?
    private var audioStream: AsyncStream<AudioChunk>?
    private var eventStream: AsyncStream<AudioEvent>?
    private var samples: AsyncStream<AudioChunk>.Continuation?
    private var events: AsyncStream<AudioEvent>.Continuation?
    private var pump: Task<Void, Never>?
    private var cursor: Int64 = 0
    private var lastRouteCheck: UInt64 = 0
    private var retryAfter: UInt64 = 0

    /// The route currently in use, for display. Includes a note when a saved
    /// device was missing and the system default stood in.
    public private(set) var selectedRoute: SelectedRoute?

    public var droppedSamples: Int { stream?.ring.droppedSamples ?? lastDropped }

    public init(selectionStore: (any MicrophoneSelectionStore)? = nil) {
        self.selectionStore = selectionStore
        self.selection = selectionStore?.load()
    }

    // MARK: - Observability

    public var isPrepared: Bool { lifecycle.isPrepared }
    public var isLive: Bool { lifecycle.isLive }
    public var health: CaptureHealth { watchdog?.health ?? CaptureHealth() }
    /// The current route generation. Callbacks carrying any older value are stale.
    public var activeGeneration: UInt64 { generation }

    /// A stream of independent watchdog state changes. Each transition (stall,
    /// all-zero, overflow, route rebuild) is delivered on its own.
    public func healthUpdates() -> AsyncStream<CaptureHealth> {
        let (updates, sink) = AsyncStream<CaptureHealth>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        sink.yield(health)
        healthContinuations.append(sink)
        return updates
    }

    // MARK: - Launch preparation and cold start

    /// Builds streams and watchdog state at launch. The microphone stays closed;
    /// the device is opened only by `start()` on the first key-down.
    public func prepare() {
        guard !lifecycle.isPrepared else { return }
        ensureStreams()
        let now = DispatchTime.now().uptimeNanoseconds
        watchdog = CaptureWatchdog(now: now)
        publishHealth()
        lifecycle.prepare()
    }

    public func start() async throws -> AudioStreams {
        guard !lifecycle.isLive else { throw SuperflowError.invalidState("microphone already running") }
        prepare()
        guard let audioStream, let eventStream else {
            throw SuperflowError.invalidState("microphone streams unavailable")
        }

        lifecycle.start()
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard lifecycle.isLive else { throw CancellationError() }
        guard granted else {
            lifecycle.stop()
            finishStreams()
            throw SuperflowError.permissionDenied(Permission.microphone.label)
        }

        usedFallback = false
        do {
            for attempt in 0..<3 {
                guard lifecycle.isLive else { throw CancellationError() }
                do {
                    let next = gate.advance()
                    let device = try InputDevice.resolve(selection: usedFallback ? nil : selection)
                    let capture = try HALInputStream(device: device, generation: next, gate: gate)
                    generation = next
                    try capture.start()
                    stream = capture
                    break
                } catch {
                    if !usedFallback, selection != nil {
                        usedFallback = true
                        continue
                    }
                    if attempt == 2 { throw error }
                    try await Task.sleep(for: .milliseconds(150))
                }
            }
        } catch {
            lifecycle.stop()
            finishStreams()
            throw error
        }

        cursor = 0
        lastDropped = 0
        let now = DispatchTime.now().uptimeNanoseconds
        watchdog = CaptureWatchdog(now: now)
        lastRouteCheck = now
        retryAfter = now
        selectedRoute = RouteResolver.resolve(
            selection: usedFallback ? nil : selection,
            inputs: InputDevice.descriptors()
        )
        publishHealth()
        pump = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                guard !Task.isCancelled else { return }
                await self?.tick()
            }
        }
        return AudioStreams(samples: audioStream, events: eventStream)
    }

    public func stop() async {
        guard lifecycle.isLive else { return }
        lifecycle.stop()
        pump?.cancel()
        pump = nil
        stream?.stop()
        deliver()
        // Advance only after the final drain so a late callback from this
        // generation can no longer feed a future stream.
        gate.advance()
        stream = nil
        finishStreams()
    }

    // MARK: - Explicit selection

    /// Selects a connected microphone by its persistent UID. A UID that is not
    /// connected, or that resolves to a virtual/output device, changes nothing.
    public func select(uid: String, name: String? = nil) throws {
        let inputs = InputDevice.descriptors()
        switch RouteResolver.saveDecision(uid: uid, name: name, inputs: inputs) {
        case .keepCurrent:
            throw SuperflowError.invalidState("Microphone is not connected or is not a microphone input: \(uid)")
        case .clear:
            try apply(nil, inputs: inputs)
        case .save(let next):
            try apply(next, inputs: inputs)
        }
    }

    /// Returns to the live macOS system default (clears the saved UID).
    public func useSystemDefault() throws {
        try apply(nil, inputs: InputDevice.descriptors())
    }

    private func apply(_ next: MicrophoneSelection?, inputs: [InputDeviceDescriptor]) throws {
        selection = next
        usedFallback = false
        try selectionStore?.save(next)
        selectedRoute = RouteResolver.resolve(selection: next, inputs: inputs)
        if lifecycle.isLive {
            // Force the next tick to re-resolve; the rebuild watchdog is owned
            // by the actual switch, not by the selection change.
            lastRouteCheck = 0
        }
    }

    // MARK: - Internals

    private func ensureStreams() {
        guard samples == nil else { return }
        let (audio, sampleSink) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingNewest(600)
        )
        let (notifications, eventSink) = AsyncStream<AudioEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
        audioStream = audio
        eventStream = notifications
        samples = sampleSink
        events = eventSink
    }

    private func finishStreams() {
        samples?.finish()
        samples = nil
        events?.yield(.stopped)
        events?.finish()
        events = nil
        audioStream = nil
        eventStream = nil
        for continuation in healthContinuations { continuation.finish() }
        healthContinuations.removeAll()
    }

    @discardableResult
    private func publishHealth() -> CaptureHealth {
        guard let watchdog else { return lastPublishedHealth }
        let current = watchdog.health
        guard current != lastPublishedHealth else { return current }
        lastPublishedHealth = current
        for continuation in healthContinuations { continuation.yield(current) }
        return current
    }

    private func deliver() {
        guard let stream else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        do {
            let audio = try stream.drain()
            let dropped = stream.ring.droppedSamples
            let newDrops = max(0, dropped - lastDropped)
            lastDropped = dropped
            if !audio.isEmpty {
                watchdog?.observe(samples: audio, dropped: newDrops, now: now)
                let result = samples?.yield(
                    AudioChunk(samples: audio, startSample: cursor, source: .mic)
                )
                if case .dropped = result {
                    events?.yield(.failed("Microphone delivery overflowed; some audio was lost."))
                }
                cursor += Int64(audio.count)
            } else if newDrops > 0 {
                watchdog?.observe(samples: [], dropped: newDrops, now: now)
            }
            if newDrops > 0 {
                events?.yield(.failed("Microphone capture overflowed; some audio was lost."))
            }
            publishHealth()
        } catch {
            events?.yield(.failed(error.localizedDescription))
        }
    }

    private func tick() {
        guard lifecycle.isLive else { return }
        let previouslyPublished = lastPublishedHealth
        deliver()
        let now = DispatchTime.now().uptimeNanoseconds
        watchdog?.check(now: now)
        let health = publishHealth()
        if health.alwaysZero, !previouslyPublished.alwaysZero {
            events?.yield(.failed("The microphone is sending silence. Check its mute switch and macOS input level."))
        }

        guard now - lastRouteCheck >= 250_000_000, now >= retryAfter else { return }
        lastRouteCheck = now
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            events?.yield(.permissionRevoked)
            stream?.stop()
            stream = nil
            gate.advance()
            return
        }
        do {
            let device = try InputDevice.resolve(selection: usedFallback ? nil : selection)
            let changed = stream?.device != device
                || InputDevice.format(device)?.mSampleRate != stream?.sampleRate
            let stalled = watchdog?.health.stalled == true
            guard changed || stalled else { return }

            watchdog?.beginRebuild(now: now)
            publishHealth()
            stream?.stop()
            deliver()
            // One advance invalidates every callback from the old route.
            let next = gate.advance()
            stream = nil
            let replacement = try HALInputStream(device: device, generation: next, gate: gate)
            try replacement.start()
            stream = replacement
            generation = next
            selectedRoute = RouteResolver.resolve(
                selection: usedFallback ? nil : selection,
                inputs: InputDevice.descriptors()
            )
            let finished = DispatchTime.now().uptimeNanoseconds
            watchdog?.endRebuild(now: finished)
            lastRouteCheck = finished
            publishHealth()
            events?.yield(.routeChanged)
        } catch {
            stream?.stop()
            stream = nil
            gate.advance()
            watchdog?.endRebuild(now: DispatchTime.now().uptimeNanoseconds)
            retryAfter = now + 1_000_000_000
            publishHealth()
            events?.yield(.failed(error.localizedDescription))
        }
    }
}
