import Foundation

/// A bundle-id rule. An identifier ending in "." is a prefix rule so a whole
/// vendor family can share a profile; everything else must match exactly.
public struct BundleRule: Sendable, Equatable {
    public var identifier: String
    public var profileID: String

    public init(_ identifier: String, _ profileID: String) {
        self.identifier = identifier
        self.profileID = profileID
    }

    func matches(_ bundleID: String) -> Bool {
        let rule = identifier.lowercased()
        guard !rule.isEmpty else { return false }
        return rule.hasSuffix(".") ? bundleID.hasPrefix(rule) : bundleID == rule
    }

    public static let builtIn: [BundleRule] = [
        BundleRule("com.apple.dt.xcode", "code"),
        BundleRule("com.microsoft.vscode", "code"),
        BundleRule("com.apple.terminal", "code"),
        BundleRule("com.googlecode.iterm2", "code"),
        BundleRule("dev.warp.warp-stable", "code"),
        BundleRule("com.jetbrains.", "code"),
        BundleRule("com.sublimetext.4", "code"),
        BundleRule("com.todesktop.230313mzl4w4u92", "code"),
        BundleRule("io.zed.zed", "code"),

        BundleRule("com.tinyspeck.slackmacgap", "chat"),
        BundleRule("com.hnc.discord", "chat"),
        BundleRule("com.apple.mobilesms", "chat"),
        BundleRule("com.apple.ichat", "chat"),
        BundleRule("com.microsoft.teams2", "chat"),
        BundleRule("org.telegram.desktop", "chat"),

        BundleRule("com.openai.chat", "prompting"),
        BundleRule("com.anthropic.claudefordesktop", "prompting"),
        BundleRule("ai.perplexity.mac", "prompting"),

        BundleRule("com.apple.notes", "writing"),
        BundleRule("com.apple.textedit", "writing"),
        BundleRule("com.apple.iwork.pages", "writing"),
        BundleRule("com.microsoft.word", "writing"),
        BundleRule("com.apple.mail", "writing"),
    ]
}

/// A host rule matching the domain itself or any subdomain of it.
public struct HostRule: Sendable, Equatable {
    public var domain: String
    public var profileID: String

    public init(_ domain: String, _ profileID: String) {
        self.domain = domain
        self.profileID = profileID
    }

    func matches(_ host: String) -> Bool {
        let rule = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !rule.isEmpty else { return false }
        return host == rule || host.hasSuffix("." + rule)
    }

    public static let builtIn: [HostRule] = [
        HostRule("chatgpt.com", "prompting"),
        HostRule("chat.openai.com", "prompting"),
        HostRule("claude.ai", "prompting"),
        HostRule("gemini.google.com", "prompting"),
        HostRule("perplexity.ai", "prompting"),
        HostRule("copilot.microsoft.com", "prompting"),
    ]
}

/// Pure resolver: no I/O, no timers, no mutation. An unknown explicit profile
/// id falls through to the signal's bundle and host, then to Writing.
public struct ContextProfileResolver: Sendable {
    public let profiles: [ContextProfile]
    public let bundleRules: [BundleRule]
    public let hostRules: [HostRule]

    private let byID: [String: ContextProfile]

    public init(profiles: [ContextProfile] = ContextProfile.builtIn,
                bundleRules: [BundleRule] = BundleRule.builtIn,
                hostRules: [HostRule] = HostRule.builtIn) {
        self.profiles = profiles
        self.bundleRules = bundleRules
        self.hostRules = hostRules
        var index: [String: ContextProfile] = [:]
        for profile in profiles where index[profile.id.lowercased()] == nil {
            index[profile.id.lowercased()] = profile
        }
        self.byID = index
    }

    public func profile(id: String) -> ContextProfile? {
        byID[Self.normalize(id)]
    }

    public func resolve(_ signal: ContextSignal) -> ProfileResolution {
        if let id = Self.normalized(signal.explicitProfileID), let profile = byID[id] {
            return ProfileResolution(profile: profile, source: .explicit)
        }
        if let bundle = Self.normalized(signal.bundleID) {
            for rule in bundleRules where rule.matches(bundle) {
                if let profile = byID[rule.profileID.lowercased()] {
                    return ProfileResolution(profile: profile, source: .bundle)
                }
            }
        }
        if let host = Self.normalizedHost(signal.host) {
            for rule in hostRules where rule.matches(host) {
                if let profile = byID[rule.profileID.lowercased()] {
                    return ProfileResolution(profile: profile, source: .host)
                }
            }
        }
        return ProfileResolution(profile: fallbackProfile, source: .fallback)
    }

    private var fallbackProfile: ContextProfile {
        byID["writing"] ?? profiles.first ?? ContextProfile.writing
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Accepts a bare host or a full URL; strips scheme, path, port and a
    /// leading "www." so the rule sees only the registrable host.
    static func normalizedHost(_ value: String?) -> String? {
        guard var host = normalized(value) else { return nil }
        if let scheme = host.range(of: "://") {
            host = String(host[scheme.upperBound...])
        }
        if let cut = host.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            host = String(host[..<cut])
        }
        if let colon = host.lastIndex(of: ":"), host[host.index(after: colon)...].allSatisfy(\.isNumber) {
            host = String(host[..<colon])
        }
        while host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }
}
