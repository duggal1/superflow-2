import Foundation
import OSLog
import SuperflowKernel
import SuperflowPorts

struct SessionLatency {
    static let signposter = OSSignposter(subsystem: "com.superflow.app", category: "latency")
    var microphoneStarted: UInt64?
    var stopStarted: UInt64?
    var stopInterval: OSSignpostIntervalState?
}

extension SessionEngine {
    func startCapture() async throws -> AudioStreams {
        latency.microphoneStarted = DispatchTime.now().uptimeNanoseconds
        let streams = try await audio.start()
        if let started = latency.microphoneStarted {
            metrics.record("session.mic.open.ms", valueMs: elapsedMilliseconds(since: started))
        }
        return streams
    }

    func feedRecognition(_ recognition: any RecognitionStream, chunk: AudioChunk) async {
        if !chunk.samples.isEmpty, let started = latency.microphoneStarted {
            latency.microphoneStarted = nil
            metrics.record("session.mic_start.to_first_feed.ms", valueMs: elapsedMilliseconds(since: started))
        }
        let started = DispatchTime.now().uptimeNanoseconds
        await recognition.feed(chunk)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        // Record slow native feed calls without sampling transcript content.
        // Per-buffer metrics during normal streaming would add overhead.
        if elapsed > 50 {
            metrics.record("session.asr.slow_feed.ms", valueMs: elapsed)
        }
    }

    func recordLatency(_ event: SessionEvent) {
        switch event {
        case .state(.finalizing):
            latency.stopStarted = DispatchTime.now().uptimeNanoseconds
            latency.stopInterval = SessionLatency.signposter.beginInterval(
                "session.stop.to_insert_return", id: SessionLatency.signposter.makeSignpostID())
        case .inserted(let outcome):
            if let started = latency.stopStarted {
                let elapsed = elapsedMilliseconds(since: started)
                metrics.record("session.stop.insertion_attempt.ms", valueMs: elapsed)
                if outcome == .pasted || outcome == .accessibility {
                    metrics.record("session.stop.to_insert_return.ms", valueMs: elapsed)
                }
            }
            finishLatencyInterval()
        case .state(.complete), .state(.failed), .state(.cancelled):
            latency.microphoneStarted = nil
            finishLatencyInterval()
        default:
            break
        }
    }

    private func finishLatencyInterval() {
        if let interval = latency.stopInterval {
            SessionLatency.signposter.endInterval("session.stop.to_insert_return", interval)
        }
        latency.stopStarted = nil
        latency.stopInterval = nil
    }

    private func elapsedMilliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}
