import Foundation
import SuperflowKernel
import SuperflowPorts

#if canImport(HarperFFI)
import HarperFFI

/// Owns one C linter pointer. A class deinit is the only safe place to free a
/// non-Sendable OpaquePointer under Swift 6. The handle is never used by two
/// tasks at once: `HarperHandlePool` hands it out exclusively.
private final class HarperLinterHandle: @unchecked Sendable {
    let pointer: OpaquePointer
    private var words: Set<String> = []

    init?(dialect: String) {
        guard let pointer = harper_linter_create(dialect) else { return nil }
        self.pointer = pointer
    }

    deinit {
        harper_linter_free(pointer)
    }

    /// Only called while this handle is checked out, so the dictionary mutation
    /// cannot race a lint on the same pointer.
    func prepare(words newWords: [String]) {
        for word in newWords where !word.isEmpty && !words.contains(word) {
            harper_linter_add_word(pointer, word)
            words.insert(word)
        }
    }
}

/// Small pool of independent Harper handles. Harper keeps dictionary/group
/// state per handle, so separate handles are safe to lint different slices in
/// parallel. The pool caps creation at the number of chunks we ever plan.
private actor HarperHandlePool {
    private let dialect: String
    private let limit: Int
    private var idle: [HarperLinterHandle] = []
    private var created = 0
    private var waiters: [CheckedContinuation<HarperLinterHandle?, Never>] = []

    init(dialect: String, limit: Int) {
        self.dialect = dialect
        self.limit = max(1, limit)
    }

    func acquire() async -> HarperLinterHandle? {
        if let handle = idle.popLast() { return handle }
        if created < limit {
            created += 1
            guard let handle = HarperLinterHandle(dialect: dialect) else {
                created -= 1
                return nil
            }
            return handle
        }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func release(_ handle: HarperLinterHandle) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: handle)
        } else {
            idle.append(handle)
        }
    }
}

/// Wraps the C ABI defined by Rust/harper-ffi. Long text is split at sentence
/// boundaries and linted on up to three cached handles; short dictation still
/// uses one handle and no task-group overhead.
public final class HarperFFILinter: HarperLinting, @unchecked Sendable {
    private let pool: HarperHandlePool

    public init(dialect: String = "american") {
        pool = HarperHandlePool(dialect: dialect, limit: HarperChunkPlanner.maximumChunks)
    }

    public func lint(_ text: String, customWords: [String]) async -> [HarperLint] {
        let chunks = HarperChunkPlanner.plan(text)
        guard !chunks.isEmpty else { return [] }
        if chunks.count == 1 {
            return await lint(chunk: chunks[0], text: text, customWords: customWords)
        }
        return await withTaskGroup(of: [HarperLint].self) { group in
            for chunk in chunks {
                group.addTask { [self] in
                    await self.lint(chunk: chunk, text: text, customWords: customWords)
                }
            }
            var merged: [HarperLint] = []
            for await lints in group { merged.append(contentsOf: lints) }
            return HarperLintMerge.merge(merged)
        }
    }

    private func lint(chunk: HarperChunk, text: String, customWords: [String]) async -> [HarperLint] {
        guard let handle = await pool.acquire() else { return [] }
        let lints = Self.lint(chunk: chunk, text: text, handle: handle, customWords: customWords)
        await pool.release(handle)
        return lints
    }

    private static func lint(chunk: HarperChunk, text: String, handle: HarperLinterHandle,
                             customWords: [String]) -> [HarperLint] {
        handle.prepare(words: customWords)
        guard chunk.utf16Offset >= 0, chunk.utf16Length >= 0,
              chunk.utf16Offset + chunk.utf16Length <= text.utf16.count
        else { return [] }
        let range = NSRange(location: chunk.utf16Offset, length: chunk.utf16Length)
        guard let swiftRange = Range(range, in: text) else { return [] }
        let slice = String(text[swiftRange])

        var raw: UnsafeMutablePointer<HarperLintC>?
        var count: Int32 = 0
        let status = slice.withCString { pointer in
            harper_linter_lint(handle.pointer, pointer, Int32(slice.utf8.count), &raw, &count)
        }
        guard status == 0, let raw, count > 0 else { return [] }
        defer { harper_lints_free(raw, count) }

        let lints = (0..<Int(count)).map { index in
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
        return HarperLintMerge.shift(lints, by: chunk.utf16Offset)
    }
}
#else
/// Fallback when the C module is somehow absent (for example a platform where
/// C interop is unavailable). Keeps the public surface stable.
public final class HarperFFILinter: HarperLinting, @unchecked Sendable {
    public init(dialect: String = "american") {}
    public func lint(_ text: String, customWords: [String]) async -> [HarperLint] { [] }
}
#endif
