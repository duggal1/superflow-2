import CoreGraphics
import SuperflowDesignSystem
import SuperflowKernel
import XCTest
@testable import SuperflowUIComponents

final class UIComponentsTests: XCTestCase {
    func testToastQueueIsFIFOAndBounded() {
        var queue = ToastQueue(capacity: 2)
        queue.enqueue(ToastMessage(text: "one"))
        queue.enqueue(ToastMessage(text: "two"))
        queue.enqueue(ToastMessage(text: "three"))
        queue.enqueue(ToastMessage(text: "four"))
        XCTAssertEqual(queue.current?.text, "one")
        XCTAssertEqual(queue.pending.map(\.text), ["three", "four"])
        XCTAssertEqual(queue.dismiss()?.text, "one")
        XCTAssertEqual(queue.current?.text, "three")
    }

    func testToastDismissByIdRemovesPending() {
        var queue = ToastQueue()
        let first = ToastMessage(text: "first")
        let second = ToastMessage(text: "second")
        queue.enqueue(first)
        queue.enqueue(second)
        queue.dismiss(id: second.id)
        XCTAssertEqual(queue.pending, [])
        queue.dismiss(id: first.id)
        XCTAssertNil(queue.current)
    }

    func testToastActionDurationIsLonger() {
        XCTAssertEqual(ToastMessage(text: "x").duration, 4)
        XCTAssertEqual(ToastMessage(text: "x", style: .error).duration, 6)
        XCTAssertEqual(ToastMessage(text: "x", actionTitle: "Undo").duration, 6)
    }

    func testWaveformNormalizesTheDecibelWindow() {
        XCTAssertEqual(WaveformEngine.normalized(rms: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(WaveformEngine.normalized(rms: 1e-6), 0, accuracy: 0.0001)
        let mid = WaveformEngine.normalized(rms: 0.01)
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 1)
    }

    func testWaveformPushClampsItsInput() {
        let engine = WaveformEngine()
        engine.push(level: 4)
        engine.push(level: -1)
        engine.seed([0.2, 0.4, 0.6])
        let frame = engine.frame(now: 1, phase: .idle, count: 8, flow: .outward, calm: true)
        XCTAssertEqual(frame.count, 8)
        XCTAssertTrue(frame.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testPixelRendererIsDeterministic() {
        let config = PixelFieldConfig()
        let first = PixelRenderer.cells(size: CGSize(width: 160, height: 96), config: config)
        let second = PixelRenderer.cells(size: CGSize(width: 160, height: 96), config: config)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(first.allSatisfy { (0...2).contains($0.tone) })
        XCTAssertEqual(first.count, 10 * 6)
    }

    func testPixelRendererClearsTextHole() {
        var config = PixelFieldConfig()
        config.disc = PixelDisc(cells: 0, grow: 0)
        let clear = [CGRect(x: 16, y: 16, width: 32, height: 16)]
        let cells = PixelRenderer.cells(size: CGSize(width: 160, height: 96), clear: clear,
                                        config: config)
        let hole = cells.filter { $0.column == 2 && $0.row == 1 }
        XCTAssertEqual(hole.count, 1)
        XCTAssertEqual(hole.first?.tone, 0)
    }

    func testPixelRendererCollapsesToNothing() {
        var config = PixelFieldConfig()
        config.collapse = 1
        config.disc = PixelDisc(cells: 0, grow: 0)
        let cells = PixelRenderer.cells(size: CGSize(width: 160, height: 96), config: config)
        XCTAssertTrue(cells.isEmpty)
    }

    func testPixelDiscGrowsBack() {
        var config = PixelFieldConfig()
        config.collapse = 1
        config.disc = PixelDisc(cells: 5, grow: 1)
        let cells = PixelRenderer.cells(size: CGSize(width: 160, height: 96), config: config)
        XCTAssertFalse(cells.isEmpty)
        XCTAssertTrue(cells.allSatisfy { (0...2).contains($0.tone) })
    }

    func testPixelPaletteUsesThreeTones() {
        XCTAssertEqual(PixelPalette.blue.hex(tone: 0, dark: true), 0x0A0A0A)
        XCTAssertEqual(PixelPalette.blue.hex(tone: 1, dark: true), 0x1E3A8A)
        XCTAssertEqual(PixelPalette.blue.hex(tone: 2, dark: true), 0x2563EB)
        XCTAssertNil(PixelPalette.blue.hex(tone: 3, dark: true))
    }

    /// Text buttons are 24 or 28 tall. 32 belongs to the search field and BarIconButton.
    func testTextButtonsAreTwentyFourOrTwentyEightTall() {
        XCTAssertEqual(AppButtonStyle(kind: .secondary).height, ControlHeight.regular)
        XCTAssertEqual(AppButtonStyle(kind: .secondary, height: ControlHeight.small).height,
                       ControlHeight.small)
        XCTAssertEqual(AppButtonStyle(kind: .primary, height: ControlHeight.regular).height,
                       ControlHeight.regular)
    }

    /// Blue 800 is removed from every control.
    func testAccentPressedIsBlueSevenHundred() {
        XCTAssertEqual(Tok.Hex.accentPressed, 0x1D4ED8)
    }

    /// The year is twelve calendars, and the levels are quartiles of the days that have words.
    func testActivityLevelsAreQuartilesOfNonZeroDays() {
        XCTAssertEqual(ActivityLevel.assign([0, 0, 0]), [0, 0, 0])
        XCTAssertEqual(ActivityLevel.assign([5]), [1])
        let levels = ActivityLevel.assign([0, 1, 10, 100, 1_000])
        XCTAssertEqual(levels.first, 0)
        XCTAssertTrue(levels.dropFirst().allSatisfy { (1...4).contains($0) })
        XCTAssertTrue(levels.allSatisfy { $0 <= 4 })
    }

    /// Every day lands in exactly one month block, once, and every block starts at column 0.
    func testActivityBlocksHoldEveryDayExactlyOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let days = (0..<300).compactMap { offset -> ActivityDay? in
            calendar.date(byAdding: .day, value: offset, to: start)
                .map { ActivityDay(date: $0, words: offset % 40, level: offset % 5) }
        }

        let blocks = ActivityBlock.make(days)
        XCTAssertEqual(blocks.reduce(0) { $0 + $1.cells.count }, days.count)
        XCTAssertEqual(Set(blocks.flatMap { $0.cells.map { $0.day.id } }).count, days.count)
        for block in blocks {
            XCTAssertGreaterThanOrEqual(block.cols, 1)
            XCTAssertEqual(block.cells.map(\.col).min(), 0)
            XCTAssertTrue(block.cells.allSatisfy { (0...6).contains($0.row) })
            XCTAssertTrue(block.cells.allSatisfy { (0..<block.cols).contains($0.col) })
        }
    }

    /// The pixel full stop stays an odd, symmetric block.
    @MainActor
    func testPixelStopSnapsToAnOddCellCount() {
        XCTAssertEqual(PixelStop(cells: 5).count, 5)
        XCTAssertEqual(PixelStop(cells: 6).count, 7)
        XCTAssertEqual(PixelStop(cells: 11).count, 11)
    }

    @MainActor
    func testToastDismissReleasesItsActionClosure() {
        let center = ToastCenter()
        center.show("Deleted", actionTitle: "Undo") {}
        XCTAssertEqual(center.pendingActionCount, 1)
        center.dismiss()
        XCTAssertEqual(center.pendingActionCount, 0)
    }

    @MainActor
    func testCommandPaletteFiltersAndWrapsSelection() {
        var ran: [String] = []
        let model = CommandPaletteModel(items: [
            CommandItem(id: "start", title: "Start dictation", subtitle: "Hold Fn") {
                ran.append("start")
            },
            CommandItem(id: "history", title: "Open history", subtitle: "Transcripts") {
                ran.append("history")
            },
            CommandItem(id: "settings", title: "Open settings") {
                ran.append("settings")
            },
        ])

        XCTAssertEqual(model.filteredItems.count, 3)
        XCTAssertEqual(model.selectedItem?.id, "start")

        model.query = "HIST"
        XCTAssertEqual(model.filteredItems.map(\.id), ["history"])
        XCTAssertEqual(model.selectedItem?.id, "history")

        model.query = "open"
        XCTAssertEqual(model.filteredItems.map(\.id), ["history", "settings"])
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedItem?.id, "settings")
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedItem?.id, "history", "selection wraps")
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedItem?.id, "settings", "selection wraps backwards")

        XCTAssertTrue(model.activateSelection())
        XCTAssertEqual(ran, ["settings"])
        model.reset()
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.selectedItem?.id, "start")
    }

    @MainActor
    func testEverySoundCueIsBundled() {
        for cue in SoundCue.allCases {
            XCTAssertNotNil(Sounds.url(for: cue), "missing resource for \(cue.rawValue)")
        }
    }

    func testTransferTextShowsMeasuredRateAndBytes() {
        let snapshot = TransferSnapshot(label: "s1-mini", receivedBytes: 120_000_000,
                                        totalBytes: 484_219_808, bytesPerSecond: 24_600_000)
        XCTAssertEqual(TransferText.progress(0.25, transfer: snapshot),
                       "25% · 25 MB/s · 120 MB of 484 MB")
        XCTAssertFalse(TransferText.progress(0.25, transfer: nil).contains("MB/s"))
        XCTAssertEqual(TransferText.bytes(1_500_000_000), "1.50 GB")
        XCTAssertEqual(TransferText.rate(0), "")
    }

    @MainActor
    func testCommandPaletteEmptyQueryAndNoMatches() {
        let model = CommandPaletteModel(items: [
            CommandItem(id: "a", title: "Alpha") {},
        ])
        model.query = "   "
        XCTAssertEqual(model.filteredItems.count, 1)
        model.query = "zzz"
        XCTAssertTrue(model.isEmpty)
        XCTAssertNil(model.selectedItem)
        XCTAssertFalse(model.activateSelection())
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectionIndex, 0)
    }
}
