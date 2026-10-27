import Foundation
import SuperflowKernel

/// A named bundle of cleanup and text-pipeline choices. Profiles are data:
/// applying one never writes settings on its own, and an unknown profile id is
/// ignored by the resolver rather than treated as an error.
public struct ContextProfile: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var cleanupStyling: String
    public var cleanupStructure: String
    public var cleanupContext: String
    public var codeSpeakEnabled: Bool

    public init(id: String, name: String, cleanupStyling: String, cleanupStructure: String,
                cleanupContext: String, codeSpeakEnabled: Bool = false) {
        self.id = id
        self.name = name
        self.cleanupStyling = cleanupStyling
        self.cleanupStructure = cleanupStructure
        self.cleanupContext = cleanupContext
        self.codeSpeakEnabled = codeSpeakEnabled
    }

    /// True when every field this profile controls already holds the profile's
    /// value. Used to show a profile as active without writing settings.
    public func matches(_ settings: AppSettings) -> Bool {
        settings.cleanupStyling == cleanupStyling
            && settings.cleanupStructure == cleanupStructure
            && settings.cleanupContext == cleanupContext
            && settings.codeSpeakEnabled == codeSpeakEnabled
    }

    /// Returns a copy of `settings` with only the profile-controlled fields
    /// replaced. Every other setting, including feature opt-ins, is preserved.
    public func applying(to settings: AppSettings) -> AppSettings {
        var next = settings
        next.cleanupStyling = cleanupStyling
        next.cleanupStructure = cleanupStructure
        next.cleanupContext = cleanupContext
        next.codeSpeakEnabled = codeSpeakEnabled
        return next
    }

    public static let writing = ContextProfile(
        id: "writing", name: "Writing",
        cleanupStyling: "semi-formal", cleanupStructure: "prose",
        cleanupContext: "general")

    public static let chat = ContextProfile(
        id: "chat", name: "Chat",
        cleanupStyling: "casual", cleanupStructure: "prose",
        cleanupContext: "chat")

    public static let code = ContextProfile(
        id: "code", name: "Code",
        cleanupStyling: "direct", cleanupStructure: "prose",
        cleanupContext: "code", codeSpeakEnabled: true)

    public static let prompting = ContextProfile(
        id: "prompting", name: "Prompting",
        cleanupStyling: "direct", cleanupStructure: "prose",
        cleanupContext: "prompt")

    public static let builtIn: [ContextProfile] = [writing, chat, code, prompting]
}

/// The only inputs the resolver looks at. Detection may propose a signal, but
/// nothing here activates itself: the caller decides when to resolve.
public struct ContextSignal: Sendable, Equatable {
    public var explicitProfileID: String?
    public var bundleID: String?
    public var host: String?

    public init(explicitProfileID: String? = nil, bundleID: String? = nil, host: String? = nil) {
        self.explicitProfileID = explicitProfileID
        self.bundleID = bundleID
        self.host = host
    }
}

public enum ProfileSource: String, Sendable, Codable, Equatable {
    case explicit
    case bundle
    case host
    case fallback
}

public struct ProfileResolution: Sendable, Equatable {
    public var profile: ContextProfile
    public var source: ProfileSource

    public init(profile: ContextProfile, source: ProfileSource) {
        self.profile = profile
        self.source = source
    }
}
