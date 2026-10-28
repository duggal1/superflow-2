import AppKit
import Foundation

/// A Sendable snapshot of every pasteboard item and type. `isComplete` is false
/// when any type could not be read or the board exceeded the size cap; an
/// incomplete snapshot is never restored.
public struct PasteboardSnapshot: Sendable {
    public struct Entry: Sendable, Equatable {
        public let type: String
        public let data: Data
        public init(type: String, data: Data) {
            self.type = type
            self.data = data
        }
    }

    public let items: [[Entry]]
    public let isComplete: Bool
    public let changeCount: Int

    public init(pasteboard: NSPasteboard, maxBytes: Int = 64 * 1024 * 1024) {
        changeCount = pasteboard.changeCount
        var total = 0
        var complete = true
        var captured: [[Entry]] = []

        for item in pasteboard.pasteboardItems ?? [] {
            var entries: [Entry] = []
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    complete = false
                    continue
                }
                total += data.count
                if total > maxBytes {
                    items = []
                    isComplete = false
                    return
                }
                entries.append(Entry(type: type.rawValue, data: data))
            }
            captured.append(entries)
        }
        items = captured
        isComplete = complete
    }

    public init(items: [[Entry]], isComplete: Bool, changeCount: Int = 0) {
        self.items = items
        self.isComplete = isComplete
        self.changeCount = changeCount
    }

    /// Restores only when no other process wrote since `expected`. Never clears
    /// a newer clipboard.
    public func restore(into pasteboard: NSPasteboard, onlyIfChangeCount expected: Int) {
        guard isComplete, pasteboard.changeCount == expected else { return }
        pasteboard.clearContents()
        let objects = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for entry in entries {
                item.setData(entry.data, forType: NSPasteboard.PasteboardType(entry.type))
            }
            return item
        }
        if !objects.isEmpty { pasteboard.writeObjects(objects) }
    }
}
