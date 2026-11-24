import AVFoundation
import CoreAudio
import Foundation

/// A snapshot of one Core Audio device. The eligibility decision is made from
/// these values so it can be tested without touching hardware.
public struct InputDeviceDescriptor: Sendable, Equatable {
    public var id: AudioDeviceID
    /// The persistent CoreAudio UID (also `AVCaptureDevice.uniqueID`). The
    /// numeric `AudioDeviceID` is session-local and is never persisted.
    public var uid: String
    public var name: String
    public var isAlive: Bool
    public var isHidden: Bool
    public var isSystemDefault: Bool
    public var hasInputFormat: Bool
    public var inputChannels: Int32
    public var sampleRate: Double
    public var transportType: UInt32

    public init(
        id: AudioDeviceID,
        uid: String,
        name: String,
        isAlive: Bool,
        isHidden: Bool,
        isSystemDefault: Bool,
        hasInputFormat: Bool,
        inputChannels: Int32,
        sampleRate: Double,
        transportType: UInt32
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isAlive = isAlive
        self.isHidden = isHidden
        self.isSystemDefault = isSystemDefault
        self.hasInputFormat = hasInputFormat
        self.inputChannels = inputChannels
        self.sampleRate = sampleRate
        self.transportType = transportType
    }

    /// Virtual endpoints and process-tap aggregate devices capture output;
    /// they are never microphones.
    public static let virtualTransport: UInt32 = kAudioDeviceTransportTypeVirtual

    public var isProcessTapOrVirtual: Bool {
        uid.hasPrefix("CADefaultDeviceAggregate") || transportType == Self.virtualTransport
    }

    public var isEligibleMicrophone: Bool {
        isAlive && !isHidden && hasInputFormat && inputChannels > 0 && sampleRate > 0
            && !isProcessTapOrVirtual
    }
}

/// The persisted choice. A nil/blank UID means "follow the system default".
/// Only a UID and a display name are stored; no ephemeral device ID.
public struct MicrophoneSelection: Codable, Equatable, Sendable {
    public var uid: String?
    public var name: String?

    public init(uid: String?, name: String?) {
        let trimmed = uid?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.uid = (trimmed?.isEmpty ?? true) ? nil : uid
        self.name = name
    }
}

public enum RouteKind: String, Sendable, Equatable {
    case automatic
    case explicit
    case fallback
    case unavailable
}

/// What will actually record, including the visible label and the reason a
/// saved device could not be honoured.
public struct SelectedRoute: Sendable, Equatable {
    public var kind: RouteKind
    public var uid: String?
    public var name: String?
    public var note: String?

    public init(kind: RouteKind, uid: String?, name: String?, note: String? = nil) {
        self.kind = kind
        self.uid = uid
        self.name = name
        self.note = note
    }

    public var displayName: String {
        switch kind {
        case .automatic: return "System default" + (name.map { " \u{2014} \($0)" } ?? "")
        case .explicit: return name ?? uid ?? "Microphone"
        case .fallback: return name ?? uid ?? "System default"
        case .unavailable: return "No microphone available"
        }
    }
}

/// Resolves a persisted choice against the devices connected now. An explicit
/// device that is gone falls back to the default without changing the choice.
public enum RouteResolver {
    public static func resolve(
        selection: MicrophoneSelection?,
        inputs: [InputDeviceDescriptor]
    ) -> SelectedRoute {
        let eligible = inputs.filter(\.isEligibleMicrophone)
        let defaultInput = eligible.first(where: \.isSystemDefault) ?? eligible.first

        guard let selection, let wanted = selection.uid else {
            guard let fallback = defaultInput else {
                return SelectedRoute(kind: .unavailable, uid: nil, name: nil)
            }
            return SelectedRoute(kind: .automatic, uid: fallback.uid, name: fallback.name)
        }

        if let chosen = eligible.first(where: { $0.uid == wanted }) {
            return SelectedRoute(kind: .explicit, uid: chosen.uid, name: chosen.name)
        }

        let wantedName = selection.name ?? wanted
        guard let fallback = defaultInput else {
            return SelectedRoute(
                kind: .fallback,
                uid: nil,
                name: nil,
                note: "\(wantedName) isn't connected, and there's no other microphone."
            )
        }
        return SelectedRoute(
            kind: .fallback,
            uid: fallback.uid,
            name: fallback.name,
            note: "\(wantedName) isn't connected. Using \(fallback.name)."
        )
    }
}

/// The result of an explicit selection request. An id that is not connected
/// (or is a virtual/output device) cannot be named, so it changes nothing.
public enum SelectionSaveDecision: Sendable, Equatable {
    case clear
    case save(MicrophoneSelection)
    case keepCurrent
}

extension RouteResolver {
    public static func saveDecision(
        uid: String?,
        name: String?,
        inputs: [InputDeviceDescriptor]
    ) -> SelectionSaveDecision {
        let trimmed = uid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty || trimmed == "default" { return .clear }
        guard let chosen = inputs.first(where: { $0.uid == trimmed && $0.isEligibleMicrophone })
        else { return .keepCurrent }
        return .save(MicrophoneSelection(uid: chosen.uid, name: name ?? chosen.name))
    }
}

public protocol MicrophoneSelectionStore: Sendable {
    func load() -> MicrophoneSelection?
    func save(_ selection: MicrophoneSelection?) throws
}

/// Owner-local JSON persistence of the chosen device UID. Saving nil (or a
/// blank UID) clears the file, which is the "System default" choice.
public final class FileMicrophoneSelectionStore: MicrophoneSelectionStore, @unchecked Sendable {
    private let url: URL
    private let fileManager: FileManager

    public init(url: URL? = nil, fileManager: FileManager = .default) {
        if let url {
            self.url = url
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.url = base.appendingPathComponent("Superflow/microphone-selection.json")
        }
        self.fileManager = fileManager
    }

    public func load() -> MicrophoneSelection? {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(MicrophoneSelection.self, from: data),
              decoded.uid != nil
        else { return nil }
        return decoded
    }

    public func save(_ selection: MicrophoneSelection?) throws {
        guard let selection, selection.uid != nil else {
            try? fileManager.removeItem(at: url)
            return
        }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(selection).write(to: url, options: .atomic)
    }
}
