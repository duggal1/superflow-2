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

/// The words an Escape threw away. Present only when the recording was long
/// enough that the Escape was probably a mistake.
public struct IslandUndo: Equatable, Sendable {
    public let text: String
    public let bundleID: String?
    public let appName: String?
    /// How long the recording had run when Escape landed. The card says it, so
    /// "keep the words" has a size: four minutes of speech is worth a second look.
    public let seconds: TimeInterval

    public init(text: String, bundleID: String?, appName: String?, seconds: TimeInterval = 0) {
        self.text = text
        self.bundleID = bundleID
        self.appName = appName
        self.seconds = seconds
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// An OS-style notification, drawn in the Island instead of Notification Centre.
public struct IslandNotice: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case milestone
        case streak
        case modelReady
        case update
        case clipboard
        case info
    }

    public let kind: Kind
    public let title: String
    public let detail: String

    public init(kind: Kind, title: String, detail: String) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public enum IslandEvent: Equatable, Sendable {
    case holdBegan(IslandTarget?)
    case handsFreeBegan(IslandTarget?)
    case meetingBegan(IslandTarget?)
    case holdEnded
    /// Escape while the microphone was open. The text is whatever the recognizer
    /// had produced at that instant, so a long dictation can still be recovered.
    case escapeCancelled(text: String)
    case cancelled
    case landed(words: Int)
    case pasteFailed(IslandTranscript)
    case notice(IslandNotice)
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
