import XCTest
import UIKit
@testable import AetherUI

@MainActor
final class ContextMenuInterruptionTests: XCTestCase {
    func testDisplayClockDoesNotSkipLiquidPhaseAfterStallAndCompletesOnce() {
        let host = makeHost(appearance: .legacy)
        defer { host.tearDownGlassEffects() }
        var completions = 0
        host.animateExpand(duration: 0.42, damping: 0.86) { completions += 1 }
        host.advanceAnimation(to: 1)
        host.advanceAnimation(to: 2)
        XCTAssertEqual(completions, 0, "A delayed callback must not jump straight to the menu")
        for frame in 1...60 { host.advanceAnimation(to: 2 + Double(frame) / 120) }
        XCTAssertEqual(completions, 1)
        host.advanceAnimation(to: 4)
        XCTAssertEqual(completions, 1)
    }

    func testOpeningSamplesTheSameMotionAt60And120Hz() {
        let slow = makeHost(appearance: .legacy, menuHeight: 160)
        let fast = makeHost(appearance: .legacy, menuHeight: 160)
        defer { slow.tearDownGlassEffects(); fast.tearDownGlassEffects() }
        for host in [slow, fast] {
            host.animateExpand(duration: 0.44, damping: 0.86)
            host.advanceAnimation(to: 1)
        }
        for frame in 1...30 {
            fast.advanceAnimation(to: 1 + Double(2*frame-1) / 120)
            fast.advanceAnimation(to: 1 + Double(2*frame) / 120)
            slow.advanceAnimation(to: 1 + Double(frame) / 60)
            for (a, b) in [(slow.finalMenuGlassSurfaceView, fast.finalMenuGlassSurfaceView),
                           (slow.liveMenuContentView, fast.liveMenuContentView)] {
                XCTAssertEqual(a.bounds.width, b.bounds.width, accuracy: 0.000001)
                XCTAssertEqual(a.bounds.height, b.bounds.height, accuracy: 0.000001)
                XCTAssertEqual(a.center.x, b.center.x, accuracy: 0.000001)
                XCTAssertEqual(a.center.y, b.center.y, accuracy: 0.000001)
                XCTAssertEqual(a.transform.a, b.transform.a, accuracy: 0.000001)
                XCTAssertEqual(a.transform.d, b.transform.d, accuracy: 0.000001)
                XCTAssertEqual(a.alpha, b.alpha, accuracy: 0.000001)
            }
        }
        XCTAssertEqual(slow.liveMenuContentView.transform, .identity)
        XCTAssertEqual(fast.liveMenuContentView.transform, .identity)
    }

    func testContentOverscaleUsesTheGlassAnchorOnEveryEdge() throws {
        for unit in [CGPoint.zero, CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1),
                     CGPoint(x: 1, y: 1), CGPoint(x: 0.5, y: 0)] {
            let source = CGRect(x: 280, y: 300, width: 88, height: 44)
            let target = CGRect(x: source.minX - (255-88)*unit.x,
                y: source.minY - (170-44)*unit.y, width: 255, height: 170)
            let host = ContextMenuGlassmorphicTransitionView(sourceFrameInOverlay: source,
                targetMenuFrameInOverlay: target, finalCornerRadius: 27, sourceCornerRadius: 22,
                sourceMode: .leasedGlassSource, isDark: false, appearanceStyle: .liquidGlassV1)
            defer { host.tearDownGlassEffects() }
            host.frame = CGRect(x: 0, y: 0, width: 600, height: 900)
            host.layoutIfNeeded()
            host.animateExpand(duration: 0.44, damping: 0.86)
            host.advanceAnimation(to: 1)
            for frame in 1...61 { host.advanceAnimation(to: 1 + 0.44 * Double(frame) / 100) }
            // At the peak, the carrier owns the full overscale while its
            // rows can still have their small directional lens deformation.
            XCTAssertEqual(try menuContentViews(in: host)[0].transform.a, 1.022, accuracy: 0.000001)
            for frame in 62...90 { host.advanceAnimation(to: 1 + 0.44 * Double(frame) / 100) }
            let glass = host.finalMenuGlassSurfaceView.frame
            let scale = 1 + contextMenuLiquidAnimationSample(fraction: 0.90, reduceMotion: false).rebound
            XCTAssertEqual(glass.width / target.width, scale, accuracy: 0.000001)
            for view in try menuContentViews(in: host) {
                let rows = view.convert(view.bounds, to: host)
                XCTAssertEqual(rows.minX, glass.minX, accuracy: 0.000001)
                XCTAssertEqual(rows.minY, glass.minY, accuracy: 0.000001)
                XCTAssertEqual(rows.width, glass.width, accuracy: 0.000001)
                XCTAssertEqual(rows.height, glass.height, accuracy: 0.000001)
                XCTAssertEqual(view.bounds.size, target.size)
            }
            XCTAssertEqual(host.sourceProxyContainer.transform, .identity)
        }
    }

    func testWideButtonCollapseKeepsConnectedDropAndRetractsUnderSource() {
        let source = CGRect(x: 220, y: 70, width: 160, height: 44)
        let target = CGRect(x: 125, y: 70, width: 255, height: 470)
        let anchor = ContextMenuBloomAnchor.detect(source: source, target: target)
        var previous: CGRect?
        for step in 1..<420 {
            let t = CGFloat(step) / 420
            let outer = contextMenuBloomGeometrySample(source: source, target: target,
                sourceRadius: 22, targetRadius: 27, anchor: anchor, direction: .closing,
                rawProgress: 1-t, reduceMotion: false)
            let sample = contextMenuGlassmorphicGeometrySample(source: source, target: target,
                outerFrame: outer.frame, outerCornerRadii: outer.cornerRadii,
                sourceRadius: 22, targetRadius: 27, anchor: anchor, direction: .closing,
                rawProgress: 1-t, reduceMotion: false)
            if sample.headAlpha > 0.001 {
                XCTAssertTrue(sample.headFrame.intersects(sample.bodyFrame), "The returning shoulder must stay joined to the drop")
            }
            if sample.bridgeRadius > 0 {
                XCTAssertTrue(sample.headFrame.contains(sample.bridgeStart))
                XCTAssertTrue(sample.bodyFrame.contains(sample.neckBulbCenter))
            }
            XCTAssertEqual(sample.bodyAlpha, 1)
            if let previous {
                XCTAssertLessThan(abs(sample.bodyFrame.minY-previous.minY), 6)
                XCTAssertLessThan(abs(sample.bodyFrame.height-previous.height), 8)
            }
            if t > 0.98 {
                XCTAssertEqual(sample.headFrame, source)
                XCTAssertTrue(source.contains(sample.bodyFrame))
            }
            previous = sample.bodyFrame
        }
    }

    func testOpeningKeepsConnectedSeedAndExactEndpointsForEveryAnchor() {
        for width: CGFloat in [44, 106, 160, 240] {
            for height: CGFloat in [160, 470] {
                for unit in [CGPoint.zero, CGPoint(x: 1, y: 0), CGPoint(x: 0.5, y: 1)] {
                    let anchor = ContextMenuBloomAnchor(unitPoint: unit)
                    let source = CGRect(x: 40, y: 70, width: width, height: 44)
                    let target = CGRect(x: 40 - (255-width)*unit.x,
                        y: 70 - (height-44)*unit.y, width: 255, height: height)
                    for frame in 0...120 {
                        let raw = CGFloat(frame) / 120
                        func sample(_ direction: ContextMenuBloomDirection) -> ContextMenuGlassmorphicGeometrySample {
                            let outer = contextMenuBloomGeometrySample(source: source, target: target,
                                sourceRadius: 22, targetRadius: 27, anchor: anchor,
                                direction: direction, rawProgress: raw, reduceMotion: false)
                            return contextMenuGlassmorphicGeometrySample(source: source, target: target,
                                outerFrame: outer.frame, outerCornerRadii: outer.cornerRadii,
                                sourceRadius: 22, targetRadius: 27, anchor: anchor,
                                direction: direction, rawProgress: raw, reduceMotion: false)
                        }
                        let opening = sample(.opening)
                        if frame == 0 || frame == 120 {
                            XCTAssertEqual(opening, sample(.closing))
                        } else {
                            XCTAssertEqual(opening.headAlpha, 0, "Opening must never expose a second source lobe")
                            if opening.bridgeRadius > 0 {
                                XCTAssertTrue(opening.bodyFrame.contains(opening.neckBulbCenter),
                                    "The neck must terminate inside the same body, never as a detached bead")
                                let reach = hypot(opening.bridgeStart.x - opening.bodyFrame.midX,
                                                  opening.bridgeStart.y - opening.bodyFrame.midY)
                                XCTAssertLessThanOrEqual(reach, min(opening.bodyFrame.width, opening.bodyFrame.height) * 0.30 + 44 * 0.60 + 0.0001)
                                let rootReach = hypot(opening.bridgeEnd.x - opening.bodyFrame.midX,
                                                      opening.bridgeEnd.y - opening.bodyFrame.midY)
                                XCTAssertLessThanOrEqual(rootReach + opening.neckBulbRadius,
                                    min(opening.bodyFrame.width, opening.bodyFrame.height) * 0.5 + 0.0001,
                                    "The broad neck root must not protrude through the shoulder as a second bump")
                            }
                            XCTAssertEqual(opening.bodyAlpha, 1)
                            XCTAssertGreaterThan(opening.bodyFrame.width, 0)
                            XCTAssertGreaterThan(opening.bodyFrame.height, 0)
                            if raw < 0.3, width > 44 * 1.6 {
                                XCTAssertLessThanOrEqual(opening.bodyFrame.width, width)
                            }
                        }
                    }
                }
            }
        }
    }

    func testRoundTriggerGrowsAFullBellyBeforeMenuExpansion() {
        let source = CGRect(x: 320, y: 70, width: 44, height: 44)
        for height: CGFloat in [160, 470] {
            let target = CGRect(x: 109, y: 70, width: 255, height: height)
            for step in 20...34 {
                let sample = contextMenuGlassmorphicGeometrySample(source: source, target: target,
                    outerFrame: source, outerCornerRadii: .uniform(22), sourceRadius: 22, targetRadius: 27,
                    anchor: .init(unitPoint: CGPoint(x: 1, y: 0)), direction: .opening,
                    rawProgress: CGFloat(step) / 100, reduceMotion: false)
                XCTAssertGreaterThanOrEqual(sample.bodyFrame.width / sample.bodyFrame.height, min(0.8, 255 / height),
                    "The growing pear must remain fuller than the final menu aspect ratio")
                XCTAssertGreaterThanOrEqual(sample.bodyFrame.width, source.width)
                XCTAssertEqual(sample.headAlpha, 0, "Volume must belong to the drop, not a second source bead")
            }
        }
    }

    func testOpeningGrowsBothAxesWhileThePearTravelsAndSettles() {
        let source = CGRect(x: 100, y: 100, width: 88, height: 44)
        func sample(_ unit: CGPoint, _ progress: CGFloat, height: CGFloat = 470, reduceMotion: Bool = false) -> ContextMenuGlassmorphicGeometrySample {
            let target = CGRect(x: source.minX - (255 - source.width) * unit.x,
                y: source.minY - (height - source.height) * unit.y, width: 255, height: height)
            return contextMenuGlassmorphicGeometrySample(source: source, target: target,
                outerFrame: source, outerCornerRadii: .uniform(22), sourceRadius: 22, targetRadius: 27,
                anchor: .init(unitPoint: unit), direction: .opening, rawProgress: progress, reduceMotion: reduceMotion)
        }
        let lens = sample(.zero, 0.52)
        XCTAssertGreaterThan(lens.bodyFrame.height, lens.bodyFrame.width,
            "A tall menu grows from a pear, not a wide lens followed by a height jump")
        XCTAssertGreaterThan(lens.bodyFrame.minY, source.minY + 15,
            "The trailing edge must travel away from the source instead of hinging on it")
        XCTAssertLessThan(sample(.zero, 0.75).bodyFrame.minY, lens.bodyFrame.minY)
        XCTAssertEqual(lens.bodyRotation, 0, "Readable content must not turn with a rigid platter")
        let seed = sample(.zero, 0.28)
        XCTAssertEqual(seed.bodyRotation, 0)
        XCTAssertEqual(seed.headRotation, 0)
        XCTAssertEqual(seed.headAlpha, 0)
        XCTAssertGreaterThan(seed.bridgeRadius, 5, "The opening must retain a liquid neck without a separate source bead")
        XCTAssertLessThan(seed.bodyCornerRadii.topLeft, seed.bodyCornerRadii.bottomRight * 0.75,
            "The source end must be narrower than the leading belly")
        XCTAssertLessThan(lens.bodyCornerRadii.topLeft, lens.bodyCornerRadii.bottomRight * 0.90,
            "Asymmetry must survive from the seed into the growing menu")
        XCTAssertGreaterThan(lens.bodyCornerRadii.topLeft / lens.bodyCornerRadii.bottomRight,
            seed.bodyCornerRadii.topLeft / seed.bodyCornerRadii.bottomRight,
            "The source shoulder must relax during expansion instead of retaining a ledge")
        XCTAssertGreaterThan(lens.bodyCornerRadii.topLeft, min(lens.bodyFrame.width, lens.bodyFrame.height) * 0.38,
            "The growing menu must keep a rounded lens shoulder before settling into a platter")
        let arriving = sample(.zero, 0.38)
        XCTAssertEqual(arriving.headAlpha, 0)
        XCTAssertGreaterThan(arriving.bodyFrame.midX, source.midX)
        XCTAssertLessThan(arriving.bodyFrame.midX, source.minX + 255 * 0.5,
            "The reference keeps translating while the pear is growing")
        XCTAssertLessThan(arriving.bodyFrame.midY, source.minY + 470 * 0.5)
        let settling = sample(.zero, 0.68)
        XCTAssertGreaterThan(settling.bodyFrame.midY, source.minY + 470 * 0.5,
            "The grown pear should settle upward from a small downward overshoot")
        XCTAssertLessThan(arriving.bodyFrame.width, 255 * 0.75)
        XCTAssertEqual(sample(.zero, 0.28, reduceMotion: true).bodyRotation, 0)
        for height: CGFloat in [160, 470] {
            for frame in 0...120 {
                let value = sample(.zero, CGFloat(frame) / 120, height: height)
                XCTAssertGreaterThan(value.bodyFrame.height, 0)
                XCTAssertLessThanOrEqual(value.bodyFrame.height, height + 0.0001)
                if frame >= 40 {
                    let widthGrowth = (value.bodyFrame.width - 63.8) / (255 - 63.8)
                    let heightGrowth = (value.bodyFrame.height - 63.8) / (height - 63.8)
                    XCTAssertLessThanOrEqual(abs(widthGrowth - heightGrowth), 0.10,
                        "Width and height must grow together, without a late vertical catch-up")
                }
            }
        }
    }

    func testOpeningDropMirrorsWithItsAnchorWithoutLosingAsymmetry() {
        let source = CGRect(x: 100, y: 100, width: 88, height: 44)
        func sample(_ unit: CGPoint, _ t: CGFloat) -> ContextMenuGlassmorphicGeometrySample {
            let target = CGRect(x: source.minX - 167 * unit.x,
                                y: source.minY - 426 * unit.y, width: 255, height: 470)
            return contextMenuGlassmorphicGeometrySample(source: source, target: target,
                outerFrame: source, outerCornerRadii: .uniform(22), sourceRadius: 22, targetRadius: 27,
                anchor: .init(unitPoint: unit), direction: .opening, rawProgress: t, reduceMotion: false)
        }
        for frame in 20...80 {
            let t = CGFloat(frame) / 100
            let left = sample(.zero, t)
            let right = sample(CGPoint(x: 1, y: 0), t)
            let up = sample(CGPoint(x: 0, y: 1), t)
            let horizontalTravel = (left.bodyFrame.midX - source.midX) / (167 * 0.5)
            let verticalTravel = (left.bodyFrame.midY - source.midY) / (426 * 0.5)
            XCTAssertGreaterThanOrEqual(verticalTravel + 0.0001, horizontalTravel,
                "The drop must descend before completing its inward travel")
            XCTAssertGreaterThan(horizontalTravel, 0)
            XCTAssertGreaterThan(verticalTravel, 0)
            if t >= 0.58 {
                XCTAssertEqual(horizontalTravel, 1, accuracy: 0.0001)
                XCTAssertGreaterThanOrEqual(verticalTravel, 1)
                XCTAssertLessThanOrEqual(verticalTravel, 1.07,
                    "Settling must remain a small continuation of travel")
            }
            XCTAssertEqual(left.bodyFrame.width, right.bodyFrame.width, accuracy: 0.0001)
            XCTAssertEqual(left.bodyFrame.midX + right.bodyFrame.midX, 2 * source.midX, accuracy: 0.0001)
            XCTAssertEqual(left.bodyFrame.midY + up.bodyFrame.midY, 2 * source.midY, accuracy: 0.0001)
            XCTAssertEqual(left.bodyCornerRadii.topLeft, right.bodyCornerRadii.topRight, accuracy: 0.0001)
            XCTAssertEqual(left.bodyCornerRadii.topLeft, up.bodyCornerRadii.bottomLeft, accuracy: 0.0001)
            if (0.30...0.40).contains(t) {
                XCTAssertLessThan(left.bodyCornerRadii.topLeft, left.bodyCornerRadii.bottomRight * 0.90)
            }
        }
    }

    func testWideMenuReturnKeepsALiquidNeckBetweenBellyAndSource() {
        let source = CGRect(x: 18, y: 70, width: 94, height: 44)
        let target = CGRect(x: 18, y: 70, width: 255, height: 160)
        let sample = contextMenuGlassmorphicGeometrySample(source: source, target: target,
            outerFrame: target, outerCornerRadii: .uniform(27), sourceRadius: 22, targetRadius: 27,
            anchor: .detect(source: source, target: target), direction: .closing,
            rawProgress: 0.45, reduceMotion: false)
        XCTAssertGreaterThan(sample.bridgeRadius, 5)
        XCTAssertTrue(sample.headFrame.contains(sample.bridgeStart))
        XCTAssertTrue(sample.bodyFrame.contains(sample.neckBulbCenter))
        XCTAssertGreaterThan(sample.bodyFrame.midY, sample.headFrame.midY + 15)
        XCTAssertLessThan(sample.bridgeRadius * 2, sample.bodyFrame.width * 0.6)
    }

    func testOpeningDoesNotRoundACustomSourceBeforeItsCaptionFades() {
        let source = CGRect(x: 40, y: 70, width: 160, height: 44)
        let target = CGRect(x: 40, y: 70, width: 255, height: 170)
        for radius: CGFloat in [4, 12, 22] {
            let sample = contextMenuGlassmorphicGeometrySample(source: source, target: target,
                outerFrame: source, outerCornerRadii: .uniform(radius),
                sourceRadius: radius, targetRadius: 27, anchor: .detect(source: source, target: target),
                direction: .opening, rawProgress: 0.1, reduceMotion: false)
            XCTAssertEqual(sample.bodyFrame, source)
            XCTAssertEqual(sample.bodyCornerRadii, .uniform(radius))
        }
    }

    func testSourceCaptionFadesBeforeOpeningShapeLeavesItsButton() {
        let host = makeHost(appearance: .legacy, menuHeight: 160, sourceWidth: 160)
        defer { host.tearDownGlassEffects() }
        host.setProgress(0.15, direction: .opening)
        XCTAssertLessThan(host.sourceProxyContainer.alpha, 0.25)
        XCTAssertEqual(host.finalMenuGlassSurfaceView.bounds.size, CGSize(width: 160, height: 44))
        host.setProgress(0.30, direction: .opening)
        XCTAssertEqual(host.sourceProxyContainer.alpha, 0)
        XCTAssertLessThan(host.finalMenuGlassSurfaceView.bounds.width, 80)
    }

    func testClosingOpticsFollowElapsedTimeInsteadOfAcceleratingWithGeometry() {
        let host = makeHost(appearance: .legacy, menuHeight: 160, sourceWidth: 160)
        defer { host.tearDownGlassEffects() }
        host.setProgress(1)
        host.animateCollapse(duration: 0.52, damping: 0.86)
        host.advanceAnimation(to: 10)
        var intermediateCaptionFrames = 0
        for frame in 1...36 {
            host.advanceAnimation(to: 10 + Double(frame) / 120)
            let alpha = host.sourceProxyContainer.alpha
            if alpha > 0.05 && alpha < 0.95 { intermediateCaptionFrames += 1 }
        }
        XCTAssertGreaterThanOrEqual(intermediateCaptionFrames, 8,
            "Focusing the source must span more than a couple of display frames")
        XCTAssertEqual(host.sourceProxyContainer.alpha, 1, accuracy: 0.001)
    }

    func testClosingContractionStartsOnTheFirstReferenceFrameAndReboundsFromSourceSizedEgg() {
        let source = CGRect(x: 18, y: 70, width: 106, height: 44)
        let target = CGRect(x: 18, y: 70, width: 230, height: 160)
        func sample(_ milliseconds: CGFloat) -> ContextMenuBloomGeometrySample {
            contextMenuBloomGeometrySample(
                source: source, target: target, sourceRadius: 22, targetRadius: 27,
                anchor: .detect(source: source, target: target), direction: .closing,
                rawProgress: 1.0 - milliseconds / 320.0, reduceMotion: false
            )
        }

        // Tolerances describe the measured silhouette, not exact spline knots.
        XCTAssertEqual(sample(17).frame.width / target.width, 0.85, accuracy: 0.025)
        XCTAssertEqual(sample(42).frame.width / target.width, 0.78, accuracy: 0.025)
        XCTAssertEqual(sample(75).frame.width / target.width, 0.66, accuracy: 0.025)
        XCTAssertEqual(sample(109).frame.width / target.width, 0.43, accuracy: 0.025)
        XCTAssertEqual(sample(142).frame.width / target.width, 0.35, accuracy: 0.025)
        XCTAssertLessThan(sample(17).frame.height, target.height)
        XCTAssertGreaterThan(sample(109).frame.height, source.height)
        XCTAssertLessThan(sample(175).frame.width, source.width)
        XCTAssertGreaterThan(sample(242).frame.width, sample(175).frame.width)
        XCTAssertEqual(sample(320).frame, source)

        for sourceWidth: CGFloat in [32, 44, 94, 150] {
            for frame in 0...38 {
                let geometry = contextMenuBloomGeometrySample(
                    source: CGRect(x: 18, y: 70, width: sourceWidth, height: 44),
                    target: target, sourceRadius: 22, targetRadius: 27,
                    anchor: .init(unitPoint: CGPoint(x: 0, y: 0)), direction: .closing,
                    rawProgress: 1 - CGFloat(frame) / 38, reduceMotion: false
                )
                XCTAssertGreaterThanOrEqual(geometry.frame.width, sourceWidth * 0.70)
                XCTAssertGreaterThanOrEqual(geometry.frame.height, 44)
            }
        }
    }

    func testClosingStartsFromTheRenderedOpeningContentAtEveryHandoff() throws {
        // Exercise invisible rows, the compressed blurred snapshot, the
        // sharp/live handoff and a nearly completed opening. A direction
        // change must preserve the actual views, not resample another curve.
        for appearance in AetherAppearanceStyle.allCases {
            for progress: CGFloat in [0.12, 0.40, 0.64, 0.78, 0.95] {
                let host = makeHost(appearance: appearance)
                defer { host.tearDownGlassEffects() }
                var reveal: CGFloat = 0
                host.contentRevealProgressChanged = { reveal = $0 }
                host.setProgress(progress)
                let contentViews = try menuContentViews(in: host)
                let before = contentViews.map(ViewRendering.init)
                let source = ViewRendering(host.sourceProxyContainer)
                let surfaceBounds = host.finalMenuGlassSurfaceView.bounds
                let surfaceCenter = host.finalMenuGlassSurfaceView.center
                let initialReveal = reveal

                host.animateCollapse(duration: 100, damping: 1)
                // Re-layout synchronously before the driver advances: this
                // is the first rendered close frame at exactly the reversal.
                host.layoutSubviews()

                for (view, rendering) in zip(contentViews, before) {
                    assertRendering(view, equals: rendering)
                }
                assertRendering(host.sourceProxyContainer, equals: source)
                XCTAssertEqual(host.finalMenuGlassSurfaceView.bounds, surfaceBounds)
                XCTAssertEqual(host.finalMenuGlassSurfaceView.center, surfaceCenter)
                XCTAssertEqual(reveal, initialReveal, accuracy: 0.000001)
            }
        }
    }

    func testRoundSourceReturnFormsANeckWhileTheMenuBellyIsStillWide() {
        let source = CGRect(x: 309, y: 92, width: 46, height: 45)
        let target = CGRect(x: 100, y: 92, width: 255, height: 378)
        let shape = contextMenuGlassmorphicGeometrySample(source: source, target: target,
            outerFrame: target, outerCornerRadii: .uniform(27), sourceRadius: 22.5, targetRadius: 27,
            anchor: .topTrailing, direction: .closing, rawProgress: 0.55, reduceMotion: false)
        XCTAssertGreaterThan(shape.bodyFrame.width, source.width * 2)
        XCTAssertGreaterThan(shape.headFrame.width, source.width * 0.15,
            "The source nose must form before the belly has shrunk to button width")
        XCTAssertGreaterThan(shape.headAlpha, 0.1)
        XCTAssertGreaterThan(shape.bridgeRadius, 1)
    }

    func testTallMenuKeepsItsMeasuredRoundedBodyAndDownwardTravelWhileClosing() {
        let source = CGRect(x: 309, y: 92, width: 46, height: 45)
        let target = CGRect(x: 100, y: 92, width: 255, height: 378)
        // Raw reference: source68px, menu378×577px. Body measurements are
        // separate from the head/neck envelope once those become visible.
        let reference: [(elapsed: CGFloat, width: CGFloat, height: CGFloat, drop: CGFloat)] = [
            (0.156, 312, 454, 88), (0.260, 249, 339, 96),
            (0.363, 185, 240, 81), (0.469, 132, 165, 58),
            (0.572, 89, 108, 45), (0.675, 58, 59, 43)
        ]
        for frame in reference {
            let outer = contextMenuBloomGeometrySample(
                source: source, target: target, sourceRadius: 22.5, targetRadius: 27,
                anchor: .topTrailing, direction: .closing,
                rawProgress: 1 - frame.elapsed, reduceMotion: false
            )
            let shape = contextMenuGlassmorphicGeometrySample(
                source: source, target: target, outerFrame: outer.frame, outerCornerRadii: outer.cornerRadii,
                sourceRadius: 22.5, targetRadius: 27, anchor: .topTrailing, direction: .closing,
                rawProgress: 1 - frame.elapsed, reduceMotion: false
            )
            let measuredBody = shape.bodyFrame
            XCTAssertEqual(measuredBody.width, frame.width * 255 / 378, accuracy: 3)
            XCTAssertEqual(measuredBody.height, frame.height * 378 / 577, accuracy: 3)
            XCTAssertEqual(measuredBody.minY - source.minY, frame.drop * 378 / 577, accuracy: 3)
            XCTAssertLessThan(shape.bodyFrame.height / shape.bodyFrame.width, 2,
                              "The filter menu collapsed into a tall narrow pillar")
        }
    }

    func testInterruptedClosingOnlyDissolvesAlreadyVisibleRowsAndCompletesOnce() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        let host = makeHost(appearance: .legacy)
        window.rootViewController?.view.addSubview(host)
        defer {
            host.tearDownGlassEffects()
            window.isHidden = true
        }
        var samples: [CGFloat] = []
        host.contentRevealProgressChanged = { samples.append($0) }
        host.setProgress(0.48)
        let originalReveal = try XCTUnwrap(samples.last)
        XCTAssertGreaterThan(originalReveal, 0)
        XCTAssertLessThan(originalReveal, 1)

        let completion = expectation(description: "Interrupted collapse finishes")
        var completionCount = 0
        host.animateCollapse(duration: 0.12, damping: 1) {
            completionCount += 1
            completion.fulfill()
        }
        wait(for: [completion], timeout: 2)

        for (previous, next) in zip(samples, samples.dropFirst()) {
            XCTAssertLessThanOrEqual(next, previous + 0.000001)
        }
        XCTAssertEqual(try XCTUnwrap(samples.last), 0, accuracy: 0.000001)
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(host.sourceProxyContainer.alpha, 1, accuracy: 0.000001)
        XCTAssertFalse(host.sourceProxyContainer.isHidden)
        XCTAssertEqual(host.liveMenuContentView.alpha, 0, accuracy: 0.000001)
        let snapshots = try menuContentViews(in: host).dropLast()
        XCTAssertTrue(snapshots.allSatisfy { $0.alpha == 0 })
    }

    func testRepeatedLayoutDoesNotResizeTransformedSnapshotContents() throws {
        let host = makeHost(appearance: .legacy)
        defer { host.tearDownGlassEffects() }
        host.setProgress(0.57)
        let views = try menuContentViews(in: host)
        let before = views.map(ViewRendering.init)

        for _ in 0..<4 { host.layoutSubviews() }

        for (view, rendering) in zip(views, before) {
            assertRendering(view, equals: rendering)
        }
    }

    func testReturningSourceMaskHasNoHolesWhereNativeLobesOverlap() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native merged glass requires iOS 26") }
        let host = makeHost(appearance: .liquidGlassV1, sourceWidth: 44)
        defer { host.tearDownGlassEffects() }
        var checkedPixels = 0
        var mismatchedPixels = 0
        var firstMismatch: CGPoint?
        for progress: CGFloat in [0.60, 0.50, 0.40, 0.30, 0.20] {
            host.setProgress(progress, direction: .closing)
            let mask = try XCTUnwrap(host.sourceProxyContainer.superview?.layer.mask)
            let paths = (mask.sublayers ?? []).compactMap { ($0 as? CAShapeLayer)?.path }
            let width = Int(ceil(mask.bounds.width))
            let height = Int(ceil(mask.bounds.height))
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(
                    data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                // CALayer renders in Quartz's bottom-left bitmap coordinates;
                // sample the result in the host's UIKit top-left coordinates.
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: 1, y: -1)
                mask.render(in: context)
            }
            let glyphArea = host.sourceProxyContainer.frame.insetBy(dx: 12, dy: 12)
            for y in stride(from: Int(glyphArea.minY), to: Int(glyphArea.maxY), by: 2) {
                for x in stride(from: Int(glyphArea.minX), to: Int(glyphArea.maxX), by: 2) {
                    let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    let interior = [
                        CGPoint(x: point.x - 1, y: point.y), CGPoint(x: point.x + 1, y: point.y),
                        CGPoint(x: point.x, y: point.y - 1), CGPoint(x: point.x, y: point.y + 1)
                    ]
                    guard paths.filter({ path in interior.allSatisfy { path.contains($0) } }).count >= 2 else { continue }
                    checkedPixels += 1
                    if pixels[(y * width + x) * 4 + 3] <= 240 {
                        mismatchedPixels += 1
                        firstMismatch = firstMismatch ?? point
                    }
                }
            }
        }
        XCTAssertGreaterThan(checkedPixels, 0, "The native close must exercise the source/body overlap")
        XCTAssertEqual(mismatchedPixels, 0,
                       "Mask holes: \(mismatchedPixels)/\(checkedPixels) pixels, first \(String(describing: firstMismatch))")
    }

    func testFallbackSourceMaskMatchesTheRenderedPlatter() throws {
        let host = makeHost(appearance: .legacy)
        defer { host.tearDownGlassEffects() }
        host.setProgress(0.60, direction: .closing)
        let mask = try XCTUnwrap(host.sourceProxyContainer.superview?.layer.mask)
        let path = try XCTUnwrap((mask.sublayers?.first as? CAShapeLayer)?.path)
        let surface = host.finalMenuGlassSurfaceView
        let renderedFrame = surface.convert(surface.bounds, to: host)
        let maskFrame = path.boundingBoxOfPath
        XCTAssertEqual(maskFrame.minX, renderedFrame.minX, accuracy: 0.000001)
        XCTAssertEqual(maskFrame.minY, renderedFrame.minY, accuracy: 0.000001)
        XCTAssertEqual(maskFrame.width, renderedFrame.width, accuracy: 0.000001)
        XCTAssertEqual(maskFrame.height, renderedFrame.height, accuracy: 0.000001)
    }

    func testSourceCaptionKeepsItsNaturalSizeInBothDirections() {
        for appearance in AetherAppearanceStyle.allCases {
            for width: CGFloat in [94, 160, 240] {
                let host = makeHost(appearance: appearance, menuHeight: 160, sourceWidth: width)
                defer { host.tearDownGlassEffects() }
                for direction in [ContextMenuBloomDirection.opening, .closing] {
                    for frame in 0...120 {
                        host.setProgress(CGFloat(frame) / 120, direction: direction)
                        let source = host.sourceProxyContainer
                        XCTAssertEqual(source.transform.a, 1)
                        XCTAssertEqual(source.transform.d, 1)
                        XCTAssertEqual(source.transform.b, 0)
                        XCTAssertEqual(source.transform.c, 0)
                        XCTAssertEqual(source.bounds.size, CGSize(width: width, height: 44))
                        XCTAssertEqual(source.frame, CGRect(x: 18, y: 70, width: width, height: 44),
                            "A returning caption must focus in place, without sliding through the shrinking belly")
                    }
                }
            }
        }
    }

    func testOpeningSizeCheckpointsHaveContinuousAccelerationAndNoExtraExtrema() {
        let times: [CGFloat] = [0, 0.26, 0.42, 0.55, 0.70, 0.78, 1]
        // Short/wide and tall silhouettes, including the compact seed plateau.
        for values: [CGFloat] in [[0, 0, 0.50, 0.80, 0.98, 1, 1],
                                  [64, 64, 122, 186, 371, 470, 470]] {
            func value(_ t: CGFloat) -> CGFloat {
                contextMenuBloomSmoothSample(times: times, values: values, at: t)
            }
            var previous = values[0]
            for step in 1...1000 {
                let current = value(CGFloat(step) / 1000)
                XCTAssertGreaterThanOrEqual(current + 0.000001, previous)
                XCTAssertLessThanOrEqual(current, values.last! + 0.000001)
                previous = current
            }
            let h: CGFloat = 0.000001
            for knot in times.dropFirst().dropLast() {
                let left = (value(knot) - 2 * value(knot-h) + value(knot-2*h)) / (h*h)
                let right = (value(knot+2*h) - 2 * value(knot+h) + value(knot)) / (h*h)
                XCTAssertEqual(left, right, accuracy: (values.last! - values[0]) * 0.03,
                    "An acceleration discontinuity at a size checkpoint reads as a skipped frame")
            }
        }
    }

    func testWideCaptionOnlyReturnsInsideTheRestoredGlassShoulder() throws {
        guard #available(iOS 26.0, *) else { return }
        for width: CGFloat in [94, 160, 240] {
            for height: CGFloat in [160, 378] {
                let host = makeHost(appearance: .liquidGlassV1, menuHeight: height, sourceWidth: width)
                defer { host.tearDownGlassEffects() }
                var visibleFrames = 0
                for frame in 0...120 {
                    host.setProgress(1 - CGFloat(frame) / 120, direction: .closing)
                    guard host.sourceProxyContainer.alpha > 0.01 else { continue }
                    visibleFrames += 1
                    let mask = try XCTUnwrap(host.sourceProxyContainer.superview?.layer.mask)
                    let paths = (mask.sublayers ?? []).filter { !$0.isHidden }
                        .compactMap { ($0 as? CAShapeLayer)?.path }
                    let caption = host.sourceProxyContainer.frame.insetBy(dx: 12, dy: 12)
                    for x in [caption.minX, caption.midX, caption.maxX] {
                        for y in [caption.minY, caption.midY, caption.maxY] {
                            XCTAssertTrue(paths.contains { $0.contains(CGPoint(x: x, y: y)) },
                                "The returning label is cut by the drop before the source shoulder arrives")
                        }
                    }
                }
                XCTAssertGreaterThan(visibleFrames, 0)
                XCTAssertEqual(host.sourceProxyContainer.alpha, 1)
            }
        }
    }

    func testMiddleOfOpeningExpansionMatchesTheReferenceTimeWindow() {
        let source = CGRect(x: 320, y: 70, width: 44, height: 44)
        let target = CGRect(x: 109, y: 70, width: 255, height: 378)
        var half: CGFloat?
        var almostFull: CGFloat?
        for frame in 0...1000 {
            let t = CGFloat(frame) / 1000
            let motion = contextMenuLiquidAnimationSample(fraction: t, reduceMotion: false)
            let shape = contextMenuGlassmorphicGeometrySample(source: source, target: target,
                outerFrame: source, outerCornerRadii: .uniform(22), sourceRadius: 22, targetRadius: 27,
                anchor: .topTrailing, direction: .opening, rawProgress: motion.progress, reduceMotion: false)
            let fraction = shape.bodyFrame.width * (1 + motion.rebound) / target.width
            if half == nil, fraction >= 0.5 { half = t }
            if almostFull == nil, fraction >= 0.9 { almostFull = t }
        }
        guard let half, let almostFull else { return XCTFail("The opening never reached its final width") }
        let milliseconds = (almostFull - half) * CGFloat(ContextMenuController.glassmorphicTiming.openDuration) * 1000
        // New native recording: roughly 100 ms, with a 16.7 ms frame window.
        // The previous accelerated phase crossed this range in about 45 ms.
        XCTAssertGreaterThanOrEqual(milliseconds, 80)
        XCTAssertLessThanOrEqual(milliseconds, 120)
    }

    func testOpeningRefractionDoesNotBlurAgainAfterRowsFocus() {
        #if !APPSTORE_SAFE
        guard #available(iOS 26.0, *) else { return }
        let host = makeHost(appearance: .liquidGlassV1)
        defer { host.tearDownGlassEffects() }
        XCTAssertTrue(host.contentRefractionForTesting.isInstalled)
        host.setProgress(0.64)
        var previous = host.contentRefractionForTesting
        XCTAssertGreaterThan(previous.displacement, 0)
        for step in 65...100 {
            host.setProgress(CGFloat(step) / 100)
            let current = host.contentRefractionForTesting
            XCTAssertLessThanOrEqual(current.displacement, previous.displacement + 0.000001)
            XCTAssertLessThanOrEqual(current.blur, previous.blur + 0.000001)
            previous = current
        }
        XCTAssertEqual(previous.displacement, 0)
        XCTAssertEqual(previous.blur, 0)
        #endif
    }

    func testOpeningKeepsAVisibleOpticalTransferBeforeTheLongSettle() throws {
        #if !APPSTORE_SAFE
        guard #available(iOS 26.0, *) else { return }
        let host = makeHost(appearance: .liquidGlassV1, menuHeight: 378, sourceWidth: 44)
        defer { host.tearDownGlassEffects() }
        let duration = ContextMenuController.glassmorphicTiming.openDuration
        host.animateExpand(duration: duration, damping: 0.86)
        host.advanceAnimation(to: 1)
        let snapshots = try menuContentViews(in: host)
        var visibleRefractionFrames = 0
        var peakScale: CGFloat = 1
        var peakTime: TimeInterval = 0
        for frame in 1...73 {
            let elapsed = Double(frame) / 120
            host.advanceAnimation(to: 1 + elapsed)
            if host.contentRefractionForTesting.displacement > 20,
               snapshots[0].alpha + host.liveMenuContentView.alpha > 0.5 {
                visibleRefractionFrames += 1
            }
            let scale = snapshots[0].transform.a
            if scale > peakScale { peakScale = scale; peakTime = elapsed }
        }
        XCTAssertGreaterThanOrEqual(Double(visibleRefractionFrames) / 120, 0.14,
            "The rows need a sustained optical transfer, not a three-frame blur flash")
        XCTAssertGreaterThanOrEqual(peakTime, 0.34)
        XCTAssertLessThanOrEqual(peakTime, 0.39)
        XCTAssertGreaterThanOrEqual(duration - peakTime, 0.20)
        XCTAssertEqual(host.contentRefractionForTesting.displacement, 0)
        XCTAssertEqual(host.liveMenuContentView.transform, .identity)
        #endif
    }

    func testOpeningExpansionDeceleratesIntoOneSmallOverscale() {
        let source = CGRect(x: 18, y: 70, width: 88, height: 44)
        let target = CGRect(x: 18, y: 70, width: 255, height: 170)
        func width(at t: CGFloat) -> CGFloat {
            let motion = contextMenuLiquidAnimationSample(fraction: t, reduceMotion: false)
            let shape = contextMenuGlassmorphicGeometrySample(source: source, target: target,
                outerFrame: source, outerCornerRadii: .uniform(22), sourceRadius: 22, targetRadius: 27,
                anchor: .init(unitPoint: .zero), direction: .opening,
                rawProgress: motion.progress, reduceMotion: false)
            return shape.bodyFrame.width * (1 + motion.rebound)
        }
        let expanding = (width(at: 0.40) - width(at: 0.32)) / 0.08
        let approaching = (width(at: 0.76) - width(at: 0.68)) / 0.08
        XCTAssertGreaterThan(expanding, approaching * 3,
            "The liquid transfer should accelerate out of the seed, then slow into the final size")
        let peak = width(at: 0.61)
        XCTAssertGreaterThan(peak, target.width * 1.02)
        XCTAssertLessThan(peak, target.width * 1.03)
        var previous = width(at: 0.32)
        for step in 321...1000 {
            let current = width(at: CGFloat(step) / 1000)
            if step <= 610 { XCTAssertGreaterThanOrEqual(current + 0.000001, previous) }
            else { XCTAssertLessThanOrEqual(current, previous + 0.000001) }
            previous = current
        }
        XCTAssertEqual(previous, target.width, accuracy: 0.000001)
    }

    func testFluidClockHasNoSeparateStationarySettlingPhase() {
        for direction in [ContextMenuBloomDirection.opening, .closing] {
            var previous: CGFloat = 0
            var previousOverscale: CGFloat = 0
            let peak: CGFloat = direction == .opening ? 0.61 : 0.52
            for frame in 0...1000 {
                let t = CGFloat(frame) / 1000
                let sample = contextMenuLiquidAnimationSample(fraction: t, reduceMotion: false, direction: direction)
                if frame > 0 { XCTAssertGreaterThan(sample.progress, previous) }
                if frame < 1000 { XCTAssertLessThan(sample.progress, 1) }
                XCTAssertGreaterThanOrEqual(sample.rebound, 0)
                XCTAssertLessThanOrEqual(sample.rebound, direction == .opening ? 0.0221 : 0.0141)
                if t <= peak { XCTAssertGreaterThanOrEqual(sample.rebound + 0.000000001, previousOverscale) }
                else { XCTAssertLessThanOrEqual(sample.rebound, previousOverscale + 0.000000001) }
                previous = sample.progress
                previousOverscale = sample.rebound
                XCTAssertEqual(contextMenuLiquidAnimationSample(fraction: t, reduceMotion: true, direction: direction).rebound, 0)
            }
            XCTAssertEqual(previous, 1)
            XCTAssertEqual(previousOverscale, 0)
        }
    }

    func testDisplayClockOverspringsGlassAndRowsTogetherAndKeepsTheLastFrameOnReversal() throws {
        for appearance in AetherAppearanceStyle.allCases {
            let host = makeHost(appearance: appearance, menuHeight: 160, sourceWidth: 160)
            defer { host.tearDownGlassEffects() }
            host.animateExpand(duration: 0.52, damping: 0.86)
            host.advanceAnimation(to: 1)
            // 467 ms is in the terminal recoil, after the content has arrived.
            for frame in 1...56 { host.advanceAnimation(to: 1 + Double(frame) / 120) }
            XCTAssertGreaterThan(host.finalMenuGlassSurfaceView.bounds.height, 160)
            XCTAssertLessThan(host.finalMenuGlassSurfaceView.bounds.height, 164)
            let scale = host.finalMenuGlassSurfaceView.bounds.height / 160
            XCTAssertEqual(host.liveMenuContentView.transform.a, scale, accuracy: 0.000001)
            XCTAssertEqual(host.liveMenuContentView.transform.d, scale, accuracy: 0.000001)
            let rows = host.liveMenuContentView.convert(host.liveMenuContentView.bounds, to: host)
            XCTAssertEqual(rows.minX, host.finalMenuGlassSurfaceView.frame.minX, accuracy: 0.000001)
            XCTAssertEqual(rows.minY, host.finalMenuGlassSurfaceView.frame.minY, accuracy: 0.000001)
            XCTAssertEqual(rows.width, host.finalMenuGlassSurfaceView.bounds.width, accuracy: 0.000001)
            let snapshots = try menuContentViews(in: host)
            XCTAssertEqual(snapshots[0].transform, host.liveMenuContentView.transform)
            XCTAssertEqual(host.sourceProxyContainer.transform.a, 1)
            let views = try menuContentViews(in: host) + [host.sourceProxyContainer, host.finalMenuGlassSurfaceView]
            let before = views.map(ViewRendering.init)
            var completions = 0
            host.animateCollapse(duration: 0.52, damping: 0.90) { completions += 1 }
            for (view, expected) in zip(views, before) { assertRendering(view, equals: expected) }
            host.advanceAnimation(to: 2)
            for frame in 1...64 {
                host.advanceAnimation(to: 2 + Double(frame) / 120)
                XCTAssertEqual(host.sourceProxyContainer.transform.a, 1)
                XCTAssertEqual(host.sourceProxyContainer.transform.d, 1)
                if frame == 51 {
                    let mask = try XCTUnwrap(host.sourceProxyContainer.superview?.layer.mask)
                    let paths = (mask.sublayers ?? []).filter { !$0.isHidden }
                        .compactMap { ($0 as? CAShapeLayer)?.path }
                    let outline = paths.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
                    XCTAssertGreaterThan(outline.width, 160)
                    XCTAssertGreaterThan(outline.height, 44)
                    XCTAssertLessThan(outline.height, 45)
                    XCTAssertEqual(outline.width / 160, outline.height / 44, accuracy: 0.005)
                }
            }
            XCTAssertEqual(completions, 1)
            XCTAssertEqual(host.sourceProxyContainer.transform, .identity)
            XCTAssertEqual(host.sourceProxyContainer.frame, CGRect(x: 18, y: 70, width: 160, height: 44))
            host.advanceAnimation(to: 4)
            XCTAssertEqual(completions, 1)
        }
    }

    func testContentRefractionSurvivesNativeLensingAndReturnsToZero() throws {
        let host = makeHost(appearance: .liquidGlassV1)
        defer { host.tearDownGlassEffects() }
        #if APPSTORE_SAFE
        XCTAssertFalse(host.contentRefractionForTesting.isInstalled)
        #else
        guard #available(iOS 26.0, *) else { return }
        XCTAssertTrue(host.contentRefractionForTesting.isInstalled)
        XCTAssertEqual(host.contentRefractionForTesting.displacement, 0)
        let contentViews = try menuContentViews(in: host)
        XCTAssertFalse(host.finalMenuGlassSurfaceView.contentView.layer.filters?.isEmpty ?? true)
        XCTAssertTrue(contentViews.allSatisfy { $0.layer.filters?.isEmpty ?? true },
                      "One parent lens must cover both snapshots and live content")
        host.animateExpand(duration: 0.52, damping: 0.86)
        host.advanceAnimation(to: 1)
        var openingPeak: CGFloat = 0
        for frame in 1...64 {
            host.advanceAnimation(to: 1 + Double(frame) / 120)
            openingPeak = max(openingPeak, host.contentRefractionForTesting.displacement)
        }
        XCTAssertGreaterThan(openingPeak, 20)
        XCTAssertEqual(host.contentRefractionForTesting.displacement, 0)
        XCTAssertEqual(host.contentRefractionForTesting.blur, 0)
        host.animateCollapse(duration: 0.52, damping: 0.90)
        host.advanceAnimation(to: 2)
        var closingPeak: CGFloat = 0
        for frame in 1...64 {
            host.advanceAnimation(to: 2 + Double(frame) / 120)
            closingPeak = max(closingPeak, host.contentRefractionForTesting.displacement)
        }
        XCTAssertGreaterThan(closingPeak, 20)
        XCTAssertEqual(host.contentRefractionForTesting.displacement, 0)
        XCTAssertEqual(host.sourceProxyContainer.transform, .identity)
        #endif
    }

    func testReversingOpeningPreservesDisplayedRefraction() {
        let host = makeHost(appearance: .liquidGlassV1)
        defer { host.tearDownGlassEffects() }
        host.animateExpand(duration: 0.52, damping: 0.86)
        host.advanceAnimation(to: 1)
        for frame in 1...32 { host.advanceAnimation(to: 1 + Double(frame) / 120) }
        let before = host.contentRefractionForTesting
        host.animateCollapse(duration: 0.52, damping: 0.90)
        XCTAssertEqual(host.contentRefractionForTesting.displacement, before.displacement, accuracy: 0.000001)
        XCTAssertEqual(host.contentRefractionForTesting.blur, before.blur, accuracy: 0.000001)
        host.cancelOrDismiss()
        XCTAssertEqual(host.contentRefractionForTesting.displacement, 0)
    }

    private func makeHost(appearance: AetherAppearanceStyle, menuHeight: CGFloat = 380, sourceWidth: CGFloat = 94) -> ContextMenuGlassmorphicTransitionView {
        let host = ContextMenuGlassmorphicTransitionView(
            sourceFrameInOverlay: CGRect(x: 18, y: 70, width: sourceWidth, height: 44),
            targetMenuFrameInOverlay: CGRect(x: 18, y: 70, width: 255, height: menuHeight),
            finalCornerRadius: 27, sourceCornerRadius: 22,
            sourceMode: .leasedGlassSource, isDark: false, appearanceStyle: appearance
        )
        host.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.layoutIfNeeded()
        return host
    }

    private func menuContentViews(in host: ContextMenuGlassmorphicTransitionView) throws -> [UIView] {
        let snapshots = try XCTUnwrap(host.finalMenuGlassSurfaceView.contentView.subviews.first {
            $0.subviews.filter { $0 is UIImageView }.count == 2
        })
        return [snapshots] + snapshots.subviews.filter { $0 is UIImageView } + [host.liveMenuContentView]
    }

    private struct ViewRendering {
        let alpha: CGFloat
        let transform: CGAffineTransform
        let bounds: CGRect
        let center: CGPoint

        init(_ view: UIView) {
            alpha = view.alpha
            transform = view.transform
            bounds = view.bounds
            center = view.center
        }
    }

    private func assertRendering(_ view: UIView, equals expected: ViewRendering, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(view.alpha, expected.alpha, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(view.transform, expected.transform, file: file, line: line)
        XCTAssertEqual(view.bounds, expected.bounds, file: file, line: line)
        XCTAssertEqual(view.center, expected.center, file: file, line: line)
    }
}
