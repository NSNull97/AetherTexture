import XCTest
import CoreGraphics
@testable import AetherUI

final class AetherModalDragGeometryTests: XCTestCase {
    private let compact = CGRect(x: 8, y: 414, width: 374, height: 422)
    private let expanded = CGRect(x: 0, y: 69, width: 390, height: 775)

    private func geometry(_ detents: Set<AetherModalController.Detent> = [.stage1, .stage2]) -> AetherModalDragGeometry {
        AetherModalDragGeometry(compactFrame: compact, expandedFrame: expanded, allowedDetents: detents)
    }

    func testInterruptedSettlePreservesCurrentFrameAtTouchDownInBothDirections() {
        // Include a frame outside the normal interpolation line, as occurs
        // while settling from a downward dismissal drag toward expanded.
        let frames = [
            CGRect(x: 3, y: 193, width: 384, height: 643),
            CGRect(x: 6, y: 352, width: 378, height: 539),
            compact.offsetBy(dx: 0, dy: 48)
        ]
        for frame in frames {
            XCTAssertEqual(geometry().frame(from: frame, translationY: 0), frame)
            for translation: CGFloat in [-0.01, 0.01] {
                let moved = geometry().frame(from: frame, translationY: translation)
                XCTAssertEqual(moved.minY, frame.minY + translation, accuracy: 0.001)
                XCTAssertEqual(moved.width, frame.width, accuracy: 0.01)
                XCTAssertEqual(moved.height, frame.height, accuracy: 0.03)
            }
        }
    }

    func testInterruptedSettleReachesTheCorrectEndpointsWithoutSnappingToStartDetent() {
        let current = CGRect(x: 4, y: 241.5, width: 382, height: 598.5)
        XCTAssertEqual(geometry().frame(from: current, translationY: expanded.minY - current.minY), expanded)
        XCTAssertEqual(geometry().frame(from: current, translationY: compact.minY - current.minY), compact)
        let belowCompact = geometry().frame(from: current, translationY: compact.minY - current.minY + 30)
        XCTAssertEqual(belowCompact, compact.offsetBy(dx: 0, dy: 30))
    }

    func testCompactOnlyContentCanScrollUp() {
        XCTAssertFalse(geometry([.stage1]).shouldDrive(
            translationY: -100, currentFrame: compact,
            startsInScrollContent: true, scrollIsAtTop: true
        ))
        XCTAssertFalse(geometry([.stage1]).shouldDrive(
            translationY: -100, currentFrame: compact,
            startsInScrollContent: true, scrollIsAtTop: false
        ))
    }

    func testUpwardContentPanExpandsOnlyWhenThereIsAnExpandedDestination() {
        XCTAssertTrue(geometry().shouldDrive(
            translationY: -100, currentFrame: compact,
            startsInScrollContent: true, scrollIsAtTop: false
        ))
        XCTAssertFalse(geometry().shouldDrive(
            translationY: -100, currentFrame: expanded,
            startsInScrollContent: true, scrollIsAtTop: true
        ))
    }

    func testDownwardContentPanRequiresScrollAtTopAndHeaderDoesNot() {
        XCTAssertFalse(geometry().shouldDrive(
            translationY: 100, currentFrame: expanded,
            startsInScrollContent: true, scrollIsAtTop: false
        ))
        XCTAssertTrue(geometry().shouldDrive(
            translationY: 100, currentFrame: expanded,
            startsInScrollContent: true, scrollIsAtTop: true
        ))
        XCTAssertTrue(geometry().shouldDrive(
            translationY: 100, currentFrame: expanded,
            startsInScrollContent: false, scrollIsAtTop: false
        ))
    }

    func testSingleExpandedDetentDismissalDragKeepsSize() {
        let moved = geometry([.stage2]).frame(from: expanded, translationY: 80)
        XCTAssertEqual(moved, expanded.offsetBy(dx: 0, dy: 80))
    }

    func testCompactHeaderRubberbandIsContinuousWhenInterrupted() {
        let overshoot = compact.offsetBy(dx: 0, dy: -18)
        XCTAssertEqual(geometry([.stage1]).frame(from: overshoot, translationY: 0), overshoot)
        let moved = geometry([.stage1]).frame(from: overshoot, translationY: -0.01)
        XCTAssertEqual(moved.minY, overshoot.minY, accuracy: 0.01)
    }
}
