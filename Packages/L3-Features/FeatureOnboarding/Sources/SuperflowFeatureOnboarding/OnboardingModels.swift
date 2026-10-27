import Foundation

/// Four steps, one backdrop. Meetings are requested lazily on the first meeting,
/// the summary screen is gone, and the display name lives in Settings.
public enum OnboardingStep: String, CaseIterable, Sendable, Identifiable {
    case welcome
    case permissions
    case models
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
        case .permissions: "Three permissions."
        case .models: "Download the models."
        case .done: "You're set."
        }
    }

    /// Only where it carries information the screen does not already show.
    public var subtitle: String? {
        switch self {
        case .welcome, .permissions, .models:
            nil
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
        case .models: .done
        case .done: nil
        }
    }

    public var previous: OnboardingStep? {
        switch self {
        case .welcome: nil
        case .permissions: .welcome
        case .models: .permissions
        case .done: .models
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
    func cancel() async
}

public extension PracticeDictation {
    func cancel() async {}
}
