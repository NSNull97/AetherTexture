import XCTest
import UIKit
@testable import AetherUI

final class ContextMenuSharedSourceReturnTests: XCTestCase {
    private let source = CGRect(x: 288, y: 70, width: 96, height: 44)
    private let target = CGRect(x: 129, y: 70, width: 255, height: 380)

    func testSharedReturnRetainsMeasuredVolumeAndDelaysHeadExpansion() {
        // Native video, normalized independently by menu and source size.
        // Times include the short pre-motion interval in the display clock.
        for (time, width, height, head): (CGFloat, CGFloat, CGFloat, CGFloat) in [
            (0.133, 0.495, 0.419, 0.216), (0.183, 0.295, 0.223, 0.611),
            (0.233, 0.178, 0.108, 0.826), (0.266, 0.130, 0.049, 0.904)
        ] {
            let shape = sample(time: time)
            XCTAssertEqual(shape.bodyFrame.width / target.width, width, accuracy: 0.045)
            XCTAssertEqual(shape.bodyFrame.height / target.height, height, accuracy: 0.045)
            XCTAssertEqual(shape.headFrame.width / source.width, head, accuracy: 0.045)
        }
        XCTAssertLessThan(sample(time: 0.150).headFrame.width, source.width * 0.5)
        XCTAssertGreaterThan(sample(time: 0.150).bodyFrame.height, source.height * 2)
    }

    func testSharedShoulderStartsBroadBeforeTheNoseRises() {
        let shoulder = sample(time: 0.116)
        XCTAssertGreaterThan(shoulder.headFrame.width / shoulder.headFrame.height, 1.4)
        XCTAssertGreaterThan(shoulder.headFrame.minY, source.maxY,
            "The first shoulder must grow from the menu before rising to the source")
        let nose = sample(time: 0.150)
        XCTAssertLessThan(nose.headFrame.minY, source.maxY)
        XCTAssertGreaterThan(nose.headFrame.height, shoulder.headFrame.height * 2)
    }

    func testSharedBodyDrainsWithoutAnIntermediateHoldOrRegrowth() {
        var previous = sample(time: 0.066)
        for frame in 5...18 {
            let current = sample(time: CGFloat(frame) / 60)
            XCTAssertLessThan(current.bodyFrame.width, previous.bodyFrame.width - 0.1)
            XCTAssertLessThan(current.bodyFrame.height, previous.bodyFrame.height - 0.1)
            previous = current
        }
    }

    func testSharedReturnMirrorsAndAbsorbsTheLastVisibleBody() {
        for unit in [CGPoint.zero, CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)] {
            let mirroredSource = CGRect(x: target.minX + (target.width - source.width) * unit.x,
                y: target.minY + (target.height - source.height) * unit.y,
                width: source.width, height: source.height)
            for time: CGFloat in [0.133, 0.183, 0.233] {
                let shape = sample(time: time, source: mirroredSource, unit: unit)
                XCTAssertGreaterThan((shape.bodyFrame.midX - shape.headFrame.midX) * (1 - 2 * unit.x), 0)
                XCTAssertGreaterThan((shape.bodyFrame.midY - shape.headFrame.midY) * (1 - 2 * unit.y), 0)
                XCTAssertTrue(shape.headFrame.contains(shape.bridgeStart))
                XCTAssertTrue(shape.bodyFrame.contains(shape.neckBulbCenter))
            }
            for time: CGFloat in [0.355, 0.370, 0.385] {
                let shape = sample(time: time, source: mirroredSource, unit: unit)
                XCTAssertGreaterThan(shape.bodyAlpha, 0.001)
                XCTAssertTrue(shape.headFrame.insetBy(dx: 3, dy: 3).contains(shape.bodyFrame),
                    "The last opaque remnant must be absorbed before it is hidden")
            }
            XCTAssertEqual(sample(time: 0.54, source: mirroredSource, unit: unit).headFrame, mirroredSource)
        }
    }

    func testSharedSourceSettlesTogetherWithoutChangingGlyphScale() {
        let anchor = ContextMenuBloomAnchor.topTrailing
        var previous = -CGFloat.greatestFiniteMagnitude
        for time: CGFloat in [0.266, 0.300, 0.350, 0.400, 0.450, 0.500, 0.540] {
            let phase = motion(time)
            let offset = ContextMenuSharedSourceReturn.sourceOffset(phase: phase, height: 44, anchor: anchor)
            XCTAssertGreaterThanOrEqual(offset, previous)
            XCTAssertLessThanOrEqual(offset, 0)
            let opposite = ContextMenuSharedSourceReturn.sourceOffset(phase: phase, height: 44,
                anchor: .init(unitPoint: CGPoint(x: 1, y: 1)))
            XCTAssertEqual(opposite, -offset, accuracy: 0.000001)
            previous = offset
        }
        for time: CGFloat in [0.183, 0.200, 0.233, 0.266, 0.300, 0.400, 0.500] {
            let offset = ContextMenuSharedSourceReturn.sourceOffset(phase: motion(time), height: 44, anchor: anchor)
            XCTAssertEqual(sample(time: time).headFrame.midY - source.midY, offset, accuracy: 0.000001,
                "Glass and content must share the final jump, without a delayed second peak")
        }
        XCTAssertEqual(previous, 0)
        XCTAssertLessThan(sample(time: 0.316).headFrame.midY, source.midY - 3)
        XCTAssertEqual(sample(time: 0.54).headFrame, source)
    }

    func testOptInPreservesOpeningAndReduceMotionGeometry() {
        for direction in [ContextMenuBloomDirection.opening, .closing] {
            for reduceMotion in [false, true] where direction == .opening || reduceMotion {
                for frame in 0...20 {
                    let raw = CGFloat(frame) / 20
                    func geometry(_ shared: Bool) -> ContextMenuGlassmorphicGeometrySample {
                        contextMenuGlassmorphicGeometrySample(source: source, target: target,
                            outerFrame: target, outerCornerRadii: .uniform(27), sourceRadius: 22,
                            targetRadius: 27, anchor: .topTrailing, direction: direction,
                            rawProgress: raw, reduceMotion: reduceMotion, sharedSource: shared)
                    }
                    XCTAssertEqual(geometry(true), geometry(false))
                }
            }
        }
        XCTAssertEqual(sample(time: 0).bodyFrame, target)
    }

    private func motion(_ time: CGFloat) -> CGFloat {
        contextMenuLiquidAnimationSample(fraction: time / CGFloat(ContextMenuSharedSourceReturn.duration),
            reduceMotion: false, direction: .closing).progress
    }

    private func sample(time: CGFloat, source override: CGRect? = nil,
                        unit: CGPoint = CGPoint(x: 1, y: 0)) -> ContextMenuGlassmorphicGeometrySample {
        contextMenuGlassmorphicGeometrySample(source: override ?? source, target: target,
            outerFrame: target, outerCornerRadii: .uniform(27), sourceRadius: 22, targetRadius: 27,
            anchor: .init(unitPoint: unit), direction: .closing, rawProgress: 1 - motion(time),
            reduceMotion: false, sharedSource: true)
    }
}
