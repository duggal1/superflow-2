import XCTest
import SuperflowKernel
@testable import SuperflowContextProfiles

final class ContextProfilesTests: XCTestCase {
    private let resolver = ContextProfileResolver()

    func testBuiltInProfiles() {
        XCTAssertEqual(ContextProfile.builtIn.map(\.id), ["writing", "chat", "code", "prompting"])
        XCTAssertFalse(ContextProfile.writing.codeSpeakEnabled)
        XCTAssertFalse(ContextProfile.chat.codeSpeakEnabled)
        XCTAssertTrue(ContextProfile.code.codeSpeakEnabled)
        XCTAssertFalse(ContextProfile.prompting.codeSpeakEnabled)
        XCTAssertEqual(resolver.resolve(ContextSignal()).profile.id, "writing")
        XCTAssertEqual(resolver.resolve(ContextSignal()).source, .fallback)
    }

    func testExplicitProfileWinsOverEverything() {
        let resolution = resolver.resolve(ContextSignal(
            explicitProfileID: "code", bundleID: "com.tinyspeck.slackmacgap",
            host: "claude.ai"))
        XCTAssertEqual(resolution.profile.id, "code")
        XCTAssertEqual(resolution.source, .explicit)
    }

    func testUnknownExplicitFallsThroughToBundle() {
        let resolution = resolver.resolve(ContextSignal(
            explicitProfileID: "does-not-exist", bundleID: "com.microsoft.vscode"))
        XCTAssertEqual(resolution.profile.id, "code")
        XCTAssertEqual(resolution.source, .bundle)
    }

    func testBundleRulesExactPrefixAndCaseInsensitive() {
        XCTAssertEqual(resolver.resolve(ContextSignal(bundleID: "com.apple.dt.Xcode")).profile.id, "code")
        XCTAssertEqual(resolver.resolve(ContextSignal(bundleID: "com.jetbrains.intellij")).profile.id, "code")
        XCTAssertEqual(resolver.resolve(ContextSignal(bundleID: " com.apple.Terminal ")).profile.id, "code")
        XCTAssertEqual(resolver.resolve(ContextSignal(bundleID: "com.tinyspeck.SlackMacGap")).profile.id, "chat")
        XCTAssertEqual(resolver.resolve(ContextSignal(bundleID: "com.apple.Notes")).profile.id, "writing")
    }

    func testUnknownBundleFallsBackToWriting() {
        let resolution = resolver.resolve(ContextSignal(bundleID: "com.example.unknown"))
        XCTAssertEqual(resolution.profile.id, "writing")
        XCTAssertEqual(resolution.source, .fallback)
    }

    func testHostRulesAcceptFullUrlsAndSubdomains() {
        XCTAssertEqual(resolver.resolve(ContextSignal(host: "https://chatgpt.com/c/123")).profile.id,
                       "prompting")
        XCTAssertEqual(resolver.resolve(ContextSignal(host: "https://chatgpt.com/c/123")).source, .host)
        XCTAssertEqual(resolver.resolve(ContextSignal(host: "docs.claude.ai")).profile.id, "prompting")
        XCTAssertEqual(resolver.resolve(ContextSignal(host: "www.claude.ai:443")).profile.id, "prompting")
    }

    func testHostRulesRespectDomainBoundaries() {
        XCTAssertEqual(resolver.resolve(ContextSignal(host: "notclaude.ai")).profile.id, "writing")
        XCTAssertEqual(resolver.resolve(ContextSignal(host: "claude.ai.evil.com")).profile.id, "writing")
    }

    func testBundleBeatsHost() {
        let resolution = resolver.resolve(ContextSignal(bundleID: "com.tinyspeck.slackmacgap",
                                                       host: "chatgpt.com"))
        XCTAssertEqual(resolution.profile.id, "chat")
        XCTAssertEqual(resolution.source, .bundle)
    }

    func testFallbackWithoutWritingProfile() {
        let custom = ContextProfile(id: "custom", name: "Custom", cleanupStyling: "formal",
                                    cleanupStructure: "prose", cleanupContext: "general")
        let local = ContextProfileResolver(profiles: [custom], bundleRules: [], hostRules: [])
        let resolution = local.resolve(ContextSignal())
        XCTAssertEqual(resolution.profile.id, "custom")
        XCTAssertEqual(resolution.source, .fallback)
    }

    func testRulePointingAtMissingProfileIsSkipped() {
        let local = ContextProfileResolver(profiles: [ContextProfile.writing],
                                           bundleRules: [BundleRule("com.example.app", "code")],
                                           hostRules: [])
        let resolution = local.resolve(ContextSignal(bundleID: "com.example.app"))
        XCTAssertEqual(resolution.profile.id, "writing")
        XCTAssertEqual(resolution.source, .fallback)
    }

    func testDuplicateProfileIDsKeepFirst() {
        let first = ContextProfile(id: "code", name: "First", cleanupStyling: "direct",
                                   cleanupStructure: "prose", cleanupContext: "code")
        let second = ContextProfile(id: "CODE", name: "Second", cleanupStyling: "formal",
                                    cleanupStructure: "prose", cleanupContext: "general")
        let local = ContextProfileResolver(profiles: [first, second],
                                           bundleRules: [BundleRule("com.example", "code")],
                                           hostRules: [])
        XCTAssertEqual(local.resolve(ContextSignal(bundleID: "com.example")).profile.name, "First")
        XCTAssertEqual(local.profile(id: " Code ")?.name, "First")
    }

    func testApplyingChangesOnlyProfileFields() {
        var settings = AppSettings.default
        settings.retentionDays = 7
        settings.harperEnabled = true
        settings.displayName = "Ada"
        settings.lineFormat.preferredMax = 50

        let applied = ContextProfile.code.applying(to: settings)
        XCTAssertEqual(applied.cleanupStyling, "direct")
        XCTAssertEqual(applied.cleanupStructure, "prose")
        XCTAssertEqual(applied.cleanupContext, "code")
        XCTAssertTrue(applied.codeSpeakEnabled)
        XCTAssertEqual(applied.retentionDays, 7)
        XCTAssertTrue(applied.harperEnabled)
        XCTAssertEqual(applied.displayName, "Ada")
        XCTAssertEqual(applied.lineFormat.preferredMax, 50)
        XCTAssertFalse(settings.codeSpeakEnabled, "applying must not mutate the input")
    }

    func testResolutionIsDeterministic() {
        let signal = ContextSignal(bundleID: "com.apple.dt.xcode", host: "example.com")
        let first = resolver.resolve(signal)
        for _ in 0..<100 {
            XCTAssertEqual(resolver.resolve(signal), first)
        }
    }

    func testProfileCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(ContextProfile.prompting)
        let decoded = try JSONDecoder().decode(ContextProfile.self, from: encoded)
        XCTAssertEqual(decoded, ContextProfile.prompting)
    }

    func testMatchesOnlyWhenEveryControlledFieldAgrees() {
        for profile in ContextProfile.builtIn {
            XCTAssertTrue(profile.matches(profile.applying(to: AppSettings.default)))
        }

        var settings = ContextProfile.code.applying(to: AppSettings.default)
        settings.displayName = "Ada"
        XCTAssertTrue(ContextProfile.code.matches(settings), "unrelated fields are ignored")

        settings.codeSpeakEnabled = false
        XCTAssertFalse(ContextProfile.code.matches(settings))

        settings = ContextProfile.writing.applying(to: AppSettings.default)
        settings.cleanupContext = "chat"
        XCTAssertFalse(ContextProfile.writing.matches(settings))
        XCTAssertFalse(ContextProfile.chat.matches(settings), "one field does not make a profile")
    }
}
