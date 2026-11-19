import XCTest
import SuperflowFeatureIntelligence
import SuperflowMeetingIntelligence

@MainActor
final class HeadlessIntelligencePromptTests: XCTestCase {
    func testSelectorEnumeratesEverySourcePromptWithoutDroppingAny() {
        let themes = IntelligenceTheme.allFromSource()
        XCTAssertEqual(themes.count, MeetingMode.allCases.count)
        for mode in MeetingMode.allCases {
            XCTAssertTrue(themes.contains { $0.id == mode.rawValue },
                          "Missing \(mode.rawValue) from selector")
        }
        XCTAssertEqual(themes.map(\.id), MeetingMode.allCases.map(\.rawValue))
    }

    func testKnownThemesUseRealNames() {
        let labels = Dictionary(uniqueKeysWithValues:
            IntelligenceTheme.allFromSource().map { ($0.id, $0.label) })
        XCTAssertEqual(labels["normal"], "General Meeting")
        XCTAssertEqual(labels["codingInterview"], "Coding Interview")
        XCTAssertEqual(labels["sales"], "Sales Call")
        XCTAssertEqual(labels["custom"], "Personal / Custom")
    }

    func testOneSharedMessyPromptBlockIsUsedEverywhere() {
        let block = IntelligencePrompts.messyTranscriptBlock
        XCTAssertTrue(block.contains("cooper netties"))
        let tasks = [IntelligencePrompts.askTask("q"),
                     IntelligencePrompts.meetingDetectionTask(),
                     IntelligencePrompts.suggestionsTask()]
        for task in tasks {
            XCTAssertEqual(task.components(separatedBy: block).count - 1, 1)
        }
    }

    func testThemeSelectionPersistsAcrossModelInstances() {
        let defaults = UserDefaults(suiteName: "intelligence.prompts.\(UUID().uuidString)")!
        let service = HeadlessAnswerClient()
        let store = HeadlessHistoryClient(items: [])
        let first = IntelligenceIslandModel(answerService: service, historyStore: store,
                                            copy: { _ in }, defaults: defaults)
        let sales = try? XCTUnwrap(IntelligenceTheme.allFromSource().first { $0.id == "sales" })
        first.selectTheme(sales!)
        XCTAssertEqual(defaults.string(forKey: "intelligence.mode"), "sales")
        let second = IntelligenceIslandModel(answerService: service, historyStore: store,
                                             copy: { _ in }, defaults: defaults)
        XCTAssertEqual(second.selectedTheme.id, "sales")
    }

    func testScreenContextDefaultsOnAndPersists() {
        let defaults = UserDefaults(suiteName: "intelligence.screen.\(UUID().uuidString)")!
        let model = IntelligenceIslandModel(answerService: HeadlessAnswerClient(),
                                            historyStore: HeadlessHistoryClient(items: []),
                                            copy: { _ in }, defaults: defaults)
        XCTAssertTrue(model.screenAware)
        model.setScreenAware(false)
        XCTAssertFalse(defaults.bool(forKey: "intelligence.screenAware"))
    }
}
