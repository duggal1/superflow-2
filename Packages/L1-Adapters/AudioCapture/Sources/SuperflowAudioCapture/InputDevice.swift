import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import SuperflowKernel

enum InputDevice {
    static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                            initial: T) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                mElement: kAudioObjectPropertyElementMain)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value : nil
    }

    static func devices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address,
                                            0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return kAudioHardwareBadObjectError }
            return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, base)
        }
        return status == noErr ? ids : []
    }

    static func format(_ device: AudioDeviceID) -> AudioStreamBasicDescription? {
        property(device, kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeInput,
                 initial: AudioStreamBasicDescription())
    }

    /// The stable CoreAudio device UID. This is the only device identity that
    /// is ever persisted; `AudioDeviceID` changes between sessions.
    static func uid(of device: AudioDeviceID) -> String? {
        let initial: CFString = "" as CFString
        guard let value: CFString = property(device, kAudioDevicePropertyDeviceUID, initial: initial)
        else { return nil }
        return value as String
    }

    static func descriptors() -> [InputDeviceDescriptor] {
        let systemDefault = property(AudioObjectID(kAudioObjectSystemObject),
                                     kAudioHardwarePropertyDefaultInputDevice,
                                     initial: AudioDeviceID(kAudioObjectUnknown)) ?? kAudioObjectUnknown
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let names = Dictionary(uniqueKeysWithValues:
            discovery.devices.map { ($0.uniqueID, $0.localizedName) })
        return devices().compactMap { id in
            guard let uid = uid(of: id) else { return nil }
            let format = format(id)
            return InputDeviceDescriptor(
                id: id,
                uid: uid,
                name: names[uid] ?? uid,
                isAlive: property(id, kAudioDevicePropertyDeviceIsAlive, initial: UInt32(0)) == 1,
                isHidden: property(id, kAudioDevicePropertyIsHidden, initial: UInt32(0)) == 1,
                isSystemDefault: id == systemDefault,
                // An output-only device has no input-scope stream format.
                hasInputFormat: format != nil,
                inputChannels: format?.mChannelsPerFrame ?? 0,
                sampleRate: format?.mSampleRate ?? 0,
                transportType: property(id, kAudioDevicePropertyTransportType, initial: UInt32(0)) ?? 0
            )
        }
    }

    /// Resolves a saved UID to a connected, eligible device. An absent choice
    /// follows the live system default; a missing choice falls back to it.
    static func resolve(selection: MicrophoneSelection? = nil) throws -> AudioDeviceID {
        let inputs = descriptors()
        let route = RouteResolver.resolve(selection: selection, inputs: inputs)
        guard let id = inputs.first(where: { $0.uid == route.uid })?.id else {
            throw SuperflowError.audioFailure("No microphone input device is available. Connect a microphone and try again.")
        }
        return id
    }
}
