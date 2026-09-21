import XCTest
import UIKit
@testable import AetherUI

final class ContextMenuClosingAbsorptionTests: XCTestCase {
    func testSharedCapsuleGrowsANoseBeforeItsBellyBecomesButtonSized() {
        let source = CGRect(x: 288, y: 70, width: 96, height: 44)
        let target = CGRect(x: 129, y: 70, width: 255, height: 380)
        let fixture = Fixture(source: source, target: target, anchor: .topTrailing)
        let duration = CGFloat(ContextMenuController.glassmorphicTiming.closeDuration)
        func sample(at milliseconds: CGFloat) -> ContextMenuGlassmorphicGeometrySample {
            let motion = contextMenuLiquidAnimationSample(fraction: milliseconds / (duration * 1000),
                reduceMotion: false, direction: .closing)
            return closingSample(fixture, elapsed: motion.progress)
        }
        // Both native recordings have a visible nose at ~100–117 ms while
        // a broad lower lobe still travels separately toward the source.
        let nose = sample(at: 110)
        XCTAssertGreaterThan(nose.headAlpha, 0.1)
        XCTAssertGreaterThan(nose.bodyFrame.width, source.height * 2)
        XCTAssertGreaterThan(nose.bodyFrame.height, source.height * 2)
        XCTAssertLessThan(nose.headFrame.width, source.width * 0.6)
        XCTAssertLessThan(nose.headFrame.minY, nose.bodyFrame.minY)

        let returnFlow = sample(at: 180)
        XCTAssertGreaterThan(returnFlow.headFrame.width, source.width * 0.95)
        XCTAssertGreaterThan(returnFlow.headFrame.midX - returnFlow.bodyFrame.midX, source.height * 0.35)
        XCTAssertGreaterThan(returnFlow.bodyFrame.maxY, source.maxY + source.height * 0.7)
        XCTAssertFalse(source.contains(sample(at: 240).bodyFrame), "Do not consume the final belly too early")
        XCTAssertTrue(source.contains(sample(at: 330).bodyFrame))
    }

    func testSharedCapsuleReturnMirrorsItsSeparateHeadAndBellyTrajectories() {
        let target = CGRect(x: 100, y: 100, width: 255, height: 380)
        for width: CGFloat in [94, 160] {
            for unit in [CGPoint.zero, CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)] {
                let source = CGRect(x: unit.x == 0 ? target.minX : target.maxX - width,
                    y: unit.y == 0 ? target.minY : target.maxY - 44, width: width, height: 44)
                let fixture = Fixture(source: source, target: target, anchor: .init(unitPoint: unit))
                let motion = contextMenuLiquidAnimationSample(fraction: 0.4, reduceMotion: false, direction: .closing)
                let shape = closingSample(fixture, elapsed: motion.progress)
                XCTAssertGreaterThan((shape.bodyFrame.midX - shape.headFrame.midX) * (1 - 2 * unit.x), 44 * 0.35)
                XCTAssertGreaterThan((shape.bodyFrame.midY - shape.headFrame.midY) * (1 - 2 * unit.y), 44 * 0.5)
                XCTAssertTrue(shape.headFrame.intersects(shape.bodyFrame))
                let final = closingSample(fixture, elapsed: 0.99)
                XCTAssertEqual(final.headFrame, source)
                XCTAssertTrue(source.contains(final.bodyFrame))
            }
        }
    }

    func testReturningSharedHeadDoesNotHitItsRestingPositionWithNonzeroVelocity() {
        let fixture = Fixture(source: CGRect(x: 292, y: 70, width: 88, height: 44),
            target: CGRect(x: 125, y: 70, width: 255, height: 470), anchor: .topTrailing)
        let step: CGFloat = 0.0001
        var previousVelocity: CGFloat?
        for frame in 4001...6000 {
            let t = CGFloat(frame) * step
            let before = closingSample(fixture, elapsed: t - step).headFrame.midY
            let now = closingSample(fixture, elapsed: t).headFrame.midY
            let velocity = (now - before) / step
            if let previousVelocity {
                XCTAssertLessThan(abs(velocity - previousVelocity), 5,
                    "The source shoulder must decelerate into place, not hit a hard coordinate clamp")
            }
            previousVelocity = velocity
        }
    }

    func testDisappearingBodyIsInsideReturningHeadOnEveryCorner() {
        for fixture in fixtures {
            var absorbedSamples = 0
            for index in 0...2000 {
                let sample = closingSample(fixture, elapsed: CGFloat(index) / 2000)
                // Native glass keeps an active lobe opaque until its 0.001
                // visibility cutoff. Its final area must already be covered
                // by the head, rather than leave a dot at the source's corner.
                guard sample.bodyAlpha > 0.001, sample.bodyAlpha <= 0.10 else { continue }
                absorbedSamples += 1
                for x in [sample.bodyFrame.minX, sample.bodyFrame.maxX] {
                    for y in [sample.bodyFrame.minY, sample.bodyFrame.maxY] {
                        let dx = (x - sample.headFrame.midX) / (sample.headFrame.width * 0.5)
                        let dy = (y - sample.headFrame.midY) / (sample.headFrame.height * 0.5)
                        XCTAssertLessThanOrEqual(dx * dx + dy * dy, 1.000001,
                            "An opaque remnant escaped the circular head: \(fixture), sample \(index)")
                    }
                }
            }
            XCTAssertGreaterThan(absorbedSamples, 0, "The test must inspect the last visible body samples")
        }
    }

    func testReturningHeadDoesNotStretchAgainAfterItStartsRelaxing() {
        for fixture in fixtures {
            var previousMajor: CGFloat = 0
            var maximumMajor: CGFloat = 0
            var isRelaxing = false
            for index in 0...2000 {
                let motion = contextMenuLiquidAnimationSample(
                    fraction: CGFloat(index) / 2000, reduceMotion: false, direction: .closing
                )
                let sample = closingSample(fixture, elapsed: motion.progress)
                let major = max(sample.headFrame.width, sample.headFrame.height) * (1 + motion.rebound)
                maximumMajor = max(maximumMajor, major)
                if major < previousMajor - 0.000001,
                   previousMajor > fixture.source.width * 1.02 {
                    isRelaxing = true
                }
                if isRelaxing {
                    XCTAssertLessThanOrEqual(major, previousMajor + 0.000001,
                        "The restored source stretched a second time: \(fixture), sample \(index)")
                }
                previousMajor = major
            }
            XCTAssertTrue(isRelaxing)
            XCTAssertGreaterThan(maximumMajor, fixture.source.width * 1.10,
                "The liquid stretch before absorption must remain visible")
            XCTAssertEqual(previousMajor, fixture.source.width, accuracy: 0.000001)
        }
    }

    private struct Fixture {
        let source: CGRect
        let target: CGRect
        let anchor: ContextMenuBloomAnchor
    }

    private var fixtures: [Fixture] {
        [CGFloat(160), 312, 400].flatMap { height in
            [CGPoint.zero, CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)].map { unit in
                let target = CGRect(x: 100, y: 100, width: 255, height: height)
                let source = CGRect(
                    x: unit.x == 0 ? target.minX : target.maxX - 44,
                    y: unit.y == 0 ? target.minY - 10 : target.maxY - 34,
                    width: 44, height: 44
                )
                return Fixture(source: source, target: target, anchor: .init(unitPoint: unit))
            }
        }
    }

    private func closingSample(_ fixture: Fixture, elapsed: CGFloat) -> ContextMenuGlassmorphicGeometrySample {
        contextMenuGlassmorphicGeometrySample(
            source: fixture.source,
            target: fixture.target,
            outerFrame: fixture.source,
            outerCornerRadii: .uniform(22),
            sourceRadius: 22,
            targetRadius: 27,
            anchor: fixture.anchor,
            direction: .closing,
            rawProgress: 1 - elapsed,
            reduceMotion: false
        )
    }
}
