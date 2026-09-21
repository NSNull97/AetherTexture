import XCTest
import UIKit
@testable import AetherUI

final class ContextMenuClosingAbsorptionTests: XCTestCase {
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
