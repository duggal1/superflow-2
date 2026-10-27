import Foundation
import SuperflowKernel
import SuperflowPorts

#if canImport(HarperFFI)
import HarperFFI

/// Owns the C linter pointer. A class deinit is the only safe place to free a
/// non-Sendable OpaquePointer under Swift 6, and this class never escapes the
/// actor that creates it.
private final class HarperLinterHandle: @unchecked Sendable {
    let pointer: OpaquePointer

    init?(dialect: String) {
        guard let pointer = harper_linter_create(dialect) else { return nil }
        self.pointer = pointer
    }

    deinit {
        harper_linter_free(pointer)
    }
}

/// Wraps the C ABI defined by Rust/harper-ffi. The actor serializes access to
/// the cached linter (Harper's dictionary rebuild is expensive) and copies every
/// lint out of the C array before freeing it.
public actor HarperFFILinter: HarperLinting {
    private let dialect: String
    private var handle: HarperLinterHandle?
    private var words: Set<String> = []

    public init(dialect: String = "american") {
        self.dialect = dialect
    }

    public func lint(_ text: String, customWords: [String]) async -> [HarperLint] {
        if handle == nil {
            handle = HarperLinterHandle(dialect: dialect)
        }
        guard let handle else { return [] }
        for word in customWords where !word.isEmpty && !words.contains(word) {
            harper_linter_add_word(handle.pointer, word)
            words.insert(word)
        }

        var raw: UnsafeMutablePointer<HarperLintC>?
        var count: Int32 = 0
        let status = text.withCString { pointer in
            harper_linter_lint(handle.pointer, pointer, Int32(text.utf8.count), &raw, &count)
        }
        guard status == 0, let raw, count > 0 else { return [] }
        defer { harper_lints_free(raw, count) }

        return (0..<Int(count)).map { index in
            let lint = raw[index]
            let kind = lint.kind.map { String(cString: $0) } ?? "Grammar"
            let message = lint.message.map { String(cString: $0) } ?? ""
            let suggestion: String?
            if lint.has_suggestion == 1, let pointer = lint.suggestion {
                suggestion = String(cString: pointer)
            } else {
                suggestion = nil
            }
            return HarperLint(utf16Start: Int(lint.start),
                              utf16Length: Int(lint.length),
                              kind: kind,
                              suggestion: suggestion,
                              message: message)
        }
    }
}
#else
/// Fallback when the C module is somehow absent (for example a platform where
/// C interop is unavailable). Keeps the public surface stable.
public actor HarperFFILinter: HarperLinting {
    public init(dialect: String = "american") {}
    public func lint(_ text: String, customWords: [String]) async -> [HarperLint] { [] }
}
#endif
