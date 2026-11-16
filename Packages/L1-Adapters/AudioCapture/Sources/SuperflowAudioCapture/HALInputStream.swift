import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import SuperflowKernel

// The actor owns lifecycle; Core Audio only accesses the SPSC ring during IO.
final class HALInputStream: @unchecked Sendable {
    let device: AudioDeviceID
    let ring: AudioRingBuffer
    let sampleRate: Double
    private var proc: AudioDeviceIOProcID?
    private let converter: AVAudioConverter?
    private let input: AVAudioPCMBuffer
    private let output: AVAudioPCMBuffer
    private let decoder: PCMDecoder
    private let ioScratch: UnsafeMutablePointer<Float>
    private static let ioScratchCapacity = 8192
    private var scratch = [Float](repeating: 0, count: 4096)

    init(device: AudioDeviceID) throws {
        self.device = device
        guard let format = InputDevice.format(device),
              format.mSampleRate >= 8_000,
              let decoder = PCMDecoder(format),
              let native = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.mSampleRate,
                                         channels: 1, interleaved: false),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                         channels: 1, interleaved: false),
              let input = AVAudioPCMBuffer(pcmFormat: native, frameCapacity: 4096),
              let output = AVAudioPCMBuffer(pcmFormat: target,
                  frameCapacity: AVAudioFrameCount(ceil(4096 * 16_000 / format.mSampleRate)) + 512)
        else { throw SuperflowError.audioFailure("The microphone does not provide a supported Float32 input format.") }
        sampleRate = format.mSampleRate
        self.decoder = decoder
        ioScratch = UnsafeMutablePointer<Float>.allocate(capacity: Self.ioScratchCapacity)
        ioScratch.initialize(repeating: 0, count: Self.ioScratchCapacity)
        ring = AudioRingBuffer(capacity: Int(sampleRate) * 4)
        self.input = input
        self.output = output
        if sampleRate == 16_000 { converter = nil }
        else {
            guard let converter = AVAudioConverter(from: native, to: target) else {
                throw SuperflowError.audioFailure("Could not create the microphone sample-rate converter.")
            }
            converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue
            converter.primeMethod = .none
            self.converter = converter
        }
    }

    func start() throws {
        guard proc == nil else { return }
        let ring = ring
        let decoder = decoder
        let ioScratch = ioScratch
        let bytesPerFrame = decoder.bytesPerFrame
        var newProc: AudioDeviceIOProcID?
        let result = AudioDeviceCreateIOProcIDWithBlock(&newProc, device, nil) { _, data, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: data))
            guard let buffer = buffers.first, let base = buffer.mData, bytesPerFrame > 0 else { return }
            let byteCount = Int(buffer.mDataByteSize)
            let frames = byteCount / bytesPerFrame
            guard frames > 0 else { return }
            // The first input channel is the microphone; averaging independent
            // interface inputs can cancel speech. Integer-device samples are
            // converted here into a preallocated buffer: no allocation, locks,
            // logging or concurrency on the audio callback thread.
            var written = 0
            while written < frames {
                let chunk = min(Self.ioScratchCapacity, frames - written)
                let source = UnsafeRawBufferPointer(start: base.advanced(by: written * bytesPerFrame),
                                                    count: chunk * bytesPerFrame)
                let destination = UnsafeMutableBufferPointer(start: ioScratch, count: chunk)
                decoder.convert(source, into: destination, frames: chunk)
                ring.write(UnsafeBufferPointer(start: ioScratch, count: chunk))
                written += chunk
            }
        }
        guard result == noErr, let newProc else {
            throw SuperflowError.audioFailure("Could not open the microphone (Core Audio \(result)).")
        }
        let started = AudioDeviceStart(device, newProc)
        guard started == noErr else {
            AudioDeviceDestroyIOProcID(device, newProc)
            throw SuperflowError.audioFailure("Could not start the microphone (Core Audio \(started)).")
        }
        proc = newProc
    }

    func stop() {
        guard let proc else { return }
        AudioDeviceStop(device, proc)
        AudioDeviceDestroyIOProcID(device, proc)
        self.proc = nil
    }

    func drain() throws -> [Float] {
        var samples: [Float] = []
        // Bound each drain even if a device continues producing during conversion.
        for _ in 0..<64 {
            let count = ring.read(into: &scratch, max: 4096)
            guard count > 0 else { break }
            guard let converter else { samples.append(contentsOf: scratch.prefix(count)); continue }
            guard let channel = input.floatChannelData?[0] else { break }
            scratch.withUnsafeBufferPointer { source in
                if let base = source.baseAddress { channel.update(from: base, count: count) }
            }
            input.frameLength = AVAudioFrameCount(count)
            var fed = false
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { [input] _, state in
                guard !fed else { state.pointee = .noDataNow; return nil }
                fed = true
                state.pointee = .haveData
                return input
            }
            if status == .error { throw SuperflowError.audioFailure(error?.localizedDescription ?? "Microphone conversion failed.") }
            if let channel = output.floatChannelData?[0] {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            }
        }
        return samples
    }

    deinit {
        stop()
        ioScratch.deinitialize(count: Self.ioScratchCapacity)
        ioScratch.deallocate()
    }
}
