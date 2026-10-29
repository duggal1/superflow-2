import AudioToolbox
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

    static func resolve() throws -> AudioDeviceID {
        let systemDefault = property(AudioObjectID(kAudioObjectSystemObject),
                                     kAudioHardwarePropertyDefaultInputDevice, initial: AudioDeviceID(0))
        let candidates = (systemDefault.map { [$0] } ?? []) + devices()
        for id in candidates where id != kAudioObjectUnknown {
            guard let format = format(id), format.mChannelsPerFrame > 0, format.mSampleRate > 0,
                  property(id, kAudioDevicePropertyDeviceIsAlive, initial: UInt32(0)) == 1,
                  property(id, kAudioDevicePropertyIsHidden, initial: UInt32(0)) != 1 else { continue }
            // Process-tap aggregates are output capture machinery, never microphones.
            var uid: CFString = "" as CFString
            if let value = property(id, kAudioDevicePropertyDeviceUID, initial: uid) { uid = value }
            guard !(uid as String).hasPrefix("CADefaultDeviceAggregate") else { continue }
            return id
        }
        throw SuperflowError.audioFailure("No microphone input device is available. Connect a microphone and try again.")
    }
}
