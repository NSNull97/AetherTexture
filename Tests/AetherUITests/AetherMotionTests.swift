import XCTest
import UIKit
@testable import AetherUI

final class AetherMotionTests: XCTestCase {
    func testShortMenuReturnsBlurredSourceBeforeGlassHasFinishedCollapsing() {
        // Recording: source begins returning near 110ms, focuses near 210ms.
        let early = contextMenuSourceMaterializationSample(
            rawProgress: 1 - 0.110 / 0.32, direction: .closing, menuHeight: 160
        )
        XCTAssertGreaterThan(early.opacity, 0.001)
        XCTAssertGreaterThan(early.blurRadius, 4)
        let readable = contextMenuSourceMaterializationSample(
            rawProgress: 1 - 0.215 / 0.32, direction: .closing, menuHeight: 160
        )
        XCTAssertGreaterThan(readable.opacity, 0.95)
        XCTAssertLessThan(readable.blurRadius, 0.5)
        let source = CGRect(x: 18, y: 70, width: 94, height: 44)
        let target = CGRect(x: 18, y: 70, width: 255, height: 160)
        let geometry = contextMenuBloomGeometrySample(
            source: source, target: target, sourceRadius: 22, targetRadius: 27,
            anchor: .detect(source: source, target: target), direction: .closing,
            rawProgress: 1 - 0.215 / 0.32, reduceMotion: false
        )
        XCTAssertGreaterThan(geometry.frame.height, source.height)
    }

    func testShortMenuDoesNotHoldAnEmptyLensForAnother120Milliseconds() {
        let rowProgress = contextMenuClosingContentProgress(rawProgress: 1 - 0.090 / 0.32, menuHeight: 160)
        let rows = contextMenuBloomClosingContentWeights(at: rowProgress)
        XCTAssertEqual(rows.live + rows.sharp + rows.blurred, 0, accuracy: 0.0001)
        let source = contextMenuSourceMaterializationSample(
            rawProgress: 1 - 0.130 / 0.32, direction: .closing, menuHeight: 160
        )
        XCTAssertGreaterThan(source.opacity, 0.1)
    }

    func testSourceMaterializationHasStableEndpointsAndAccessibilityBlur() {
        for height: CGFloat in [120, 180, 380, 600] {
            for direction in [ContextMenuBloomDirection.opening, .closing] {
                let source = contextMenuSourceMaterializationSample(rawProgress: 0, direction: direction, menuHeight: height)
                let menu = contextMenuSourceMaterializationSample(rawProgress: 1, direction: direction, menuHeight: height)
                XCTAssertEqual(source.opacity, 1)
                XCTAssertEqual(source.blurRadius, 0)
                XCTAssertEqual(menu.opacity, 0)
            }
            let accessible = contextMenuSourceMaterializationSample(
                rawProgress: 0.5, direction: .closing, menuHeight: height, reduceMotion: true
            )
            XCTAssertEqual(accessible.blurRadius, 0)
        }
    }

    @MainActor
    func testReturningSourceIsNotClippedByTheStillTinySourceLobe() {
        let source = CGRect(x: 18, y: 70, width: 94, height: 44)
        let host = ContextMenuGlassmorphicTransitionView(
            sourceFrameInOverlay: source,
            targetMenuFrameInOverlay: CGRect(x: 18, y: 70, width: 255, height: 160),
            finalCornerRadius: 27, sourceCornerRadius: 22,
            sourceMode: .leasedGlassSource, isDark: false, appearanceStyle: .legacy
        )
        host.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.setProgress(1 - 0.130 / 0.32, direction: .closing)
        XCTAssertGreaterThan(host.sourceProxyContainer.alpha, 0.1)
        XCTAssertFalse(host.sourceProxyContainer.isHidden)
        XCTAssertEqual(host.sourceProxyContainer.bounds.size, source.size)
        XCTAssertEqual(host.sourceProxyContainer.superview?.bounds.size, host.bounds.size)
        host.setProgress(0, direction: .closing)
        XCTAssertEqual(host.sourceProxyContainer.frame, source)
        host.tearDownGlassEffects()
    }

    private struct TimedContextMenuBloomSample {
        let normalizedElapsed: CGFloat
        let rawProgress: CGFloat
        let geometry: ContextMenuBloomGeometrySample
    }

    private func contextMenuBloomSamplesAt120Hz(
        source: CGRect,
        target: CGRect,
        anchor: ContextMenuBloomAnchor,
        direction: ContextMenuBloomDirection,
        duration: TimeInterval
    ) -> [TimedContextMenuBloomSample] {
        let frameRate: TimeInterval = 120.0
        let frameCount = Int(ceil(duration * frameRate))
        return (0...frameCount).map { frameIndex in
            let elapsed = min(duration, TimeInterval(frameIndex) / frameRate)
            let normalizedElapsed = CGFloat(elapsed / duration)
            let rawProgress = direction == .opening
                ? normalizedElapsed
                : 1.0 - normalizedElapsed
            return TimedContextMenuBloomSample(
                normalizedElapsed: normalizedElapsed,
                rawProgress: rawProgress,
                geometry: contextMenuBloomGeometrySample(
                    source: source,
                    target: target,
                    sourceRadius: 22.5,
                    targetRadius: 27.0,
                    anchor: anchor,
                    direction: direction,
                    rawProgress: rawProgress,
                    reduceMotion: false
                )
            )
        }
    }

    private func contextMenuGlassmorphicSample(
        rawProgress: CGFloat,
        direction: ContextMenuBloomDirection,
        reduceMotion: Bool = false
    ) -> (outer: ContextMenuBloomGeometrySample, morph: ContextMenuGlassmorphicGeometrySample) {
        let source = CGRect(x: 309, y: 92, width: 46, height: 45)
        let target = CGRect(x: 100, y: 92, width: 255, height: 378)
        let anchor = ContextMenuBloomAnchor.topTrailing
        let outer = contextMenuBloomGeometrySample(
            source: source,
            target: target,
            sourceRadius: 22.5,
            targetRadius: 27.0,
            anchor: anchor,
            direction: .closing,
            rawProgress: rawProgress,
            reduceMotion: reduceMotion
        )
        let morph = contextMenuGlassmorphicGeometrySample(
            source: source,
            target: target,
            outerFrame: outer.frame,
            outerCornerRadii: outer.cornerRadii,
            sourceRadius: 22.5,
            targetRadius: 27.0,
            anchor: anchor,
            direction: direction,
            rawProgress: rawProgress,
            reduceMotion: reduceMotion
        )
        return (outer, morph)
    }

    private func contextMenuGlassmorphicVisibleBounds(
        of sample: ContextMenuGlassmorphicGeometrySample
    ) -> CGRect {
        func rotatedBounds(_ frame: CGRect, angle: CGFloat) -> CGRect {
            guard abs(angle) > 0.0001 else { return frame }
            let transform = CGAffineTransform(
                translationX: frame.midX,
                y: frame.midY
            )
                .rotated(by: angle)
                .translatedBy(x: -frame.midX, y: -frame.midY)
            return frame.applying(transform)
        }

        var bounds = CGRect.null
        if sample.headAlpha > 0.001 {
            bounds = bounds.union(rotatedBounds(sample.headFrame, angle: sample.headRotation))
        }
        if sample.bodyAlpha > 0.001 {
            bounds = bounds.union(rotatedBounds(sample.bodyFrame, angle: sample.bodyRotation))
        }
        if sample.bridgeRadius > 0.001 {
            let radius = sample.bridgeRadius
            let bridgeBounds = CGRect(
                x: min(sample.bridgeStart.x, sample.bridgeEnd.x) - radius,
                y: min(sample.bridgeStart.y, sample.bridgeEnd.y) - radius,
                width: abs(sample.bridgeEnd.x - sample.bridgeStart.x) + radius * 2.0,
                height: abs(sample.bridgeEnd.y - sample.bridgeStart.y) + radius * 2.0
            )
            bounds = bounds.union(bridgeBounds)
        }
        if sample.bridgeRadius > 0.001, sample.neckBulbRadius > 0.001 {
            let radius = sample.neckBulbRadius
            let continuationBounds = CGRect(
                x: min(sample.bridgeEnd.x, sample.neckBulbCenter.x) - radius,
                y: min(sample.bridgeEnd.y, sample.neckBulbCenter.y) - radius,
                width: abs(sample.neckBulbCenter.x - sample.bridgeEnd.x) + radius * 2.0,
                height: abs(sample.neckBulbCenter.y - sample.bridgeEnd.y) + radius * 2.0
            )
            bounds = bounds.union(continuationBounds)
        }
        if sample.neckBulbRadius > 0.001 {
            let radius = sample.neckBulbRadius
            bounds = bounds.union(CGRect(
                x: sample.neckBulbCenter.x - radius,
                y: sample.neckBulbCenter.y - radius,
                width: radius * 2.0,
                height: radius * 2.0
            ))
        }
        return bounds
    }

    func testReferenceProfilesKeepClosingFasterThanOpening() {
        XCTAssertEqual(AetherMotion.navigation.duration, 0.34, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.geometry.duration, 0.34, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.contentAppearanceDuration, 0.34, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.contentDisappearanceDuration, 0.34, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.contentBlurRadius, 12.0, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.replacementContentDelay, 0.0, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.contentScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.replacementContentScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.appearancePulseAmplitude, 0.08, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.replacementPulseAmplitude, 0.08, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.disappearancePulseAmplitude, -0.08, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.separatedGeometryDuration, 0.34, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.sizeMorphPulseDuration, 0.40, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.sizeMorphPrimaryAmplitude, 0.23, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.sizeMorphCrossAmplitude, 0.23, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.navigationChrome.sizeMorphCounterAmplitude, 0.032, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.tabBarSelection.duration, 0.54, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.tabBarMorph.duration, 0.58, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.tabBarMorph.dampingRatio, 0.77, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.tabBarMorph.initialVelocity, 0.12, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.bottomBarAccessoryResize.duration, 0.38, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.bottomBarAccessoryResize.dampingRatio, 0.80, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.bottomBarAccessoryResize.initialVelocity, 0.10, accuracy: 0.001)

        XCTAssertEqual(AetherMotion.contextMenu.presentation.duration, 0.42, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.contextMenu.dismissal.duration, 0.42, accuracy: 0.001)
        XCTAssertEqual(
            AetherMotion.contextMenu.dismissal.duration,
            AetherMotion.contextMenu.presentation.duration
        )

        XCTAssertEqual(AetherMotion.sourceModal.presentation.duration, 0.72, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.sourceModal.dismissal.duration, 0.52, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.search.presentation.duration, 0.86, accuracy: 0.001)
        XCTAssertEqual(AetherMotion.search.dismissal.duration, 0.60, accuracy: 0.001)
    }

    func testNavigationChromeMaterializationIsEndpointExactAndReversible() {
        let appearing = AetherMotion.navigationChromeMaterializationSamples(appearing: true)
        let disappearing = AetherMotion.navigationChromeMaterializationSamples(appearing: false)

        XCTAssertEqual(appearing.count, 41)
        XCTAssertEqual(appearing.first?.opacity ?? -1.0, 0.0, accuracy: 0.000_001)
        XCTAssertEqual(
            appearing.first?.blurRadius ?? -1.0,
            AetherMotion.navigationChrome.contentBlurRadius * 1.35,
            accuracy: 0.000_001
        )
        XCTAssertEqual(appearing.last?.opacity ?? -1.0, 1.0, accuracy: 0.000_001)
        XCTAssertEqual(appearing.last?.blurRadius ?? -1.0, 0.0, accuracy: 0.000_001)
        XCTAssertEqual(disappearing, Array(appearing.reversed()))
    }

    func testPublicSpringRatiosAreValidUIKitValues() {
        let springs = [
            AetherMotion.navigation,
            AetherMotion.navigationChrome.geometry,
            AetherMotion.tabBarSelection,
            AetherMotion.tabBarMorph,
            AetherMotion.bottomBarAccessoryResize,
            AetherMotion.contextMenu.presentation,
            AetherMotion.contextMenu.dismissal,
            AetherMotion.sourceModal.presentation,
            AetherMotion.sourceModal.dismissal,
            AetherMotion.search.presentation,
            AetherMotion.search.dismissal
        ]

        for spring in springs {
            XCTAssertGreaterThan(spring.duration, 0.0)
            XCTAssertGreaterThan(spring.dampingRatio, 0.0)
            XCTAssertLessThanOrEqual(spring.dampingRatio, 1.0)
        }
    }

    func testModalSourceTransitionUsesMeasuredDefaults() {
        let configuration = AetherModalSourceTransition.Configuration()
        XCTAssertEqual(configuration.presentationDuration, AetherMotion.sourceModal.presentation.duration)
        XCTAssertEqual(configuration.dismissalDuration, AetherMotion.sourceModal.dismissal.duration)
        XCTAssertEqual(configuration.presentationDampingRatio, AetherMotion.sourceModal.presentation.dampingRatio)
        XCTAssertEqual(configuration.dismissalDampingRatio, AetherMotion.sourceModal.dismissal.dampingRatio)
        XCTAssertEqual(configuration.initialSpringVelocity, AetherMotion.sourceModal.presentation.initialVelocity)
        XCTAssertEqual(configuration.dismissalInitialSpringVelocity, AetherMotion.sourceModal.dismissal.initialVelocity)
    }

    func testContextMenuGlassmorphicUsesReferenceTimingProfile() {
        let timing = ContextMenuController.glassmorphicTiming
        XCTAssertEqual(timing.openDuration, 0.42, accuracy: 0.001)
        XCTAssertEqual(timing.closeDuration, 0.42, accuracy: 0.001)
        XCTAssertEqual(timing.closeDuration, timing.openDuration, accuracy: 0.001)
    }

    func testContextMenuContentHandoffHasExactEndpoints() {
        let start = contextMenuBloomContentWeights(at: 0.0)
        XCTAssertEqual(start.blurred, 0.0, accuracy: 0.001)
        XCTAssertEqual(start.sharp, 0.0, accuracy: 0.001)
        XCTAssertEqual(start.live, 0.0, accuracy: 0.001)

        let heldSeed = contextMenuBloomContentWeights(at: 0.20)
        XCTAssertEqual(heldSeed.blurred, 0.0, accuracy: 0.001)
        XCTAssertEqual(heldSeed.sharp, 0.0, accuracy: 0.001)
        XCTAssertEqual(heldSeed.live, 0.0, accuracy: 0.001)

        let lensFirst = contextMenuBloomContentWeights(at: 0.36)
        XCTAssertGreaterThan(lensFirst.blurred, 0.10)
        XCTAssertEqual(lensFirst.sharp, 0.0, accuracy: 0.001)
        XCTAssertEqual(lensFirst.live, 0.0, accuracy: 0.001)

        let snapshotHandoff = contextMenuBloomContentWeights(at: 0.49)
        XCTAssertGreaterThan(snapshotHandoff.blurred, 0.0)
        XCTAssertGreaterThan(snapshotHandoff.sharp, 0.0)
        XCTAssertEqual(snapshotHandoff.live, 0.0, accuracy: 0.001)

        let liveHandoff = contextMenuBloomContentWeights(at: 0.70)
        XCTAssertLessThan(liveHandoff.blurred, liveHandoff.sharp)
        XCTAssertGreaterThan(liveHandoff.sharp, 0.0)
        XCTAssertGreaterThan(liveHandoff.live, 0.0)

        for progress in [CGFloat(0.80), 1.0, 1.25] {
            let settled = contextMenuBloomContentWeights(at: progress)
            XCTAssertEqual(settled.blurred, 0.0, accuracy: 0.001)
            XCTAssertEqual(settled.sharp, 0.0, accuracy: 0.001)
            XCTAssertEqual(settled.live, 1.0, accuracy: 0.001)
            XCTAssertEqual(settled.snapshotContainer, 0.0, accuracy: 0.001)
        }
    }

    func testContextMenuClosingContentKeepsEstablishedSlowerHandoff() {
        let start = contextMenuBloomClosingContentWeights(at: 0.0)
        XCTAssertEqual(start.blurred, 0.0, accuracy: 0.001)
        XCTAssertEqual(start.sharp, 0.0, accuracy: 0.001)
        XCTAssertEqual(start.live, 0.0, accuracy: 0.001)

        let lensFirst = contextMenuBloomClosingContentWeights(at: 0.32)
        XCTAssertGreaterThan(lensFirst.blurred, 0.0)
        XCTAssertEqual(lensFirst.sharp, 0.0, accuracy: 0.001)
        XCTAssertEqual(lensFirst.live, 0.0, accuracy: 0.001)

        let snapshotHandoff = contextMenuBloomClosingContentWeights(at: 0.52)
        XCTAssertGreaterThan(snapshotHandoff.blurred, 0.0)
        XCTAssertGreaterThan(snapshotHandoff.sharp, 0.0)
        XCTAssertEqual(snapshotHandoff.live, 0.0, accuracy: 0.001)

        let liveHandoff = contextMenuBloomClosingContentWeights(at: 0.80)
        XCTAssertEqual(liveHandoff.blurred, 0.0, accuracy: 0.001)
        XCTAssertGreaterThan(liveHandoff.sharp, 0.0)
        XCTAssertGreaterThan(liveHandoff.live, 0.0)
        XCTAssertEqual(liveHandoff.sharp, liveHandoff.live, accuracy: 0.001)

        let settled = contextMenuBloomClosingContentWeights(at: 0.92)
        XCTAssertEqual(settled.blurred, 0.0, accuracy: 0.001)
        XCTAssertEqual(settled.sharp, 0.0, accuracy: 0.001)
        XCTAssertEqual(settled.live, 1.0, accuracy: 0.001)
        XCTAssertEqual(settled.snapshotContainer, 0.0, accuracy: 0.001)
    }

    func testContextMenuContentRevealUsesFiniteMonotonicEqualPowerWeights() {
        var previous: CGFloat = 0.0
        for index in 0...1_000 {
            let progress = CGFloat(index) / 1_000.0
            let weights = contextMenuBloomContentWeights(at: progress)
            let reveal = contextMenuBloomRevealProgress(at: progress)

            for component in [
                weights.blurred,
                weights.sharp,
                weights.live,
                weights.snapshotContainer,
                reveal
            ] {
                XCTAssertTrue(component.isFinite, "Non-finite content weight at progress \(progress)")
                XCTAssertGreaterThanOrEqual(component, 0.0)
                XCTAssertLessThanOrEqual(component, 1.0)
            }

            XCTAssertEqual(
                hypot(weights.blurred, weights.sharp),
                weights.snapshotContainer,
                accuracy: 0.000_001,
                "Snapshot handoff lost equal power at progress \(progress)"
            )
            XCTAssertEqual(
                weights.blurred * weights.blurred
                    + weights.sharp * weights.sharp
                    + weights.live * weights.live,
                reveal * reveal,
                accuracy: 0.000_001,
                "Total content energy diverged from reveal at progress \(progress)"
            )
            XCTAssertGreaterThanOrEqual(reveal + 0.000_001, previous)
            previous = reveal
        }
        XCTAssertEqual(previous, 1.0, accuracy: 0.001)
    }

    func testContextMenuBloomGeometryHasExactEndpointsInBothDirections() {
        let source = CGRect(x: 309, y: 92, width: 46, height: 45)
        let target = CGRect(x: 100, y: 92, width: 255, height: 378)
        let anchor = ContextMenuBloomAnchor.detect(source: source, target: target)

        let openStart = contextMenuBloomGeometrySample(
            source: source,
            target: target,
            sourceRadius: 22.5,
            targetRadius: 27,
            anchor: anchor,
            direction: .opening,
            rawProgress: 0,
            reduceMotion: false
        )
        let openEnd = contextMenuBloomGeometrySample(
            source: source,
            target: target,
            sourceRadius: 22.5,
            targetRadius: 27,
            anchor: anchor,
            direction: .opening,
            rawProgress: 1,
            reduceMotion: false
        )
        let closeStart = contextMenuBloomGeometrySample(
            source: source,
            target: target,
            sourceRadius: 22.5,
            targetRadius: 27,
            anchor: anchor,
            direction: .closing,
            rawProgress: 1,
            reduceMotion: false
        )
        let closeEnd = contextMenuBloomGeometrySample(
            source: source,
            target: target,
            sourceRadius: 22.5,
            targetRadius: 27,
            anchor: anchor,
            direction: .closing,
            rawProgress: 0,
            reduceMotion: false
        )

        XCTAssertEqual(anchor, .topTrailing)
        XCTAssertEqual(openStart.frame, source)
        XCTAssertEqual(openEnd.frame, target)
        XCTAssertEqual(closeStart.frame, target)
        XCTAssertEqual(closeEnd.frame, source)
        XCTAssertEqual(openStart.cornerRadii, .uniform(22.5))
        XCTAssertEqual(openEnd.cornerRadii, .uniform(27))
        XCTAssertEqual(closeStart.cornerRadii, .uniform(27))
        XCTAssertEqual(closeEnd.cornerRadii, .uniform(22.5))
    }

    func testContextMenuBloomPinsSourceAndDestinationContentToTheSameAnchor() {
        let container = CGRect(x: 0, y: 0, width: 260, height: 300)
        let source = contextMenuBloomAnchoredFrame(
            contentSize: CGSize(width: 44, height: 44),
            in: container,
            anchor: .topTrailing
        )
        let destination = contextMenuBloomAnchoredFrame(
            contentSize: CGSize(width: 260, height: 220),
            in: container,
            anchor: .topTrailing
        )

        XCTAssertEqual(source, CGRect(x: 216, y: 0, width: 44, height: 44))
        XCTAssertEqual(destination, CGRect(x: 0, y: 0, width: 260, height: 220))
        XCTAssertEqual(source.maxX, destination.maxX)
        XCTAssertEqual(source.minY, destination.minY)
    }

    func testContextMenuBloomKeepsTopTrailingAnchorAcrossActual120HzFrames() throws {
        let source = CGRect(x: 309, y: 92, width: 46, height: 45)
        let target = CGRect(x: 100, y: 92, width: 255, height: 378)
        let anchor = ContextMenuBloomAnchor.detect(source: source, target: target)

        let timing = ContextMenuController.glassmorphicTiming
        let opening = contextMenuBloomSamplesAt120Hz(
            source: source,
            target: target,
            anchor: anchor,
            direction: .opening,
            duration: timing.openDuration
        )
        let closing = contextMenuBloomSamplesAt120Hz(
            source: source,
            target: target,
            anchor: anchor,
            direction: .closing,
            duration: timing.closeDuration
        )

        XCTAssertEqual(try XCTUnwrap(opening.first).geometry.frame, source)
        XCTAssertEqual(try XCTUnwrap(opening.last).geometry.frame, target)
        XCTAssertEqual(try XCTUnwrap(closing.first).geometry.frame, target)
        XCTAssertEqual(try XCTUnwrap(closing.last).geometry.frame, source)

        for timedSample in opening + closing {
            XCTAssertEqual(timedSample.geometry.frame.maxX, source.maxX, accuracy: 0.001)
            XCTAssertEqual(timedSample.geometry.frame.minY, source.minY, accuracy: 0.001)
        }
    }

    func testContextMenuBloomOpeningUsesMeasuredIndependentXYPeakWindowsAt120Hz() throws {
        let source = CGRect(x: 309, y: 92, width: 46, height: 45)
        let target = CGRect(x: 100, y: 92, width: 255, height: 378)
        let anchor = ContextMenuBloomAnchor.topTrailing
        let samples = contextMenuBloomSamplesAt120Hz(
            source: source,
            target: target,
            anchor: anchor,
            direction: .opening,
            duration: ContextMenuController.glassmorphicTiming.openDuration
        )
        let widthPeak = try XCTUnwrap(samples.max {
            $0.geometry.frame.width / target.width < $1.geometry.frame.width / target.width
        })
        let heightPeak = try XCTUnwrap(samples.max {
            $0.geometry.frame.height / target.height < $1.geometry.frame.height / target.height
        })

        let widthRatio = widthPeak.geometry.frame.width / target.width
        let heightRatio = heightPeak.geometry.frame.height / target.height
        XCTAssertEqual(widthRatio, 1.020, accuracy: 0.006)
        XCTAssertEqual(heightRatio, 1.027, accuracy: 0.006)

        // The measured opening holds a compact drop, then catches up late:
        // height peaks just before the 233 ms width rebound and both are
        // settled by roughly 267 ms of the 320 ms driver.
        let widthPeakMilliseconds = widthPeak.rawProgress
            * CGFloat(ContextMenuController.glassmorphicTiming.openDuration)
            * 1_000.0
        let heightPeakMilliseconds = heightPeak.rawProgress
            * CGFloat(ContextMenuController.glassmorphicTiming.openDuration)
            * 1_000.0
        XCTAssertEqual(widthPeakMilliseconds, 233.0 * 0.42 / 0.32, accuracy: 10.0)
        XCTAssertEqual(heightPeakMilliseconds, 222.0 * 0.42 / 0.32, accuracy: 14.0)

        let teardropProgress = CGFloat(117.0 / 320.0)
        let teardrop = try XCTUnwrap(samples.min {
            abs($0.rawProgress - teardropProgress) < abs($1.rawProgress - teardropProgress)
        })
        XCTAssertGreaterThan(teardrop.geometry.cornerRadii.topLeft, teardrop.geometry.cornerRadii.topRight)
    }

    func testContextMenuBloomOpeningKeepsVelocityThroughMeasuredCheckpoints() {
        let source = CGRect(x: 309, y: 92, width: 46, height: 45)
        let target = CGRect(x: 100, y: 92, width: 255, height: 378)
        let epsilon: CGFloat = 0.0001

        func sample(rawProgress: CGFloat) -> ContextMenuBloomGeometrySample {
            contextMenuBloomGeometrySample(
                source: source,
                target: target,
                sourceRadius: 22.5,
                targetRadius: 27,
                anchor: .topTrailing,
                direction: .opening,
                rawProgress: rawProgress,
                reduceMotion: false
            )
        }

        let checkpoint: CGFloat = 150.0 / 320.0
        let before = sample(rawProgress: checkpoint - epsilon)
        let center = sample(rawProgress: checkpoint)
        let after = sample(rawProgress: checkpoint + epsilon)
        let widthVelocityBefore = (center.widthT - before.widthT) / epsilon
        let widthVelocityAfter = (after.widthT - center.widthT) / epsilon
        let heightVelocityBefore = (center.heightT - before.heightT) / epsilon
        let heightVelocityAfter = (after.heightT - center.heightT) / epsilon

        // A segmented smootherstep has zero velocity on both sides here and
        // creates a tiny stop. The continuous Hermite profile keeps the shell
        // moving and matches its derivative across the measured checkpoint.
        XCTAssertGreaterThan(widthVelocityBefore, 0.5)
        XCTAssertGreaterThan(widthVelocityAfter, 0.5)
        XCTAssertGreaterThan(heightVelocityBefore, 0.5)
        XCTAssertGreaterThan(heightVelocityAfter, 0.5)
        XCTAssertEqual(widthVelocityBefore, widthVelocityAfter, accuracy: 0.01)
        XCTAssertEqual(heightVelocityBefore, heightVelocityAfter, accuracy: 0.01)
    }

    func testContextMenuBloomClosingIsNotTimeReversedOpening() {
        let source = CGRect(x: 309, y: 92, width: 46, height: 45)
        let target = CGRect(x: 100, y: 92, width: 255, height: 378)
        let anchor = ContextMenuBloomAnchor.topTrailing
        var maximumCloseT: CGFloat = 0
        var maximumBodyWidth: CGFloat = 0
        var maximumBodyHeight: CGFloat = 0

        for index in 0...120 {
            let raw = CGFloat(index) / 120.0
            let close = contextMenuBloomGeometrySample(
                source: source,
                target: target,
                sourceRadius: 22.5,
                targetRadius: 27,
                anchor: anchor,
                direction: .closing,
                rawProgress: raw,
                reduceMotion: false
            )
            maximumCloseT = max(maximumCloseT, max(close.widthT, close.heightT))
            let body = contextMenuGlassmorphicGeometrySample(
                source: source, target: target, outerFrame: close.frame, outerCornerRadii: close.cornerRadii,
                sourceRadius: 22.5, targetRadius: 27, anchor: anchor,
                direction: .closing, rawProgress: raw, reduceMotion: false
            ).bodyFrame
            maximumBodyWidth = max(maximumBodyWidth, body.width)
            maximumBodyHeight = max(maximumBodyHeight, body.height)
        }

        let openingMiddle = contextMenuBloomGeometrySample(
            source: source,
            target: target,
            sourceRadius: 22.5,
            targetRadius: 27,
            anchor: anchor,
            direction: .opening,
            rawProgress: 0.5,
            reduceMotion: false
        )
        let closingMiddle = contextMenuBloomGeometrySample(
            source: source,
            target: target,
            sourceRadius: 22.5,
            targetRadius: 27,
            anchor: anchor,
            direction: .closing,
            rawProgress: 0.5,
            reduceMotion: false
        )

        XCTAssertNotEqual(openingMiddle.widthT, closingMiddle.widthT, accuracy: 0.05)
        // The tall reference moves its shrinking body down on the first
        // frames. Its source-to-body envelope grows about 1.8% even though
        // the body itself never expands; allow the measured edge tolerance.
        XCTAssertLessThanOrEqual(maximumCloseT, 1.025)
        XCTAssertLessThanOrEqual(maximumBodyWidth, target.width + 0.01)
        XCTAssertLessThanOrEqual(maximumBodyHeight, target.height + 0.01)
    }

    func testContextMenuBloomOpeningKeepsReferenceAccelerationAtAdjustedTempo() {
        let source = CGRect(x: 309, y: 92, width: 46, height: 45)
        let target = CGRect(x: 100, y: 92, width: 255, height: 378)
        // Check the recorded phase positions independently of the slower runtime clock.
        let duration: CGFloat = 0.32

        func sample(milliseconds: CGFloat) -> ContextMenuBloomGeometrySample {
            contextMenuBloomGeometrySample(
                source: source,
                target: target,
                sourceRadius: 22.5,
                targetRadius: 27.0,
                anchor: .topTrailing,
                direction: .opening,
                rawProgress: milliseconds / 1_000.0 / duration,
                reduceMotion: false
            )
        }

        let compactDrop = sample(milliseconds: 50)
        let acceleratingDrop = sample(milliseconds: 83)
        let developedPear = sample(milliseconds: 117)
        let broadPear = sample(milliseconds: 150)
        let almostFullDrop = sample(milliseconds: 183)
        let rebound = sample(milliseconds: 233)
        let settled = sample(milliseconds: 267)

        XCTAssertLessThan(compactDrop.widthT, 0.12)
        XCTAssertLessThan(compactDrop.heightT, 0.12)
        XCTAssertGreaterThan(acceleratingDrop.widthT, 0.36)
        XCTAssertLessThan(acceleratingDrop.widthT, 0.48)
        XCTAssertGreaterThan(developedPear.widthT, 0.62)
        XCTAssertLessThan(developedPear.widthT, 0.72)
        XCTAssertGreaterThan(broadPear.widthT, 0.76)
        XCTAssertLessThan(broadPear.widthT, 0.84)
        XCTAssertGreaterThan(almostFullDrop.widthT, 0.90)
        XCTAssertLessThan(almostFullDrop.heightT, 0.93)
        XCTAssertGreaterThan(rebound.widthT, 1.020)
        XCTAssertGreaterThan(rebound.heightT, 1.020)
        XCTAssertEqual(settled.widthT, 1.0, accuracy: 0.01)
        XCTAssertEqual(settled.heightT, 1.0, accuracy: 0.01)
    }

    func testContextMenuGlassmorphicHasExactSourceAndMenuEndpoints() {
        let source = CGRect(x: 309, y: 92, width: 46, height: 45)
        let target = CGRect(x: 100, y: 92, width: 255, height: 378)
        let sourceCenter = CGPoint(x: source.midX, y: source.midY)
        let collapsedHead = CGRect(
            x: sourceCenter.x - 0.5,
            y: sourceCenter.y - 0.5,
            width: 1.0,
            height: 1.0
        )

        for direction in [ContextMenuBloomDirection.opening, .closing] {
            let start = contextMenuGlassmorphicSample(rawProgress: 0.0, direction: direction).morph
            XCTAssertEqual(start.headFrame, source)
            XCTAssertEqual(start.bodyFrame, source)
            XCTAssertEqual(start.headRadius, 22.5)
            XCTAssertEqual(start.bodyCornerRadii, .uniform(22.5))
            XCTAssertEqual(start.bridgeStart, sourceCenter)
            XCTAssertEqual(start.bridgeEnd, sourceCenter)
            XCTAssertEqual(start.bridgeRadius, 0.0)
            XCTAssertEqual(start.neckBulbCenter, sourceCenter)
            XCTAssertEqual(start.neckBulbRadius, 0.0)
            XCTAssertEqual(start.headAlpha, 1.0)
            XCTAssertEqual(start.bodyAlpha, 0.0)

            let end = contextMenuGlassmorphicSample(rawProgress: 1.0, direction: direction).morph
            XCTAssertEqual(end.headFrame, collapsedHead)
            XCTAssertEqual(end.bodyFrame, target)
            XCTAssertEqual(end.headRadius, 0.5)
            XCTAssertEqual(end.bodyCornerRadii, .uniform(27.0))
            XCTAssertEqual(end.bridgeStart, sourceCenter)
            XCTAssertEqual(end.bridgeEnd, sourceCenter)
            XCTAssertEqual(end.bridgeRadius, 0.0)
            XCTAssertEqual(end.neckBulbCenter, sourceCenter)
            XCTAssertEqual(end.neckBulbRadius, 0.0)
            XCTAssertEqual(end.headAlpha, 0.0)
            XCTAssertEqual(end.bodyAlpha, 1.0)
        }
    }

    func testContextMenuGlassmorphicOpeningVisibleUnionIsContinuousAt120Hz() throws {
        let duration = ContextMenuController.glassmorphicTiming.openDuration
        let frameCount = Int(ceil(duration * 120.0))
        let sourceMinSide: CGFloat = 45.0
        var previousBounds: CGRect?

        for frameIndex in 0...frameCount {
            let elapsed = min(duration, TimeInterval(frameIndex) / 120.0)
            let progress = CGFloat(elapsed / duration)
            let bounds = contextMenuGlassmorphicVisibleBounds(
                of: contextMenuGlassmorphicSample(
                    rawProgress: progress,
                    direction: .opening
                ).morph
            )
            XCTAssertFalse(bounds.isNull)

            if let previousBounds {
                // The liquid profile now spends nearly the entire 320 ms
                // driver on motion. Keep every 120 Hz step comfortably below
                // one source diameter while allowing the measured late
                // acceleration and rebound.
                XCTAssertLessThanOrEqual(
                    abs(bounds.width - previousBounds.width),
                    sourceMinSide * 0.80,
                    "Opening union width jumped at 120 Hz frame \(frameIndex)"
                )
                XCTAssertLessThanOrEqual(
                    abs(bounds.height - previousBounds.height),
                    sourceMinSide * 1.00,
                    "Opening union height jumped at 120 Hz frame \(frameIndex)"
                )
                XCTAssertLessThanOrEqual(
                    hypot(bounds.midX - previousBounds.midX, bounds.midY - previousBounds.midY),
                    sourceMinSide * 0.90,
                    "Opening union centroid jumped at 120 Hz frame \(frameIndex)"
                )
            }
            previousBounds = bounds
        }
    }

    func testContextMenuGlassmorphicKeepsVisibleUnionInsideTopTrailingPinnedOuterBounds() {
        let source = CGRect(x: 309, y: 92, width: 46, height: 45)
        let checkpoints: [CGFloat] = [0.0, 0.36, 0.48, 0.58, 0.70, 0.82, 1.0]

        for direction in [ContextMenuBloomDirection.opening, .closing] {
            for progress in checkpoints {
                let sample = contextMenuGlassmorphicSample(
                    rawProgress: progress,
                    direction: direction
                )
                let visibleBounds = contextMenuGlassmorphicVisibleBounds(of: sample.morph)

                XCTAssertFalse(visibleBounds.isNull)
                XCTAssertLessThanOrEqual(
                    visibleBounds.maxX,
                    sample.outer.frame.maxX + 0.01,
                    "Visible union escaped the trailing bound at progress \(progress), direction \(direction)"
                )
                XCTAssertGreaterThanOrEqual(
                    visibleBounds.minY,
                    sample.outer.frame.minY - 0.01,
                    "Visible union escaped the top bound at progress \(progress), direction \(direction)"
                )
                XCTAssertEqual(sample.outer.frame.maxX, source.maxX, accuracy: 0.01)
                XCTAssertEqual(sample.outer.frame.minY, source.minY, accuracy: 0.01)
            }
        }
    }

    func testContextMenuGlassmorphicUsesThickerBodySideContinuationDuringNeckPhase() {

        let sample = contextMenuGlassmorphicSample(
            rawProgress: 0.42,
            direction: .closing
        ).morph
        XCTAssertGreaterThan(sample.bridgeRadius, 0.5)
        XCTAssertGreaterThan(sample.neckBulbRadius, sample.bridgeRadius)
        XCTAssertGreaterThan(sample.headAlpha, 0.001)
        XCTAssertGreaterThan(sample.bodyAlpha, 0.001)

        let distanceToBridgeStart = hypot(
            sample.neckBulbCenter.x - sample.bridgeStart.x,
            sample.neckBulbCenter.y - sample.bridgeStart.y
        )
        let distanceToBridgeEnd = hypot(
            sample.neckBulbCenter.x - sample.bridgeEnd.x,
            sample.neckBulbCenter.y - sample.bridgeEnd.y
        )
        XCTAssertLessThan(
            distanceToBridgeEnd,
            distanceToBridgeStart,
            "Bulb must terminate the body side of the shortened bridge"
        )

        for direction in [ContextMenuBloomDirection.opening, .closing] {
            for progress in [CGFloat(0.0), 0.01, 0.99, 1.0] {
                let sample = contextMenuGlassmorphicSample(
                    rawProgress: progress,
                    direction: direction
                ).morph
                XCTAssertEqual(
                    sample.neckBulbRadius,
                    0.0,
                    accuracy: 0.001,
                    "Bulb leaked outside the middle morph phase at progress \(progress)"
                )
            }

            for index in 0...200 {
                let progress = CGFloat(index) / 200.0
                let sample = contextMenuGlassmorphicSample(
                    rawProgress: progress,
                    direction: direction
                ).morph
                if sample.bridgeRadius > 0.5 {
                    XCTAssertGreaterThan(sample.neckBulbRadius, sample.bridgeRadius)
                    XCTAssertGreaterThan(progress, 0.0)
                    XCTAssertLessThan(progress, 1.0)
                }
            }
        }
    }

    func testContextMenuGlassmorphicTopTrailingTailExitsBottomLeadingThenCurvesInward() {

        let progress: CGFloat = 0.42
        let sample = contextMenuGlassmorphicSample(
            rawProgress: progress,
            direction: .closing
        ).morph

        XCTAssertGreaterThan(sample.bridgeRadius, 4.0)
        XCTAssertGreaterThan(sample.neckBulbRadius, sample.bridgeRadius)

        let points = [
            sample.bridgeStart,
            sample.bridgeEnd,
            sample.neckBulbCenter
        ]
        for point in points {
            XCTAssertTrue(point.x.isFinite)
            XCTAssertTrue(point.y.isFinite)
        }
        XCTAssertTrue(sample.bridgeRadius.isFinite)
        XCTAssertTrue(sample.neckBulbRadius.isFinite)

        let headCenter = CGPoint(
            x: sample.headFrame.midX,
            y: sample.headFrame.midY
        )
        XCTAssertLessThan(
            sample.bridgeStart.x,
            headCenter.x,
            "Top-trailing tail must leave through the leading half"
        )
        XCTAssertGreaterThan(
            sample.bridgeStart.y,
            headCenter.y,
            "Top-trailing tail must leave through the bottom half"
        )

        let sourceSegment = (
            dx: sample.bridgeEnd.x - sample.bridgeStart.x,
            dy: sample.bridgeEnd.y - sample.bridgeStart.y
        )
        let continuationSegment = (
            dx: sample.neckBulbCenter.x - sample.bridgeEnd.x,
            dy: sample.neckBulbCenter.y - sample.bridgeEnd.y
        )

        XCTAssertLessThan(sourceSegment.dx, 0.0)
        XCTAssertGreaterThan(sourceSegment.dy, 0.0)
        XCTAssertLessThan(continuationSegment.dx, 0.0)
        XCTAssertGreaterThan(continuationSegment.dy, 0.0)
        XCTAssertGreaterThan(abs(sourceSegment.dy), abs(sourceSegment.dx))

        let sourceLeadingSlope = abs(sourceSegment.dx) / sourceSegment.dy
        let continuationLeadingSlope = abs(continuationSegment.dx) / continuationSegment.dy
        XCTAssertGreaterThan(
            continuationLeadingSlope,
            sourceLeadingSlope,
            "Continuation must turn inward after the nearly vertical exit"
        )

        let cross = sourceSegment.dx * continuationSegment.dy
            - sourceSegment.dy * continuationSegment.dx
        let dot = sourceSegment.dx * continuationSegment.dx
            + sourceSegment.dy * continuationSegment.dy
        XCTAssertGreaterThan(cross, 0.0, "Tail segments became collinear or turned outward")
        XCTAssertGreaterThan(dot, 0.0, "Tail segments lost directional continuity")

        let bodyCenter = CGPoint(
            x: sample.bodyFrame.midX,
            y: sample.bodyFrame.midY
        )
        let kneeToBody = hypot(
            sample.bridgeEnd.x - bodyCenter.x,
            sample.bridgeEnd.y - bodyCenter.y
        )
        let continuationToBody = hypot(
            sample.neckBulbCenter.x - bodyCenter.x,
            sample.neckBulbCenter.y - bodyCenter.y
        )
        XCTAssertLessThan(continuationToBody, kneeToBody)

        // Production renders two capsules that share the exact knee;
        // the body-side continuation uses neckBulbRadius throughout.
        let sourceCapsuleEnd = sample.bridgeEnd
        let continuationCapsuleStart = sample.bridgeEnd
        XCTAssertEqual(sourceCapsuleEnd, continuationCapsuleStart)

        let reduced = contextMenuGlassmorphicSample(
            rawProgress: progress,
            direction: .closing,
            reduceMotion: true
        ).morph
        XCTAssertEqual(reduced.bridgeRadius, 0.0)
        XCTAssertEqual(reduced.neckBulbRadius, 0.0)
    }

    func testContextMenuGlassmorphicRegistersBridgeAndBulbTogetherAndRemovesThemForReduceMotion() {
        let sampleCount = 4_000

        for direction in [ContextMenuBloomDirection.opening, .closing] {
            var sawActiveNeck = false
            for index in 0...sampleCount {
                let progress = CGFloat(index) / CGFloat(sampleCount)
                let sample = contextMenuGlassmorphicSample(
                    rawProgress: progress,
                    direction: direction
                ).morph
                let bridgeIsVisible = sample.bridgeRadius > 0.5
                let bulbIsVisible = sample.neckBulbRadius > 0.5

                XCTAssertEqual(
                    bridgeIsVisible,
                    bulbIsVisible,
                    "Bridge and bulb visibility diverged at progress \(progress), direction \(direction)"
                )
                if bridgeIsVisible {
                    sawActiveNeck = true
                    XCTAssertGreaterThan(sample.neckBulbRadius, sample.bridgeRadius)
                }
            }
            XCTAssertTrue(sawActiveNeck, "Both directions must traverse the same connected neck")

            let reducedSample = contextMenuGlassmorphicSample(
                rawProgress: 0.5,
                direction: direction,
                reduceMotion: true
            ).morph
            XCTAssertEqual(reducedSample.bridgeRadius, 0.0)
            XCTAssertEqual(reducedSample.neckBulbRadius, 0.0)
        }
    }

    func testContextMenuGlassmorphicInterpolationPreservesEndpoints() {
        let from = contextMenuGlassmorphicSample(rawProgress: 0.48, direction: .opening).morph
        let to = contextMenuGlassmorphicSample(rawProgress: 0.42, direction: .closing).morph

        XCTAssertEqual(
            ContextMenuGlassmorphicGeometrySample.interpolated(from: from, to: to, progress: -1.0),
            from
        )
        XCTAssertEqual(
            ContextMenuGlassmorphicGeometrySample.interpolated(from: from, to: to, progress: 0.0),
            from
        )
        XCTAssertEqual(
            ContextMenuGlassmorphicGeometrySample.interpolated(from: from, to: to, progress: 1.0),
            to
        )
        XCTAssertEqual(
            ContextMenuGlassmorphicGeometrySample.interpolated(from: from, to: to, progress: 2.0),
            to
        )

        let midpoint = ContextMenuGlassmorphicGeometrySample.interpolated(
            from: from,
            to: to,
            progress: 0.5
        )
        XCTAssertEqual(midpoint.headFrame.midX, (from.headFrame.midX + to.headFrame.midX) * 0.5, accuracy: 0.001)
        XCTAssertEqual(midpoint.bodyFrame.height, (from.bodyFrame.height + to.bodyFrame.height) * 0.5, accuracy: 0.001)
        XCTAssertEqual(midpoint.headRotation, (from.headRotation + to.headRotation) * 0.5, accuracy: 0.001)
        XCTAssertEqual(midpoint.bodyRotation, (from.bodyRotation + to.bodyRotation) * 0.5, accuracy: 0.001)
        XCTAssertEqual(midpoint.bridgeRadius, (from.bridgeRadius + to.bridgeRadius) * 0.5, accuracy: 0.001)
        XCTAssertEqual(midpoint.neckBulbCenter.x, (from.neckBulbCenter.x + to.neckBulbCenter.x) * 0.5, accuracy: 0.001)
        XCTAssertEqual(midpoint.neckBulbCenter.y, (from.neckBulbCenter.y + to.neckBulbCenter.y) * 0.5, accuracy: 0.001)
        XCTAssertEqual(midpoint.neckBulbRadius, (from.neckBulbRadius + to.neckBulbRadius) * 0.5, accuracy: 0.001)
        XCTAssertEqual(midpoint.headAlpha, (from.headAlpha + to.headAlpha) * 0.5, accuracy: 0.001)
        XCTAssertEqual(midpoint.bodyAlpha, (from.bodyAlpha + to.bodyAlpha) * 0.5, accuracy: 0.001)
    }

    func testTouchEffectAnimationsAreRemovalSafe() {
        let view = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 44.0, height: 44.0))
        let effect = TouchEffect(view: view, highlightContainerView: view, reducesMotion: false)
        effect.setIsTracking(true)

        let press = view.layer.animation(forKey: "aether.touchEffect.sublayerTransform")
        XCTAssertNotNil(press)
        XCTAssertEqual(press?.isRemovedOnCompletion, true)

        effect.setIsTracking(false)
        let release = view.layer.animation(forKey: "aether.touchEffect.sublayerTransform")
        XCTAssertNotNil(release)
        XCTAssertEqual(release?.isRemovedOnCompletion, true)
        XCTAssertTrue(CATransform3DIsIdentity(view.layer.sublayerTransform))
    }

    func testGrowingTrailingGlassGroupGetsIndependentEdgeAnchoredSizePulse() throws {
        guard !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Size pulses are intentionally disabled with Reduce Motion")
        }
        let group = GlassControlGroup()
        group.transitionContentAlignment = .trailing
        let trailingImage = try XCTUnwrap(UIImage(systemName: "ellipsis"))
        let leadingImage = try XCTUnwrap(UIImage(systemName: "camera"))
        let trailing = GlassControlGroup.Item(id: "trailing", content: .icon(trailingImage), action: nil)
        let leading = GlassControlGroup.Item(id: "leading", content: .icon(leadingImage), action: nil)

        _ = group.update(items: [trailing], transition: .immediate)
        _ = group.update(
            items: [leading, trailing],
            transition: .animated(duration: 0.20, curve: .easeInOut)
        )

        let animation = try XCTUnwrap(group.sizeMorphPulseAnimationForTesting)
        let transforms = try XCTUnwrap(animation.values).compactMap { value -> CATransform3D? in
            (value as? NSValue)?.caTransform3DValue
        }
        XCTAssertEqual(animation.keyPath, "transform")
        XCTAssertEqual(animation.duration, AetherMotion.navigationChrome.sizeMorphPulseDuration, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(transforms.count, 30)
        let peakIndex = try XCTUnwrap(transforms.indices.max(by: { transforms[$0].m22 < transforms[$1].m22 }))
        let counterIndex = try XCTUnwrap(transforms.indices.min(by: { transforms[$0].m22 < transforms[$1].m22 }))
        let peak = transforms[peakIndex]
        let counter = transforms[counterIndex]
        XCTAssertEqual(peak.m22, 1.23, accuracy: 0.001)
        XCTAssertEqual(counter.m22, 0.968_282, accuracy: 0.001)
        XCTAssertEqual(peak.m41, 0.0, accuracy: 0.000_001)
        let peakProgress = ContainedViewLayoutTransitionCurve.easeInOut.value(
            at: CGFloat(peakIndex) / CGFloat(transforms.count - 1)
        )
        let peakWidth = 44.0 + 44.0 * peakProgress
        XCTAssertEqual((peak.m11 - 1.0) * peakWidth, (peak.m22 - 1.0) * 44.0, accuracy: 0.01)
        let counterProgress = ContainedViewLayoutTransitionCurve.easeInOut.value(
            at: CGFloat(counterIndex) / CGFloat(transforms.count - 1)
        )
        let counterWidth = 44.0 + 44.0 * counterProgress
        XCTAssertEqual((counter.m11 - 1.0) * counterWidth, (counter.m22 - 1.0) * 44.0, accuracy: 0.01)
        XCTAssertTrue(CATransform3DIsIdentity(transforms[0]))
        XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(transforms.last)))
        XCTAssertTrue(CATransform3DIsIdentity(group.sizeMorphPulseModelTransformForTesting))
        XCTAssertTrue(CATransform3DIsIdentity(group.layer.sublayerTransform))
        XCTAssertTrue(CATransform3DIsIdentity(group.layer.transform))
        XCTAssertNotNil(group.materialPulseCounterAnimationForTesting)
    }

    func testShrinkingLeadingGlassGroupUsesCompressionThenRebound() throws {
        guard !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Size pulses are intentionally disabled with Reduce Motion")
        }
        let group = GlassControlGroup()
        group.transitionContentAlignment = .leading
        let firstImage = try XCTUnwrap(UIImage(systemName: "camera"))
        let secondImage = try XCTUnwrap(UIImage(systemName: "ellipsis"))
        let first = GlassControlGroup.Item(id: "first", content: .icon(firstImage), action: nil)
        let second = GlassControlGroup.Item(id: "second", content: .icon(secondImage), action: nil)

        _ = group.update(items: [first, second], transition: .immediate)
        _ = group.update(
            items: [first],
            transition: .animated(duration: 0.20, curve: .easeInOut)
        )

        let animation = try XCTUnwrap(group.sizeMorphPulseAnimationForTesting)
        let transforms = try XCTUnwrap(animation.values).compactMap { value -> CATransform3D? in
            (value as? NSValue)?.caTransform3DValue
        }
        XCTAssertGreaterThanOrEqual(transforms.count, 30)
        let peakIndex = try XCTUnwrap(transforms.indices.max(by: { transforms[$0].m22 < transforms[$1].m22 }))
        let counterIndex = try XCTUnwrap(transforms.indices.min(by: { transforms[$0].m22 < transforms[$1].m22 }))
        let peak = transforms[peakIndex]
        let counter = transforms[counterIndex]
        XCTAssertEqual(peak.m22, 1.23, accuracy: 0.001)
        XCTAssertEqual(counter.m22, 0.968_282, accuracy: 0.001)
        XCTAssertEqual(peak.m41, 0.0, accuracy: 0.000_001)
        let peakProgress = ContainedViewLayoutTransitionCurve.easeInOut.value(
            at: CGFloat(peakIndex) / CGFloat(transforms.count - 1)
        )
        let peakWidth = 88.0 - 44.0 * peakProgress
        XCTAssertEqual((peak.m11 - 1.0) * peakWidth, (peak.m22 - 1.0) * 44.0, accuracy: 0.01)
        let counterProgress = ContainedViewLayoutTransitionCurve.easeInOut.value(
            at: CGFloat(counterIndex) / CGFloat(transforms.count - 1)
        )
        let counterWidth = 88.0 - 44.0 * counterProgress
        XCTAssertEqual((counter.m11 - 1.0) * counterWidth, (counter.m22 - 1.0) * 44.0, accuracy: 0.01)
        XCTAssertTrue(CATransform3DIsIdentity(transforms[0]))
        XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(transforms.last)))
    }

    func testGlassGroupAppearanceUsesSingleReturnPhase() throws {
        guard !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Material pulses are intentionally disabled with Reduce Motion")
        }
        let group = GlassControlGroup()
        let image = try XCTUnwrap(UIImage(systemName: "ellipsis"))
        _ = group.update(
            items: [.init(id: "menu", content: .icon(image), action: nil)],
            transition: .animated(duration: AetherMotion.navigationChrome.geometry.duration, curve: .easeInOut)
        )

        let animation = try XCTUnwrap(group.sizeMorphPulseAnimationForTesting)
        let transforms = try XCTUnwrap(animation.values).compactMap {
            ($0 as? NSValue)?.caTransform3DValue
        }
        XCTAssertGreaterThanOrEqual(transforms.count, 30)
        XCTAssertTrue(CATransform3DIsIdentity(transforms[0]))
        XCTAssertEqual(transforms.map(\.m11).max() ?? 0.0, 1.23, accuracy: 0.001)
        XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(transforms.last)))
    }

    func testGlassGroupDisappearanceUsesReverseSinglePhase() throws {
        guard !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Material pulses are intentionally disabled with Reduce Motion")
        }
        let group = GlassControlGroup()
        let image = try XCTUnwrap(UIImage(systemName: "ellipsis"))
        let item = GlassControlGroup.Item(id: "menu", content: .icon(image), action: nil)
        _ = group.update(items: [item], transition: .immediate)
        _ = group.update(
            items: [],
            transition: .animated(duration: AetherMotion.navigationChrome.geometry.duration, curve: .easeInOut)
        )

        let animation = try XCTUnwrap(group.sizeMorphPulseAnimationForTesting)
        let transforms = try XCTUnwrap(animation.values).compactMap {
            ($0 as? NSValue)?.caTransform3DValue
        }
        XCTAssertGreaterThanOrEqual(transforms.count, 30)
        XCTAssertTrue(CATransform3DIsIdentity(transforms[0]))
        XCTAssertEqual(transforms.map(\.m11).max() ?? 0.0, 1.23, accuracy: 0.001)
        XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(transforms.last)))
    }

    func testSemanticallyDifferentEqualSizeButtonUsesFullMaterialPulse() throws {
        guard !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Material pulses are intentionally disabled with Reduce Motion")
        }
        let group = GlassControlGroup()
        let oldImage = try XCTUnwrap(UIImage(systemName: "camera"))
        let newImage = try XCTUnwrap(UIImage(systemName: "ellipsis"))
        _ = group.update(
            items: [.init(id: "old", content: .icon(oldImage), action: nil)],
            transition: .immediate
        )
        _ = group.update(
            items: [.init(id: "new", content: .icon(newImage), action: nil)],
            transition: .animated(duration: AetherMotion.navigationChrome.geometry.duration, curve: .easeInOut)
        )
        let animation = try XCTUnwrap(group.sizeMorphPulseAnimationForTesting)
        let transforms = try XCTUnwrap(animation.values).compactMap {
            ($0 as? NSValue)?.caTransform3DValue
        }
        let peak = try XCTUnwrap(transforms.max(by: { $0.m11 < $1.m11 }))
        XCTAssertEqual(peak.m11, 1.23, accuracy: 0.001)
        XCTAssertTrue(CATransform3DIsIdentity(transforms[0]))
        XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(transforms.last)))
    }

    func testCustomViewToAutomaticBackUsesFullMaterialPulseAtEqualSize() throws {
        guard !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Material pulses are intentionally disabled with Reduce Motion")
        }
        let group = GlassControlGroup()
        let customView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 34.0, height: 34.0))
        let backImage = try XCTUnwrap(UIImage(systemName: "chevron.left"))

        _ = group.update(
            items: [
                .init(
                    id: BarButtonID("left.semantic.custom.profile.0"),
                    content: .customView(customView),
                    action: nil
                )
            ],
            transition: .immediate
        )
        _ = group.update(
            items: [
                .init(
                    id: BarButtonID("left.nav.back"),
                    content: .icon(backImage),
                    action: nil
                )
            ],
            transition: .animated(duration: AetherMotion.navigationChrome.geometry.duration, curve: .easeInOut)
        )

        let animation = try XCTUnwrap(group.sizeMorphPulseAnimationForTesting)
        let transforms = try XCTUnwrap(animation.values).compactMap {
            ($0 as? NSValue)?.caTransform3DValue
        }
        XCTAssertGreaterThanOrEqual(transforms.count, 30)
        XCTAssertTrue(CATransform3DIsIdentity(transforms[0]))
        let peak = try XCTUnwrap(transforms.max(by: { $0.m11 < $1.m11 }))
        let counter = try XCTUnwrap(transforms.min(by: { $0.m11 < $1.m11 }))
        XCTAssertEqual(peak.m11, 1.23, accuracy: 0.001)
        XCTAssertEqual(peak.m22, 1.23, accuracy: 0.001)
        XCTAssertEqual(counter.m11, 0.968_282, accuracy: 0.001)
        XCTAssertEqual(counter.m22, 0.968_282, accuracy: 0.001)
        XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(transforms.last)))
        XCTAssertNotNil(group.materialPulseCounterAnimationForTesting)
    }

    func testAutomaticBackToCustomViewUsesSameFullMaterialPulse() throws {
        guard !UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Material pulses are intentionally disabled with Reduce Motion")
        }
        let group = GlassControlGroup()
        let backImage = try XCTUnwrap(UIImage(systemName: "chevron.left"))
        let customView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 34.0, height: 34.0))

        _ = group.update(
            items: [
                .init(
                    id: BarButtonID("left.nav.back"),
                    content: .icon(backImage),
                    action: nil
                )
            ],
            transition: .immediate
        )
        _ = group.update(
            items: [
                .init(
                    id: BarButtonID("left.semantic.custom.profile.0"),
                    content: .customView(customView),
                    action: nil
                )
            ],
            transition: .animated(duration: AetherMotion.navigationChrome.geometry.duration, curve: .easeInOut)
        )

        let animation = try XCTUnwrap(group.sizeMorphPulseAnimationForTesting)
        let transforms = try XCTUnwrap(animation.values).compactMap {
            ($0 as? NSValue)?.caTransform3DValue
        }
        XCTAssertGreaterThanOrEqual(transforms.count, 30)
        XCTAssertTrue(CATransform3DIsIdentity(transforms[0]))
        let peak = try XCTUnwrap(transforms.max(by: { $0.m11 < $1.m11 }))
        let counter = try XCTUnwrap(transforms.min(by: { $0.m11 < $1.m11 }))
        XCTAssertEqual(peak.m11, 1.23, accuracy: 0.001)
        XCTAssertEqual(peak.m22, 1.23, accuracy: 0.001)
        XCTAssertEqual(counter.m11, 0.968_282, accuracy: 0.001)
        XCTAssertEqual(counter.m22, 0.968_282, accuracy: 0.001)
        XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(transforms.last)))
        XCTAssertNotNil(group.materialPulseCounterAnimationForTesting)
    }

    func testLiveNavigationItemMutationRequestsProductionChromeLayout() throws {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 640.0))
        let controller = AetherViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.isInFocus = true

        let bar = NavigationBarImpl(
            presentationData: NavigationBarPresentationData(
                theme: NavigationBarTheme(style: .glass)
            )
        )
        controller.navigationBarView = bar
        var capturedTransition: ContainedViewLayoutTransition?
        bar.requestContainerLayout = { transition in
            capturedTransition = transition
        }

        controller.navigationBarItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil)
        ]

        let transition = try XCTUnwrap(capturedTransition)
        XCTAssertTrue(transition.isAnimated)
        XCTAssertEqual(transition.duration, AetherMotion.navigationChrome.geometry.duration, accuracy: 0.001)
        XCTAssertIdentical(bar.item, controller.navigationBarItem)
        window.isHidden = true
    }
}
