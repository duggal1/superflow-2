import CoreAudio
import Foundation

/// Converts a device's linear PCM buffer to mono Float32 without allocation,
/// locks or concurrency. AirPods and USB headsets frequently expose integer PCM;
/// reading those bytes as Float32 produces near-silent, crackly speech.
struct PCMDecoder: Sendable {
    enum Encoding: Sendable {
        case float32, float64, int16, int24Packed, int24In32, int32
    }

    let encoding: Encoding
    let bytesPerChannel: Int
    let channels: Int
    let bigEndian: Bool

    init(encoding: Encoding, bytesPerChannel: Int, channels: Int, bigEndian: Bool = false) {
        self.encoding = encoding
        self.bytesPerChannel = bytesPerChannel
        self.channels = max(1, channels)
        self.bigEndian = bigEndian
    }

    init?(_ format: AudioStreamBasicDescription) {
        guard format.mFormatID == kAudioFormatLinearPCM, format.mChannelsPerFrame > 0 else { return nil }
        let bits = Int(format.mBitsPerChannel)
        let channels = Int(format.mChannelsPerFrame)
        let bytes = format.mBytesPerFrame > 0
            ? Int(format.mBytesPerFrame) / channels : (bits + 7) / 8
        let bigEndian = format.mFormatFlags & kAudioFormatFlagIsBigEndian != 0
        let encoding: Encoding?
        if format.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            switch bits {
            case 32 where bytes >= 4: encoding = .float32
            case 64 where bytes >= 8: encoding = .float64
            default: return nil
            }
        } else if format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 {
            switch (bits, bytes) {
            case (16, 2), (16, 4): encoding = .int16
            case (24, 3): encoding = .int24Packed
            case (24, 4): encoding = .int24In32
            case (32, 4): encoding = .int32
            default: return nil
            }
        } else { return nil }
        self.init(encoding: encoding!, bytesPerChannel: bytes, channels: channels,
                  bigEndian: bigEndian)
    }

    var bytesPerFrame: Int { bytesPerChannel * channels }

    /// Decodes the first input channel of `frames` frames into `output`.
    /// Both buffers must outlive the call; no allocation happens here.
    func convert(_ source: UnsafeRawBufferPointer,
                 into output: UnsafeMutableBufferPointer<Float>,
                 frames: Int) {
        let available = source.count / max(1, bytesPerFrame)
        let count = min(frames, output.count, available)
        if count <= 0 { return }
        let step = bytesPerFrame
        for frame in 0..<count {
            output[frame] = sample(source, offset: frame * step)
        }
    }

    @inline(__always)
    private func sample(_ source: UnsafeRawBufferPointer, offset: Int) -> Float {
        func unsigned(_ width: Int) -> UInt32 {
            var value: UInt32 = 0
            for index in 0..<width {
                let byte = UInt32(source[offset + index])
                value = bigEndian ? (value << 8) | byte : value | (byte << (8 * index))
            }
            return value
        }
        switch encoding {
        case .float32:
            return Float(bitPattern: unsigned(4))
        case .float64:
            let low = unsigned(4)
            let high = {
                var value: UInt32 = 0
                for index in 0..<4 {
                    let byte = UInt32(source[offset + 4 + index])
                    value = bigEndian ? (value << 8) | byte : value | (byte << (8 * index))
                }
                return value
            }()
            let bits = bigEndian
                ? UInt64(low) << 32 | UInt64(high)
                : UInt64(low) | UInt64(high) << 32
            return Float(Float64(bitPattern: bits))
        case .int16:
            let value = Int16(bitPattern: UInt16(truncatingIfNeeded: unsigned(2)))
            return Float(value) / 32_768
        case .int32:
            return Float(Int32(bitPattern: unsigned(4))) / 2_147_483_648
        case .int24In32:
            return Float(Int32(bitPattern: unsigned(4)) >> 8) / 8_388_608
        case .int24Packed:
            var raw: Int32 = 0
            if bigEndian {
                raw = Int32(source[offset]) << 16
                    | Int32(source[offset + 1]) << 8
                    | Int32(source[offset + 2])
            } else {
                raw = Int32(source[offset])
                    | Int32(source[offset + 1]) << 8
                    | Int32(source[offset + 2]) << 16
            }
            let signed = raw & 0x800_000 != 0 ? raw | ~0xFF_FFFF : raw
            return Float(signed) / 8_388_608
        }
    }
}
