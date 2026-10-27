import Foundation
import SuperflowKernel
import SuperflowPorts

/// Neutral lint shape shared by the FFI shim and the mapper. Offsets are UTF-16,
/// matching GrammarLint and NSAttributedString.
public struct HarperLint: Sendable, Equatable {
    public var utf16Start: Int
    public var utf16Length: Int
    public var kind: String
    public var suggestion: String?
    public var message: String

    public init(utf16Start: Int, utf16Length: Int, kind: String,
                suggestion: String?, message: String = "") {
        self.utf16Start = utf16Start
        self.utf16Length = utf16Length
        self.kind = kind
        self.suggestion = suggestion
        self.message = message
    }
}

public struct HarperConfig: Sendable, Equatable {
    public var enabled: Bool
    public var allowedKinds: Set<String>
    public var customWords: [String]
    public var maxLints: Int

    public init(enabled: Bool = false,
                allowedKinds: Set<String> = HarperConfig.defaultAllowedKinds,
                customWords: [String] = [], maxLints: Int = 50) {
        self.enabled = enabled
        self.allowedKinds = allowedKinds
        self.customWords = customWords
        self.maxLints = max(0, maxLints)
    }

    /// Only categories measured at 98 percent precision or better ship on.
    /// `aOrAn` is a rule-level classification: harper-core 2.13 reports its
    /// indefinite-article rule as `Miscellaneous`, which is otherwise ignored.
    public static let defaultAllowedKinds: Set<String> = [
        "Spelling", "Agreement", "Repetition", "aOrAn",
    ]

    public func allows(kind: String) -> Bool {
        guard !allowedKinds.isEmpty else { return true }
        let key = HarperMapper.canonicalKind(kind)
        return allowedKinds.contains { HarperMapper.canonicalKind($0) == key }
    }
}

public enum HarperMapper {
    /// Canonicalizes Harper's lint kind names and our rule-level aliases.
    /// harper-core 2.13 uses `Repetition` for repeated words and reports the
    /// indefinite-article rule as `Miscellaneous`; the adapter reclassifies
    /// that one rule as `aOrAn` from its message before the gate sees it.
    public static func canonicalKind(_ kind: String) -> String {
        let key = kind.lowercased().filter { $0.isLetter || $0.isNumber }
        switch key {
        case "repetition", "repeatedword", "repeatedwords": return "repetition"
        case "aan", "ana", "aoran": return "aoran"
        case "spelling": return "spelling"
        case "agreement": return "agreement"
        default: return key
        }
    }

    /// Maps the article rule's message to `aOrAn` so the gate can allow it
    /// without allowing every `Miscellaneous` lint.
    public static func classify(kind: String, message: String) -> String {
        if kind == "Miscellaneous",
           message.localizedCaseInsensitiveContains("incorrect indefinite article") {
            return "aOrAn"
        }
        return kind
    }

    public static func map(_ lints: [HarperLint], config: HarperConfig,
                           utf16Length: Int) -> [GrammarLint] {
        guard config.enabled else { return [] }
        var output: [GrammarLint] = []
        for lint in lints {
            guard lint.utf16Start >= 0, lint.utf16Length >= 0 else { continue }
            guard lint.utf16Start + lint.utf16Length <= utf16Length else { continue }
            guard config.allows(kind: lint.kind) else { continue }
            output.append(GrammarLint(utf16Start: lint.utf16Start, utf16Length: lint.utf16Length,
                                      kind: lint.kind, suggestion: lint.suggestion))
            if output.count >= config.maxLints { break }
        }
        return output
    }
}
