import CoreGraphics
import Foundation
import SuperflowTextInsertion

/// Thread-safe mutable box shared between a fake poster and a fake target, so a
/// simulated paste can change the observed character count or value.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

@MainActor
final class FakeTarget: InsertionTarget {
    let count: Box<Int?>
    /// Nil models a view that exposes no whole value (rich text, web areas).
    let value: Box<String?>?
    var selectedRangeValue: (location: Int, length: Int)?
    var accepts = true
    /// Some views update the value without updating `AXNumberOfCharacters`.
    var updatesCountOnInsert = true
    private(set) var insertedTexts: [String] = []

    init(count: Box<Int?>, value: Box<String?>? = nil,
         selection: (location: Int, length: Int)? = nil) {
        self.count = count
        self.value = value
        selectedRangeValue = selection
    }

    func characterCount() -> Int? { count.value }

    func textValue() -> String? { value?.value }

    func selectedRange() -> (location: Int, length: Int)? { selectedRangeValue }

    func selectionLength() -> Int? { selectedRangeValue?.length }

    func insertSelectedText(_ text: String) -> Bool {
        guard accepts else { return false }
        insertedTexts.append(text)
        if let value {
            let updated = AXValueReplacement.replacing(value: value.value ?? "",
                                                       range: selectedRangeValue, with: text)
            value.value = updated
            if updatesCountOnInsert { count.value = updated.utf16.count }
        } else if updatesCountOnInsert, let current = count.value {
            count.value = current + text.utf16.count
        }
        return true
    }
}

@MainActor
final class FakeFocusInspector: FocusInspecting {
    var focus: InsertionFocus
    var target: (any InsertionTarget)?
    private(set) var preparedPIDs: [pid_t] = []
    private(set) var inspectedPIDs: [pid_t] = []

    init(focus: InsertionFocus, target: (any InsertionTarget)?) {
        self.focus = focus
        self.target = target
    }

    func inspect(pid: pid_t) -> (focus: InsertionFocus, target: (any InsertionTarget)?) {
        inspectedPIDs.append(pid)
        return (focus, target)
    }

    func prepare(pid: pid_t) {
        preparedPIDs.append(pid)
    }
}

actor FakeClipboard: PasteboardAccess {
    private(set) var text: String?
    private(set) var writes = 0
    private(set) var restores = 0
    private(set) var snapshotTexts: [String?] = []
    private var count = 1
    private var storedSnapshot: PasteboardSnapshot? = PasteboardSnapshot(items: [], isComplete: true)
    var failWrites = false

    func setFailWrites(_ value: Bool) { failWrites = value }
    func setSnapshot(_ snapshot: PasteboardSnapshot?) { storedSnapshot = snapshot }

    func changeCount() async -> Int { count }

    func writeTransient(_ text: String) async -> Int? {
        guard !failWrites else { return nil }
        writes += 1
        self.text = text
        count += 1
        return count
    }

    func snapshot(maxBytes: Int) async -> PasteboardSnapshot? {
        snapshotTexts.append(text)
        return storedSnapshot
    }

    func restore(_ snapshot: PasteboardSnapshot, ifChangeCount expected: Int) async {
        guard count == expected else { return }
        restores += 1
        text = nil
        count += 1
    }
}

actor FakePoster: PasteEventPosting {
    nonisolated let isTrusted = true
    private var result: Bool
    private let increments: Bool
    private let box: Box<Int?>?
    private let valueBox: Box<String?>?
    private let pasteValue: String
    private var noChangePosts: Int
    private(set) var posts = 0
    private(set) var taps: [CGEventTapLocation?] = []

    init(result: Bool = true, increments: Bool = true, box: Box<Int?>? = nil,
         valueBox: Box<String?>? = nil, pasteValue: String = "", noChangePosts: Int = 0) {
        self.result = result
        self.increments = increments
        self.box = box
        self.valueBox = valueBox
        self.pasteValue = pasteValue
        self.noChangePosts = noChangePosts
    }

    func setResult(_ value: Bool) { result = value }

    func postPaste(keyCode: CGKeyCode, tap: CGEventTapLocation?) async -> Bool {
        taps.append(tap)
        guard result else { return false }
        posts += 1
        if noChangePosts > 0 {
            noChangePosts -= 1
            return true
        }
        if increments, let box, let current = box.value {
            box.value = current + 1
        }
        if let valueBox {
            valueBox.value = (valueBox.value ?? "") + pasteValue
        }
        return true
    }
}

@MainActor
struct FakeKeyResolver: PasteKeyResolving {
    let code: CGKeyCode
    func pasteKeyCode() -> CGKeyCode { code }
}

actor FakeApps: FrontmostAppProviding {
    private var current: pid_t?
    private let own: pid_t
    private(set) var activated: [pid_t] = []

    init(frontmost: pid_t?, ownPID: pid_t = 999) {
        current = frontmost
        own = ownPID
    }

    func frontmostPID() async -> pid_t? { current }
    func selfPID() async -> pid_t { own }

    func activate(pid: pid_t) async {
        activated.append(pid)
        current = pid
    }

    func setFrontmost(_ pid: pid_t?) async { current = pid }
}

final class InlineRestoreScheduler: RestoreScheduling, @unchecked Sendable {
    private final class Entry: @unchecked Sendable {
        let action: @Sendable () async -> Void
        let cancelled = Box(false)

        init(action: @escaping @Sendable () async -> Void) {
            self.action = action
        }
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var recordedDelays: [Duration] = []

    @discardableResult
    func schedule(after delay: Duration,
                  _ action: @escaping @Sendable () async -> Void) -> RestoreHandle {
        let entry = Entry(action: action)
        lock.withLock {
            entries.append(entry)
            recordedDelays.append(delay)
        }
        return RestoreHandle { entry.cancelled.value = true }
    }

    var pendingCount: Int { lock.withLock { entries.count } }
    var delays: [Duration] { lock.withLock { recordedDelays } }

    func runPending() async {
        let pending = lock.withLock { () -> [Entry] in
            let copy = entries
            entries.removeAll()
            return copy
        }
        for entry in pending where !entry.cancelled.value {
            await entry.action()
        }
    }
}

/// Records whether two insertions ever mutate the pasteboard at the same time.
actor ConcurrencyTrackingClipboard: PasteboardAccess {
    private(set) var maxConcurrentWrites = 0
    private var inFlight = 0
    private var count = 1

    func changeCount() async -> Int { count }

    func writeTransient(_ text: String) async -> Int? {
        inFlight += 1
        maxConcurrentWrites = max(maxConcurrentWrites, inFlight)
        // Yield so a second, unguarded insertion can enter this method.
        try? await Task.sleep(for: .milliseconds(20))
        inFlight -= 1
        count += 1
        return count
    }

    func snapshot(maxBytes: Int) async -> PasteboardSnapshot? { nil }

    func restore(_ snapshot: PasteboardSnapshot, ifChangeCount expected: Int) async {}
}
