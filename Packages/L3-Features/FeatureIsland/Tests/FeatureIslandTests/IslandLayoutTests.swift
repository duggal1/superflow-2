import CoreGraphics
import XCTest
@testable import SuperflowFeatureIsland

final class IslandLayoutTests: XCTestCase {
    private let transcript = IslandTranscript(text: "Hello", bundleID: nil, appName: nil,
                                              date: Date(timeIntervalSince1970: 0), words: 1)
    private let notch = NotchGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                      safeTop: 32, leftWidth: 620, rightWidth: 620, scale: 2)
    private let plain = NotchGeometry(frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                                      safeTop: 0, leftWidth: nil, rightWidth: nil, scale: 2)

    private var phases: [IslandPhase] {
        [.idle, .hover, .listening, .processing, .landed(words: 2),
         .failed(transcript), .recent(transcript), .recent(nil)]
    }

    func testEveryBoxFitsTheCanvas() {
        for geometry in [notch, plain] {
            for phase in phases {
                let size = IslandLayout.box(phase, geometry).frameSize
                XCTAssertLessThanOrEqual(size.width, IslandLayout.canvas.width, "\(phase)")
                XCTAssertLessThanOrEqual(size.height, IslandLayout.canvas.height, "\(phase)")
                XCTAssertGreaterThan(size.width, 0, "\(phase)")
                XCTAssertGreaterThan(size.height, 0, "\(phase)")
            }
        }
    }

    func testEveryHitRectFitsTheCanvas() {
        let canvas = CGRect(origin: .zero, size: IslandLayout.canvas)
        for geometry in [notch, plain] {
            for phase in phases {
                XCTAssertTrue(canvas.contains(IslandLayout.hitRect(phase, geometry)), "\(phase)")
            }
        }
    }

    func testIdleOnANotchIsTheNotchRect() {
        let rect = IslandLayout.hitRect(.idle, notch)
        XCTAssertEqual(rect.size, notch.notch)
        XCTAssertEqual(rect.midX, IslandLayout.canvas.width / 2)
        XCTAssertEqual(rect.minY, 0)
    }

    func testIdleOnADisplayWithoutANotchIsClickThrough() {
        XCTAssertEqual(IslandLayout.hitRect(.idle, plain), .zero)
    }

    func testHoverGrowsByEightByFour() {
        let body = IslandLayout.box(.hover, notch).body
        XCTAssertEqual(body.width, notch.notch.width + 8)
        XCTAssertEqual(body.height, notch.notch.height + 4)
        XCTAssertEqual(IslandLayout.box(.hover, notch).top, 6)
        XCTAssertEqual(IslandLayout.box(.hover, notch).bottom, IslandLayout.restBottom)
    }

    func testCardBodyHeightIsBandPlusSixty() {
        for geometry in [notch, plain] {
            XCTAssertEqual(IslandLayout.box(.failed(transcript), geometry).body.height,
                           geometry.band + 60)
            XCTAssertEqual(IslandLayout.box(.recent(nil), geometry).body.height,
                           geometry.band + 60)
        }
    }

    func testWingsAreTheNotchPlusTwoWings() {
        let body = IslandLayout.box(.listening, notch).body
        XCTAssertEqual(body.width, notch.notch.width + 112)
        XCTAssertEqual(body.height, notch.band)
        XCTAssertEqual(IslandLayout.box(.landed(words: 1), notch), IslandLayout.box(.listening, notch))
    }

    func testIdleOnADisplayWithoutANotchIsInvisible() {
        XCTAssertEqual(IslandLayout.box(.idle, plain).opacity, 0)
        XCTAssertEqual(IslandLayout.box(.idle, notch).opacity, 1)
    }

    func testMotionCurveDependsOnTheKindOfMove() {
        XCTAssertEqual(IslandLayout.animation(from: .idle, to: .listening, reduceMotion: false),
                       .smooth(duration: 0.44))
        XCTAssertEqual(IslandLayout.animation(from: .listening, to: .idle, reduceMotion: false),
                       .smooth(duration: 0.32))
        XCTAssertEqual(IslandLayout.animation(from: .listening, to: .processing, reduceMotion: false),
                       .snappy(duration: 0.20))
        XCTAssertEqual(IslandLayout.animation(from: .listening, to: .failed(transcript),
                                              reduceMotion: false),
                       .smooth(duration: 0.38))
        XCTAssertEqual(IslandLayout.animation(from: .idle, to: .hover, reduceMotion: false),
                       .snappy(duration: 0.20))
        XCTAssertEqual(IslandLayout.animation(from: .idle, to: .listening, reduceMotion: true),
                       .easeOut(duration: 0.15))
    }
}
