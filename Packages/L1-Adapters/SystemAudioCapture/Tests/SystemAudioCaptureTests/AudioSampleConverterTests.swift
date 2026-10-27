import AVFoundation
import CoreMedia
import XCTest
@testable import SuperflowSystemAudioCapture

final class AudioSampleConverterTests: XCTestCase {
    func testLinearResamplerHalvesSampleCountAt32k() {
        var resampler = LinearResampler(inputRate: 32_000, outputRate: 16_000)
        let input = (0..<320).map { Float($0) / 320 }
        let output = resampler.process(input)
        XCTAssertEqual(Double(output.count), 160, accuracy: 2)
        XCTAssertEqual(output.first ?? -1, 0, accuracy: 0.001)
    }

    func testLinearResamplerPassesThrough16k() {
        var resampler = LinearResampler(inputRate: 16_000, outputRate: 16_000)
        let input: [Float] = [0.1, 0.2, 0.3, 0.4]
        XCTAssertEqual(resampler.process(input), input)
    }

    func testResamplerKeepsContinuityBetweenBuffers() {
        var resampler = LinearResampler(inputRate: 48_000, outputRate: 16_000)
        let first = resampler.process([Float](repeating: 0.5, count: 480))
        let second = resampler.process([Float](repeating: 0.5, count: 480))
        XCTAssertFalse(first.isEmpty)
        XCTAssertFalse(second.isEmpty)
        XCTAssertTrue(first.allSatisfy { abs($0 - 0.5) < 0.001 })
        XCTAssertTrue(second.allSatisfy { abs($0 - 0.5) < 0.001 })
    }

    func testInterleavedStereoDownmix() {
        var samples: [Float] = [1, 0, 0.5, 0.5]
        let asbd = AudioStreamBasicDescription(
            mSampleRate: 16_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        let result = samples.withUnsafeMutableBytes { raw -> [Float] in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 2,
                                      mDataByteSize: UInt32(raw.count),
                                      mData: raw.baseAddress))
            return withUnsafeMutablePointer(to: &list) { pointer in
                guard let sampleBuffer = makeSampleBuffer(bufferList: pointer, frames: 2, asbd: asbd) else {
                    return []
                }
                return AudioSampleConverter.monoSamples(from: sampleBuffer, frames: 2, asbd: asbd)
            }
        }
        XCTAssertEqual(result, [0.5, 0.5])
    }

    private func makeSampleBuffer(bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int,
                                  asbd: AudioStreamBasicDescription) -> CMSampleBuffer? {
        var format: CMAudioFormatDescription?
        var mutableASBD = asbd
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &mutableASBD,
                                             layoutSize: 0, layout: nil, magicCookieSize: 0,
                                             magicCookie: nil, extensions: nil,
                                             formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 16_000),
                                        presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        let status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
                                               formatDescription: format, sampleCount: frames,
                                               sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                               sampleSizeEntryCount: 0, sampleSizeArray: nil,
                                               sampleBufferOut: &sample)
        guard status == noErr, let sample else { return nil }
        CMSampleBufferSetDataBufferFromAudioBufferList(sample, blockBufferAllocator: kCFAllocatorDefault,
                                                       blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                       flags: 0, bufferList: bufferList)
        return sample
    }
}
