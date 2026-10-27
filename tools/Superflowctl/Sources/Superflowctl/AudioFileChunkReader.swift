import AVFoundation
import Foundation
import SuperflowKernel

struct AudioFileChunkReader {
    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let canReadDirectly: Bool
    private var nextSample: Int64 = 0

    init(url: URL) throws {
        let audioFile = try AVAudioFile(forReading: url)
        let sourceFormat = audioFile.processingFormat
        guard let output = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let converter = AVAudioConverter(from: sourceFormat, to: output) else {
            throw SuperflowError.audioFailure("Could not create the 16 kHz mono audio converter.")
        }
        file = audioFile
        inputFormat = sourceFormat
        outputFormat = output
        self.converter = converter
        canReadDirectly = sourceFormat.sampleRate == Double(sampleRate)
            && sourceFormat.channelCount == 1
            && sourceFormat.commonFormat == .pcmFormatFloat32
            && !sourceFormat.isInterleaved
    }

    mutating func next() throws -> AudioChunk? {
        while true {
            guard file.framePosition < file.length else { return nil }
            let inputCapacity = AVAudioFrameCount(max(1, Int(inputFormat.sampleRate.rounded())))
            guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputCapacity) else {
                throw SuperflowError.audioFailure("Could not allocate an audio file buffer.")
            }
            try file.read(into: input)
            guard input.frameLength > 0 else { return nil }

            if canReadDirectly, let channel = input.floatChannelData?.pointee {
                let count = Int(input.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channel, count: count))
                defer { nextSample += Int64(count) }
                return AudioChunk(samples: samples, startSample: nextSample, source: .mic)
            }

            let estimatedFrames = Int(ceil(Double(input.frameLength) * Double(sampleRate) / inputFormat.sampleRate)) + 512
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                frameCapacity: AVAudioFrameCount(estimatedFrames)) else {
                throw SuperflowError.audioFailure("Could not allocate a converted audio buffer.")
            }
            var suppliedInput = false
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                guard !suppliedInput else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                suppliedInput = true
                inputStatus.pointee = .haveData
                return input
            }
            if let conversionError { throw conversionError }
            if status == .error {
                throw SuperflowError.audioFailure("Audio file conversion failed.")
            }
            guard output.frameLength > 0, let channel = output.floatChannelData?.pointee else { continue }
            let count = Int(output.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channel, count: count))
            defer { nextSample += Int64(count) }
            return AudioChunk(samples: samples, startSample: nextSample, source: .mic)
        }
    }
}
