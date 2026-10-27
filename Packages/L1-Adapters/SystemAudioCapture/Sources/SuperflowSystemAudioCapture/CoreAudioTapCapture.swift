import CoreAudio
import Foundation
import SuperflowKernel
import SuperflowPorts

/// Core Audio process tap backend (macOS 14.2+).
///
/// A tap exposes the mixed output of every process except ours. The tap is
/// wrapped in a private aggregate device so a single IOProc delivers its audio
/// on a serial queue. The sample clock continues across route changes: the tap
/// is rebuilt in place and the sample cursor is preserved.
final class CoreAudioTapCapture: SystemAudioBackend, @unchecked Sendable {
    let kind: SystemAudioBackendKind = .processTap

    private let controlQueue = DispatchQueue(label: "com.superflow.system-audio.tap.control",
                                             qos: .userInitiated)
    private let ioQueue = DispatchQueue(label: "com.superflow.system-audio.tap.io",
                                        qos: .userInitiated)
    private let lock = NSLock()

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var listeners: [PropertyListener] = []
    private var sampleContinuation: AsyncStream<AudioChunk>.Continuation?
    private var eventContinuation: AsyncStream<AudioEvent>.Continuation?
    private var converter: AudioSampleConverter?
    private var format = AudioStreamBasicDescription()
    private var cursor: Int64 = 0
    private var running = false
    private var stopping = false
    private var restartPending = false

    private struct PropertyListener {
        let objectID: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    func start() async throws -> AudioStreams {
        try controlQueue.sync { try startLocked() }
    }

    func stop() async {
        controlQueue.sync {
            stopping = true
            teardownCapture()
            let continuations = takeContinuations()
            continuations.samples?.finish()
            continuations.events?.yield(.stopped)
            continuations.events?.finish()
            stopping = false
        }
    }

    // MARK: lifecycle (control queue only)

    private func startLocked() throws -> AudioStreams {
        if lock.withLock({ running }) {
            throw SuperflowError.invalidState("system audio tap already running")
        }
        guard #available(macOS 14.2, *) else { throw SystemAudioCaptureFailure.unsupportedSystem }

        let (samples, sampleContinuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingNewest(600))
        let (events, eventContinuation) = AsyncStream<AudioEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(16))
        lock.withLock {
            self.sampleContinuation = sampleContinuation
            self.eventContinuation = eventContinuation
            cursor = 0
            running = false
        }

        do {
            try buildCapture()
            installListeners()
            let started = AudioDeviceStart(aggregateID, ioProcID)
            guard started == noErr else { throw tapError(started, "starting the audio device") }
            lock.withLock { running = true }
            return AudioStreams(samples: samples, events: events)
        } catch {
            teardownCapture()
            sampleContinuation.finish()
            eventContinuation.finish()
            lock.withLock {
                self.sampleContinuation = nil
                self.eventContinuation = nil
            }
            throw Self.mapStartError(error)
        }
    }

    private func buildCapture() throws {
        guard #available(macOS 14.2, *) else { throw SystemAudioCaptureFailure.unsupportedSystem }

        let excluded = CoreAudioSupport.processObjectID(pid: getpid()).map { [$0] } ?? []
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.uuid = UUID()
        description.name = "Superflow System Audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        guard tapStatus == noErr else { throw tapError(tapStatus, "creating the process tap") }
        tapID = tap

        format = CoreAudioSupport.tapFormat(tap) ?? CoreAudioSupport.fallbackFormat
        let inputRate = format.mSampleRate > 0 ? format.mSampleRate : 48_000
        lock.withLock {
            self.format = format
            converter = AudioSampleConverter(inputRate: inputRate)
        }

        let outputUID = CoreAudioSupport.defaultOutputDeviceUID()
        var subDevices: [[String: Any]] = []
        var aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Superflow System Audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        if let outputUID {
            subDevices = [[kAudioSubDeviceUIDKey: outputUID]]
            aggregate[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
        }
        aggregate[kAudioAggregateDeviceSubDeviceListKey] = subDevices

        var device: AudioObjectID = 0
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard aggregateStatus == noErr else { throw tapError(aggregateStatus, "creating the aggregate device") }
        aggregateID = device

        var proc: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&proc, device, ioQueue) { [weak self] _, input, _, _, _ in
            self?.handleInput(input)
        }
        guard ioStatus == noErr, let proc else { throw tapError(ioStatus, "installing the audio callback") }
        ioProcID = proc
    }

    private func teardownCapture() {
        removeListeners()
        if aggregateID != 0 {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if #available(macOS 14.2, *), tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
        }
        lock.withLock {
            aggregateID = 0
            tapID = 0
            ioProcID = nil
            running = false
            converter = nil
        }
    }

    private func takeContinuations() -> (samples: AsyncStream<AudioChunk>.Continuation?,
                                         events: AsyncStream<AudioEvent>.Continuation?) {
        lock.withLock {
            let value = (sampleContinuation, eventContinuation)
            sampleContinuation = nil
            eventContinuation = nil
            return value
        }
    }

    // MARK: audio callback

    private func handleInput(_ input: UnsafePointer<AudioBufferList>) {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let chunk: AudioChunk? = lock.withLock {
            guard running, let continuation = sampleContinuation, var converter else { return nil }
            let samples = converter.convert(list, asbd: format)
            self.converter = converter
            guard !samples.isEmpty else { return nil }
            let value = AudioChunk(samples: samples, startSample: cursor, source: .system)
            cursor += Int64(samples.count)
            continuation.yield(value)
            return value
        }
        _ = chunk
    }

    // MARK: route changes and stream death

    private func installListeners() {
        var defaultOutput = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        addListener(objectID: AudioObjectID(kAudioObjectSystemObject), address: &defaultOutput) { [weak self] in
            self?.scheduleRestart(reason: .routeChanged)
        }

        var alive = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        addListener(objectID: aggregateID, address: &alive) { [weak self] in
            self?.scheduleRestart(reason: .deviceDied)
        }
    }

    private enum RestartReason { case routeChanged, deviceDied }

    private func addListener(objectID: AudioObjectID, address: inout AudioObjectPropertyAddress,
                             action: @escaping @Sendable () -> Void) {
        let block: AudioObjectPropertyListenerBlock = { _, _ in action() }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, controlQueue, block)
        guard status == noErr else { return }
        listeners.append(PropertyListener(objectID: objectID, address: address, block: block))
    }

    private func removeListeners() {
        for listener in listeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(listener.objectID, &address, controlQueue, listener.block)
        }
        listeners.removeAll()
    }

    private func scheduleRestart(reason: RestartReason) {
        if restartPending { return }
        restartPending = true
        controlQueue.async { [weak self] in
            self?.restart(reason: reason)
        }
    }

    private func restart(reason: RestartReason) {
        defer { restartPending = false }
        let isRunning = lock.withLock { running }
        guard isRunning, !stopping else { return }
        let events = lock.withLock { eventContinuation }
        if reason == .routeChanged { events?.yield(.routeChanged) }

        teardownCapture()
        do {
            try buildCapture()
            installListeners()
            let status = AudioDeviceStart(aggregateID, ioProcID)
            guard status == noErr else { throw tapError(status, "restarting the audio device") }
            lock.withLock { running = true }
        } catch {
            let message = "System audio tap could not recover: \(Self.describe(error))"
            let continuations = takeContinuations()
            continuations.samples?.finish()
            continuations.events?.yield(.failed(message))
            continuations.events?.finish()
        }
    }

    // MARK: errors

    private func tapError(_ status: OSStatus, _ operation: String) -> Error {
        if status == kAudioHardwareIllegalOperationError {
            return SystemAudioCaptureFailure.permissionDenied
        }
        return SystemAudioCaptureFailure.startFailed(
            "\(operation) failed (\(CoreAudioSupport.fourCC(status))).")
    }

    private static func mapStartError(_ error: Error) -> Error {
        if error is SystemAudioCaptureFailure { return error }
        return SystemAudioCaptureFailure.startFailed(error.localizedDescription)
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? SystemAudioCaptureFailure { return failure.localizedDescription }
        return error.localizedDescription
    }
}

enum CoreAudioSupport {
    static let fallbackFormat = AudioStreamBasicDescription(
        mSampleRate: 48_000,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
        mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)

    static func processObjectID(pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var input = pid
        var objectID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &input, &size, &objectID)
        return status == noErr && objectID != 0 ? objectID : nil
    }

    static func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                         &size, &device) == noErr, device != 0 else { return nil }
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var unmanaged: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let uidStatus = withUnsafeMutablePointer(to: &unmanaged) { pointer in
            AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize,
                                       UnsafeMutableRawPointer(pointer))
        }
        guard uidStatus == noErr, let unmanaged else { return nil }
        return unmanaged.takeRetainedValue() as String
    }

    static func tapFormat(_ tap: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format)
        return status == noErr && format.mSampleRate > 0 ? format : nil
    }

    static func fourCC(_ status: OSStatus) -> String {
        let value = UInt32(bitPattern: status)
        let bytes = [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                     UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) {
            return "'\(String(bytes: bytes, encoding: .ascii) ?? "?")' (\(status))"
        }
        return "\(status)"
    }
}
