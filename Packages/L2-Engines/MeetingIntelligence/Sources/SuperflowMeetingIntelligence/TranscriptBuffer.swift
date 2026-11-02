import Foundation

public enum TranscriptSpeaker: String, Sendable {
    case me = "ME"
    case them = "THEM"
}

public actor TranscriptBuffer {
    private struct Segment {
        let speaker: TranscriptSpeaker
        var text: String
        let startedAt: TimeInterval
        var isFinal: Bool
    }

    private let capacity: Int
    private var segments: [Segment] = []
    private var origin = ContinuousClock.now
    private var suppressMe = false

    public init(capacity: Int = 7_000) {
        self.capacity = max(0, capacity)
    }

    public func reset() {
        segments.removeAll()
        origin = .now
        suppressMe = false
    }

    public func setSuppressMe(_ value: Bool) {
        suppressMe = value
        if value { segments.removeAll { $0.speaker == .me && !$0.isFinal } }
    }

    public func ingest(speaker: TranscriptSpeaker, text: String, isFinal: Bool) {
        guard !(speaker == .me && suppressMe), capacity > 0 else { return }
        let elapsed = origin.duration(to: .now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        let boundedText = String(text.suffix(capacity))
        if let index = segments.lastIndex(where: { $0.speaker == speaker && !$0.isFinal }) {
            segments[index].text = boundedText
            segments[index].isFinal = isFinal
        } else {
            segments.append(Segment(speaker: speaker, text: boundedText, startedAt: seconds, isFinal: isFinal))
        }
        trim()
    }

    public func snapshot(maxChars: Int = 7_000) -> String {
        let limit = max(0, min(maxChars, capacity))
        guard limit > 0 else { return "" }
        let text = segments.map { segment in
            let seconds = Int(segment.startedAt)
            let timestamp = String(format: "%02d:%02d", seconds / 60, seconds % 60)
            return "[\(timestamp)] \(segment.speaker.rawValue): \(segment.text)" + (segment.isFinal ? "" : " …")
        }.joined(separator: "\n")
        return String(text.suffix(limit))
    }

    private func trim() {
        while segments.count > 1 && segments.reduce(0, { $0 + $1.text.count + 20 }) > capacity {
            segments.removeFirst()
        }
    }
}
