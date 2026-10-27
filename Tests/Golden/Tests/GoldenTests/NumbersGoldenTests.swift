import Foundation
import SuperflowKernel
import SuperflowTextNumbers
import XCTest

final class NumbersGoldenTests: XCTestCase {
    private func fixture() throws -> CaseFixture {
        try Golden.load("numbers/cases.json")
    }

    func testNumbersCorpus() throws {
        let fixture = try fixture()
        for c in fixture.cases {
            let settings = Golden.stageSettings(c.settings)
            let actual = NumbersStage.transform(c.input, protected: Protected(), settings: settings)
            assertGolden(actual, c.expected, name: c.name)
        }
    }

    func testDocumentedSourceGaps() throws {
        let fixture = try fixture()
        for c in fixture.knownFailures ?? [] {
            let settings = Golden.stageSettings(c.settings)
            let actual = NumbersStage.transform(c.input, protected: Protected(), settings: settings)
            assertGolden(actual, c.expected, name: c.name, knownFailure: c)
        }
    }

    func testIdempotence() throws {
        let fixture = try fixture()
        for c in fixture.cases {
            let settings = Golden.stageSettings(c.settings)
            let once = NumbersStage.transform(c.input, protected: Protected(), settings: settings)
            let twice = NumbersStage.transform(once, protected: Protected(), settings: settings)
            XCTAssertEqual(once, twice, "numbers stage is not idempotent for \(c.name)")
        }
    }

    func testProtectedSpansAreNeverEdited() {
        let settings = Golden.stageSettings()
        let protected = Protected(literals: ["twenty five", "one hundred"])
        XCTAssertEqual(NumbersStage.transform("twenty five apples", protected: protected, settings: settings),
                       "twenty five apples")
        XCTAssertEqual(NumbersStage.transform("one hundred apples", protected: protected, settings: settings),
                       "one hundred apples")
        XCTAssertEqual(NumbersStage.transform("twenty five 200 apples", protected: protected, settings: settings),
                       "twenty five 200 apples")
    }

    func testEmptyAndWhitespaceAreStable() {
        let settings = Golden.stageSettings()
        XCTAssertEqual(NumbersStage.transform("", protected: Protected(), settings: settings), "")
        XCTAssertEqual(NumbersStage.transform("   ", protected: Protected(), settings: settings), "   ")
        XCTAssertEqual(NumbersStage.transform("\n\n", protected: Protected(), settings: settings), "\n\n")
    }

    func testOutputGrowthIsBounded() throws {
        let fixture = try fixture()
        for c in fixture.cases where !c.input.isEmpty {
            let settings = Golden.stageSettings(c.settings)
            let output = NumbersStage.transform(c.input, protected: Protected(), settings: settings)
            XCTAssertLessThanOrEqual(output.count, c.input.count + 16,
                                     "numbers output grew unexpectedly for \(c.name)")
        }
    }

    func testLargeNumberStyleSettingIsHonoured() {
        var settings = Golden.stageSettings()
        settings.numberStyle = .full
        XCTAssertEqual(NumbersStage.transform("two hundred thousand dollars", protected: Protected(),
                                              settings: settings), "$200,000")
        XCTAssertEqual(NumbersStage.transform("five million", protected: Protected(), settings: settings),
                       "5,000,000")
        settings.numberStyle = .abbreviated
        XCTAssertEqual(NumbersStage.transform("five million", protected: Protected(), settings: settings), "5M")
    }
}
