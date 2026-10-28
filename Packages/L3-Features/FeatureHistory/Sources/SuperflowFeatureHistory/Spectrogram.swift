import Accelerate
import AVFoundation
import Foundation

/// The picture of a voice. Eight frequency bands, one column per 25 ms, each
/// cell one byte. Low bands are at the bottom of the grid, so a hum sits on the
/// bottom row and an "s" lights the top. The numbers are tuned for 16 kHz
/// speech, which is the only thing the archive writes.
enum Spectro {
    static let bands = 8
    /// 32 ms at 16 kHz.
    static let window = 512
    /// 25 ms: 40 columns a second.
    static let hop = 400
    /// FFT bins, 31.25 Hz each, low to high.
    static let edges = [0, 8, 16, 32, 48, 74, 109, 160, 256]
    /// dB added per band so speech's low-frequency tilt does not swallow the
    /// consonants. Tuned by eye on a real clip; see DESIGN.md §0.11.
    static let tilt: [Float] = [0, 2, 4, 6, 8, 10, 12, 14]
    /// dB shown below the loudest cell.
    static let range: Float = 38
    /// Frames quieter than this are silence and stay at zero.
    static let gateDB: Float = -62
}

struct ClipData: Sendable {
    let url: URL
    /// Mono samples, kept so playback and grains never touch the disk again.
    let samples: [Float]
    let sampleRate: Double
    let duration: TimeInterval
    let frames: Int
    /// `frames` × 8, row-major by frame, 0...255. Index `frame * bands + band`.
    let cells: [UInt8]
}

enum ClipLoader {
    private final class Box {
        let clip: ClipData
        init(_ clip: ClipData) { self.clip = clip }
    }

    nonisolated(unsafe) private static let cache: NSCache<NSURL, Box> = {
        let cache = NSCache<NSURL, Box>()
        cache.totalCostLimit = 96_000_000
        return cache
    }()

    static func load(_ url: URL) async -> ClipData? {
        if let hit = cache.object(forKey: url as NSURL) { return hit.clip }
        let clip = await Task.detached(priority: .userInitiated) { decode(url) }.value
        if let clip {
            cache.setObject(Box(clip), forKey: url as NSURL, cost: clip.samples.count * 4)
        }
        return clip
    }

    nonisolated private static func decode(_ url: URL) -> ClipData? {
        // 15 minutes at 16 kHz. Dictation clips are seconds; this only stops a
        // corrupt or foreign file from asking for a gigabyte of memory.
        let frameLimit: Int64 = 16_000 * 900
        guard let file = try? AVAudioFile(forReading: url),
              file.length > 0,
              file.length <= frameLimit,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else { return nil }

        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        guard samples.count >= Spectro.window else { return nil }
        let cells = analyze(samples)
        guard !cells.isEmpty else { return nil }
        let rate = file.processingFormat.sampleRate
        return ClipData(url: url,
                        samples: samples,
                        sampleRate: rate,
                        duration: Double(samples.count) / rate,
                        frames: cells.count / Spectro.bands,
                        cells: cells)
    }
}

/// One FFT per frame, one value per band. Silence stays at zero so the grid
/// keeps its structure while the picture shows nothing.
private func analyze(_ samples: [Float]) -> [UInt8] {
    let size = Spectro.window
    let half = size / 2
    let bands = Spectro.bands
    guard samples.count >= size else { return [] }

    let frames = (samples.count - size) / Spectro.hop + 1
    let log2n = vDSP_Length(log2(Double(size)))
    guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
    defer { vDSP_destroy_fftsetup(setup) }

    var window = [Float](repeating: 0, count: size)
    vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))

    var windowed = [Float](repeating: 0, count: size)
    var real = [Float](repeating: 0, count: half)
    var imaginary = [Float](repeating: 0, count: half)
    var power = [Float](repeating: 0, count: half)
    var db = [Float](repeating: -200, count: frames * bands)
    var loudest: Float = -200

    for frame in 0..<frames {
        var rms: Float = 0
        samples.withUnsafeBufferPointer { source in
            vDSP_rmsqv(source.baseAddress! + frame * Spectro.hop, 1, &rms, vDSP_Length(size))
            vDSP_vmul(source.baseAddress! + frame * Spectro.hop, 1, window, 1, &windowed, 1,
                      vDSP_Length(size))
        }
        guard 20 * log10(max(rms, 1e-7)) > Spectro.gateDB else { continue }

        windowed.withUnsafeBufferPointer { input in
            input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                real.withUnsafeMutableBufferPointer { realBuffer in
                    imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                        var split = DSPSplitComplex(realp: realBuffer.baseAddress!,
                                                    imagp: imaginaryBuffer.baseAddress!)
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
                    }
                }
            }
        }
        // Bin 0 packs DC and Nyquist together, so it is not a band.
        power[0] = 0
        for band in 0..<bands {
            let low = Spectro.edges[band]
            let high = Spectro.edges[band + 1]
            var mean: Float = 0
            power.withUnsafeBufferPointer {
                vDSP_meanv($0.baseAddress! + low, 1, &mean, vDSP_Length(high - low))
            }
            let value = 10 * log10(max(mean, 1e-12)) + Spectro.tilt[band]
            db[frame * bands + band] = value
            loudest = max(loudest, value)
        }
    }

    guard loudest > -150 else { return [UInt8](repeating: 0, count: db.count) }
    let floor = loudest - Spectro.range
    return db.map { value in
        value <= floor ? 0 : UInt8(min(255, ((value - floor) / Spectro.range * 255).rounded()))
    }
}
