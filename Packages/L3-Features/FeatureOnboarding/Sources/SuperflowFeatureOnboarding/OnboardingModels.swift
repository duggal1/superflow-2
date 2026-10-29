import Foundation

/// Five steps, one backdrop. Meetings are requested lazily on the first meeting,
/// the summary screen is gone, and the display name lives in Settings. The last
/// choice before the sandbox is the dictation key, because the sandbox and the app
/// both have to use the same key.
public enum OnboardingStep: String, CaseIterable, Sendable, Identifiable {
    case welcome
    case permissions
    case models
    case key
    case done

    public var id: String { rawValue }

    public var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public var count: Int { Self.allCases.count }

    /// The single progress value that drives the pixel field: step / (count − 1).
    public var progress: Double {
        Double(index) / Double(max(1, count - 1))
    }

    public var title: String {
        switch self {
        case .welcome: "Speak. It types."
        case .permissions: "Four permissions."
        case .models: "Download the models."
        case .key: "Pick your key."
        case .done: "You're set."
        }
    }

    /// Only where it carries information the screen does not already show.
    public var subtitle: String? {
        switch self {
        case .welcome, .permissions, .models:
            nil
        case .key:
            "Hold to talk. Double-tap for hands-free."
        case .done:
            "Hold fn anywhere to dictate."
        }
    }

    public var primaryTitle: String {
        self == .done ? "Open Superflow" : "Continue"
    }

    public var next: OnboardingStep? {
        switch self {
        case .welcome: .permissions
        case .permissions: .models
        case .models: .key
        case .key: .done
        case .done: nil
        }
    }

    public var previous: OnboardingStep? {
        switch self {
        case .welcome: nil
        case .permissions: .welcome
        case .models: .permissions
        case .key: .models
        case .done: .key
        }
    }
}

public enum PracticeState: Equatable, Sendable {
    case idle
    case listening
    case done
    case failed(String)
}

/// The composition root supplies a real capture that writes only into the
/// onboarding sandbox field. Tests supply a scripted transcript.
public protocol PracticeDictation: Sendable {
    func transcribe() async throws -> String
    /// Ends the take early, flushing whatever was said. `transcribe()` then returns.
    func finish() async
    func cancel() async
}

public extension PracticeDictation {
    func finish() async {}
    func cancel() async {}
}
