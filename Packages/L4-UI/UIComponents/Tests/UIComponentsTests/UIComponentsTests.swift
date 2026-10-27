import CoreGraphics
import SuperflowDesignSystem
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

    func testContributionColumnsAreSevenDayWeeks() {
        let days = (0..<16).map { ContributionGridDay(day: String(format: "2026-01-%02d", $0 + 1),
                                                       words: $0, level: $0 % 5, isFuture: false) }
        let columns = ContributionLayout.columns(days)
        XCTAssertEqual(columns.count, 3)
        XCTAssertEqual(columns[0].count, 7)
        XCTAssertEqual(columns[1].count, 7)
        XCTAssertEqual(columns[2].count, 2)
        XCTAssertEqual(ContributionLayout.columns([]).count, 0)
    }

    func testMonthLabelsChangeOncePerMonth() {
        let days = ["2026-01-01", "2026-01-20", "2026-02-02", "2026-02-10"]
            .map { ContributionGridDay(day: $0, words: 1, level: 1, isFuture: false) }
        let labels = ContributionLayout.monthLabels(days)
        XCTAssertEqual(labels.count, 2)
        XCTAssertEqual(labels.first, "Jan")
        XCTAssertEqual(labels.last, "Feb")
    }

    func testWaveformPadsAndNormalizes() {
        let bars = Waveform.bars(from: [0.5, 1.0], count: 4)
        XCTAssertEqual(bars.count, 4)
        XCTAssertEqual(bars[0], 0.06, accuracy: 0.001)
        XCTAssertEqual(bars[2], 0.5, accuracy: 0.001)
        XCTAssertEqual(bars[3], 1.0, accuracy: 0.001)
        XCTAssertEqual(Waveform.bars(from: [], count: 3), [0.08, 0.08, 0.08])
    }

    func testWaveformRMS() {
        XCTAssertEqual(Waveform.rms([0.5, -0.5]), 0.5, accuracy: 0.0001)
        XCTAssertEqual(Waveform.rms([]), 0)
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

    func testButtonHeightsMatchTheControlScale() {
        XCTAssertEqual(AppButtonStyle(kind: .secondary).height, 28)
        XCTAssertEqual(AppButtonStyle(kind: .secondary, height: ControlHeight.small).height, 24)
        XCTAssertEqual(AppButtonStyle(kind: .primary, height: ControlHeight.large).height, 32)
    }

    /// The pixel full stop stays an odd, symmetric block.
    func testPixelStopSnapsToAnOddCellCount() {
        XCTAssertEqual(PixelStop(cells: 5).count, 5)
        XCTAssertEqual(PixelStop(cells: 6).count, 7)
        XCTAssertEqual(PixelStop(cells: 11).count, 11)
    }

    func testContributionGridHasFiveLevels() {
        XCTAssertEqual(ContributionLayout.levelCount, 5)
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
