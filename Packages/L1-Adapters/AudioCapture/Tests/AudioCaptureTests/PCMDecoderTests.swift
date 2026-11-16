import CoreAudio
import XCTest
@testable import SuperflowAudioCapture

final class PCMDecoderTests: XCTestCase {
    private func decode(_ bytes: [UInt8], decoder: PCMDecoder, frames: Int) -> [Float] {
        bytes.withUnsafeBytes { source in
            var output = [Float](repeating: .nan, count: frames)
            output.withUnsafeMutableBufferPointer { destination in
                decoder.convert(source, into: destination, frames: frames)
            }
            return output
        }
    }

    func testInt16LittleEndian() {
        let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x40, 0x00, 0x80]
        let decoder = PCMDecoder(encoding: .int16, bytesPerChannel: 2, channels: 1)
        let output = decode(bytes, decoder: decoder, frames: 3)
        XCTAssertEqual(output[0], 0, accuracy: 1e-6)
        XCTAssertEqual(output[1], 0.5, accuracy: 1e-6)
        XCTAssertEqual(output[2], -1, accuracy: 1e-6)
    }

    func testInt16BigEndian() {
        let bytes: [UInt8] = [0x40, 0x00]
        let decoder = PCMDecoder(encoding: .int16, bytesPerChannel: 2, channels: 1, bigEndian: true)
        XCTAssertEqual(decode(bytes, decoder: decoder, frames: 1)[0], 0.5, accuracy: 1e-6)
    }

    func testInt32AndInt24Containers() {
        let int32 = PCMDecoder(encoding: .int32, bytesPerChannel: 4, channels: 1)
        XCTAssertEqual(decode([0x00, 0x00, 0x00, 0x40], decoder: int32, frames: 1)[0], 0.5, accuracy: 1e-6)
        let int24in32 = PCMDecoder(encoding: .int24In32, bytesPerChannel: 4, channels: 1)
        XCTAssertEqual(decode([0x00, 0x00, 0x00, 0x40], decoder: int24in32, frames: 1)[0], 0.5, accuracy: 1e-6)
        let packed = PCMDecoder(encoding: .int24Packed, bytesPerChannel: 3, channels: 1)
        XCTAssertEqual(decode([0x00, 0x00, 0x40], decoder: packed, frames: 1)[0], 0.5, accuracy: 1e-6)
        XCTAssertEqual(decode([0x00, 0x00, 0x80], decoder: packed, frames: 1)[0], -1, accuracy: 1e-6)
    }

    func testFloatingPointFormats() {
        let float32 = PCMDecoder(encoding: .float32, bytesPerChannel: 4, channels: 1)
        var bits = Float(0.25).bitPattern
        let bytes32 = withUnsafeBytes(of: &bits) { Array($0) }
        XCTAssertEqual(decode(bytes32, decoder: float32, frames: 1)[0], 0.25, accuracy: 1e-6)
        let float64 = PCMDecoder(encoding: .float64, bytesPerChannel: 8, channels: 1)
        var wide = Float64(-0.75).bitPattern
        let bytes64 = withUnsafeBytes(of: &wide) { Array($0) }
        XCTAssertEqual(decode(bytes64, decoder: float64, frames: 1)[0], -0.75, accuracy: 1e-6)
    }

    func testInterleavedPicksFirstChannelOnly() {
        let decoder = PCMDecoder(encoding: .int16, bytesPerChannel: 2, channels: 2)
        let bytes: [UInt8] = [0x00, 0x40, 0x00, 0x80, 0x00, 0x80, 0x00, 0x40]
        XCTAssertEqual(decode(bytes, decoder: decoder, frames: 2), [0.5, -1])
    }

    func testUnsupportedFormatsAreRejected() {
        var format = AudioStreamBasicDescription()
        format.mFormatID = kAudioFormatLinearPCM
        format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        format.mChannelsPerFrame = 1
        format.mBitsPerChannel = 20
        format.mBytesPerFrame = 4
        XCTAssertNil(PCMDecoder(format))
    }
}
