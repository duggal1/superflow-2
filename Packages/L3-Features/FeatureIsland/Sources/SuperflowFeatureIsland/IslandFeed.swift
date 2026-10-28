import Foundation

/// The app the text will land in.
public struct IslandTarget: Equatable, Sendable {
    public let bundleID: String?
    public let name: String?

    public init(bundleID: String?, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct IslandTranscript: Equatable, Sendable {
    /// Cleaned text.
    public let text: String
    public let bundleID: String?
    public let appName: String?
    public let date: Date
    public let words: Int

    public init(text: String, bundleID: String?, appName: String?, date: Date, words: Int) {
        self.text = text
        self.bundleID = bundleID
        self.appName = appName
        self.date = date
        self.words = words
    }
}

public enum IslandEvent: Equatable, Sendable {
    case holdBegan(IslandTarget?)
    case holdEnded
    case cancelled
    case landed(words: Int)
    case pasteFailed(IslandTranscript)
    case dismissed
}

/// The Island's only boundary. It never imports an engine or an adapter.
public protocol IslandFeed: Sendable {
    var events: AsyncStream<IslandEvent> { get }
    /// Microphone level, 0...1, already mapped from dBFS, about 30 Hz, only while capturing.
    var levels: AsyncStream<Float> { get }
    /// The last stored dictation. nil when "Don't store transcripts" is on or nothing exists yet.
    func lastTranscript() -> IslandTranscript?
    var storesTranscripts: Bool { get }
}
