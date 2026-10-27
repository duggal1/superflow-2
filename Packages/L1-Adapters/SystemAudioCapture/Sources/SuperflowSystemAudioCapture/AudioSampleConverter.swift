import AVFoundation
import CoreMedia
import Foundation
import SuperflowKernel

/// Decodes the LPCM that system audio hands back and resamples it to the
/// 16 kHz mono clock every other Superflow component uses.
///
/// Two input paths share the same math: ScreenCaptureKit delivers a
/// `CMSampleBuffer`, the Core Audio process tap delivers an `AudioBufferList`.
/// Both end in `monoSamples(from:frames:asbd:)` so the channel handling cannot
/// drift between backends.
struct AudioSampleConverter {
    private var resampler: LinearResampler

    init(inputRate: Double, outputRate: Double = Double(sampleRate)) {
        resampler = LinearResampler(inputRate: inputRate, outputRate: outputRate)
    }

    mutating func convert(_ sampleBuffer: CMSampleBuffer) -> [Float] {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            return []
        }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else { return [] }
        let mono = Self.monoSamples(from: sampleBuffer, frames: frames, asbd: asbd.pointee)
        guard !mono.isEmpty else { return [] }
        return resampler.process(mono)
    }

    mutating func convert(_ bufferList: UnsafeMutableAudioBufferListPointer,
                          asbd: AudioStreamBasicDescription) -> [Float] {
        let mono = Self.monoSamples(from: bufferList, asbd: asbd)
        guard !mono.isEmpty else { return [] }
        return resampler.process(mono)
    }

    static func monoSamples(from sampleBuffer: CMSampleBuffer, frames: Int,
                            asbd: AudioStreamBasicDescription) -> [Float] {
        var bufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &bufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer)
        guard status == noErr else { return [] }
        return monoSamples(from: UnsafeMutableAudioBufferListPointer(&bufferList), asbd: asbd)
    }

    /// Downmixes an `AudioBufferList` to mono Float32. Handles interleaved and
    /// non-interleaved layouts as well as Float32 and Int16 samples.
    static func monoSamples(from list: UnsafeMutableAudioBufferListPointer,
                            asbd: AudioStreamBasicDescription) -> [Float] {
        guard !list.isEmpty else { return [] }
        let channels = max(1, Int(asbd.mChannelsPerFrame))
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let nonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let bytesPerSample = isFloat ? 4 : 2

        func scalar(_ data: UnsafeMutableRawPointer, _ index: Int) -> Float {
            if isFloat {
                return data.assumingMemoryBound(to: Float.self)[index]
            }
            return Float(data.assumingMemoryBound(to: Int16.self)[index]) / 32_768
        }

        if nonInterleaved {
            var output: [Float] = []
            for buffer in list {
                guard let data = buffer.mData else { continue }
                let available = Int(buffer.mDataByteSize) / bytesPerSample
                if output.isEmpty {
                    output = [Float](repeating: 0, count: available)
                }
                let count = min(output.count, available)
                for i in 0..<count { output[i] += scalar(data, i) }
            }
            guard !output.isEmpty else { return [] }
            let divisor = Float(max(1, list.count))
            for i in output.indices { output[i] /= divisor }
            return output
        }

        guard let data = list[0].mData else { return [] }
        let bytesPerFrame = max(1, Int(asbd.mBytesPerFrame))
        let frames = min(Int(list[0].mDataByteSize) / bytesPerFrame,
                         Int(list[0].mDataByteSize) / (bytesPerSample * channels))
        guard frames > 0 else { return [] }
        var output = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels {
                sum += scalar(data, frame * channels + channel)
            }
            output[frame] = sum / Float(channels)
        }
        return output
    }
}

/// Streaming linear interpolator. Keeps its phase between buffers so a 48 kHz
/// device feed produces one continuous 16 kHz signal instead of clicks.
struct LinearResampler {
    private let ratio: Double
    private var carry: Float = 0
    private var phase: Double = 0
    private var started = false

    init(inputRate: Double, outputRate: Double) {
        ratio = max(0.0001, inputRate / max(1, outputRate))
    }

    mutating func process(_ input: [Float]) -> [Float] {
        guard !input.isEmpty else { return [] }
        if ratio <= 1.0001 { return input }
        let buffer: [Float]
        if started {
            buffer = [carry] + input
        } else {
            buffer = input
            started = true
        }
        var output: [Float] = []
        output.reserveCapacity(Int(Double(buffer.count) / ratio) + 2)
        var position = phase
        while position < Double(buffer.count - 1) {
            let index = Int(position)
            let fraction = Float(position - Double(index))
            output.append(buffer[index] * (1 - fraction) + buffer[index + 1] * fraction)
            position += ratio
        }
        phase = position - Double(buffer.count - 1)
        carry = input[input.count - 1]
        return output
    }
}
