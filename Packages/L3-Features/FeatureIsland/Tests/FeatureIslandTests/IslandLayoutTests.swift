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

    private let undo = IslandUndo(text: "Hello", bundleID: nil, appName: nil)
    private let notice = IslandNotice(kind: .milestone, title: "1,000 words.", detail: "Kept.")

    private var phases: [IslandPhase] {
        [.idle, .hover, .listening, .handsFree, .meeting, .meetingPanel, .processing,
         .landed(words: 2), .undo(undo), .notice(notice), .history,
         .failed(transcript), .recent(transcript), .recent(nil)]
    }

    func testEveryBoxFitsTheCanvas() {
        let wideNotch = NotchGeometry(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                      safeTop: 38, leftWidth: 704, rightWidth: 704, scale: 2)
        for geometry in [notch, wideNotch, plain] {
            for phase in phases {
                for hint in [false, true] {
                    for live in [false, true] {
                        let size = IslandLayout.box(phase, geometry, hint: hint, live: live).frameSize
                        XCTAssertLessThanOrEqual(size.width, IslandLayout.canvas.width, "\(phase)")
                        XCTAssertLessThanOrEqual(size.height, IslandLayout.canvas.height, "\(phase)")
                        XCTAssertGreaterThan(size.width, 0, "\(phase)")
                        XCTAssertGreaterThan(size.height, 0, "\(phase)")
                    }
                }
            }
        }
    }

    func testOnlyTheVisibleSilhouetteReceivesClicks() {
        for phase in phases {
            let box = IslandLayout.box(phase, notch, live: true,
                                       prefs: IslandPrefs(alwaysOn: true, liveText: true))
            XCTAssertTrue(IslandLayout.contains(CGPoint(x: IslandLayout.canvas.width / 2,
                                                        y: box.body.height / 2), box: box))
            XCTAssertFalse(IslandLayout.contains(CGPoint(x: 0, y: box.body.height / 2), box: box))
            XCTAssertFalse(IslandLayout.contains(CGPoint(x: IslandLayout.canvas.width / 2,
                                                         y: box.body.height + 1), box: box))
            let left = (IslandLayout.canvas.width - box.frameSize.width) / 2
            XCTAssertFalse(IslandLayout.contains(CGPoint(x: left + 1, y: box.body.height - 1),
                                                 box: box))
        }
        XCTAssertFalse(IslandLayout.contains(CGPoint(x: IslandLayout.canvas.width / 2, y: 10),
                                             box: IslandLayout.box(.idle, plain)))
    }

    func testAlwaysOnLampExtendsBelowTheHardwareNotch() {
        let prefs = IslandPrefs(alwaysOn: true)
        let box = IslandLayout.box(.idle, notch, prefs: prefs)
        XCTAssertEqual(box.body.width, notch.notch.width)
        XCTAssertEqual(box.body.height, notch.band + 5)
        XCTAssertTrue(IslandLayout.contains(CGPoint(x: IslandLayout.canvas.width / 2,
                                                    y: notch.band + 1), box: box))
        let external = IslandLayout.box(.idle, plain, prefs: prefs)
        XCTAssertEqual(external.opacity, 1)
        XCTAssertTrue(IslandLayout.contains(CGPoint(x: IslandLayout.canvas.width / 2, y: 10),
                                            box: external))
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

    func testCardBodyHeightFitsBandRowAndMeta() {
        for geometry in [notch, plain] {
            // The failure card is three lines plus an action row, the history
            // panel is five rows plus a footer, and the meeting panel carries a
            // metric, a share bar and a legend.
            XCTAssertEqual(IslandLayout.box(.failed(transcript), geometry).body.height,
                           IslandLayout.cardHeight(geometry.band, below: 132))
            XCTAssertEqual(IslandLayout.box(.history, geometry).body.height,
                           IslandLayout.cardHeight(geometry.band, below: 248))
            XCTAssertEqual(IslandLayout.box(.meetingPanel, geometry).body.height,
                           IslandLayout.cardHeight(geometry.band, below: 176))
            XCTAssertEqual(IslandLayout.box(.notice(notice), geometry).body.height,
                           IslandLayout.cardHeight(geometry.band, below: 76))
            XCTAssertEqual(IslandLayout.box(.recent(nil), geometry).body.height,
                           IslandLayout.cardHeight(geometry.band, below: 88))
            XCTAssertEqual(IslandLayout.box(.undo(undo), geometry).body.height,
                           IslandLayout.cardHeight(geometry.band))
        }
    }

    func testWideWingsNameTheModeAndTheOthersDoNot() {
        XCTAssertEqual(IslandLayout.box(.handsFree, notch).body.width,
                       notch.notch.width + 2 * IslandLayout.wingWide)
        // A meeting also carries its elapsed time, so its wings are wider still —
        // clamped so they can never leave the canvas on a wide notch.
        XCTAssertEqual(IslandLayout.box(.meeting, notch).body.width,
                       notch.notch.width + 2 * IslandLayout.wingWidth(.meeting, gap: notch.notch.width))
        XCTAssertEqual(IslandLayout.wingWidth(.meeting, gap: notch.notch.width),
                       IslandLayout.wingMeeting)
        XCTAssertEqual(IslandLayout.box(.handsFree, notch).body.height, notch.band)
    }

    func testWingsAreTheNotchPlusTwoWings() {
        let body = IslandLayout.box(.listening, notch).body
        XCTAssertEqual(body.width, notch.notch.width + 112)
        XCTAssertEqual(body.height, notch.band)
        XCTAssertEqual(IslandLayout.box(.landed(words: 1), notch), IslandLayout.box(.listening, notch))
    }

    /// The key hints are part of the silhouette: the live wings grow by exactly
    /// one shelf, and no other phase grows at all.
    func testHintShelfGrowsOnlyTheLiveModes() {
        XCTAssertEqual(IslandLayout.box(.handsFree, notch, hint: true).body.height,
                       notch.band + IslandLayout.hintShelf)
        XCTAssertEqual(IslandLayout.box(.meeting, notch, hint: true).body.height,
                       notch.band + IslandLayout.hintShelf)
        for phase in [IslandPhase.listening, .processing, .landed(words: 2)] {
            XCTAssertEqual(IslandLayout.box(phase, notch, hint: true).body.height, notch.band,
                           "\(phase)")
        }
        XCTAssertGreaterThan(IslandLayout.hitRect(.meeting, notch, hint: true).height,
                             IslandLayout.hitRect(.meeting, notch).height)
        XCTAssertEqual(IslandLayout.hitRect(.handsFree, notch, hint: true).height,
                       IslandLayout.hitRect(.meeting, notch, hint: true).height)
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
