import Foundation
import SuperflowKernel
import SuperflowPorts
#if canImport(HarperFFI)
import HarperFFI
#endif

public enum HarperAvailability {
    /// True only when the real Rust backend is linked. The C stub also imports
    /// as `HarperFFI`, so the check asks the backend itself.
    public static var isCompiledIn: Bool {
        #if canImport(HarperFFI)
        return harper_linter_is_stub() == 0
        #else
        return false
        #endif
    }

    public static var explanation: String {
        if isCompiledIn { return "Harper is compiled in." }
        return "Harper is not compiled in. Build the Rust XCFramework with `make harper` and rebuild. "
            + "The deterministic Tier 0 path stays active until then."
    }
}

public protocol HarperLinting: Sendable {
    func lint(_ text: String, customWords: [String]) async -> [HarperLint]
}

public struct UnavailableHarperLinter: HarperLinting {
    public init() {}
    public func lint(_ text: String, customWords: [String]) async -> [HarperLint] { [] }
}

public struct HarperChecker: GrammarChecker {
    private let linter: any HarperLinting
    private let config: HarperConfig

    public init(linter: any HarperLinting = UnavailableHarperLinter(),
                config: HarperConfig = HarperConfig()) {
        self.linter = linter
        self.config = config
    }

    public func lint(_ text: String, customWords: [String]) async -> [GrammarLint] {
        guard config.enabled else { return [] }
        let words = Array(Set(customWords + config.customWords)).sorted()
        let raw = await linter.lint(text, customWords: words)
        let classified = raw.map { lint in
            var copy = lint
            copy.kind = HarperMapper.classify(kind: lint.kind, message: lint.message)
            return copy
        }
        return HarperMapper.map(classified, config: config, utf16Length: text.utf16.count)
    }
}
