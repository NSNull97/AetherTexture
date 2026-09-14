import XCTest
import UIKit
@testable import AetherUI

final class BottomBarAccessoryReleaseResolverTests: XCTestCase {
    private let expandedFrame = CGRect(x: 0, y: 0, width: 390, height: 800)
    private let collapsedFrame = CGRect(x: 20, y: 720, width: 350, height: 60)
    private let containerSize = CGSize(width: 390, height: 844)

    func testSlowShortDragReturnsToExpanded() {
        XCTAssertEqual(resolve(translationY: 70, velocityY: 0), .expanded)
    }

    func testSlowIntentionalDragCollapses() {
        XCTAssertEqual(resolve(translationY: 140, velocityY: 0), .collapsed)
    }

    func testShortFastDownwardFlickCollapses() {
        XCTAssertEqual(resolve(translationY: 30, velocityY: 1_300), .collapsed)
    }

    func testUpwardReleaseOverridesCrossedDistance() {
        XCTAssertEqual(resolve(translationY: 150, velocityY: -600), .expanded)
    }

    func testResolverUsesFinalPositionInsteadOfStickyPriorThreshold() {
        XCTAssertEqual(resolve(translationY: 70, velocityY: 0), .expanded)
    }

    func testCancelledGestureAlwaysReturnsToExpanded() {
        XCTAssertEqual(
            resolve(translationY: 300, velocityY: 2_000, reason: .cancelled),
            .expanded
        )
    }

    func testFailedGestureAlwaysReturnsToExpanded() {
        XCTAssertEqual(
            resolve(translationY: 300, velocityY: 2_000, reason: .failed),
            .expanded
        )
    }

    func testVelocityIsClampedBeforeProjection() {
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        let decision = BottomBarAccessoryReleaseResolver.decision(
            input(translationY: 0, velocityY: 100_000),
            configuration: configuration
        )

        XCTAssertEqual(
            decision.clampedVelocityY,
            configuration.maximumResolvedVelocity,
            accuracy: 0.001
        )
        XCTAssertEqual(
            decision.projectedTranslationY,
            configuration.maximumResolvedVelocity * configuration.projectionTime,
            accuracy: 0.001
        )
        XCTAssertEqual(decision.target, .collapsed)
    }

    func testCompactGeometryUsesMinimumCommitDistance() {
        let compactExpanded = CGRect(x: 0, y: 0, width: 320, height: 500)
        let compactCollapsed = CGRect(x: 12, y: 390, width: 296, height: 56)
        let decision = BottomBarAccessoryReleaseResolver.decision(
            BottomBarAccessoryReleaseInput(
                translationY: 109,
                velocityY: 0,
                expandedFrame: compactExpanded,
                collapsedFrame: compactCollapsed,
                containerSize: CGSize(width: 320, height: 480)
            ),
            configuration: .default
        )

        XCTAssertEqual(decision.commitDistance, 110, accuracy: 0.001)
        XCTAssertEqual(decision.target, .expanded)
    }

    func testLargeGeometryUsesMaximumCommitDistance() {
        let largeExpanded = CGRect(x: 0, y: 0, width: 1_024, height: 1_300)
        let largeCollapsed = CGRect(x: 24, y: 1_550, width: 976, height: 64)
        let decision = BottomBarAccessoryReleaseResolver.decision(
            BottomBarAccessoryReleaseInput(
                translationY: 174,
                velocityY: 0,
                expandedFrame: largeExpanded,
                collapsedFrame: largeCollapsed,
                containerSize: CGSize(width: 1_024, height: 1_660)
            ),
            configuration: .default
        )

        XCTAssertEqual(decision.commitDistance, 175, accuracy: 0.001)
        XCTAssertEqual(decision.target, .expanded)
    }

    private func resolve(
        translationY: CGFloat,
        velocityY: CGFloat,
        reason: BottomBarAccessoryGestureEndReason = .ended
    ) -> BottomBarAccessoryReleaseTarget {
        BottomBarAccessoryReleaseResolver.resolve(
            input(
                translationY: translationY,
                velocityY: velocityY,
                reason: reason
            )
        )
    }

    private func input(
        translationY: CGFloat,
        velocityY: CGFloat,
        reason: BottomBarAccessoryGestureEndReason = .ended
    ) -> BottomBarAccessoryReleaseInput {
        BottomBarAccessoryReleaseInput(
            translationY: translationY,
            velocityY: velocityY,
            expandedFrame: expandedFrame,
            collapsedFrame: collapsedFrame,
            containerSize: containerSize,
            endReason: reason
        )
    }
}

final class BottomBarAccessoryTransitionCoreTests: XCTestCase {
    @MainActor
    func testExpandedPlanePrecedesMaterialExitAndSurvivesCollapseMiddle() {
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator
                .expandedContentPlaneAlpha(presentationProgress: 0),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator
                .expandedContentPlaneAlpha(presentationProgress: 0.04),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator
                .expandedContentPlaneAlpha(presentationProgress: 0.08),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator
                .expandedContentPlaneAlpha(presentationProgress: 0.50),
            1,
            accuracy: 0.001,
            "the Full content plane must not disappear in collapse's middle"
        )

        XCTAssertEqual(
            AetherTabBarController.bottomBarAccessoryMaterialAlpha(
                presentationProgress: 0.08
            ),
            1,
            accuracy: 0.001,
            "glass must remain until Full's backdrop entrance has completed"
        )
        XCTAssertEqual(
            AetherTabBarController.bottomBarAccessoryMaterialAlpha(
                presentationProgress: 0.24
            ),
            0.5,
            accuracy: 0.001,
            "glass must use one broad C2 optical handoff"
        )
        XCTAssertEqual(
            AetherTabBarController.bottomBarAccessoryMaterialAlpha(
                presentationProgress: 0.40
            ),
            0,
            accuracy: 0.001,
            "glass must be gone well before the surface approaches fullscreen"
        )
    }

    @MainActor
    func testEndpointPlanesAreOwnedByPresentationGeometryAcrossRetargets() {
        let capturedAlpha: CGFloat = 0.83
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator
                .resolvedExpandedContentPlaneAlpha(
                    presentationProgress: 0.72,
                    originAlpha: capturedAlpha,
                    settleProgress: 0
                ),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator
                .resolvedExpandedContentPlaneAlpha(
                    presentationProgress: 0.72,
                    originAlpha: capturedAlpha,
                    settleProgress: 0.12
                ),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator
                .collapsedContentPlaneAlpha(presentationProgress: 0.40),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator
                .collapsedContentPlaneAlpha(presentationProgress: 0.72),
            0,
            accuracy: 0.001
        )
    }

    @MainActor
    func testDefaultPhysicalSpringsHaveFiniteBoundedDurations() {
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        let springs = [
            ("expand", configuration.expandSpring),
            ("collapse", configuration.collapseSpring),
            ("cancel", configuration.cancelSpring),
        ]

        for (name, spring) in springs {
            for velocityY in [CGFloat(0), 1.5, -12, 12] {
                let timing = spring.timingParameters(
                    initialVelocity: CGVector(dx: 0, dy: velocityY)
                )
                let animator = UIViewPropertyAnimator(
                    duration: 0,
                    timingParameters: timing
                )

                XCTAssertTrue(
                    animator.duration.isFinite,
                    "\(name) duration must be finite at velocity \(velocityY)"
                )
                XCTAssertGreaterThan(
                    animator.duration,
                    0,
                    "\(name) duration must be positive at velocity \(velocityY)"
                )
                XCTAssertLessThan(
                    animator.duration,
                    2,
                    "\(name) duration is unexpectedly long at velocity \(velocityY)"
                )
            }
        }
    }

    @MainActor
    func testReferenceMotionTracksMatchSlowMotionCheckpoints() throws {
        let configuration = BottomBarAccessoryTransitionConfiguration.default

        let openingAt167ms = BottomBarAccessoryTransitionCoordinator
            .expansionGeometryProgress(
                at: CGFloat(0.167 / configuration.expansionDuration),
                configuration: configuration
            )
        let openingAt267ms = BottomBarAccessoryTransitionCoordinator
            .expansionGeometryProgress(
                at: CGFloat(0.267 / configuration.expansionDuration),
                configuration: configuration
            )
        XCTAssertGreaterThanOrEqual(openingAt167ms, 0.78)
        XCTAssertLessThanOrEqual(openingAt167ms, 0.84)
        XCTAssertGreaterThanOrEqual(openingAt267ms, 0.94)
        XCTAssertLessThanOrEqual(openingAt267ms, 0.97)
        XCTAssertEqual(configuration.expansionDuration, 0.40, accuracy: 0.001)
        XCTAssertEqual(
            configuration.expansionGeometryDuration,
            0.40,
            accuracy: 0.001
        )

        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator.collapseBoundaryProgress(
                at: 1,
                configuration: configuration
            ).bottom,
            1,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            configuration.collapseDuration,
            32.0 / 60.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            configuration.collapseShapeDuration,
            12.0 / 60.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            configuration.collapseShapeDuration / configuration.collapseDuration,
            12.0 / 32.0,
            accuracy: 0.000_001
        )
        let shapeImmediatelyBeforeReferenceDock = BottomBarAccessoryTransitionCoordinator
            .collapseBoundaryProgress(
                at: (12.0 / 32.0) - 0.01,
                configuration: configuration
            ).shape
        let shapeAtReferenceDock = BottomBarAccessoryTransitionCoordinator
            .collapseBoundaryProgress(
                at: 12.0 / 32.0,
                configuration: configuration
            ).shape
        let shapeAfterReferenceDock = BottomBarAccessoryTransitionCoordinator
            .collapseBoundaryProgress(
                at: 0.75,
                configuration: configuration
            ).shape
        XCTAssertLessThan(shapeImmediatelyBeforeReferenceDock, 1)
        XCTAssertEqual(shapeAtReferenceDock, 1, accuracy: 0.000_001)
        XCTAssertEqual(shapeAfterReferenceDock, 1, accuracy: 0.000_001)
        let referenceSurfaceWidth: [(nativeFrame: Int, progress: CGFloat)] = [
            (1, 0.050_7),
            (4, 0.384_9),
            (8, 0.769_2),
            (12, 1.000),
        ]
        for checkpoint in referenceSurfaceWidth {
            let shape = BottomBarAccessoryTransitionCoordinator
                .collapseBoundaryProgress(
                    at: CGFloat(checkpoint.nativeFrame) / 32,
                    configuration: configuration
                ).shape
            XCTAssertEqual(
                shape,
                checkpoint.progress,
                accuracy: checkpoint.nativeFrame == 12 ? 0.000_001 : 0.008,
                "surface width misses the original twelve-frame shape clock at s\(checkpoint.nativeFrame)"
            )
        }
        XCTAssertEqual(configuration.collapseBottomPower, 2, accuracy: 0.001)

        let originFrame = CGRect(x: 0, y: 180, width: 402, height: 874)
        let targetFrame = CGRect(x: 20, y: 735, width: 362, height: 48)
        let origin = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: originFrame.midX, y: originFrame.midY),
            bounds: CGRect(origin: .zero, size: originFrame.size),
            cornerRadius: 60
        )
        let target = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: targetFrame.midX, y: targetFrame.midY),
            bounds: CGRect(origin: .zero, size: targetFrame.size),
            cornerRadius: 24
        )
        let collapseFrames = (0 ... 240).map { index in
            BottomBarAccessoryTransitionCoordinator.settleSurfaceGeometry(
                from: origin,
                to: target,
                target: .collapsed,
                linearProgress: CGFloat(index) / 240,
                configuration: configuration
            ).frame
        }
        for frame in collapseFrames {
            XCTAssertGreaterThanOrEqual(frame.width, targetFrame.width - 0.001)
            XCTAssertGreaterThanOrEqual(frame.height, targetFrame.height - 0.001)
        }
        let topOvershoot = (collapseFrames.map(\.minY).max() ?? targetFrame.minY)
            - targetFrame.minY
        XCTAssertGreaterThanOrEqual(topOvershoot, 5.75)
        XCTAssertLessThanOrEqual(topOvershoot, 6.25)
        XCTAssertEqual(try XCTUnwrap(collapseFrames.last), targetFrame)
    }

    @MainActor
    func testCollapsedArtworkOpticalTopMatchesOriginalThirtyTwoFrameSpring() throws {
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        let duration = configuration.collapseDuration
        let normalizedReleaseVelocity: CGFloat = 12.6
        let reference: [(nativeFrame: Int, progress: CGFloat)] = [
            (1, 0.225),
            (4, 0.676),
            (8, 0.995),
            (12, 1.053),
            (16, 1.064),
            (20, 1.025),
            (24, 1.006),
            (28, 0.999),
            (32, 1.000),
        ]

        func progress(atNativeFrame frame: Int) -> CGFloat {
            BottomBarAccessoryTransitionCoordinator
                .sharedElementVerticalProgress(
                    at: CGFloat((Double(frame) / 60) / duration),
                    settleDuration: duration,
                    spring: configuration.sharedElementVerticalSpring,
                    normalizedInitialVelocity: normalizedReleaseVelocity
                )
        }

        for checkpoint in reference {
            XCTAssertEqual(
                progress(atNativeFrame: checkpoint.nativeFrame),
                checkpoint.progress,
                accuracy: checkpoint.nativeFrame == 32 ? 0.000_001 : 0.025,
                "cover visible-top flight misses original frame s\(checkpoint.nativeFrame)"
            )
        }

        let samples = (0 ... 64).map { halfFrame -> CGFloat in
            let elapsed = Double(halfFrame) / 120
            return BottomBarAccessoryTransitionCoordinator
                .sharedElementVerticalProgress(
                    at: CGFloat(elapsed / duration),
                    settleDuration: duration,
                    spring: configuration.sharedElementVerticalSpring,
                    normalizedInitialVelocity: normalizedReleaseVelocity
                )
        }
        let peakIndex = try XCTUnwrap(samples.indices.max {
            samples[$0] < samples[$1]
        })
        XCTAssertGreaterThanOrEqual(samples[peakIndex], 1.05)
        XCTAssertLessThanOrEqual(samples[peakIndex], 1.08)
        XCTAssertGreaterThan(peakIndex, 16)
        XCTAssertLessThan(peakIndex, 36)

        let meaningfulDirections = zip(
            samples.dropFirst(),
            samples
        ).compactMap { current, previous -> Int? in
            let chord = current - previous
            guard abs(chord) > 0.0015 else { return nil }
            return chord > 0 ? 1 : -1
        }
        let reversals = zip(
            meaningfulDirections.dropFirst(),
            meaningfulDirections
        ).reduce(into: 0) { count, pair in
            if pair.0 != pair.1 { count += 1 }
        }
        XCTAssertEqual(
            reversals,
            1,
            "the cover must overshoot once and make one uninterrupted return"
        )
        XCTAssertEqual(try XCTUnwrap(samples.last), 1, accuracy: 0.000_001)

        let terminalChords = zip(
            samples.suffix(7).dropFirst(),
            samples.suffix(7)
        ).map { abs($0 - $1) }
        XCTAssertGreaterThanOrEqual(terminalChords.count, 6)
        XCTAssertLessThan(
            try XCTUnwrap(terminalChords.last),
            terminalChords[0] * 0.35,
            "the original has a visible nonlinear slowdown in the final 50ms"
        )
    }

    @MainActor
    func testCollapseUsesOneContinuousSixPointSpringFlightAndRigidReturn() throws {
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        let originFrame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let targetFrame = CGRect(x: 20, y: 735, width: 362, height: 48)
        let origin = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: originFrame.midX, y: originFrame.midY),
            bounds: CGRect(origin: .zero, size: originFrame.size),
            cornerRadius: 0
        )
        let target = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: targetFrame.midX, y: targetFrame.midY),
            bounds: CGRect(origin: .zero, size: targetFrame.size),
            cornerRadius: 24
        )
        let referenceVelocity: CGFloat = 9.128_67
        let topDistance = targetFrame.minY - originFrame.minY
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator
                .collapseTopResponseBlendAmplitude(
                    travelDistance: topDistance,
                    maximumOvershoot: configuration.collapseTopOvershoot,
                    normalizedInitialVelocity: referenceVelocity,
                    configuration: configuration
                ),
            0.789_905_497_3,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator
                .collapseTopResponseBlendAmplitude(
                    travelDistance: 364,
                    maximumOvershoot: configuration.collapseTopOvershoot,
                    normalizedInitialVelocity: referenceVelocity,
                    configuration: configuration
                ),
            0.965_594_153,
            accuracy: 0.000_001
        )
        let referenceProgress: [(nativeFrame: Int, progress: CGFloat)] = [
            (1, 0.154_188),
            (4, 0.567_205),
            (8, 0.886_703),
            (12, 0.998_988),
        ]
        for checkpoint in referenceProgress {
            let progress = BottomBarAccessoryTransitionCoordinator
                .collapseBoundaryProgress(
                    at: CGFloat(checkpoint.nativeFrame) / 32,
                    normalizedInitialTopVelocity: referenceVelocity,
                    preservesInitialTopVelocity: true,
                    configuration: configuration
                ).top
            XCTAssertEqual(
                progress,
                checkpoint.progress,
                accuracy: 0.008,
                "raw underdamped surface response misses frame s\(checkpoint.nativeFrame)"
            )
        }

        let shortOriginFrame = originFrame.offsetBy(
            dx: 0,
            dy: targetFrame.minY - 364 - originFrame.minY
        )
        let shortOrigin = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(
                x: shortOriginFrame.midX,
                y: shortOriginFrame.midY
            ),
            bounds: origin.bounds,
            cornerRadius: origin.cornerRadius
        )
        let blendedReference: [(nativeFrame: Int, progress: CGFloat)] = [
            (1, 0.153_951),
            (4, 0.565_061),
            (8, 0.883_102),
            (12, 0.995_929),
            (16, 1.016_467),
            (20, 1.011_156),
            (24, 1.004_021),
            (28, 1.000_450),
            (32, 1.000_000),
        ]
        for checkpoint in blendedReference {
            let geometry = BottomBarAccessoryTransitionCoordinator
                .settleSurfaceGeometry(
                    from: shortOrigin,
                    to: target,
                    target: .collapsed,
                    linearProgress: CGFloat(checkpoint.nativeFrame) / 32,
                    initialVelocityY: 364 * referenceVelocity,
                    initialTopVelocityY: 364 * referenceVelocity,
                    initialBottomVelocityY: 0,
                    configuration: configuration,
                    settleDuration: configuration.collapseDuration,
                    preservesBoundaryVelocities: true,
                    preservesTopBoundaryVelocity: true,
                    preservesBottomBoundaryVelocity: false
                )
            XCTAssertEqual(
                normalizedEdgeProgress(
                    geometry.frame.minY,
                    from: shortOriginFrame.minY,
                    to: targetFrame.minY
                ),
                checkpoint.progress,
                accuracy: checkpoint.nativeFrame == 32 ? 0.000_001 : 0.001,
                "distance-calibrated surface blend misses frame s\(checkpoint.nativeFrame)"
            )
        }

        let sampleCount = 384
        let samples = (0 ... sampleCount).map { index in
            BottomBarAccessoryTransitionCoordinator.settleSurfaceGeometry(
                from: origin,
                to: target,
                target: .collapsed,
                linearProgress: CGFloat(index) / CGFloat(sampleCount),
                initialVelocityY: topDistance * referenceVelocity,
                initialTopVelocityY: topDistance * referenceVelocity,
                initialBottomVelocityY: 0,
                configuration: configuration,
                settleDuration: configuration.collapseDuration,
                preservesBoundaryVelocities: true,
                preservesTopBoundaryVelocity: true,
                preservesBottomBoundaryVelocity: false
            )
        }
        let frames = samples.map(\.frame)
        XCTAssertEqual(try XCTUnwrap(frames.first), originFrame)
        XCTAssertEqual(try XCTUnwrap(frames.last), targetFrame)
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame.width, targetFrame.width - 0.001)
            XCTAssertGreaterThanOrEqual(frame.height, targetFrame.height - 0.001)
        }

        let topValues = frames.map(\.minY)
        let peakIndex = topValues.indices.max {
            topValues[$0] < topValues[$1]
        } ?? 0
        let peakProgress = CGFloat(peakIndex) / CGFloat(sampleCount)
        let peakOffset = topValues[peakIndex] - targetFrame.minY
        XCTAssertEqual(
            peakProgress,
            17.58 / 32.0,
            accuracy: 1.5 / CGFloat(sampleCount),
            "the distance-calibrated response blend must crest near native frame 17.58"
        )
        XCTAssertGreaterThanOrEqual(peakOffset, 5.75)
        XCTAssertLessThanOrEqual(
            peakOffset,
            6.25,
            "the spatial spring cap owns the six-point overshoot"
        )

        let topChords = zip(topValues.dropFirst(), topValues).map {
            $0.0 - $0.1
        }
        let movingDirections = topChords.compactMap { chord -> Int? in
            guard abs(chord) > 0.000_5 else { return nil }
            return chord > 0 ? 1 : -1
        }
        let reversals = zip(
            movingDirections.dropFirst(),
            movingDirections
        ).reduce(into: 0) { count, pair in
            if pair.0 != pair.1 { count += 1 }
        }
        XCTAssertEqual(
            reversals,
            1,
            "surface top must be one continuous spring flight with one return"
        )
        XCTAssertLessThanOrEqual(
            longestStationaryChordRun(
                in: Array(topValues[...peakIndex]),
                tolerance: 0.000_1
            ),
            1,
            "surface top may not enter a zero-slope smootherstep slot before overshooting"
        )

        let terminalFrames = frames.suffix(48)
        for frame in terminalFrames where abs(frame.height - targetFrame.height) <= 0.05 {
            XCTAssertEqual(
                frame.minY - targetFrame.minY,
                frame.maxY - targetFrame.maxY,
                accuracy: 0.03,
                "once Mini is formed the fitted spring must return it rigidly"
            )
        }
        let returnResiduals = topValues[peakIndex...].map {
            $0 - targetFrame.minY
        }
        let returnChords = zip(
            returnResiduals,
            returnResiduals.dropFirst()
        ).map { previous, current in
            previous - current
        }
        XCTAssertTrue(
            returnChords.allSatisfy { $0 >= -0.000_5 },
            "the single spring return may not relaunch a second dip"
        )
        let finalChord = abs(try XCTUnwrap(returnChords.last))
        let visiblePeakChord = returnChords.map(abs).max() ?? 0
        XCTAssertLessThan(
            finalChord,
            visiblePeakChord * 0.08,
            "the spring needs a strong nonlinear terminal slowdown"
        )
    }

    @MainActor
    func testCollapseHorizontalShapeAndCornerFinishAtReferenceThreeEighthsWhileVerticalFoldContinues() {
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        let originFrame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let targetFrame = CGRect(x: 20, y: 735, width: 362, height: 48)
        let origin = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: originFrame.midX, y: originFrame.midY),
            bounds: CGRect(x: 3, y: 5, width: originFrame.width, height: originFrame.height),
            cornerRadius: 0
        )
        let target = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: targetFrame.midX, y: targetFrame.midY),
            bounds: CGRect(origin: .zero, size: targetFrame.size),
            cornerRadius: 24
        )
        func geometry(at progress: CGFloat) -> BottomBarAccessorySurfaceGeometry {
            BottomBarAccessoryTransitionCoordinator.settleSurfaceGeometry(
                from: origin,
                to: target,
                target: .collapsed,
                linearProgress: progress,
                configuration: configuration
            )
        }

        let shapeEndpoint: CGFloat = 12.0 / 32.0
        let dockedShape = geometry(at: shapeEndpoint)
        let immediatelyBeforeDock = geometry(at: shapeEndpoint - 0.01)
        for checkpoint in [
            (nativeFrame: 1, progress: CGFloat(0.050_7)),
            (nativeFrame: 4, progress: CGFloat(0.384_9)),
            (nativeFrame: 8, progress: CGFloat(0.769_2)),
            (nativeFrame: 12, progress: CGFloat(1.000)),
        ] {
            let sample = geometry(
                at: CGFloat(checkpoint.nativeFrame) / 32
            )
            XCTAssertEqual(
                normalizedEdgeProgress(
                    sample.frame.width,
                    from: originFrame.width,
                    to: targetFrame.width
                ),
                checkpoint.progress,
                accuracy: checkpoint.nativeFrame == 12 ? 0.000_1 : 0.008,
                "rendered surface width misses reference frame s\(checkpoint.nativeFrame)"
            )
        }
        XCTAssertNotEqual(immediatelyBeforeDock.frame.width, targetFrame.width, accuracy: 0.001)
        XCTAssertEqual(dockedShape.frame.minX, targetFrame.minX, accuracy: 0.001)
        XCTAssertEqual(dockedShape.frame.width, targetFrame.width, accuracy: 0.001)
        XCTAssertEqual(dockedShape.bounds.origin.x, target.bounds.origin.x, accuracy: 0.001)
        XCTAssertEqual(dockedShape.bounds.origin.y, target.bounds.origin.y, accuracy: 0.001)
        XCTAssertEqual(dockedShape.cornerRadius, target.cornerRadius, accuracy: 0.001)
        XCTAssertGreaterThan(
            dockedShape.frame.height,
            targetFrame.height + 0.1,
            "horizontal squeeze must finish while the independent vertical fold is still moving"
        )

        let shapeHoldSamples: [CGFloat] = [shapeEndpoint, 0.5, 0.625, 0.75, 0.875, 1]
        for progress in shapeHoldSamples {
            let sample = geometry(at: progress)
            XCTAssertEqual(sample.frame.minX, targetFrame.minX, accuracy: 0.001)
            XCTAssertEqual(sample.frame.width, targetFrame.width, accuracy: 0.001)
            XCTAssertEqual(sample.bounds.origin.x, target.bounds.origin.x, accuracy: 0.001)
            XCTAssertEqual(sample.bounds.origin.y, target.bounds.origin.y, accuracy: 0.001)
            XCTAssertEqual(sample.cornerRadius, target.cornerRadius, accuracy: 0.001)
        }
        XCTAssertGreaterThan(
            abs(dockedShape.frame.maxY - targetFrame.maxY),
            0.1,
            "the lower boundary must still have visible work after shape lands"
        )
        XCTAssertEqual(geometry(at: 1), target)
    }

    @MainActor
    func testOpeningUsesIndependentContinuousBoundaryResponses() {
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        let originFrame = CGRect(x: 20, y: 735, width: 362, height: 48)
        let targetFrame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let origin = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: originFrame.midX, y: originFrame.midY),
            bounds: CGRect(origin: .zero, size: originFrame.size),
            cornerRadius: 24
        )
        let target = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: targetFrame.midX, y: targetFrame.midY),
            bounds: CGRect(origin: .zero, size: targetFrame.size),
            cornerRadius: 0
        )
        let firstNativeFrame = BottomBarAccessoryTransitionCoordinator
            .settleSurfaceGeometry(
                from: origin,
                to: target,
                target: .expanded,
                linearProgress: CGFloat((1.0 / 60.0) / configuration.expansionDuration),
                configuration: configuration
            ).frame
        XCTAssertEqual(
            originFrame.minY - firstNativeFrame.minY,
            (originFrame.minY - targetFrame.minY) * 0.0323,
            accuracy: 0.6
        )
        XCTAssertEqual(
            firstNativeFrame.maxY,
            originFrame.maxY,
            accuracy: 0.25,
            "the opening bottom remains anchored while the top launches"
        )

        let topArrival = BottomBarAccessoryTransitionCoordinator
            .settleSurfaceGeometry(
                from: origin,
                to: target,
                target: .expanded,
                linearProgress: CGFloat(
                    configuration.expansionGeometryDuration
                        / configuration.expansionDuration
                ),
                configuration: configuration
            ).frame
        XCTAssertEqual(topArrival.minY, targetFrame.minY, accuracy: 0.2)
        XCTAssertEqual(topArrival.maxY, targetFrame.maxY, accuracy: 0.2)

        let endpoint = BottomBarAccessoryTransitionCoordinator
            .settleSurfaceGeometry(
                from: origin,
                to: target,
                target: .expanded,
                linearProgress: 1,
                configuration: configuration
            ).frame
        XCTAssertEqual(endpoint, targetFrame)
        XCTAssertEqual(
            BottomBarAccessoryTransitionCoordinator.expansionBottomProgress(
                at: CGFloat((13.0 / 60.0) / configuration.expansionDuration),
                configuration: configuration
            ),
            0.87,
            accuracy: 0.02
        )
    }

    @MainActor
    func testSettleDurationShrinksOnlyWhenEveryGeometryComponentIsNearEndpoint() {
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        let expandedFrame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let collapsedFrame = CGRect(x: 20, y: 735, width: 362, height: 48)
        let expanded = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: expandedFrame.midX, y: expandedFrame.midY),
            bounds: CGRect(origin: .zero, size: expandedFrame.size),
            cornerRadius: 0
        )
        let collapsed = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: collapsedFrame.midX, y: collapsedFrame.midY),
            bounds: CGRect(origin: .zero, size: collapsedFrame.size),
            cornerRadius: 24
        )
        let nearFrame = collapsedFrame.offsetBy(dx: 0, dy: -2)
        let near = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: nearFrame.midX, y: nearFrame.midY),
            bounds: collapsed.bounds,
            cornerRadius: collapsed.cornerRadius
        )
        let nearDuration = BottomBarAccessoryTransitionCoordinator
            .resolvedSettleDuration(
                from: near,
                to: collapsed,
                opposite: expanded,
                baseDuration: configuration.collapseDuration,
                initialVelocityY: 0
            )
        XCTAssertEqual(
            nearDuration,
            configuration.collapseDuration * 0.18,
            accuracy: 0.000_1
        )

        let rigidHeldFrame = expandedFrame.offsetBy(dx: 0, dy: 180)
        let rigidHeld = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: rigidHeldFrame.midX, y: rigidHeldFrame.midY),
            bounds: expanded.bounds,
            cornerRadius: 60
        )
        let heldDuration = BottomBarAccessoryTransitionCoordinator
            .resolvedSettleDuration(
                from: rigidHeld,
                to: collapsed,
                opposite: expanded,
                baseDuration: configuration.collapseDuration,
                initialVelocityY: 0
            )
        XCTAssertEqual(heldDuration, configuration.collapseDuration, accuracy: 0.000_1)
    }

    @MainActor
    func testProgrammaticAndGestureZeroVelocityUseSameMeasuredTerminalTrack() {
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        let originFrame = CGRect(x: 0, y: 40, width: 402, height: 774)
        let targetFrame = CGRect(x: 20, y: 735, width: 362, height: 48)
        let origin = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: originFrame.midX, y: originFrame.midY),
            bounds: CGRect(origin: .zero, size: originFrame.size),
            cornerRadius: 0
        )
        let target = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: targetFrame.midX, y: targetFrame.midY),
            bounds: CGRect(origin: .zero, size: targetFrame.size),
            cornerRadius: 24
        )
        let programmaticFrames = (0 ... 240).map { index in
            BottomBarAccessoryTransitionCoordinator.settleSurfaceGeometry(
                from: origin,
                to: target,
                target: .collapsed,
                linearProgress: CGFloat(index) / 240,
                configuration: configuration,
                seedsProgrammaticCollapseLaunch: true
            ).frame
        }
        let endpointOvershoot = (programmaticFrames.map(\.minY).max() ?? targetFrame.minY)
            - targetFrame.minY
        XCTAssertGreaterThanOrEqual(endpointOvershoot, 5.75)
        XCTAssertLessThanOrEqual(endpointOvershoot, 6.25)

        let gestureFrames = (0 ... 240).map { index in
            BottomBarAccessoryTransitionCoordinator.settleSurfaceGeometry(
                from: origin,
                to: target,
                target: .collapsed,
                linearProgress: CGFloat(index) / 240,
                initialVelocityY: 0,
                configuration: configuration,
                seedsProgrammaticCollapseLaunch: false
            ).frame
        }
        XCTAssertEqual(programmaticFrames, gestureFrames)

        let derivativeSample = CGFloat(0.000_001)
        let gestureSample = BottomBarAccessoryTransitionCoordinator
            .settleSurfaceGeometry(
                from: origin,
                to: target,
                target: .collapsed,
                linearProgress: derivativeSample,
                initialVelocityY: 0,
                configuration: configuration,
                seedsProgrammaticCollapseLaunch: false
            )
        let gestureInitialTopVelocity = (
            gestureSample.frame.minY - originFrame.minY
        ) / (derivativeSample * CGFloat(configuration.collapseDuration))
        XCTAssertGreaterThan(gestureInitialTopVelocity, 0)
        XCTAssertTrue(gestureInitialTopVelocity.isFinite)
    }

    @MainActor
    func testBoundaryVelocityHandoffIsC1AcrossBothRetargetDirections() {
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        let expandedFrame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let collapsedFrame = CGRect(x: 20, y: 735, width: 362, height: 48)
        let expanded = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: expandedFrame.midX, y: expandedFrame.midY),
            bounds: CGRect(origin: .zero, size: expandedFrame.size),
            cornerRadius: 0
        )
        let collapsed = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: collapsedFrame.midX, y: collapsedFrame.midY),
            bounds: CGRect(origin: .zero, size: collapsedFrame.size),
            cornerRadius: 24
        )

        assertBoundaryC1Retarget(
            source: expanded,
            firstTarget: collapsed,
            firstReleaseTarget: .collapsed,
            firstDuration: configuration.collapseDuration,
            firstInitialVelocity: 900,
            sampleTime: 0.16,
            reverseTarget: expanded,
            reverseReleaseTarget: .expanded,
            reverseBaseDuration: configuration.expansionDuration,
            opposite: collapsed,
            configuration: configuration
        )
        assertBoundaryC1Retarget(
            source: collapsed,
            firstTarget: expanded,
            firstReleaseTarget: .expanded,
            firstDuration: configuration.expansionDuration,
            firstInitialVelocity: 0,
            sampleTime: 0.18,
            reverseTarget: collapsed,
            reverseReleaseTarget: .collapsed,
            reverseBaseDuration: configuration.collapseDuration,
            opposite: expanded,
            configuration: configuration
        )
    }

    @MainActor
    func testDragReleaseSurfaceHasC1FirstChordAndSmoothInternalJoinsAt120And60Hz() {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }
        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        fixture.coordinator.reset(to: .expanded)
        XCTAssertTrue(fixture.coordinator.beginDrag())
        fixture.coordinator.updateDrag(translationY: 313)

        let release = BottomBarAccessorySurfaceGeometry(
            position: fixture.surface.layer.position,
            bounds: fixture.surface.layer.bounds,
            cornerRadius: fixture.surface.layer.cornerRadius
        )
        let target = fixture.geometry.surfaceGeometry(at: 0)
        let duration = BottomBarAccessoryTransitionConfiguration.default
            .collapseDuration
        let releaseVelocityY: CGFloat = 300
        let referenceTopLaunchVelocity = (
            target.frame.minY - release.frame.minY
        ) * BottomBarAccessoryTransitionCoordinator
            .referenceCollapseTopNormalizedVelocity

        for hardwareRate in [120, 60] {
            let cadence = TimeInterval(1) / TimeInterval(hardwareRate)
            func geometry(
                at elapsed: TimeInterval,
                velocitySampleInterval: TimeInterval? = nil
            ) -> BottomBarAccessorySurfaceGeometry {
                BottomBarAccessoryTransitionCoordinator.settleSurfaceGeometry(
                    from: release,
                    to: target,
                    target: .collapsed,
                    linearProgress: CGFloat(elapsed / duration),
                    initialVelocityY: releaseVelocityY,
                    initialTopVelocityY: releaseVelocityY,
                    initialBottomVelocityY: releaseVelocityY,
                    configuration: .default,
                    settleDuration: duration,
                    preservesBoundaryVelocities: true,
                    preservesTopBoundaryVelocity: false,
                    preservesBottomBoundaryVelocity: false,
                    velocityHandoffSampleInterval: velocitySampleInterval
                )
            }

            // Both boundaries replay the original force-independent close for
            // an ordinary finger release: measured top velocity and a
            // critically damped bottom released from rest. Only an actual
            // animator retarget inherits presentation derivatives.
            let derivativeStep = min(0.000_001, cadence / 1_000)
            let infinitesimal = geometry(at: derivativeStep)
            let topLaunchVelocity = (
                infinitesimal.frame.minY - release.frame.minY
            ) / CGFloat(derivativeStep)
            let bottomLaunchVelocity = (
                infinitesimal.frame.maxY - release.frame.maxY
            ) / CGFloat(derivativeStep)
            XCTAssertEqual(
                topLaunchVelocity,
                referenceTopLaunchVelocity,
                accuracy: 1,
                "ordinary drag top must replay the measured reference launch @\(hardwareRate) Hz"
            )
            XCTAssertEqual(
                bottomLaunchVelocity,
                0,
                accuracy: 1,
                "ordinary drag bottom must use the fixed critical seed zero @\(hardwareRate) Hz"
            )

            let analyticFirstVisible = geometry(at: cadence)
            let cadenceParameterizedFirstVisible = geometry(
                at: cadence,
                velocitySampleInterval: cadence
            )
            XCTAssertEqual(
                cadenceParameterizedFirstVisible.frame.minY,
                analyticFirstVisible.frame.minY,
                accuracy: 0.02,
                "top may not switch to a cadence-specific launch curve at \(hardwareRate) Hz"
            )
            XCTAssertEqual(
                cadenceParameterizedFirstVisible.frame.maxY,
                analyticFirstVisible.frame.maxY,
                accuracy: 0.02,
                "bottom may not switch to a cadence-specific launch curve at \(hardwareRate) Hz"
            )
            XCTAssertGreaterThan(
                abs(analyticFirstVisible.frame.minY - release.frame.minY),
                0.01,
                "top may not hold its release frame at \(hardwareRate) Hz"
            )
            XCTAssertGreaterThan(
                abs(analyticFirstVisible.frame.maxY - release.frame.maxY),
                0.01,
                "bottom may not hold its release frame at \(hardwareRate) Hz"
            )

            let h = min(cadence / 50, 0.000_05)
            func assertDerivativeContinuity(
                at join: TimeInterval,
                label: String,
                requiresJerkContinuity: Bool,
                edge: (BottomBarAccessorySurfaceGeometry) -> CGFloat
            ) {
                func value(_ time: TimeInterval) -> CGFloat {
                    edge(geometry(at: time))
                }
                let backwardAcceleration = (
                    value(join) - 2 * value(join - h) + value(join - 2 * h)
                ) / CGFloat(h * h)
                let forwardAcceleration = (
                    value(join + 2 * h) - 2 * value(join + h) + value(join)
                ) / CGFloat(h * h)
                let backwardJerk = (
                    value(join) - 3 * value(join - h)
                        + 3 * value(join - 2 * h) - value(join - 3 * h)
                ) / CGFloat(h * h * h)
                let forwardJerk = (
                    value(join + 3 * h) - 3 * value(join + 2 * h)
                        + 3 * value(join + h) - value(join)
                ) / CGFloat(h * h * h)

                XCTAssertLessThanOrEqual(
                    abs(forwardAcceleration - backwardAcceleration),
                    500,
                    "\(label) acceleration is discontinuous at the internal \(hardwareRate) Hz join: before=\(backwardAcceleration), after=\(forwardAcceleration) pt/s²"
                )
                if requiresJerkContinuity {
                    XCTAssertLessThanOrEqual(
                        abs(forwardJerk - backwardJerk),
                        100_000,
                        "\(label) jerk is discontinuous at the internal \(hardwareRate) Hz join: before=\(backwardJerk), after=\(forwardJerk) pt/s³"
                    )
                } else {
                    XCTAssertLessThanOrEqual(
                        max(abs(backwardJerk), abs(forwardJerk)),
                        8_000_000,
                        "\(label) is C2 but exposes an unbounded jerk pulse: before=\(backwardJerk), after=\(forwardJerk) pt/s³"
                    )
                }
            }

            func assertTopKeepsMovingThroughSlot(
                at join: TimeInterval,
                label: String
            ) {
                let before = geometry(at: join - h).frame.minY
                let atJoin = geometry(at: join).frame.minY
                let after = geometry(at: join + h).frame.minY
                let incomingVelocity = (atJoin - before) / CGFloat(h)
                let outgoingVelocity = (after - atJoin) / CGFloat(h)
                XCTAssertGreaterThan(
                    incomingVelocity,
                    5,
                    "\(label) may not ease to a stationary slot before the next close segment"
                )
                XCTAssertGreaterThan(
                    outgoingVelocity,
                    5,
                    "\(label) may not restart from a zero-slope smootherstep slot"
                )
                XCTAssertEqual(
                    outgoingVelocity,
                    incomingVelocity,
                    accuracy: max(30, abs(incomingVelocity) * 0.12),
                    "\(label) must remain one continuous top flight through the analytic slot"
                )
            }

            // Reference footage establishes C0/C1 at finger release. Higher
            // derivative continuity belongs to the analytic-to-terminal joins
            // and endpoint landings, not to the human gesture itself.
            let topFlightDuration = min(duration, 12.0 / 60.0)
            let topLandingJoin = topFlightDuration * 0.70
            let bottomLandingJoin = min(duration * 0.75, 0.30)
            assertDerivativeContinuity(
                at: topLandingJoin,
                label: "top analytic-to-C2 landing",
                requiresJerkContinuity: false,
                edge: { $0.frame.minY }
            )
            assertTopKeepsMovingThroughSlot(
                at: topLandingJoin,
                label: "top analytic-to-terminal join"
            )
            assertDerivativeContinuity(
                at: bottomLandingJoin,
                label: "bottom analytic-to-C3 landing",
                requiresJerkContinuity: true,
                edge: { $0.frame.maxY }
            )
            assertDerivativeContinuity(
                at: topFlightDuration,
                label: "top endpoint",
                requiresJerkContinuity: false,
                edge: { $0.frame.minY }
            )
            assertTopKeepsMovingThroughSlot(
                at: topFlightDuration,
                label: "top raw-flight docking slot"
            )
            assertDerivativeContinuity(
                at: duration,
                label: "bottom endpoint",
                requiresJerkContinuity: true,
                edge: { $0.frame.maxY }
            )

            var topSamples: [CGFloat] = []
            var bottomSamples: [CGFloat] = []
            var elapsed: TimeInterval = 0
            while elapsed < duration {
                let frame = geometry(at: elapsed).frame
                topSamples.append(frame.minY)
                bottomSamples.append(frame.maxY)
                elapsed += cadence
            }
            topSamples.append(geometry(at: duration).frame.minY)
            bottomSamples.append(geometry(at: duration).frame.maxY)
            let topVelocities = zip(topSamples.dropFirst(), topSamples).map {
                ($0.0 - $0.1) / CGFloat(cadence)
            }
            let movingTopSigns = topVelocities.compactMap { velocity -> Int? in
                guard abs(velocity) > 1 else { return nil }
                return velocity > 0 ? 1 : -1
            }
            let topReversalCount = zip(
                movingTopSigns.dropFirst(),
                movingTopSigns
            ).reduce(into: 0) { count, pair in
                if pair.0 != pair.1 { count += 1 }
            }
            XCTAssertEqual(
                topReversalCount,
                1,
                "top should make exactly one rigid Mini dip and return at \(hardwareRate) Hz"
            )
            let topPeakIndex = topSamples.indices.max {
                topSamples[$0] < topSamples[$1]
            } ?? (topSamples.count - 1)
            XCTAssertLessThanOrEqual(
                longestStationaryChordRun(
                    in: Array(topSamples[...topPeakIndex]),
                    tolerance: 0.000_1
                ),
                1,
                "the main flight and global dip must not be separated by a rendered top hold"
            )
            let prePeakVelocities = Array(topVelocities.prefix(topPeakIndex))
            if prePeakVelocities.count > 4 {
                for index in 2 ..< (prePeakVelocities.count - 1) {
                    XCTAssertGreaterThan(
                        prePeakVelocities[index],
                        0,
                        "composed top must remain one downward flight before its beta peak @\(hardwareRate)Hz"
                    )
                    if abs(prePeakVelocities[index]) <= 8 {
                        let laterMaximum = prePeakVelocities[(index + 1)...]
                            .map { abs($0) }.max() ?? 0
                        XCTAssertLessThan(
                            laterMaximum,
                            16,
                            "top may not slow to a hold and relaunch the dip as a second phase @\(hardwareRate)Hz"
                        )
                    }
                }
            }
            let bottomVelocities = zip(
                bottomSamples.dropFirst(),
                bottomSamples
            ).map { ($0.0 - $0.1) / CGFloat(cadence) }
            let movingBottomSigns = bottomVelocities.compactMap { velocity -> Int? in
                guard abs(velocity) > 1 else { return nil }
                return velocity > 0 ? 1 : -1
            }
            let bottomReversalCount = zip(
                movingBottomSigns.dropFirst(),
                movingBottomSigns
            ).reduce(into: 0) { count, pair in
                if pair.0 != pair.1 { count += 1 }
            }
            XCTAssertLessThanOrEqual(
                bottomReversalCount,
                2,
                "the fixed lower fold plus the one rigid dip may not introduce repeated turns"
            )
            for (label, samples) in [
                ("top", topSamples),
                ("bottom", bottomSamples),
            ] {
                let normalized = samples.map {
                    $0 / max(1, fixture.geometry.layoutSize.height)
                }
                assertFiniteMotionBounds(
                    normalized,
                    sampleInterval: CGFloat(cadence),
                    maximumVelocity: 40,
                    maximumAcceleration: 2_500,
                    maximumJerk: 50_000,
                    label: "\(label) post-release @\(hardwareRate)Hz"
                )
            }
        }
    }

    @MainActor
    func testTransitionDisplayLinkRequestsMaximumAvailableRefreshUpTo120Hz() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }

        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))

        let range = try XCTUnwrap(
            fixture.coordinator.displayLinkFrameRateRangeForTesting,
            "an active morph must own one configured display link"
        )
        let screenMaximum = fixture.window.screen.maximumFramesPerSecond
        let requestedMaximum = screenMaximum > 0
            ? min(120, screenMaximum)
            : 120

        if #available(iOS 15.0, *) {
            let preferred = try XCTUnwrap(range.preferred)
            XCTAssertEqual(
                preferred,
                Float(requestedMaximum),
                accuracy: 0.001,
                "ProMotion hardware must request 120 Hz; 60 Hz screens must use a safe fallback"
            )
            XCTAssertEqual(range.maximum, Float(requestedMaximum), accuracy: 0.001)
            XCTAssertEqual(range.minimum, Float(requestedMaximum), accuracy: 0.001)
        }

        let promotion = BottomBarAccessoryTransitionCoordinator
            .resolvedPreferredFrameRateRange(maximumFramesPerSecond: 120)
        XCTAssertEqual(promotion.minimum, 120, accuracy: 0.001)
        XCTAssertEqual(promotion.maximum, 120, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(promotion.preferred), 120, accuracy: 0.001)

        let sixtyHertz = BottomBarAccessoryTransitionCoordinator
            .resolvedPreferredFrameRateRange(maximumFramesPerSecond: 60)
        XCTAssertEqual(sixtyHertz.minimum, 60, accuracy: 0.001)
        XCTAssertEqual(sixtyHertz.maximum, 60, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(sixtyHertz.preferred), 60, accuracy: 0.001)

        let constrained = BottomBarAccessoryTransitionCoordinator
            .resolvedPreferredFrameRateRange(maximumFramesPerSecond: 30)
        XCTAssertEqual(constrained.minimum, 30, accuracy: 0.001)
        XCTAssertEqual(constrained.maximum, 30, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(constrained.preferred), 30, accuracy: 0.001)

        let configuration = BottomBarAccessoryTransitionConfiguration.default
        XCTAssertEqual(configuration.geometryKeyframesPerSecond, 120, accuracy: 0.001)
    }

    @MainActor
    func testCollapseUsesIndependentTopAndBottomCurvesWithSlowBottomTail() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }

        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        fixture.coordinator.reset(to: .expanded)
        XCTAssertTrue(fixture.coordinator.beginDrag())
        fixture.coordinator.updateDrag(translationY: 180)

        let releaseFrame = fixture.surface.frame
        fixture.coordinator.settle(to: .collapsed, initialVelocity: 0)
        let geometryTrack = try XCTUnwrap(
            fixture.surface.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator
                    .surfaceGeometryAnimationKey
            ) as? CAAnimationGroup
        )
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        XCTAssertEqual(
            geometryTrack.duration,
            configuration.collapseDuration,
            accuracy: 0.001
        )
        let positionTrack = try XCTUnwrap(
            geometryTrack.animations?.compactMap { $0 as? CAKeyframeAnimation }
                .first { $0.keyPath == "position" }
        )
        XCTAssertGreaterThanOrEqual(
            positionTrack.values?.count ?? 0,
            Int(ceil(
                configuration.collapseDuration
                    * TimeInterval(configuration.geometryKeyframesPerSecond)
            )) + 1
        )
        let samples = sampleRuntimeFrames(
            surface: fixture.surface,
            coordinator: fixture.coordinator,
            until: .collapsed
        )

        XCTAssertEqual(fixture.coordinator.state, .collapsed)
        XCTAssertGreaterThan(samples.count, 8)
        let target = fixture.geometry.collapsedFrame
        let frame35 = frame(in: samples, atFraction: 0.35)
        let frame65 = frame(in: samples, atFraction: 0.65)
        let frame100 = frame(in: samples, atFraction: 1)

        let top35 = normalizedEdgeProgress(
            frame35.minY,
            from: releaseFrame.minY,
            to: target.minY
        )
        let bottom35 = normalizedEdgeProgress(
            frame35.maxY,
            from: releaseFrame.maxY,
            to: target.maxY
        )
        let top65 = normalizedEdgeProgress(
            frame65.minY,
            from: releaseFrame.minY,
            to: target.minY
        )
        let bottom65 = normalizedEdgeProgress(
            frame65.maxY,
            from: releaseFrame.maxY,
            to: target.maxY
        )

        XCTAssertGreaterThan(
            max(abs(top35 - bottom35), abs(top65 - bottom65)),
            0.08,
            "the top's downward flight and the bottom's fold must not share one interpolation curve"
        )

        let bottomFoldTravel = abs(frame65.maxY - releaseFrame.maxY)
        let terminalSamples = samples.drop { sample in
            sample.frame.height > target.height + 0.10
        }
        let peakSample = terminalSamples.max {
            $0.frame.minY < $1.frame.minY
        }?.frame ?? frame100
        let rigidDipResidual = peakSample.minY - target.minY
        let rigidReturnTravel = abs(frame100.minY - peakSample.minY)
        XCTAssertGreaterThan(
            bottomFoldTravel,
            1,
            "the lower edge must perform a substantial fold before the rigid Mini tail"
        )
        XCTAssertGreaterThanOrEqual(
            rigidDipResidual,
            0.10,
            "the late-forming capsule must retain a measurable nonzero rigid return"
        )
        XCTAssertLessThanOrEqual(
            rigidDipResidual,
            6.25,
            "the rigid portion may not exceed the global roughly-six-point envelope"
        )
        XCTAssertEqual(
            rigidReturnTravel,
            rigidDipResidual,
            accuracy: 0.15,
            "post-peak travel is the one-shot capsule return, not continued lower-edge folding"
        )
        XCTAssertEqual(frame100.maxY, target.maxY, accuracy: 0.05)

        let formedIndex = try XCTUnwrap(samples.firstIndex {
            $0.frame.height <= target.height + 0.10
        })
        let bottomTargetDirection: CGFloat = target.maxY
            - releaseFrame.maxY >= 0 ? 1 : -1
        if formedIndex > 1 {
            for index in 1 ..< formedIndex {
                let projectedBottomChord = bottomTargetDirection * (
                    samples[index].frame.maxY
                        - samples[index - 1].frame.maxY
                )
                XCTAssertGreaterThanOrEqual(
                    projectedBottomChord,
                    -0.05,
                    "ordinary fixed-seed lower fold may not turn away from Mini before contact"
                )
            }
        }
        if formedIndex > 0 {
            for index in formedIndex ..< samples.count {
                let bottomChord = samples[index].frame.maxY
                    - samples[index - 1].frame.maxY
                let topChord = samples[index].frame.minY
                    - samples[index - 1].frame.minY
                XCTAssertEqual(
                    bottomChord,
                    topChord,
                    accuracy: 0.15,
                    "after Mini forms, the lower edge must share the top's one rigid dip and return"
                )
            }
        }

        let maximumTop = samples.map(\.frame.minY).max() ?? target.minY
        XCTAssertLessThanOrEqual(
            maximumTop,
            target.minY + 6.25,
            "the compact top may use only the measured roughly-six-point dip"
        )
        XCTAssertGreaterThanOrEqual(
            maximumTop,
            target.minY + 5.75,
            "the formed Mini should retain the reference's visible terminal spring"
        )

        var previousTop = releaseFrame.minY
        for sample in samples {
            XCTAssertGreaterThanOrEqual(
                sample.frame.minY,
                previousTop - 1.5,
                "the one-lobe return must not jump upward between samples"
            )
            XCTAssertGreaterThanOrEqual(
                sample.frame.width,
                target.width - 0.75,
                "collapse must never become narrower than Mini"
            )
            XCTAssertGreaterThanOrEqual(
                sample.frame.height,
                target.height - 0.75,
                "collapse must never become shorter than Mini"
            )
            previousTop = sample.frame.minY
        }
    }

    @MainActor
    func testRuntimeOpening120HzKeyframesDoNotReplaySixtyHertzVelocitySteps() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }

        let origin = fixture.geometry.collapsedFrame
        let target = fixture.geometry.expandedFrame
        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        let geometryTrack = try XCTUnwrap(
            fixture.surface.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator
                    .surfaceGeometryAnimationKey
            ) as? CAAnimationGroup
        )
        let frames = try surfaceFrames(in: geometryTrack)
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        let expectedCount = Int(ceil(
            configuration.expansionDuration
                * TimeInterval(configuration.geometryKeyframesPerSecond)
        )) + 1

        XCTAssertEqual(frames.count, expectedCount)
        let topProgress = frames.map {
            normalizedEdgeProgress($0.minY, from: origin.minY, to: target.minY)
        }
        let bottomProgress = frames.map {
            normalizedEdgeProgress($0.maxY, from: origin.maxY, to: target.maxY)
        }
        let topVelocitySteps = holdThenJumpCount(in: topProgress)
        let bottomVelocitySteps = holdThenJumpCount(in: bottomProgress)

        XCTAssertLessThanOrEqual(
            topVelocitySteps,
            2,
            "the 120 Hz top track contains \(topVelocitySteps) hold-then-jump velocity steps; native 60 Hz checkpoints need a continuous interpolant before CA sampling"
        )
        XCTAssertLessThanOrEqual(
            bottomVelocitySteps,
            2,
            "the 120 Hz bottom track contains \(bottomVelocitySteps) hold-then-jump velocity steps; duplicated chord velocities make the glass fold in visible 60 Hz stair steps"
        )

        let sampleInterval = CGFloat(
            geometryTrack.duration / Double(max(1, frames.count - 1))
        )
        let topArrivalIndex = try XCTUnwrap(
            topProgress.firstIndex { $0 >= 1 - 0.000_001 }
        )
        XCTAssertGreaterThan(topArrivalIndex, 0)
        let terminalTopVelocity = (
            topProgress[topArrivalIndex] - topProgress[topArrivalIndex - 1]
        ) / sampleInterval
        XCTAssertLessThanOrEqual(
            abs(terminalTopVelocity),
            0.08,
            "the top reaches its stop at \(terminalTopVelocity) normalized/s; opening has no extra endpoint bounce"
        )

        let firstBottomVelocity = (
            bottomProgress[1] - bottomProgress[0]
        ) / sampleInterval
        let lastBottomVelocity = (
            bottomProgress[bottomProgress.count - 1]
                - bottomProgress[bottomProgress.count - 2]
        ) / sampleInterval
        XCTAssertEqual(firstBottomVelocity, 0, accuracy: 0.000_1)
        XCTAssertLessThanOrEqual(abs(lastBottomVelocity), 0.05)
    }

    @MainActor
    func testRuntimeCollapseEdgesStayCoupledWithoutClampPlateauOrEndpointSnap() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }

        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        fixture.coordinator.reset(to: .expanded)
        let origin = fixture.geometry.expandedFrame
        let target = fixture.geometry.collapsedFrame
        fixture.coordinator.settle(to: .collapsed, initialVelocity: 0)
        let geometryTrack = try XCTUnwrap(
            fixture.surface.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator
                    .surfaceGeometryAnimationKey
            ) as? CAAnimationGroup
        )
        let frames = try surfaceFrames(in: geometryTrack)
        let sampleInterval = CGFloat(
            geometryTrack.duration / Double(max(1, frames.count - 1))
        )
        let topProgress = frames.map {
            normalizedEdgeProgress($0.minY, from: origin.minY, to: target.minY)
        }
        let bottomProgress = frames.map {
            normalizedEdgeProgress($0.maxY, from: origin.maxY, to: target.maxY)
        }

        let firstTopVelocity = (topProgress[1] - topProgress[0]) / sampleInterval
        let firstBottomVelocity = (
            bottomProgress[1] - bottomProgress[0]
        ) / sampleInterval
        XCTAssertGreaterThan(firstTopVelocity, 0)
        XCTAssertLessThan(
            firstTopVelocity,
            30,
            "the top launch must not begin with a one-frame velocity spike"
        )
        XCTAssertGreaterThan(
            firstBottomVelocity,
            0,
            "a zero-velocity programmatic fold must still begin on its first compositor chord"
        )
        XCTAssertLessThan(
            firstBottomVelocity,
            2,
            "the physical zero-velocity spring may accelerate during the chord but must not be cadence-seeded into a launch pulse"
        )
        XCTAssertGreaterThan(
            bottomProgress[1],
            0,
            "the fold must begin on the first rendered chord instead of waiting behind the top-edge flight"
        )

        let normalizedEdgeGaps = zip(topProgress, bottomProgress).map {
            $0.0 - $0.1
        }
        XCTAssertLessThanOrEqual(
            normalizedEdgeGaps.max() ?? .greatestFiniteMagnitude,
            0.43,
            "independent curves may separate in phase, but the bottom must remain inside the measured coupled envelope"
        )
        let topArrivalIndex = try XCTUnwrap(topProgress.firstIndex { $0 >= 1 })
        XCTAssertGreaterThanOrEqual(
            bottomProgress[topArrivalIndex],
            0.64,
            "the independent lower edge must already be well into its stronger fold when the top lands"
        )
        XCTAssertLessThanOrEqual(
            holdThenJumpCount(in: Array(topProgress[...topArrivalIndex])),
            1,
            "the moving top segment must not contain paired 60 Hz chords"
        )

        let rigidIndex = try XCTUnwrap(frames.firstIndex {
            abs($0.height - target.height) <= 0.001
        })
        XCTAssertGreaterThan(
            rigidIndex,
            1,
            "the independent lower fold must have at least one nonrigid compositor chord"
        )
        guard rigidIndex > 1 else { return }
        let bottomChordVelocities = zip(
            bottomProgress[1 ..< rigidIndex],
            bottomProgress[0 ..< (rigidIndex - 1)]
        ).map { pair in
            (pair.0 - pair.1) / sampleInterval
        }
        let bottomPeakIndex = bottomChordVelocities.indices.max {
            bottomChordVelocities[$0] < bottomChordVelocities[$1]
        } ?? 0
        XCTAssertGreaterThan(
            bottomPeakIndex,
            0,
            "a zero-velocity physical spring should accelerate smoothly before decelerating"
        )
        XCTAssertLessThan(bottomPeakIndex, bottomChordVelocities.count - 1)
        XCTAssertTrue(bottomChordVelocities.allSatisfy(\.isFinite))
        XCTAssertLessThanOrEqual(
            stationaryThenMovingChordCount(
                in: Array(bottomProgress[0 ..< rigidIndex])
            ),
            0,
            "the bottom spring plus global lobe may not hold and relaunch before rigid contact"
        )
        for index in bottomChordVelocities.indices {
            XCTAssertGreaterThanOrEqual(bottomChordVelocities[index], -0.000_1)
        }
        let rigidFrames = Array(frames[rigidIndex...])
        for frame in rigidFrames {
            XCTAssertEqual(
                frame.height,
                target.height,
                accuracy: 0.1,
                "the formed Mini capsule must remain at its exact stable size"
            )
            XCTAssertEqual(
                frame.minY - target.minY,
                frame.maxY - target.maxY,
                accuracy: 0.03,
                "the post-contact spring must translate the formed capsule rigidly"
            )
        }
        for index in rigidIndex ..< frames.count {
            guard index > 0 else { continue }
            XCTAssertEqual(
                frames[index].maxY - frames[index - 1].maxY,
                frames[index].minY - frames[index - 1].minY,
                accuracy: 0.15,
                "the contact chord and every formed-Mini chord must belong to the one rigid dip"
            )
        }
        let globalDip = (frames.map(\.minY).max() ?? target.minY) - target.minY
        XCTAssertGreaterThanOrEqual(globalDip, 5.75)
        XCTAssertLessThanOrEqual(globalDip, 6.25)
        let rigidDip = (rigidFrames.map(\.minY).max() ?? target.minY) - target.minY
        XCTAssertGreaterThanOrEqual(rigidDip, 0.5)
        XCTAssertLessThanOrEqual(rigidDip, 6.25)

        let terminalTopVelocity = (
            topProgress[topProgress.count - 1]
                - topProgress[topProgress.count - 2]
        ) / sampleInterval
        let terminalBottomVelocity = (
            bottomProgress[bottomProgress.count - 1]
                - bottomProgress[bottomProgress.count - 2]
        ) / sampleInterval
        XCTAssertLessThanOrEqual(
            abs(terminalTopVelocity),
            0.08,
            "the last top chord still moves at \(terminalTopVelocity) normalized/s before snapping to the stable Mini frame"
        )
        XCTAssertLessThanOrEqual(abs(terminalBottomVelocity), 0.06)
    }

    @MainActor
    func testDownwardDragCollapsePreservesBoundaryC1AtActualCadenceBeforeReversing() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }

        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        fixture.coordinator.reset(to: .expanded)
        XCTAssertTrue(fixture.coordinator.beginDrag())
        fixture.coordinator.updateDrag(translationY: 313)

        let releaseFrame = fixture.surface.frame
        let target = fixture.geometry.collapsedFrame
        let signedBottomDistance = target.maxY - releaseFrame.maxY
        XCTAssertLessThan(signedBottomDistance, 0)
        let referenceNormalizedBottomVelocity: CGFloat = -15
        let releaseVelocityY = referenceNormalizedBottomVelocity
            * signedBottomDistance
        XCTAssertGreaterThan(releaseVelocityY, 0)
        let releaseSurface = BottomBarAccessorySurfaceGeometry(
            position: fixture.surface.layer.position,
            bounds: fixture.surface.layer.bounds,
            cornerRadius: fixture.surface.layer.cornerRadius
        )
        let targetSurface = fixture.geometry.surfaceGeometry(at: 0)

        fixture.coordinator.settle(
            to: .collapsed,
            initialVelocity: releaseVelocityY
        )
        let geometryTrack = try XCTUnwrap(
            fixture.surface.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator
                    .surfaceGeometryAnimationKey
            ) as? CAAnimationGroup
        )
        let frames = try surfaceFrames(in: geometryTrack)
        let sampleInterval = CGFloat(
            geometryTrack.duration / Double(max(1, frames.count - 1))
        )
        XCTAssertEqual(sampleInterval, 1.0 / 120.0, accuracy: 0.000_01)
        XCTAssertGreaterThanOrEqual(frames.count, 3)

        let settleDuration = geometryTrack.duration
        func analyticGeometry(
            at elapsed: TimeInterval
        ) -> BottomBarAccessorySurfaceGeometry {
            BottomBarAccessoryTransitionCoordinator.settleSurfaceGeometry(
                from: releaseSurface,
                to: targetSurface,
                target: .collapsed,
                linearProgress: CGFloat(elapsed / settleDuration),
                initialVelocityY: releaseVelocityY,
                initialTopVelocityY: releaseVelocityY,
                initialBottomVelocityY: releaseVelocityY,
                configuration: .default,
                settleDuration: settleDuration,
                preservesBoundaryVelocities: true,
                preservesTopBoundaryVelocity: false,
                preservesBottomBoundaryVelocity: false,
                velocityHandoffSampleInterval: nil
            )
        }
        func zeroForceGeometry(
            at elapsed: TimeInterval
        ) -> BottomBarAccessorySurfaceGeometry {
            BottomBarAccessoryTransitionCoordinator.settleSurfaceGeometry(
                from: releaseSurface,
                to: targetSurface,
                target: .collapsed,
                linearProgress: CGFloat(elapsed / settleDuration),
                initialVelocityY: 0,
                initialTopVelocityY: 0,
                initialBottomVelocityY: 0,
                configuration: .default,
                settleDuration: settleDuration,
                preservesBoundaryVelocities: true,
                preservesTopBoundaryVelocity: false,
                preservesBottomBoundaryVelocity: false,
                velocityHandoffSampleInterval: nil
            )
        }
        for index in frames.indices {
            let elapsed = Double(index) * Double(sampleInterval)
            XCTAssertEqual(
                frames[index].maxY,
                zeroForceGeometry(at: elapsed).frame.maxY,
                accuracy: 0.02,
                "ordinary bottom flight must be independent of gesture force at compositor sample \(index)"
            )
        }
        let derivativeStep: TimeInterval = 0.000_001
        let infinitesimal = analyticGeometry(at: derivativeStep)
        let topLaunchVelocity = (
            infinitesimal.frame.minY - releaseFrame.minY
        ) / CGFloat(derivativeStep)
        let bottomLaunchVelocity = (
            infinitesimal.frame.maxY - releaseFrame.maxY
        ) / CGFloat(derivativeStep)
        let referenceTopLaunchVelocity = (
            target.minY - releaseFrame.minY
        ) * BottomBarAccessoryTransitionCoordinator
            .referenceCollapseTopNormalizedVelocity
        let topLaunchTolerance = max(2, releaseVelocityY * 0.002)
        XCTAssertEqual(
            topLaunchVelocity,
            referenceTopLaunchVelocity,
            accuracy: topLaunchTolerance,
            "ordinary finger close must replay the original top launch instead of inheriting gesture speed"
        )
        XCTAssertEqual(
            bottomLaunchVelocity,
            0,
            accuracy: 1,
            "ordinary finger close must release the critical bottom response from rest"
        )

        let hardwareMaximum = fixture.window.screen.maximumFramesPerSecond
        let visibleInterval = BottomBarAccessoryTransitionCoordinator
            .resolvedVelocityHandoffSampleInterval(
                keyframesPerSecond: 120,
                maximumFramesPerSecond: hardwareMaximum
            )
        let visibleIndex = max(
            1,
            Int((visibleInterval / Double(sampleInterval)).rounded())
        )
        let visibleVelocity = (
            frames[visibleIndex].maxY - releaseFrame.maxY
        ) / CGFloat(visibleInterval)
        let analyticVisible = analyticGeometry(at: visibleInterval)
        XCTAssertEqual(
            frames[visibleIndex].minY,
            analyticVisible.frame.minY,
            accuracy: 0.1,
            "runtime top must sample the cadence-independent analytic response"
        )
        XCTAssertEqual(
            frames[visibleIndex].maxY,
            analyticVisible.frame.maxY,
            accuracy: 0.1,
            "runtime bottom must sample the cadence-independent analytic response"
        )
        XCTAssertLessThan(
            visibleVelocity,
            0,
            "the first visible bottom chord must accelerate toward Mini without an outward gesture-force prefix"
        )
        for index in 1 ... visibleIndex {
            XCTAssertLessThan(frames[index].maxY, frames[index - 1].maxY)
        }

        for hardwareRate in [120, 60] {
            let cadence = TimeInterval(1) / TimeInterval(hardwareRate)
            let analyticFirstVisible = analyticGeometry(at: cadence)
            let cadenceParameterizedFirstVisible = BottomBarAccessoryTransitionCoordinator
                .settleSurfaceGeometry(
                    from: releaseSurface,
                    to: targetSurface,
                    target: .collapsed,
                    linearProgress: CGFloat(cadence / settleDuration),
                    initialVelocityY: releaseVelocityY,
                    initialTopVelocityY: releaseVelocityY,
                    initialBottomVelocityY: releaseVelocityY,
                    configuration: .default,
                    settleDuration: settleDuration,
                    preservesBoundaryVelocities: true,
                    preservesTopBoundaryVelocity: false,
                    preservesBottomBoundaryVelocity: false,
                    velocityHandoffSampleInterval: cadence
                )
            XCTAssertEqual(
                cadenceParameterizedFirstVisible.frame.minY,
                analyticFirstVisible.frame.minY,
                accuracy: 0.02,
                "120/60Hz must sample one analytic top launch, not distinct finite-chord seeds"
            )
            XCTAssertEqual(
                cadenceParameterizedFirstVisible.frame.maxY,
                analyticFirstVisible.frame.maxY,
                accuracy: 0.02,
                "120/60Hz must sample one analytic bottom launch, not distinct finite-chord seeds"
            )
            XCTAssertGreaterThan(
                analyticFirstVisible.frame.minY,
                releaseFrame.minY,
                "top must visibly continue downward on the first \(hardwareRate)Hz chord"
            )
            XCTAssertLessThan(
                analyticFirstVisible.frame.maxY,
                releaseFrame.maxY,
                "fixed bottom must visibly fold toward Mini on the first \(hardwareRate)Hz chord"
            )
        }

        let contactIndex = try XCTUnwrap(frames.firstIndex {
            $0.height <= target.height + 0.001
        })
        XCTAssertGreaterThan(contactIndex, 1)
        let bottomTargetDirection: CGFloat = signedBottomDistance >= 0 ? 1 : -1
        if contactIndex > 1 {
            for index in 1 ..< contactIndex {
                let projectedBottomChord = bottomTargetDirection * (
                    frames[index].maxY - frames[index - 1].maxY
                )
                XCTAssertGreaterThanOrEqual(
                    projectedBottomChord,
                    -0.001,
                    "fixed critical bottom may not turn away from Mini before rigid contact"
                )
            }
        }
        for index in contactIndex ..< frames.count {
            guard index > 0 else { continue }
            XCTAssertEqual(
                frames[index].maxY - frames[index - 1].maxY,
                frames[index].minY - frames[index - 1].minY,
                accuracy: 0.15,
                "from the contact chord onward, bottom must share the one rigid Mini dip"
            )
        }

        let bottomProgress = frames.map {
            normalizedEdgeProgress(
                $0.maxY,
                from: releaseFrame.maxY,
                to: target.maxY
            )
        }
        XCTAssertLessThanOrEqual(
            holdThenJumpCount(in: bottomProgress),
            2,
            "the fixed critical bottom flight must not introduce repeated-keyframe velocity stairs"
        )
    }

    @MainActor
    func testCollapsedArtworkTrackMatchesOriginalTopFlightAndSizeCoupledHorizontalPath() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }
        let collapsedArtwork = UIView(
            frame: CGRect(x: 8, y: 2, width: 44, height: 44)
        )
        let expandedArtwork = UIView(
            frame: CGRect(x: 51, y: 150, width: 300, height: 300)
        )
        fixture.collapsedHost.addSubview(collapsedArtwork)
        fixture.expandedHost.addSubview(expandedArtwork)
        fixture.window.layoutIfNeeded()
        let targetArtworkFrame = collapsedArtwork.convert(
            collapsedArtwork.bounds,
            to: fixture.sharedHost
        )
        let collapsedParticipant = SharedElementParticipant(
            view: collapsedArtwork,
            cornerRadius: 12
        )
        let expandedParticipant = SharedElementParticipant(
            view: expandedArtwork,
            cornerRadius: 24
        )

        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: collapsedParticipant,
            expandedParticipant: expandedParticipant,
            reduceMotion: false
        ))
        fixture.coordinator.reset(to: .expanded)
        XCTAssertTrue(fixture.coordinator.beginDrag())
        fixture.coordinator.updateDrag(translationY: 313)

        let representation = try XCTUnwrap(fixture.sharedHost.subviews.first)
        let releasePosition = representation.layer.position
        let releaseBounds = representation.layer.bounds
        let releaseTop = releasePosition.y - 0.5 * releaseBounds.height
        let targetPosition = CGPoint(
            x: targetArtworkFrame.midX,
            y: targetArtworkFrame.midY
        )
        let targetBounds = CGRect(origin: .zero, size: targetArtworkFrame.size)
        let targetTop = targetPosition.y - 0.5 * targetBounds.height
        let artworkTopTravel = targetTop - releaseTop
        XCTAssertGreaterThan(artworkTopTravel, 1)

        let normalizedReleaseVelocity: CGFloat = 12.6
        fixture.coordinator.settle(
            to: .collapsed,
            initialVelocity: artworkTopTravel * normalizedReleaseVelocity
        )
        let surfaceGroup = try XCTUnwrap(
            fixture.surface.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator
                    .surfaceGeometryAnimationKey
            ) as? CAAnimationGroup
        )
        let artworkGroup = try XCTUnwrap(
            animationGroup(
                on: representation.layer,
                containing: ["position", "bounds", "cornerRadius"]
            )
        )
        let artworkTracks = try surfaceKeyframeTracks(in: artworkGroup)
        let positions = try XCTUnwrap(
            artworkTracks.position.values as? [NSValue]
        ).map(\.cgPointValue)
        let bounds = try XCTUnwrap(
            artworkTracks.bounds.values as? [NSValue]
        ).map(\.cgRectValue)
        let keyTimes = try XCTUnwrap(artworkTracks.position.keyTimes)

        XCTAssertEqual(artworkGroup.duration, 32.0 / 60.0, accuracy: 0.000_001)
        XCTAssertEqual(artworkGroup.duration, surfaceGroup.duration, accuracy: 0.000_1)
        XCTAssertEqual(positions.count, bounds.count)
        XCTAssertEqual(positions.count, keyTimes.count)
        XCTAssertEqual(try XCTUnwrap(positions.first).x, releasePosition.x, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(positions.first).y, releasePosition.y, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(bounds.first), releaseBounds)
        XCTAssertEqual(try XCTUnwrap(positions.last).x, targetPosition.x, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(positions.last).y, targetPosition.y, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(bounds.last), targetBounds)

        let referenceTop: [(nativeFrame: Int, progress: CGFloat)] = [
            (1, 0.225),
            (4, 0.676),
            (8, 0.995),
            (12, 1.053),
            (16, 1.064),
            (20, 1.025),
            (24, 1.006),
            (28, 0.999),
            (32, 1.000),
        ]
        for checkpoint in referenceTop {
            let requestedKeyTime = (Double(checkpoint.nativeFrame) / 60)
                / artworkGroup.duration
            let index = keyTimes.indices.min { lhs, rhs in
                abs(keyTimes[lhs].doubleValue - requestedKeyTime)
                    < abs(keyTimes[rhs].doubleValue - requestedKeyTime)
            } ?? 0
            let visibleTop = positions[index].y - 0.5 * bounds[index].height
            XCTAssertEqual(
                normalizedEdgeProgress(
                    visibleTop,
                    from: releaseTop,
                    to: targetTop
                ),
                checkpoint.progress,
                accuracy: checkpoint.nativeFrame == 32 ? 0.000_1 : 0.035,
                "runtime cover top misses original frame s\(checkpoint.nativeFrame)"
            )
        }

        let referenceSize: [(nativeFrame: Int, progress: CGFloat)] = [
            (1, 0.048_3),
            (4, 0.361_8),
            (8, 0.711_0),
            (12, 0.885_1),
            (16, 0.957_4),
            (20, 0.984_9),
            (24, 0.995_5),
            (28, 0.999_5),
            (32, 1.000),
        ]
        for checkpoint in referenceSize {
            let requestedKeyTime = (Double(checkpoint.nativeFrame) / 60)
                / artworkGroup.duration
            let index = keyTimes.indices.min { lhs, rhs in
                abs(keyTimes[lhs].doubleValue - requestedKeyTime)
                    < abs(keyTimes[rhs].doubleValue - requestedKeyTime)
            } ?? 0
            XCTAssertEqual(
                normalizedEdgeProgress(
                    bounds[index].width,
                    from: releaseBounds.width,
                    to: targetBounds.width
                ),
                checkpoint.progress,
                accuracy: checkpoint.nativeFrame == 32 ? 0.002 : 0.008,
                "cover size misses its full 32-frame critically damped clock at s\(checkpoint.nativeFrame)"
            )
        }

        for index in positions.indices {
            let sizeProgress = normalizedEdgeProgress(
                bounds[index].width,
                from: releaseBounds.width,
                to: targetBounds.width
            )
            let expectedX = releasePosition.x
                + (targetPosition.x - releasePosition.x) * sizeProgress
            XCTAssertEqual(
                positions[index].x,
                expectedX,
                accuracy: 0.75,
                "collapse X must stay coupled to cover size without a separate arc or inertial plateau at sample \(index)"
            )
        }
    }

    @MainActor
    func testOpeningArtworkDoesNotInheritStrongCloseResidualOrLagTheSurfaceClock() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }
        let collapsedArtwork = UIView(
            frame: CGRect(x: 8, y: 2, width: 44, height: 44)
        )
        let expandedArtwork = UIView(
            frame: CGRect(x: 51, y: 150, width: 300, height: 300)
        )
        fixture.collapsedHost.addSubview(collapsedArtwork)
        fixture.expandedHost.addSubview(expandedArtwork)
        let collapsedParticipant = SharedElementParticipant(
            view: collapsedArtwork,
            cornerRadius: 12
        )
        let expandedParticipant = SharedElementParticipant(
            view: expandedArtwork,
            cornerRadius: 24
        )

        func openingTracks() throws -> (
            surface: [CGRect],
            artwork: [CGPoint],
            bounds: [CGRect],
            corners: [CGFloat],
            keyTimes: [NSNumber],
            duration: TimeInterval
        ) {
            XCTAssertTrue(fixture.coordinator.beginExpansion(
                geometry: fixture.geometry,
                dockingContext: runtimeDockingContext,
                collapsedParticipant: collapsedParticipant,
                expandedParticipant: expandedParticipant,
                reduceMotion: false
            ))
            let surfaceGroup = try XCTUnwrap(
                fixture.surface.layer.animation(
                    forKey: BottomBarAccessoryTransitionCoordinator
                        .surfaceGeometryAnimationKey
                ) as? CAAnimationGroup
            )
            let representation = try XCTUnwrap(fixture.sharedHost.subviews.first)
            let artworkGroup = try XCTUnwrap(
                animationGroup(
                    on: representation.layer,
                    containing: ["position", "bounds", "cornerRadius"]
                )
            )
            let artworkTracks = try surfaceKeyframeTracks(in: artworkGroup)
            let surfaceTracks = try surfaceKeyframeTracks(in: surfaceGroup)
            let keyTimes = try XCTUnwrap(artworkTracks.position.keyTimes)
            XCTAssertEqual(keyTimes, surfaceTracks.position.keyTimes)
            XCTAssertEqual(artworkTracks.bounds.keyTimes, keyTimes)
            XCTAssertEqual(artworkTracks.cornerRadius.keyTimes, keyTimes)
            XCTAssertEqual(artworkGroup.duration, surfaceGroup.duration, accuracy: 0.000_1)
            XCTAssertEqual(
                try explicitMediaBeginTime(of: artworkGroup, on: representation.layer),
                try explicitMediaBeginTime(of: surfaceGroup, on: fixture.surface.layer),
                accuracy: 0.000_1,
                "opening artwork and surface must publish on the same compositor frame"
            )
            return (
                try surfaceFrames(in: surfaceGroup),
                try XCTUnwrap(
                    artworkTracks.position.values as? [NSValue]
                ).map(\.cgPointValue),
                try XCTUnwrap(
                    artworkTracks.bounds.values as? [NSValue]
                ).map(\.cgRectValue),
                try XCTUnwrap(
                    artworkTracks.cornerRadius.values as? [NSNumber]
                ).map { CGFloat($0.doubleValue) },
                keyTimes,
                artworkGroup.duration
            )
        }

        let cleanOpening = try openingTracks()
        fixture.coordinator.reset(to: .expanded)

        XCTAssertTrue(fixture.coordinator.beginDrag())
        let measurementInterval: TimeInterval = 1 / 120
        fixture.coordinator.updateDrag(translationY: 150)
        RunLoop.main.run(
            until: Date().addingTimeInterval(measurementInterval)
        )
        fixture.coordinator.updateDrag(translationY: 200)
        fixture.coordinator.settle(to: .collapsed, initialVelocity: 6_000)
        let strongCloseRepresentation = try XCTUnwrap(
            fixture.sharedHost.subviews.first
        )
        let strongCloseGroup = try XCTUnwrap(
            animationGroup(
                on: strongCloseRepresentation.layer,
                containing: ["position", "bounds", "cornerRadius"]
            )
        )
        let strongClosePositions = try XCTUnwrap(
            try surfaceKeyframeTracks(in: strongCloseGroup)
                .position.values as? [NSValue]
        ).map(\.cgPointValue)
        XCTAssertGreaterThan(
            strongClosePositions[1].y,
            strongClosePositions[0].y,
            "fixture must install a genuinely forward strong-close artwork launch"
        )

        fixture.coordinator.reset(to: .collapsed)
        // `reset` commits the collapsed model geometry synchronously, while
        // Core Animation may keep the just-cancelled close presentation alive
        // until the transaction reaches the render server. A real second tap
        // cannot occur inside that same uncommitted transaction. Let the test
        // fixture cross one display chord before capturing the next opening;
        // otherwise it accidentally retargets from the old drag frame and
        // mistakes that synthetic origin for inherited close velocity.
        CATransaction.flush()
        let endpointCommitDeadline = Date().addingTimeInterval(0.10)
        while let presentation = fixture.surface.layer.presentation(),
              abs(
                presentation.frame.minY
                    - fixture.geometry.collapsedFrame.minY
              ) > 0.02,
              Date() < endpointCommitDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertEqual(
            fixture.surface.layer.presentation()?.frame.minY
                ?? fixture.surface.frame.minY,
            fixture.geometry.collapsedFrame.minY,
            accuracy: 0.02,
            "opening fixture must begin after the collapsed endpoint commit"
        )
        let openingAfterStrongClose = try openingTracks()
        XCTAssertEqual(cleanOpening.surface.count, openingAfterStrongClose.surface.count)
        XCTAssertEqual(cleanOpening.artwork.count, openingAfterStrongClose.artwork.count)
        XCTAssertEqual(cleanOpening.bounds.count, openingAfterStrongClose.bounds.count)
        XCTAssertEqual(cleanOpening.corners.count, openingAfterStrongClose.corners.count)
        XCTAssertEqual(cleanOpening.keyTimes, openingAfterStrongClose.keyTimes)
        XCTAssertEqual(cleanOpening.duration, openingAfterStrongClose.duration, accuracy: 0.000_1)

        for index in cleanOpening.artwork.indices {
            XCTAssertEqual(
                openingAfterStrongClose.surface[index].minY,
                cleanOpening.surface[index].minY,
                accuracy: 0.02,
                "opening surface may not inherit prior close velocity at sample \(index)"
            )
            XCTAssertEqual(
                openingAfterStrongClose.artwork[index].x,
                cleanOpening.artwork[index].x,
                accuracy: 0.02,
                "opening artwork X may not inherit prior close residual at sample \(index)"
            )
            XCTAssertEqual(
                openingAfterStrongClose.artwork[index].y,
                cleanOpening.artwork[index].y,
                accuracy: 0.02,
                "opening artwork Y may not inherit prior close residual at sample \(index)"
            )
            XCTAssertEqual(
                openingAfterStrongClose.bounds[index].width,
                cleanOpening.bounds[index].width,
                accuracy: 0.02,
                "opening size must remain on its clean slow clock at sample \(index)"
            )
            XCTAssertEqual(
                openingAfterStrongClose.corners[index],
                cleanOpening.corners[index],
                accuracy: 0.02,
                "opening corner radius must remain on its clean slow clock at sample \(index)"
            )
        }

        for hardwareRate in [120.0, 60.0] {
            var previousIndex = 0
            for chordNumber in 1 ... 2 {
                let requestedTime = Double(chordNumber) / hardwareRate
                let index = try XCTUnwrap(
                    openingAfterStrongClose.keyTimes.indices.min { lhs, rhs in
                        let lhsTime = Double(
                            truncating: openingAfterStrongClose.keyTimes[lhs]
                        ) * openingAfterStrongClose.duration
                        let rhsTime = Double(
                            truncating: openingAfterStrongClose.keyTimes[rhs]
                        ) * openingAfterStrongClose.duration
                        return abs(lhsTime - requestedTime)
                            < abs(rhsTime - requestedTime)
                    }
                )
                let surfaceTravel = openingAfterStrongClose.surface[index].minY
                    - openingAfterStrongClose.surface[previousIndex].minY
                let artworkTravel = openingAfterStrongClose.artwork[index].y
                    - openingAfterStrongClose.artwork[previousIndex].y
                XCTAssertLessThan(
                    surfaceTravel,
                    -0.001,
                    "opening surface may not hold visible chord \(chordNumber) at \(Int(hardwareRate))Hz"
                )
                XCTAssertLessThan(
                    artworkTravel,
                    -0.001,
                    "opening artwork may not lag or run in the stale close direction on chord \(chordNumber) at \(Int(hardwareRate))Hz"
                )
                previousIndex = index
            }
        }
    }

    @MainActor
    func testCollapseReturnKeepsVisibleNonlinearDecelerationAtNativeCadences() throws {
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        let originFrame = CGRect(x: 0, y: 180, width: 402, height: 874)
        let targetFrame = CGRect(x: 20, y: 735, width: 362, height: 48)
        let origin = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: originFrame.midX, y: originFrame.midY),
            bounds: CGRect(origin: .zero, size: originFrame.size),
            cornerRadius: 60
        )
        let target = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: targetFrame.midX, y: targetFrame.midY),
            bounds: CGRect(origin: .zero, size: targetFrame.size),
            cornerRadius: 24
        )

        for hardwareRate in [60, 120] {
            let cadence = 1.0 / Double(hardwareRate)
            var elapsed: TimeInterval = 0
            var frames: [CGRect] = []
            while elapsed < configuration.collapseDuration {
                frames.append(
                    BottomBarAccessoryTransitionCoordinator
                        .settleSurfaceGeometry(
                            from: origin,
                            to: target,
                            target: .collapsed,
                            linearProgress: CGFloat(
                                elapsed / configuration.collapseDuration
                            ),
                            configuration: configuration,
                            settleDuration: configuration.collapseDuration
                        ).frame
                )
                elapsed += cadence
            }
            frames.append(targetFrame)

            let peakIndex = frames.indices.max {
                frames[$0].minY < frames[$1].minY
            } ?? 0
            XCTAssertGreaterThan(peakIndex, 0)
            XCTAssertLessThan(peakIndex, frames.count - 4)
            let returnResiduals = frames[peakIndex...].map {
                $0.minY - targetFrame.minY
            }
            XCTAssertGreaterThan(try XCTUnwrap(returnResiduals.first), 5.75)
            XCTAssertEqual(try XCTUnwrap(returnResiduals.last), 0, accuracy: 0.001)

            let inwardChords = zip(
                returnResiduals,
                returnResiduals.dropFirst()
            ).map { previous, current in
                previous - current
            }
            XCTAssertTrue(
                inwardChords.allSatisfy { $0 > 0 },
                "the (hardwareRate)Hz return may not hold, reverse, or relaunch"
            )
            let maximumChordIndex = inwardChords.indices.max {
                inwardChords[$0] < inwardChords[$1]
            } ?? 0
            XCTAssertLessThan(
                maximumChordIndex,
                inwardChords.count - 3,
                "the return needs a visible slowing region, not a peak-speed endpoint"
            )
            let decelerationChords = inwardChords[maximumChordIndex...]
            for pair in zip(
                decelerationChords,
                decelerationChords.dropFirst()
            ) {
                XCTAssertLessThan(
                    pair.1,
                    pair.0 + 0.000_5,
                    "the (hardwareRate)Hz terminal return must continuously shed speed after its single velocity crest"
                )
            }
            let maximumChord = try XCTUnwrap(decelerationChords.first)
            let finalChord = try XCTUnwrap(decelerationChords.last)
            XCTAssertLessThan(
                finalChord,
                maximumChord * 0.08,
                "a nearly linear tail is perceptually abrupt; the last (hardwareRate)Hz chord must be under eight percent of the return's visible peak chord"
            )

            XCTAssertEqual(
                stationaryThenMovingChordCount(
                    in: returnResiduals.map {
                        $0 / max(1, targetFrame.height)
                    }
                ),
                0,
                "terminal deceleration may not be synthesized as a stationary key followed by a final correction"
            )
        }
    }

    @MainActor
    func testReferenceVelocityCollapseMatchesBottomFlightAndFormsMiniWithoutContactKink() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }

        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        fixture.coordinator.reset(to: .expanded)
        XCTAssertTrue(fixture.coordinator.beginDrag())
        fixture.coordinator.updateDrag(translationY: 313)

        let releaseFrame = fixture.surface.frame
        let target = fixture.geometry.collapsedFrame
        let signedBottomDistance = target.maxY - releaseFrame.maxY
        let releaseVelocityY = -15 * signedBottomDistance
        fixture.coordinator.settle(
            to: .collapsed,
            initialVelocity: releaseVelocityY
        )
        let geometryTrack = try XCTUnwrap(
            fixture.surface.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator
                    .surfaceGeometryAnimationKey
            ) as? CAAnimationGroup
        )
        let frames = try surfaceFrames(in: geometryTrack)
        let sampleInterval = geometryTrack.duration
            / Double(max(1, frames.count - 1))
        XCTAssertEqual(sampleInterval, 1.0 / 120.0, accuracy: 0.000_01)
        XCTAssertLessThanOrEqual(
            geometryTrack.duration,
            BottomBarAccessoryTransitionConfiguration.default.collapseDuration
                + 0.000_1
        )

        let referenceBottomProgress: [(nativeFrame: Int, progress: CGFloat)] = [
            (13, 0.847_087),
            (16, 0.916_827),
            (18, 0.945_305),
            (20, 0.964_410),
            (24, 0.987_496),
        ]
        for checkpoint in referenceBottomProgress {
            let elapsed = TimeInterval(checkpoint.nativeFrame) / 60
            let index = Int((elapsed / sampleInterval).rounded())
            let frame = try XCTUnwrap(
                frames.indices.contains(index) ? frames[index] : nil
            )
            let progress = normalizedEdgeProgress(
                frame.maxY,
                from: releaseFrame.maxY,
                to: target.maxY
            )
            XCTAssertEqual(
                progress,
                checkpoint.progress,
                accuracy: 0.001,
                "fixed critical bottom misses the force-independent reference fit at native frame s\(checkpoint.nativeFrame)"
            )
        }

        for frame in frames {
            XCTAssertGreaterThanOrEqual(
                frame.height,
                target.height - 0.01,
                "contact with the top boundary must never squeeze the glass below Mini"
            )
        }
        let endpoint = try XCTUnwrap(frames.last)
        XCTAssertEqual(endpoint.maxY, target.maxY, accuracy: 0.01)
        XCTAssertEqual(endpoint.height, target.height, accuracy: 0.01)

        let heightGap = frames.map { $0.height - target.height }
        let contactIndex = try XCTUnwrap(
            heightGap.indices.dropFirst().first { heightGap[$0] <= 0.001 },
            "the two independent boundaries must form the rigid Mini capsule by completion"
        )
        XCTAssertLessThan(
            contactIndex,
            frames.count - 2,
            "Mini contact must leave compositor samples for the rigid dip and return"
        )
        let incomingContactVelocity = (
            heightGap[contactIndex] - heightGap[contactIndex - 1]
        ) / CGFloat(sampleInterval)
        XCTAssertLessThanOrEqual(incomingContactVelocity, 0.001)
        if contactIndex < heightGap.count - 1 {
            let outgoingContactVelocity = (
                heightGap[contactIndex + 1] - heightGap[contactIndex]
            ) / CGFloat(sampleInterval)
            XCTAssertLessThanOrEqual(outgoingContactVelocity, 0.001)
            XCTAssertLessThan(
                abs(outgoingContactVelocity),
                abs(incomingContactVelocity),
                "the last sampled height chord must keep slowing into rigid Mini contact without reversing"
            )
        } else if contactIndex >= 2 {
            let precedingContactVelocity = (
                heightGap[contactIndex - 1] - heightGap[contactIndex - 2]
            ) / CGFloat(sampleInterval)
            XCTAssertLessThanOrEqual(precedingContactVelocity, 0.001)
            XCTAssertLessThan(
                abs(incomingContactVelocity),
                abs(precedingContactVelocity),
                "an endpoint contact must keep decelerating on its final sampled chord without reversing"
            )
        }

        let bottomProgress = frames.map {
            normalizedEdgeProgress(
                $0.maxY,
                from: releaseFrame.maxY,
                to: target.maxY
            )
        }
        let lateReferenceIndex = Int(
            ((22.0 / 60.0) / sampleInterval).rounded()
        )
        XCTAssertEqual(
            bottomProgress[lateReferenceIndex],
            0.977_694,
            accuracy: 0.001,
            "fixed critical bottom misses the fitted s22 tail checkpoint"
        )
        let terminalBottomVelocities = zip(
            bottomProgress.dropFirst(),
            bottomProgress
        ).map { pair in
            (pair.0 - pair.1) / CGFloat(sampleInterval)
        }
        let terminalVelocity = try XCTUnwrap(terminalBottomVelocities.last)
        let precedingVelocity = terminalBottomVelocities[
            terminalBottomVelocities.count - 2
        ]
        let terminalAcceleration = (
            terminalVelocity - precedingVelocity
        ) / CGFloat(sampleInterval)
        XCTAssertGreaterThanOrEqual(terminalVelocity, 0)
        XCTAssertLessThanOrEqual(
            terminalVelocity,
            0.06,
            "the analytic ease-out must arrive with a low terminal 120 Hz chord velocity"
        )
        XCTAssertLessThanOrEqual(
            abs(terminalAcceleration),
            15,
            "the C2 landing must also taper its final sampled acceleration toward zero"
        )
        for pair in zip(
            terminalBottomVelocities.suffix(4),
            terminalBottomVelocities.suffix(3)
        ) {
            XCTAssertLessThan(
                pair.1,
                pair.0,
                "each terminal bottom chord must be slower than the preceding chord"
            )
            XCTAssertGreaterThanOrEqual(pair.1, 0)
        }
        XCTAssertLessThanOrEqual(
            holdThenJumpCount(in: bottomProgress),
            2,
            "the fitted bottom flight must not replay quantized hold-then-jump chord velocities"
        )
    }

    @MainActor
    func testCollapseSurfaceCompositorTrackIsUniform120HzAndUnquantized() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }
        let collapse = try beginReferenceVelocityCollapse(in: fixture)
        let group = collapse.geometryTrack
        let tracks = try surfaceKeyframeTracks(in: group)
        let keyTimes = try XCTUnwrap(tracks.position.keyTimes)
        let expectedCount = Int(round(group.duration * 120)) + 1

        XCTAssertEqual(
            group.duration,
            BottomBarAccessoryTransitionConfiguration.default.collapseDuration,
            accuracy: 0.000_1
        )
        XCTAssertEqual(keyTimes.count, expectedCount)
        XCTAssertEqual(tracks.bounds.keyTimes, keyTimes)
        XCTAssertEqual(tracks.cornerRadius.keyTimes, keyTimes)
        for (index, keyTime) in keyTimes.enumerated() {
            XCTAssertEqual(
                keyTime.doubleValue,
                Double(index) / Double(expectedCount - 1),
                accuracy: 0.000_000_1,
                "surface keyTimes must be uniform 120 Hz samples"
            )
        }
        assertExactFrameRateRange(
            group,
            maximumFramesPerSecond: fixture.window.screen.maximumFramesPerSecond
        )

        let geometries = try surfaceGeometries(in: group)
        XCTAssertEqual(geometries.count, expectedCount)
        let target = fixture.geometry.collapsedFrame
        let topDistance = target.minY - collapse.releaseFrame.minY
        let expectedTopProgress: [(nativeFrame: Int, progress: CGFloat)] = [
            (1, 0.160),
            (4, 0.559),
            (8, 0.890),
            (12, 0.999),
        ]
        for checkpoint in expectedTopProgress {
            let index = checkpoint.nativeFrame * 2
            let geometry = try XCTUnwrap(
                geometries.indices.contains(index) ? geometries[index] : nil
            )
            let progress = normalizedEdgeProgress(
                geometry.frame.minY,
                from: collapse.releaseFrame.minY,
                to: target.minY
            )
            XCTAssertEqual(
                progress,
                checkpoint.progress,
                accuracy: checkpoint.nativeFrame == 1 ? 0.04 : 0.055,
                "surface top misses the original 32-frame close at native frame s\(checkpoint.nativeFrame)"
            )
        }
        let firstLandingIndex = try XCTUnwrap(
            geometries.firstIndex { $0.frame.minY >= target.minY }
        )
        var previousTop = collapse.releaseFrame.minY
        for geometry in geometries[...firstLandingIndex] {
            XCTAssertGreaterThanOrEqual(
                geometry.frame.minY,
                previousTop - 0.001,
                "the close launch must remain monotonic until Mini first lands"
            )
            previousTop = geometry.frame.minY
        }
        let terminalDip = (geometries.map { $0.frame.minY }.max() ?? target.minY)
            - target.minY
        XCTAssertGreaterThanOrEqual(terminalDip, 5.75)
        XCTAssertLessThanOrEqual(terminalDip, 6.25)
        let topValues = geometries.map { $0.frame.minY }
        let topPeakIndex = topValues.indices.max {
            topValues[$0] < topValues[$1]
        } ?? (topValues.count - 1)
        XCTAssertLessThanOrEqual(
            abs(topPeakIndex - 16 * 2),
            2,
            "the six-point Mini dip should crest around native frame 16/32"
        )
        XCTAssertLessThanOrEqual(
            longestStationaryChordRun(
                in: Array(topValues[...topPeakIndex]),
                tolerance: 0.000_1
            ),
            1,
            "the 120Hz composed top may not dock, hold, and then launch its dip"
        )
        let prePeakVelocities = zip(
            topValues[1 ... topPeakIndex],
            topValues[0 ..< topPeakIndex]
        ).map { ($0.0 - $0.1) / CGFloat(group.duration / Double(expectedCount - 1)) }
        if prePeakVelocities.count > 4 {
            for index in 2 ..< (prePeakVelocities.count - 1) {
                if abs(prePeakVelocities[index]) <= 8 {
                    let laterMaximum = prePeakVelocities[(index + 1)...]
                        .map { abs($0) }.max() ?? 0
                    XCTAssertLessThan(
                        laterMaximum,
                        16,
                        "a near-zero 120Hz top chord may not relaunch into a separate dip phase"
                    )
                }
            }
        }
        for geometry in geometries {
            XCTAssertGreaterThanOrEqual(geometry.frame.width, target.width - 0.001)
            XCTAssertGreaterThanOrEqual(geometry.frame.height, target.height - 0.001)
        }
        let endpoint = try XCTUnwrap(geometries.last)
        XCTAssertEqual(endpoint.frame.minY, target.minY, accuracy: 0.001)

        let layoutScale = max(fixture.geometry.layoutSize.height, 1)
        let topScale = max(
            abs(topDistance),
            1
        )
        let bottomScale = max(
            abs(target.maxY - collapse.releaseFrame.maxY),
            1
        )
        let widthScale = max(
            abs(target.width - collapse.releaseFrame.width),
            1
        )
        let heightScale = max(
            abs(target.height - collapse.releaseFrame.height),
            1
        )
        let cornerValues = try XCTUnwrap(
            tracks.cornerRadius.values as? [NSNumber]
        ).map { CGFloat($0.doubleValue) }
        let cornerScale = max(
            abs((cornerValues.last ?? 0) - (cornerValues.first ?? 0)),
            1
        )
        let series: [(String, [CGFloat], CGFloat)] = [
            ("position.x", geometries.map(\.position.x), fixture.geometry.layoutSize.width),
            ("position.y", geometries.map(\.position.y), layoutScale),
            ("top", geometries.map { $0.frame.minY }, topScale),
            ("bottom", geometries.map { $0.frame.maxY }, bottomScale),
            ("bounds.origin.x", geometries.map(\.bounds.origin.x), layoutScale),
            ("bounds.origin.y", geometries.map(\.bounds.origin.y), layoutScale),
            ("bounds.width", geometries.map(\.bounds.width), widthScale),
            ("bounds.height", geometries.map(\.bounds.height), heightScale),
            ("cornerRadius", cornerValues, cornerScale),
        ]
        let sampleInterval = CGFloat(group.duration) / CGFloat(expectedCount - 1)
        for item in series {
            let normalized = item.1.map { $0 / item.2 }
            let allowedTopLandingPairs = item.0 == "top" ? 0 : 1
            XCTAssertLessThanOrEqual(
                holdThenJumpCount(in: normalized),
                allowedTopLandingPairs,
                "\(item.0) contains repeated/paird chords characteristic of a 60 Hz path replayed at 120 Hz"
            )
            XCTAssertLessThanOrEqual(
                stationaryThenMovingChordCount(in: normalized),
                allowedTopLandingPairs,
                "\(item.0) contains held frames followed by compositor jumps"
            )
            assertFiniteMotionBounds(
                normalized,
                sampleInterval: sampleInterval,
                label: item.0
            )
        }
    }

    @MainActor
    func testSharedArtworkOpeningKeepsTheSameSubtleRightwardArc() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }
        let collapsedArtwork = UIView(
            frame: CGRect(x: 8, y: 2, width: 44, height: 44)
        )
        let expandedArtwork = UIView(
            frame: CGRect(x: 51, y: 150, width: 300, height: 300)
        )
        fixture.collapsedHost.addSubview(collapsedArtwork)
        fixture.expandedHost.addSubview(expandedArtwork)
        let collapsedParticipant = SharedElementParticipant(
            view: collapsedArtwork,
            cornerRadius: 12
        )
        let expandedParticipant = SharedElementParticipant(
            view: expandedArtwork,
            cornerRadius: 24
        )

        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: collapsedParticipant,
            expandedParticipant: expandedParticipant,
            reduceMotion: false
        ))
        let surfaceGroup = try XCTUnwrap(
            fixture.surface.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator
                    .surfaceGeometryAnimationKey
            ) as? CAAnimationGroup
        )
        let representation = try XCTUnwrap(fixture.sharedHost.subviews.first)
        let artworkGroup = try XCTUnwrap(
            animationGroup(
                on: representation.layer,
                containing: ["position", "bounds", "cornerRadius"]
            )
        )
        let surfaceTracks = try surfaceKeyframeTracks(in: surfaceGroup)
        let artworkTracks = try surfaceKeyframeTracks(in: artworkGroup)
        let commonKeyTimes = try XCTUnwrap(surfaceTracks.position.keyTimes)
        XCTAssertEqual(commonKeyTimes.count, 49)
        XCTAssertEqual(artworkTracks.position.keyTimes, commonKeyTimes)
        XCTAssertEqual(artworkTracks.bounds.keyTimes, commonKeyTimes)
        XCTAssertEqual(artworkTracks.cornerRadius.keyTimes, commonKeyTimes)
        XCTAssertEqual(artworkGroup.duration, surfaceGroup.duration, accuracy: 0.000_1)
        XCTAssertEqual(
            try explicitMediaBeginTime(of: artworkGroup, on: representation.layer),
            try explicitMediaBeginTime(of: surfaceGroup, on: fixture.surface.layer),
            accuracy: 0.000_1
        )
        assertExactFrameRateRange(
            artworkGroup,
            maximumFramesPerSecond: fixture.window.screen.maximumFramesPerSecond
        )

        let positions = try XCTUnwrap(
            artworkTracks.position.values as? [NSValue]
        ).map(\.cgPointValue)
        let bounds = try XCTUnwrap(
            artworkTracks.bounds.values as? [NSValue]
        ).map(\.cgRectValue)
        let corners = try XCTUnwrap(
            artworkTracks.cornerRadius.values as? [NSNumber]
        ).map { CGFloat($0.doubleValue) }
        let originPosition = CGPoint(
            x: fixture.geometry.collapsedFrame.minX + collapsedArtwork.frame.midX,
            y: fixture.geometry.collapsedFrame.minY + collapsedArtwork.frame.midY
        )
        let targetPosition = CGPoint(
            x: fixture.geometry.expandedFrame.minX + expandedArtwork.frame.midX,
            y: fixture.geometry.expandedFrame.minY + expandedArtwork.frame.midY
        )
        let originBounds = CGRect(origin: .zero, size: collapsedArtwork.bounds.size)
        let targetBounds = CGRect(origin: .zero, size: expandedArtwork.bounds.size)

        XCTAssertEqual(try XCTUnwrap(positions.first).x, originPosition.x, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(positions.first).y, originPosition.y, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(positions.last).x, targetPosition.x, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(positions.last).y, targetPosition.y, accuracy: 0.01)
        let firstBounds = try XCTUnwrap(bounds.first)
        let lastBounds = try XCTUnwrap(bounds.last)
        XCTAssertEqual(firstBounds.minX, originBounds.minX, accuracy: 0.001)
        XCTAssertEqual(firstBounds.minY, originBounds.minY, accuracy: 0.001)
        XCTAssertEqual(firstBounds.width, originBounds.width, accuracy: 0.001)
        XCTAssertEqual(firstBounds.height, originBounds.height, accuracy: 0.001)
        XCTAssertEqual(lastBounds.minX, targetBounds.minX, accuracy: 0.001)
        XCTAssertEqual(lastBounds.minY, targetBounds.minY, accuracy: 0.001)
        XCTAssertEqual(lastBounds.width, targetBounds.width, accuracy: 0.001)
        XCTAssertEqual(lastBounds.height, targetBounds.height, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(corners.first), 12, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(corners.last), 24, accuracy: 0.01)

        for checkpoint in [(10, CGFloat(0.793_28)), (16, 0.960_52), (22, 1)] {
            let index = checkpoint.0 * 2
            XCTAssertEqual(
                normalizedEdgeProgress(
                    bounds[index].width,
                    from: originBounds.width,
                    to: targetBounds.width
                ),
                checkpoint.1,
                accuracy: 0.003
            )
            XCTAssertEqual(
                normalizedEdgeProgress(
                    corners[index],
                    from: 12,
                    to: 24
                ),
                checkpoint.1,
                accuracy: 0.003
            )
        }

        assertRightwardArtworkArc(
            positions: positions,
            bounds: bounds,
            from: originPosition,
            originBounds: originBounds,
            to: targetPosition,
            targetBounds: targetBounds,
            label: "opening artwork"
        )
    }

    @MainActor
    func testSharedArtworkRetargetStartsAtCapturedCurvedPresentationGeometry() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }
        let collapsedArtwork = UIView(
            frame: CGRect(x: 8, y: 2, width: 44, height: 44)
        )
        let expandedArtwork = UIView(
            frame: CGRect(x: 51, y: 150, width: 300, height: 300)
        )
        fixture.collapsedHost.addSubview(collapsedArtwork)
        fixture.expandedHost.addSubview(expandedArtwork)
        let collapsedParticipant = SharedElementParticipant(
            view: collapsedArtwork,
            cornerRadius: 12
        )
        let expandedParticipant = SharedElementParticipant(
            view: expandedArtwork,
            cornerRadius: 24
        )
        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: collapsedParticipant,
            expandedParticipant: expandedParticipant,
            reduceMotion: false
        ))
        let representation = try XCTUnwrap(fixture.sharedHost.subviews.first)
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        let captured = try XCTUnwrap(representation.layer.presentation())
        let capturedPosition = captured.position
        let capturedBounds = captured.bounds
        let capturedCorner = captured.cornerRadius

        fixture.coordinator.settle(to: .collapsed, initialVelocity: 0)
        let surfaceGroup = try XCTUnwrap(
            fixture.surface.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator
                    .surfaceGeometryAnimationKey
            ) as? CAAnimationGroup
        )
        let artworkGroup = try XCTUnwrap(
            animationGroup(
                on: representation.layer,
                containing: ["position", "bounds", "cornerRadius"]
            )
        )
        let surfaceTracks = try surfaceKeyframeTracks(in: surfaceGroup)
        let artworkTracks = try surfaceKeyframeTracks(in: artworkGroup)
        XCTAssertEqual(artworkTracks.position.keyTimes, surfaceTracks.position.keyTimes)
        XCTAssertEqual(artworkGroup.duration, surfaceGroup.duration, accuracy: 0.000_1)
        XCTAssertEqual(
            try explicitMediaBeginTime(of: artworkGroup, on: representation.layer),
            try explicitMediaBeginTime(of: surfaceGroup, on: fixture.surface.layer),
            accuracy: 0.000_1
        )

        let positions = try XCTUnwrap(
            artworkTracks.position.values as? [NSValue]
        ).map(\.cgPointValue)
        let bounds = try XCTUnwrap(
            artworkTracks.bounds.values as? [NSValue]
        ).map(\.cgRectValue)
        let corners = try XCTUnwrap(
            artworkTracks.cornerRadius.values as? [NSNumber]
        ).map { CGFloat($0.doubleValue) }
        let firstPosition = try XCTUnwrap(positions.first)
        let firstBounds = try XCTUnwrap(bounds.first)
        let firstCorner = try XCTUnwrap(corners.first)
        XCTAssertEqual(firstPosition.x, capturedPosition.x, accuracy: 1)
        XCTAssertEqual(firstPosition.y, capturedPosition.y, accuracy: 1)
        XCTAssertEqual(firstBounds.minX, capturedBounds.minX, accuracy: 1)
        XCTAssertEqual(firstBounds.minY, capturedBounds.minY, accuracy: 1)
        XCTAssertEqual(firstBounds.width, capturedBounds.width, accuracy: 1)
        XCTAssertEqual(firstBounds.height, capturedBounds.height, accuracy: 1)
        XCTAssertEqual(firstCorner, capturedCorner, accuracy: 0.5)

        let targetPosition = CGPoint(
            x: fixture.geometry.collapsedFrame.minX + collapsedArtwork.frame.midX,
            y: fixture.geometry.collapsedFrame.minY + collapsedArtwork.frame.midY
        )
        let targetBounds = CGRect(origin: .zero, size: collapsedArtwork.bounds.size)
        let lastPosition = try XCTUnwrap(positions.last)
        let lastBounds = try XCTUnwrap(bounds.last)
        XCTAssertEqual(lastPosition.x, targetPosition.x, accuracy: 0.01)
        XCTAssertEqual(lastPosition.y, targetPosition.y, accuracy: 0.01)
        XCTAssertEqual(lastBounds.minX, targetBounds.minX, accuracy: 0.01)
        XCTAssertEqual(lastBounds.minY, targetBounds.minY, accuracy: 0.01)
        XCTAssertEqual(lastBounds.width, targetBounds.width, accuracy: 0.01)
        XCTAssertEqual(lastBounds.height, targetBounds.height, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(corners.last), 12, accuracy: 0.01)
        for index in positions.indices {
            let sizeProgress = normalizedEdgeProgress(
                bounds[index].width,
                from: firstBounds.width,
                to: targetBounds.width
            )
            XCTAssertEqual(
                positions[index].x,
                firstPosition.x
                    + (targetPosition.x - firstPosition.x) * sizeProgress,
                accuracy: 0.75,
                "a collapse retarget must preserve captured C0, then keep X coupled to size without starting a new arc at sample \(index)"
            )
        }
    }

    @MainActor
    func testEndpointContentOpacityUsesSurfaceSynchronizedCompositorTracks() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }
        let collapse = try beginReferenceVelocityCollapse(in: fixture)
        let surfaceTracks = try surfaceKeyframeTracks(in: collapse.geometryTrack)
        let surfaceKeyTimes = try XCTUnwrap(surfaceTracks.position.keyTimes)
        let collapsedOpacity = try XCTUnwrap(
            keyframeAnimation(on: fixture.collapsedHost.layer, keyPath: "opacity"),
            "collapsed endpoint opacity must be compositor-driven during settle"
        )
        let expandedOpacity = try XCTUnwrap(
            keyframeAnimation(on: fixture.expandedHost.layer, keyPath: "opacity"),
            "expanded endpoint opacity must be compositor-driven during settle"
        )
        XCTAssertEqual(collapsedOpacity.duration, collapse.geometryTrack.duration, accuracy: 0.000_1)
        XCTAssertEqual(expandedOpacity.duration, collapse.geometryTrack.duration, accuracy: 0.000_1)
        XCTAssertEqual(collapsedOpacity.keyTimes, surfaceKeyTimes)
        XCTAssertEqual(expandedOpacity.keyTimes, surfaceKeyTimes)
        assertExactFrameRateRange(
            collapsedOpacity,
            maximumFramesPerSecond: fixture.window.screen.maximumFramesPerSecond
        )
        assertExactFrameRateRange(
            expandedOpacity,
            maximumFramesPerSecond: fixture.window.screen.maximumFramesPerSecond
        )
        let surfaceMediaBeginTime = try explicitMediaBeginTime(
            of: collapse.geometryTrack,
            on: fixture.surface.layer
        )
        XCTAssertEqual(
            try explicitMediaBeginTime(
                of: collapsedOpacity,
                on: fixture.collapsedHost.layer
            ),
            surfaceMediaBeginTime,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try explicitMediaBeginTime(
                of: expandedOpacity,
                on: fixture.expandedHost.layer
            ),
            surfaceMediaBeginTime,
            accuracy: 0.000_1
        )
        let collapsedValues = try XCTUnwrap(
            collapsedOpacity.values as? [NSNumber]
        ).map { CGFloat($0.doubleValue) }
        let expandedValues = try XCTUnwrap(
            expandedOpacity.values as? [NSNumber]
        ).map { CGFloat($0.doubleValue) }
        let geometries = try surfaceGeometries(in: collapse.geometryTrack)
        XCTAssertEqual(collapsedValues.count, geometries.count)
        XCTAssertEqual(expandedValues.count, geometries.count)
        let handoffDuration = min(
            0.06,
            max(1.0 / 120.0, collapse.geometryTrack.duration * 0.18)
        )
        for index in geometries.indices {
            let progress = fixture.geometry.presentationProgress(
                for: geometries[index]
            )
            let elapsed = Double(index) * collapse.geometryTrack.duration
                / Double(max(1, geometries.count - 1))
            if elapsed >= handoffDuration - 0.000_1 {
                XCTAssertEqual(
                    collapsedValues[index],
                    BottomBarAccessoryTransitionCoordinator
                        .collapsedContentPlaneAlpha(presentationProgress: progress),
                    accuracy: 0.001,
                    "collapsed content opacity is phase-shifted from surface keyframe \(index)"
                )
                XCTAssertEqual(
                    expandedValues[index],
                    BottomBarAccessoryTransitionCoordinator
                        .expandedContentPlaneAlpha(presentationProgress: progress),
                    accuracy: 0.001,
                    "expanded content opacity is phase-shifted from surface keyframe \(index)"
                )
            }
        }
        XCTAssertEqual(try XCTUnwrap(collapsedValues.first), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(expandedValues.first), 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(collapsedValues.last), 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(expandedValues.last), 0, accuracy: 0.001)
        let sampleInterval = CGFloat(collapse.geometryTrack.duration)
            / CGFloat(max(1, geometries.count - 1))
        for item in [
            ("collapsed opacity", collapsedValues),
            ("expanded opacity", expandedValues),
        ] {
            XCTAssertLessThanOrEqual(holdThenJumpCount(in: item.1), 1)
            XCTAssertLessThanOrEqual(
                stationaryThenMovingChordCount(in: item.1),
                1
            )
            assertFiniteMotionBounds(
                item.1,
                sampleInterval: sampleInterval,
                maximumVelocity: 120,
                maximumAcceleration: 30_000,
                maximumJerk: 5_000_000,
                label: item.0
            )
        }
    }

    @MainActor
    func testDeepDragToSettleKeepsExpandedPlaneAlphaC0AtSixtyPercentPresentation() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }
        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        fixture.coordinator.reset(to: .expanded)
        XCTAssertTrue(fixture.coordinator.beginDrag())

        let requestedProgress: CGFloat = 0.60
        var lowerTranslation: CGFloat = 0
        var upperTranslation: CGFloat = 700
        var resolvedProgress: CGFloat = 1
        for _ in 0 ..< 24 {
            let translation = (lowerTranslation + upperTranslation) * 0.5
            fixture.coordinator.updateDrag(translationY: translation)
            let geometry = BottomBarAccessorySurfaceGeometry(
                position: fixture.surface.layer.position,
                bounds: fixture.surface.layer.bounds,
                cornerRadius: fixture.surface.layer.cornerRadius
            )
            resolvedProgress = fixture.geometry.presentationProgress(for: geometry)
            if resolvedProgress > requestedProgress {
                lowerTranslation = translation
            } else {
                upperTranslation = translation
            }
        }
        XCTAssertEqual(resolvedProgress, requestedProgress, accuracy: 0.001)
        let alphaAtRelease = fixture.expandedHost.alpha
        XCTAssertEqual(
            alphaAtRelease,
            BottomBarAccessoryTransitionCoordinator
                .expandedContentPlaneAlpha(presentationProgress: resolvedProgress),
            accuracy: 0.001,
            "interactive drag must publish the same geometry-owned expanded alpha used by settle"
        )

        fixture.coordinator.settle(to: .collapsed, initialVelocity: 0)
        let opacity = try XCTUnwrap(
            keyframeAnimation(
                on: fixture.expandedHost.layer,
                keyPath: "opacity"
            )
        )
        let values = try XCTUnwrap(opacity.values as? [NSNumber])
            .map { CGFloat($0.doubleValue) }
        XCTAssertEqual(
            try XCTUnwrap(values.first),
            alphaAtRelease,
            accuracy: 0.001,
            "settle's first compositor sample must be C0 with the held drag plane"
        )
    }

    @MainActor
    func testNativeGlassHierarchyUsesSurfaceSynchronizedCompositorTracks() throws {
        let glassFixture = makeRuntimeGlassMotionFixture()
        let fixture = glassFixture.fixture
        let glass = glassFixture.glass
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }
        guard glass.usesNativeGlassRendererForTesting else {
            throw XCTSkip("native liquid glass requires iOS 26")
        }

        let collapse = try beginReferenceVelocityCollapse(in: fixture)
        let surfaceTracks = try surfaceKeyframeTracks(in: collapse.geometryTrack)
        let keyTimes = try XCTUnwrap(surfaceTracks.position.keyTimes)
        let glassTrack = try XCTUnwrap(
            glass.transitionCompositorSettleTrackForTesting
        )
        XCTAssertTrue(glass.isTransitionCompositorSettleActive)
        XCTAssertEqual(glassTrack.duration, collapse.geometryTrack.duration, accuracy: 0.000_1)
        XCTAssertEqual(glassTrack.keyTimes, keyTimes)
        XCTAssertEqual(glassTrack.sizes.count, keyTimes.count)
        XCTAssertEqual(glassTrack.cornerRadii.count, keyTimes.count)
        XCTAssertEqual(glassTrack.materialAlphaValues.count, keyTimes.count)
        XCTAssertGreaterThanOrEqual(
            glass.transitionCompositorTrackedLayerCountForTesting,
            3
        )
        XCTAssertEqual(
            glassTrack.mediaBeginTime,
            try explicitMediaBeginTime(
                of: collapse.geometryTrack,
                on: fixture.surface.layer
            ),
            accuracy: 0.000_1
        )

        let nativeParams = try synchronizedKeyframeGroup(
            glass.transitionNativeParamsAnimationForTesting,
            requiredKeyPaths: ["position", "bounds", "opacity"],
            keyTimes: keyTimes,
            duration: collapse.geometryTrack.duration,
            localBeginTime: collapse.geometryTrack.beginTime,
            maximumFramesPerSecond: fixture.window.screen.maximumFramesPerSecond
        )
        let nativeEffect = try synchronizedKeyframeGroup(
            glass.transitionNativeEffectAnimationForTesting,
            requiredKeyPaths: ["position", "bounds", "cornerRadius"],
            keyTimes: keyTimes,
            duration: collapse.geometryTrack.duration,
            localBeginTime: collapse.geometryTrack.beginTime,
            maximumFramesPerSecond: fixture.window.screen.maximumFramesPerSecond
        )
        let content = try synchronizedKeyframeGroup(
            glass.transitionContentContainerAnimationForTesting,
            requiredKeyPaths: ["position", "bounds", "cornerRadius"],
            keyTimes: keyTimes,
            duration: collapse.geometryTrack.duration,
            localBeginTime: collapse.geometryTrack.beginTime,
            maximumFramesPerSecond: fixture.window.screen.maximumFramesPerSecond
        )
        let maskContainerAnimation = glass
            .transitionMaskContainerAnimationForTesting
        let maskContentAnimation = glass.transitionMaskContentAnimationForTesting
        XCTAssertEqual(
            maskContainerAnimation != nil,
            maskContentAnimation != nil,
            "an active mask must move both of its synchronized layers"
        )
        if let maskContainerAnimation, let maskContentAnimation {
            _ = try synchronizedKeyframeGroup(
                maskContainerAnimation,
                requiredKeyPaths: ["position", "bounds"],
                keyTimes: keyTimes,
                duration: collapse.geometryTrack.duration,
                localBeginTime: collapse.geometryTrack.beginTime,
                maximumFramesPerSecond: fixture.window.screen.maximumFramesPerSecond
            )
            _ = try synchronizedKeyframeGroup(
                maskContentAnimation,
                requiredKeyPaths: ["position", "bounds"],
                keyTimes: keyTimes,
                duration: collapse.geometryTrack.duration,
                localBeginTime: collapse.geometryTrack.beginTime,
                maximumFramesPerSecond: fixture.window.screen.maximumFramesPerSecond
            )
        }
        if glass.isSyntheticStrokeVisible {
            let stroke = try synchronizedKeyframeGroup(
                glass.transitionSyntheticStrokeAnimationForTesting,
                requiredKeyPaths: ["position", "bounds", "path"],
                keyTimes: keyTimes,
                duration: collapse.geometryTrack.duration,
                localBeginTime: collapse.geometryTrack.beginTime,
                maximumFramesPerSecond: fixture.window.screen.maximumFramesPerSecond
            )
            XCTAssertEqual(stroke["path"]?.values?.count, keyTimes.count)
        }

        for (label, animation) in [
            ("native material bounds", nativeParams["bounds"]),
            ("native effect bounds", nativeEffect["bounds"]),
            ("native effect corner", nativeEffect["cornerRadius"]),
            ("glass content bounds", content["bounds"]),
            ("glass content corner", content["cornerRadius"]),
            ("native material opacity", nativeParams["opacity"]),
        ] {
            let values = try normalizedScalarValues(
                in: XCTUnwrap(animation),
                keyPath: XCTUnwrap(animation?.keyPath)
            )
            XCTAssertLessThanOrEqual(
                holdThenJumpCount(in: values),
                1,
                "\(label) replays paired/repeated compositor chords"
            )
            XCTAssertLessThanOrEqual(
                stationaryThenMovingChordCount(in: values),
                1,
                "\(label) holds a frame before jumping"
            )
        }

        let directCount = glass.transitionDirectGeometryUpdateCountForTesting
        glass.updateInteractiveGeometry(
            size: CGSize(width: 111, height: 77),
            cornerRadius: 9
        )
        XCTAssertEqual(
            glass.transitionDirectGeometryUpdateCountForTesting,
            directCount,
            "display-link/direct geometry writes must be ignored while the native compositor owns settle"
        )
        XCTAssertTrue(glass.isTransitionCompositorSettleActive)
    }

    @MainActor
    func testNativeGlassKeepsOneBlurEffectAndFilterConfigurationThroughDragAndSettle() throws {
        let glassFixture = makeRuntimeGlassMotionFixture()
        let fixture = glassFixture.fixture
        let glass = glassFixture.glass
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("native liquid glass requires iOS 26")
        }
        guard glass.usesNativeGlassRendererForTesting,
              let effectView = glass.transitionMaterialHitTargetForTesting
                as? UIVisualEffectView,
              let originalEffect = effectView.effect as? UIGlassEffect else {
            throw XCTSkip("native liquid glass requires iOS 26")
        }
        let originalEffectClass = ObjectIdentifier(type(of: originalEffect))
        let originalTintColor = originalEffect.tintColor
        let originalIsInteractive = originalEffect.isInteractive
        let originalAssignmentCount = glass
            .nativeGlassEffectAssignmentCountForTesting
        let originalFilterIdentities = (effectView.layer.filters ?? []).map {
            ObjectIdentifier($0 as AnyObject)
        }

        func assertConstantBlur(_ phase: String) {
            guard let currentEffectView = glass
                .transitionMaterialHitTargetForTesting as? UIVisualEffectView,
                  let currentEffect = currentEffectView.effect
                    as? UIGlassEffect else {
                XCTFail("\(phase) removed the native UIGlassEffect renderer")
                return
            }
            XCTAssertTrue(
                currentEffectView === effectView,
                "\(phase) replaced the one live native material view"
            )
            XCTAssertEqual(
                ObjectIdentifier(type(of: currentEffect)),
                originalEffectClass,
                "\(phase) changed the native effect class"
            )
            XCTAssertEqual(
                currentEffect.tintColor,
                originalTintColor,
                "\(phase) changed the glass tint/effect configuration"
            )
            XCTAssertEqual(
                currentEffect.isInteractive,
                originalIsInteractive,
                "\(phase) changed native glass interaction/effect configuration"
            )
            XCTAssertEqual(
                glass.nativeGlassEffectAssignmentCountForTesting,
                originalAssignmentCount,
                "\(phase) assigned a new copied UIGlassEffect instead of resizing the existing material"
            )
            let currentFilterIdentities = (currentEffectView.layer.filters ?? []).map {
                ObjectIdentifier($0 as AnyObject)
            }
            XCTAssertEqual(
                currentFilterIdentities,
                originalFilterIdentities,
                "\(phase) rebuilt the effect filters instead of resizing one live material"
            )
            let forbiddenFragments = ["blur", "filter", "effect"]
            let animatedKeyPaths = (currentEffectView.layer.animationKeys() ?? [])
                .compactMap { currentEffectView.layer.animation(forKey: $0) }
                .flatMap(flattenedPropertyKeyPaths(in:))
                .map { $0.lowercased() }
            XCTAssertTrue(
                animatedKeyPaths.allSatisfy { keyPath in
                    forbiddenFragments.allSatisfy { !keyPath.contains($0) }
                },
                "\(phase) animates blur/effect state instead of geometry only: \(animatedKeyPaths)"
            )
        }

        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        assertConstantBlur("opening settle")
        fixture.coordinator.reset(to: .expanded)
        assertConstantBlur("expanded endpoint")

        XCTAssertTrue(fixture.coordinator.beginDrag())
        fixture.coordinator.updateDrag(translationY: 80)
        assertConstantBlur("first direct drag sample")
        fixture.coordinator.updateDrag(translationY: 240)
        assertConstantBlur("later direct drag sample")

        fixture.coordinator.settle(to: .collapsed, initialVelocity: 300)
        XCTAssertTrue(glass.isTransitionCompositorSettleActive)
        assertConstantBlur("collapse settle")
        fixture.coordinator.settle(to: .expanded, initialVelocity: 0)
        XCTAssertTrue(glass.isTransitionCompositorSettleActive)
        assertConstantBlur("retargeted settle")
        fixture.coordinator.reset(to: .collapsed)
        assertConstantBlur("collapsed completion")
    }

    @MainActor
    func testNativeGlassRetargetCapturesPresentationAndCompletionRemovesTrack() throws {
        let glassFixture = makeRuntimeGlassMotionFixture()
        let fixture = glassFixture.fixture
        let glass = glassFixture.glass
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }
        guard glass.usesNativeGlassRendererForTesting,
              let nativeEffect = glass.transitionMaterialHitTargetForTesting,
              let nativeParams = nativeEffect.superview else {
            throw XCTSkip("native liquid glass requires iOS 26")
        }

        _ = try beginReferenceVelocityCollapse(in: fixture)
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let paramsPresentation = nativeParams.layer.presentation()
        let effectPresentation = nativeEffect.layer.presentation()
        let expectedParamsPosition = paramsPresentation?.position
            ?? nativeParams.layer.position
        let expectedParamsBounds = paramsPresentation?.bounds
            ?? nativeParams.layer.bounds
        let expectedParamsOpacity = paramsPresentation?.opacity
            ?? nativeParams.layer.opacity
        let expectedEffectPosition = effectPresentation?.position
            ?? nativeEffect.layer.position
        let expectedEffectBounds = effectPresentation?.bounds
            ?? nativeEffect.layer.bounds
        let expectedEffectCorner = effectPresentation?.cornerRadius
            ?? nativeEffect.layer.cornerRadius
        let captureCount = glass.transitionCompositorCaptureCountForTesting

        glass.captureTransitionCompositorPresentation()

        XCTAssertEqual(
            glass.transitionCompositorCaptureCountForTesting,
            captureCount + 1
        )
        XCTAssertFalse(glass.isTransitionCompositorSettleActive)
        XCTAssertNil(
            glass.transitionCompositorSettleTrackForTesting,
            "captured/invalidated compositor metadata must not masquerade as an active track"
        )
        XCTAssertNil(glass.transitionNativeParamsAnimationForTesting)
        XCTAssertNil(glass.transitionNativeEffectAnimationForTesting)
        XCTAssertNil(glass.transitionSyntheticStrokeAnimationForTesting)
        XCTAssertEqual(nativeParams.layer.position.x, expectedParamsPosition.x, accuracy: 0.5)
        XCTAssertEqual(nativeParams.layer.position.y, expectedParamsPosition.y, accuracy: 0.5)
        XCTAssertEqual(nativeParams.layer.bounds.width, expectedParamsBounds.width, accuracy: 0.5)
        XCTAssertEqual(nativeParams.layer.bounds.height, expectedParamsBounds.height, accuracy: 0.5)
        XCTAssertEqual(nativeParams.layer.opacity, expectedParamsOpacity, accuracy: 0.01)
        XCTAssertEqual(nativeEffect.layer.position.x, expectedEffectPosition.x, accuracy: 0.5)
        XCTAssertEqual(nativeEffect.layer.position.y, expectedEffectPosition.y, accuracy: 0.5)
        XCTAssertEqual(nativeEffect.layer.bounds.width, expectedEffectBounds.width, accuracy: 0.5)
        XCTAssertEqual(nativeEffect.layer.bounds.height, expectedEffectBounds.height, accuracy: 0.5)
        XCTAssertEqual(nativeEffect.layer.cornerRadius, expectedEffectCorner, accuracy: 0.2)

        let targetSize = fixture.geometry.expandedFrame.size
        glass.endInteractiveGeometryUpdates(size: targetSize, cornerRadius: 0)
        XCTAssertFalse(glass.isTransitionCompositorSettleActive)
        XCTAssertNil(glass.transitionCompositorSettleTrackForTesting)
        XCTAssertNil(glass.transitionNativeParamsAnimationForTesting)
        XCTAssertNil(glass.transitionNativeEffectAnimationForTesting)
        XCTAssertNil(glass.transitionSyntheticStrokeAnimationForTesting)
        XCTAssertEqual(nativeParams.bounds.size.width, targetSize.width, accuracy: 0.01)
        XCTAssertEqual(nativeParams.bounds.size.height, targetSize.height, accuracy: 0.01)
        XCTAssertEqual(nativeEffect.bounds.size.width, targetSize.width, accuracy: 0.01)
        XCTAssertEqual(nativeEffect.bounds.size.height, targetSize.height, accuracy: 0.01)
        XCTAssertEqual(nativeEffect.layer.cornerRadius, 0, accuracy: 0.01)
    }

    @MainActor
    func testNearEndpointReleaseCompletesWithoutAnInvisibleFullLengthShield() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }
        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        fixture.coordinator.reset(to: .expanded)

        fixture.surface.frame = fixture.geometry.collapsedFrame.offsetBy(
            dx: 0,
            dy: -2
        )
        fixture.surface.layer.cornerRadius = fixture.geometry.collapsedCornerRadius
        XCTAssertTrue(fixture.coordinator.beginDrag())
        fixture.coordinator.settle(to: .collapsed, initialVelocity: 0)
        let track = try XCTUnwrap(
            fixture.surface.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator
                    .surfaceGeometryAnimationKey
            ) as? CAAnimationGroup
        )
        XCTAssertEqual(
            track.duration,
            BottomBarAccessoryTransitionConfiguration.default.collapseDuration * 0.18,
            accuracy: 0.001
        )

        let samples = sampleRuntimeFrames(
            surface: fixture.surface,
            coordinator: fixture.coordinator,
            until: .collapsed,
            timeout: 0.30
        )
        let elapsed = samples.last?.elapsed ?? .infinity
        XCTAssertEqual(fixture.coordinator.state, .collapsed)
        XCTAssertLessThan(elapsed, 0.18)
    }

    @MainActor
    func testExtremeRetargetVelocityIsBoundedBeforeBoundaryHandoff() {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }
        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        fixture.coordinator.reset(to: .expanded)
        fixture.coordinator.settle(to: .collapsed, initialVelocity: 100_000)
        fixture.coordinator.settle(to: .expanded, initialVelocity: 100_000)

        let limit = BottomBarAccessoryTransitionConfiguration.default
            .maximumResolvedVelocity
        XCTAssertEqual(
            fixture.coordinator.resolvedSettlingInitialVelocityY,
            limit,
            accuracy: 0.001
        )
        XCTAssertEqual(
            fixture.coordinator.resolvedSettlingInitialTopVelocityY,
            limit,
            accuracy: 0.001
        )
        XCTAssertEqual(
            fixture.coordinator.resolvedSettlingInitialBottomVelocityY,
            limit,
            accuracy: 0.001
        )
        let samples = sampleRuntimeFrames(
            surface: fixture.surface,
            coordinator: fixture.coordinator,
            until: .expanded
        )
        XCTAssertEqual(fixture.coordinator.state, .expanded)
        let oneFrameReferenceVelocityMargin = limit / 60 + 20
        let minimumTop = samples.map(\.frame.minY).min() ?? -.infinity
        let maximumBottom = samples.map(\.frame.maxY).max() ?? .infinity
        XCTAssertGreaterThan(
            minimumTop,
            -oneFrameReferenceVelocityMargin,
            "extreme retarget top escaped to \(minimumTop)pt"
        )
        XCTAssertLessThan(
            maximumBottom,
            fixture.geometry.layoutSize.height + oneFrameReferenceVelocityMargin,
            "extreme retarget bottom escaped to \(maximumBottom)pt"
        )
    }

    @MainActor
    func testExpansionCoversMostDistanceEarlyThenHasAVisibleSlowTail() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }

        let start = fixture.geometry.collapsedFrame
        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        let geometryTrack = try XCTUnwrap(
            fixture.surface.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator
                    .surfaceGeometryAnimationKey
            ) as? CAAnimationGroup
        )
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        XCTAssertEqual(
            geometryTrack.duration,
            configuration.expansionDuration,
            accuracy: 0.001,
            "the analytic geometry and lifecycle clock must share the real 0.40s endpoint"
        )
        let positionTrack = try XCTUnwrap(
            geometryTrack.animations?.compactMap { $0 as? CAKeyframeAnimation }
                .first { $0.keyPath == "position" }
        )
        XCTAssertGreaterThanOrEqual(
            positionTrack.values?.count ?? 0,
            Int(ceil(
                configuration.expansionDuration
                    * TimeInterval(configuration.geometryKeyframesPerSecond)
            )) + 1
        )
        let samples = sampleRuntimeFrames(
            surface: fixture.surface,
            coordinator: fixture.coordinator,
            until: .expanded
        )

        XCTAssertEqual(fixture.coordinator.state, .expanded)
        XCTAssertGreaterThan(samples.count, 8)
        let target = fixture.geometry.expandedFrame
        let frame50 = frame(in: samples, atFraction: 0.50)
        let frame80 = frame(in: samples, atFraction: 0.80)
        let frame100 = frame(in: samples, atFraction: 1)
        let progress50 = normalizedEdgeProgress(
            frame50.minY,
            from: start.minY,
            to: target.minY
        )
        let progress80 = normalizedEdgeProgress(
            frame80.minY,
            from: start.minY,
            to: target.minY
        )

        XCTAssertGreaterThanOrEqual(
            progress50,
            0.80,
            "opening must cover at least 80% of its distance in the fast first half"
        )
        XCTAssertGreaterThan(progress80, progress50)

        let firstHalfTravel = abs(frame50.minY - start.minY)
        let tailTravel = abs(frame100.minY - frame80.minY)
        XCTAssertGreaterThan(firstHalfTravel, tailTravel * 5)
        XCTAssertEqual(frame100.minY, target.minY, accuracy: 0.75)

        // "Slow after 80%" describes spatial progress rather than 80% of
        // wall-clock time. The curve reaches that boundary early, then spends
        // the majority of its duration easing through the remaining distance.
        let crossingIndex = (0 ... 1_000).first { index in
            BottomBarAccessoryTransitionCoordinator.expansionGeometryProgress(
                at: CGFloat(index) / 1_000,
                configuration: configuration
            ) >= 0.80
        } ?? 1_000
        let crossingTime = CGFloat(crossingIndex) / 1_000
        XCTAssertLessThanOrEqual(
            crossingTime * CGFloat(configuration.expansionDuration),
            0.18
        )
        let geometryEndTime = CGFloat(
            configuration.expansionGeometryDuration
                / configuration.expansionDuration
        )
        XCTAssertGreaterThanOrEqual(geometryEndTime - crossingTime, 0.35)

        let tenthOfASecond = CGFloat(0.10 / configuration.expansionDuration)
        let firstPostBoundaryEnd = min(1, crossingTime + tenthOfASecond)
        let firstPostBoundaryTravel = BottomBarAccessoryTransitionCoordinator
            .expansionGeometryProgress(
                at: firstPostBoundaryEnd,
                configuration: configuration
            ) - BottomBarAccessoryTransitionCoordinator.expansionGeometryProgress(
                at: crossingTime,
                configuration: configuration
            )
        let terminalStart = CGFloat(
            (configuration.expansionGeometryDuration - 2.0 / 60.0)
                / configuration.expansionDuration
        )
        let terminalTravel = BottomBarAccessoryTransitionCoordinator
            .expansionGeometryProgress(at: geometryEndTime, configuration: configuration)
            - BottomBarAccessoryTransitionCoordinator.expansionGeometryProgress(
                at: terminalStart,
                configuration: configuration
            )
        XCTAssertGreaterThan(firstPostBoundaryTravel, 0.03)
        XCTAssertLessThan(
            terminalTravel,
            firstPostBoundaryTravel * 0.10,
            "the opening tail must continuously and visibly decelerate toward 100%"
        )
    }

    @MainActor
    func testMidFlightRetargetPreservesPresentationFrameAndNeverUndershootsMini() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }

        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        fixture.coordinator.reset(to: .expanded)
        fixture.coordinator.settle(to: .collapsed, initialVelocity: 500)
        RunLoop.main.run(until: Date().addingTimeInterval(0.11))

        let capturedPresentation = fixture.surface.layer.presentation()
            ?? fixture.surface.layer
        let before = capturedPresentation.frame
        let capturedBounds = capturedPresentation.bounds
        fixture.coordinator.settle(to: .expanded)
        let immediatelyAfter = visibleFrame(of: fixture.surface)

        let retargetTrack = try XCTUnwrap(
            fixture.surface.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator
                    .surfaceGeometryAnimationKey
            ) as? CAAnimationGroup
        )
        let boundsTrack = try XCTUnwrap(
            retargetTrack.animations?.compactMap { $0 as? CAKeyframeAnimation }
                .first { $0.keyPath == "bounds" }
        )
        let retargetBounds = try XCTUnwrap(
            boundsTrack.values as? [NSValue]
        ).map(\.cgRectValue)
        XCTAssertGreaterThan(retargetBounds.count, 1)
        XCTAssertEqual(
            retargetBounds[0],
            capturedBounds,
            "Retarget key 0 must preserve the exact captured presentation bounds for C0 continuity"
        )
        for (index, bounds) in retargetBounds.dropFirst().enumerated() {
            XCTAssertGreaterThanOrEqual(
                bounds.height,
                fixture.geometry.collapsedFrame.height - 0.001,
                "retarget bounds key[\(index + 1)]=\(bounds) fell below compact height \(fixture.geometry.collapsedFrame.height)"
            )
        }

        XCTAssertEqual(fixture.coordinator.activeGeometryAnimatorCountForTesting, 1)
        XCTAssertEqual(before.minX, immediatelyAfter.minX, accuracy: 1.5)
        XCTAssertEqual(before.minY, immediatelyAfter.minY, accuracy: 1.5)
        XCTAssertEqual(before.width, immediatelyAfter.width, accuracy: 1.5)
        XCTAssertEqual(before.height, immediatelyAfter.height, accuracy: 1.5)

        let samples = sampleRuntimeFrames(
            surface: fixture.surface,
            coordinator: fixture.coordinator,
            until: .expanded
        )
        XCTAssertEqual(fixture.coordinator.state, .expanded)
        for (index, sample) in samples.enumerated() {
            XCTAssertGreaterThanOrEqual(
                sample.frame.width,
                fixture.geometry.collapsedFrame.width - 0.75,
                "sample[\(index)] frame=\(sample.frame) collapsed=\(fixture.geometry.collapsedFrame)"
            )
            XCTAssertGreaterThanOrEqual(
                sample.frame.height,
                fixture.geometry.collapsedFrame.height - 0.75,
                "sample[\(index)] frame=\(sample.frame) collapsed=\(fixture.geometry.collapsedFrame)"
            )
        }
    }

    @MainActor
    func testReduceMotionSpringIsShorterThanTheFullMorphSpring() {
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        let reduced = UIViewPropertyAnimator(
            duration: 0,
            timingParameters: configuration.reduceMotionSpring.timingParameters(
                initialVelocity: .zero
            )
        )
        let collapse = UIViewPropertyAnimator(
            duration: 0,
            timingParameters: configuration.collapseSpring.timingParameters(
                initialVelocity: .zero
            )
        )

        XCTAssertGreaterThan(reduced.duration, 0)
        XCTAssertLessThan(reduced.duration, collapse.duration)
        XCTAssertLessThan(reduced.duration, 0.8)
    }

    @MainActor
    func testDirectDragKeepsExpandedTopEdgeUnderFinger() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let geometry = makeGeometry()
        let surface = UIView(frame: geometry.collapsedFrame)
        let collapsedHost = UIView(frame: surface.bounds)
        let expandedHost = UIView(frame: CGRect(origin: .zero, size: geometry.expandedFrame.size))
        let sharedHost = UIView(frame: container.bounds)
        surface.addSubview(collapsedHost)
        surface.addSubview(expandedHost)
        container.addSubview(surface)
        container.addSubview(sharedHost)

        let coordinator = BottomBarAccessoryTransitionCoordinator(
            containerView: container,
            surfaceView: surface,
            collapsedContentHost: collapsedHost,
            expandedContentHost: expandedHost,
            sharedElementHost: sharedHost
        )
        XCTAssertTrue(coordinator.beginExpansion(
            geometry: geometry,
            dockingContext: BottomBarAccessoryDockingContext(
                mode: .regular,
                isTabBarVisible: true,
                isSearchActive: false
            ),
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        coordinator.reset(to: .expanded)
        XCTAssertTrue(coordinator.beginDrag())

        coordinator.updateDrag(translationY: 96)

        XCTAssertEqual(surface.frame.minY, 96, accuracy: 0.001)
        XCTAssertEqual(
            surface.bounds.size,
            geometry.expandedFrame.size,
            "the held Full sheet must translate without scaling"
        )
        XCTAssertEqual(
            surface.layer.cornerRadius,
            geometry.expandedCornerRadius + 60,
            accuracy: 0.5,
            "the held Full sheet quickly acquires the reference card radius"
        )
        coordinator.reset(to: .expanded)
    }

    @MainActor
    func testDirectDragRemainsLinearUntilTheSurfaceReachesTheDock() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let geometry = makeGeometry()
        let surface = UIView(frame: geometry.collapsedFrame)
        let collapsedHost = UIView(frame: surface.bounds)
        let expandedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.expandedFrame.size)
        )
        let sharedHost = UIView(frame: container.bounds)
        surface.addSubview(collapsedHost)
        surface.addSubview(expandedHost)
        container.addSubview(surface)
        container.addSubview(sharedHost)

        let coordinator = BottomBarAccessoryTransitionCoordinator(
            containerView: container,
            surfaceView: surface,
            collapsedContentHost: collapsedHost,
            expandedContentHost: expandedHost,
            sharedElementHost: sharedHost
        )
        XCTAssertTrue(coordinator.beginExpansion(
            geometry: geometry,
            dockingContext: BottomBarAccessoryDockingContext(
                mode: .regular,
                isTabBarVisible: true,
                isSearchActive: false
            ),
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        coordinator.reset(to: .expanded)
        XCTAssertTrue(coordinator.beginDrag())

        let dockTravel = geometry.collapsedFrame.maxY
            - geometry.expandedFrame.minY
        let heldTranslation = dockTravel * 0.95
        coordinator.updateDrag(translationY: heldTranslation)

        XCTAssertEqual(
            surface.frame.minY,
            geometry.expandedFrame.minY + heldTranslation,
            accuracy: 0.001
        )
        coordinator.reset(to: .expanded)
    }

    @MainActor
    func testHeldGrabberDragKeepsArtworkRigidlyAttachedWithoutHorizontalArcOrScale() throws {
        let fixture = makeRuntimeMotionFixture()
        defer {
            fixture.coordinator.reset(to: .collapsed)
            fixture.window.isHidden = true
        }
        let collapsedArtwork = UIView(
            frame: CGRect(x: 8, y: 2, width: 44, height: 44)
        )
        let expandedArtwork = UIView(
            frame: CGRect(x: 51, y: 150, width: 300, height: 300)
        )
        fixture.collapsedHost.addSubview(collapsedArtwork)
        fixture.expandedHost.addSubview(expandedArtwork)
        fixture.window.layoutIfNeeded()
        let collapsedParticipant = SharedElementParticipant(
            view: collapsedArtwork,
            cornerRadius: 12
        )
        let expandedParticipant = SharedElementParticipant(
            view: expandedArtwork,
            cornerRadius: 24
        )

        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: collapsedParticipant,
            expandedParticipant: expandedParticipant,
            reduceMotion: false
        ))
        fixture.coordinator.reset(to: .expanded)
        XCTAssertTrue(fixture.coordinator.beginDrag())

        let representation = try XCTUnwrap(fixture.sharedHost.subviews.first)
        let expandedPosition = representation.layer.position
        let expandedBounds = representation.layer.bounds
        let expandedCornerRadius = representation.layer.cornerRadius
        let initialSurfaceFrame = fixture.surface.frame

        let topEdgeTravel = fixture.geometry.collapsedFrame.minY
            - fixture.geometry.expandedFrame.minY
        for phase: CGFloat in [0.20, 0.35, 0.50, 0.70] {
            fixture.coordinator.updateDrag(
                translationY: topEdgeTravel * phase
            )
            let resolvedPhase = normalizedEdgeProgress(
                fixture.surface.frame.minY,
                from: fixture.geometry.expandedFrame.minY,
                to: fixture.geometry.collapsedFrame.minY
            ).clamped(to: 0 ... 1)
            XCTAssertEqual(
                resolvedPhase,
                phase,
                accuracy: 0.000_1,
                "held artwork attachment belongs to the surface top edge, not center-based dragProgress"
            )
            let surfaceDelta = CGPoint(
                x: fixture.surface.frame.minX - initialSurfaceFrame.minX,
                y: fixture.surface.frame.minY - initialSurfaceFrame.minY
            )
            XCTAssertEqual(
                representation.layer.position.x,
                expandedPosition.x + surfaceDelta.x,
                accuracy: 0.01,
                "the original held gesture has no independent horizontal artwork bow"
            )
            XCTAssertEqual(
                representation.layer.position.y,
                expandedPosition.y + surfaceDelta.y,
                accuracy: 0.01,
                "the held artwork must stay vertically attached to the moving Full surface"
            )
            XCTAssertEqual(
                representation.layer.bounds,
                expandedBounds,
                "the original held gesture does not resize the cover before release"
            )
            XCTAssertEqual(
                representation.layer.cornerRadius,
                expandedCornerRadius,
                accuracy: 0.001
            )
        }
    }


    func testReducedMotionSettleGeometryIsBoundedAndVertical() {
        let configuration = BottomBarAccessoryTransitionConfiguration.default
        let current = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: 195, y: 400),
            bounds: CGRect(x: 0, y: 0, width: 390, height: 800),
            cornerRadius: 8
        )
        let endpoint = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: 195, y: 750),
            bounds: CGRect(x: 0, y: 0, width: 350, height: 60),
            cornerRadius: 28
        )

        let reduced = configuration.reducedMotionSettleSurface(
            from: current,
            toward: endpoint
        )

        XCTAssertEqual(reduced.position.x, current.position.x, accuracy: 0.001)
        XCTAssertEqual(
            reduced.position.y - current.position.y,
            configuration.reduceMotionMaximumSettleTranslation,
            accuracy: 0.001
        )
        XCTAssertEqual(reduced.bounds.width, 388.05, accuracy: 0.001)
        XCTAssertEqual(reduced.bounds.height, 796, accuracy: 0.001)
        XCTAssertEqual(reduced.cornerRadius, 10, accuracy: 0.001)
        XCTAssertNotEqual(reduced, endpoint)
    }

    @MainActor
    func testReducedMotionKeepsDirectDragAndUsesSmallPostReleaseSettle() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let geometry = makeGeometry()
        let surface = UIView(frame: geometry.collapsedFrame)
        let collapsedHost = UIView(frame: surface.bounds)
        let expandedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.expandedFrame.size)
        )
        let sharedHost = UIView(frame: container.bounds)
        surface.addSubview(collapsedHost)
        surface.addSubview(expandedHost)
        container.addSubview(surface)
        container.addSubview(sharedHost)

        let coordinator = BottomBarAccessoryTransitionCoordinator(
            containerView: container,
            surfaceView: surface,
            collapsedContentHost: collapsedHost,
            expandedContentHost: expandedHost,
            sharedElementHost: sharedHost
        )
        XCTAssertTrue(coordinator.beginExpansion(
            geometry: geometry,
            dockingContext: BottomBarAccessoryDockingContext(
                mode: .regular,
                isTabBarVisible: true,
                isSearchActive: false
            ),
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: true
        ))
        coordinator.reset(to: .expanded)
        XCTAssertTrue(coordinator.beginDrag())

        coordinator.updateDrag(translationY: 96)

        XCTAssertEqual(coordinator.state, .dragging)
        XCTAssertEqual(surface.frame.minY, 96, accuracy: 0.001)
        XCTAssertLessThan(surface.bounds.height, geometry.expandedFrame.height)

        let derivativeSample: CGFloat = 0.1
        coordinator.updateDrag(translationY: 96 - derivativeSample)
        let beforeMidY = surface.frame.midY
        coordinator.updateDrag(translationY: 96 + derivativeSample)
        let afterMidY = surface.frame.midY
        coordinator.updateDrag(translationY: 96)
        let expectedVisualVelocity = (
            (afterMidY - beforeMidY) / (2 * derivativeSample)
        ) * 800

        coordinator.settle(to: .collapsed, initialVelocity: 800)

        XCTAssertEqual(coordinator.state, .settlingToCollapsed)
        XCTAssertEqual(coordinator.currentContext?.target, .collapsed)
        XCTAssertEqual(coordinator.currentContext?.isReduceMotionEnabled, true)
        XCTAssertTrue(coordinator.resolvedSettlingInitialVelocityY.isFinite)
        XCTAssertGreaterThan(coordinator.resolvedSettlingInitialVelocityY, 0)
        XCTAssertLessThanOrEqual(coordinator.resolvedSettlingInitialVelocityY, 800)
        XCTAssertEqual(
            coordinator.resolvedSettlingInitialVelocityY,
            expectedVisualVelocity,
            accuracy: 0.5,
            "Reduce Motion must inherit the derivative of the geometry under the finger, not the unmodified recognizer velocity"
        )
        // The model commits the real endpoint immediately, while presentation
        // keyframes expose only a bounded lead-in and perform that model swap
        // during a zero-opacity interval.
        XCTAssertEqual(surface.frame, geometry.collapsedFrame)
        let handoff = surface.layer.animation(
            forKey: BottomBarAccessoryTransitionCoordinator
                .reducedMotionHandoffAnimationKey
        ) as? CAAnimationGroup
        let opacity = handoff?.animations?.compactMap {
            $0 as? CAKeyframeAnimation
        }.first { $0.keyPath == "opacity" }
        let position = handoff?.animations?.compactMap {
            $0 as? CAKeyframeAnimation
        }.first { $0.keyPath == "position" }
        XCTAssertEqual(
            (opacity?.values as? [NSNumber])?.map(\.floatValue),
            [1, 0, 0, 0, 1]
        )
        let positions = position?.values as? [NSValue]
        XCTAssertEqual(positions?.count, 5)
        if let start = positions?[0].cgPointValue,
           let nearby = positions?[1].cgPointValue {
            XCTAssertLessThanOrEqual(
                abs(nearby.y - start.y),
                BottomBarAccessoryTransitionConfiguration.default
                    .reduceMotionMaximumSettleTranslation + 0.001
            )
            XCTAssertEqual(nearby.x, start.x, accuracy: 0.001)
        }
        XCTAssertEqual(surface.layer.opacity, 1, accuracy: 0.001)
        coordinator.reset(to: .expanded)
    }

    @MainActor
    func testReducedMotionEndpointSwapIsHiddenByOneSurfaceFadeThrough() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let geometry = makeGeometry()
        let surface = UIView(frame: geometry.collapsedFrame)
        let collapsedHost = UIView(frame: surface.bounds)
        let expandedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.expandedFrame.size)
        )
        let sharedHost = UIView(frame: container.bounds)
        surface.addSubview(collapsedHost)
        surface.addSubview(expandedHost)
        container.addSubview(surface)
        container.addSubview(sharedHost)

        let coordinator = BottomBarAccessoryTransitionCoordinator(
            containerView: container,
            surfaceView: surface,
            collapsedContentHost: collapsedHost,
            expandedContentHost: expandedHost,
            sharedElementHost: sharedHost
        )
        XCTAssertTrue(coordinator.beginExpansion(
            geometry: geometry,
            dockingContext: BottomBarAccessoryDockingContext(
                mode: .regular,
                isTabBarVisible: true,
                isSearchActive: false
            ),
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: true
        ))

        let handoff = try XCTUnwrap(
            surface.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator
                    .reducedMotionHandoffAnimationKey
            ) as? CAAnimationGroup
        )
        let animations = try XCTUnwrap(handoff.animations).compactMap {
            $0 as? CAKeyframeAnimation
        }
        let opacity = try XCTUnwrap(
            animations.first { $0.keyPath == "opacity" }
        )
        let bounds = try XCTUnwrap(
            animations.first { $0.keyPath == "bounds" }
        )
        let alphaValues = try XCTUnwrap(opacity.values as? [NSNumber])
        let boundsValues = try XCTUnwrap(bounds.values as? [NSValue])

        XCTAssertEqual(opacity.keyTimes, bounds.keyTimes)
        XCTAssertEqual(alphaValues.count, boundsValues.count)
        XCTAssertEqual(alphaValues[2].floatValue, 0, accuracy: 0.001)
        XCTAssertEqual(alphaValues[3].floatValue, 0, accuracy: 0.001)
        XCTAssertNotEqual(boundsValues[2].cgRectValue, geometry.expandedFrame)
        XCTAssertEqual(boundsValues[3].cgRectValue.size, geometry.expandedFrame.size)
        XCTAssertEqual(surface.layer.bounds.size, geometry.expandedFrame.size)
        XCTAssertEqual(surface.layer.opacity, 1, accuracy: 0.001)
        XCTAssertEqual(
            handoff.duration,
            try XCTUnwrap(coordinator.reducedMotionHandoffDuration),
            accuracy: 0.000_1
        )
        coordinator.reset(to: .collapsed)
    }

    @MainActor
    func testRuntimeReduceMotionToggleRetargetsMidSettleFromPresentationState() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        window.isHidden = false
        defer { window.isHidden = true }

        let geometry = makeGeometry()
        let surface = UIView(frame: geometry.collapsedFrame)
        let collapsedHost = UIView(frame: surface.bounds)
        let expandedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.expandedFrame.size)
        )
        let sharedHost = UIView(frame: container.bounds)
        surface.addSubview(collapsedHost)
        surface.addSubview(expandedHost)
        container.addSubview(surface)
        container.addSubview(sharedHost)

        let coordinator = BottomBarAccessoryTransitionCoordinator(
            containerView: container,
            surfaceView: surface,
            collapsedContentHost: collapsedHost,
            expandedContentHost: expandedHost,
            sharedElementHost: sharedHost
        )
        XCTAssertTrue(coordinator.beginExpansion(
            geometry: geometry,
            dockingContext: BottomBarAccessoryDockingContext(
                mode: .regular,
                isTabBarVisible: true,
                isSearchActive: false
            ),
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        coordinator.reset(to: .expanded)
        XCTAssertTrue(coordinator.beginDrag())
        coordinator.updateDrag(translationY: 120)
        coordinator.settle(to: .collapsed, initialVelocity: 650)
        XCTAssertEqual(coordinator.activeGeometryAnimatorCountForTesting, 1)

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let presentation = try XCTUnwrap(surface.layer.presentation())
        let capturedPosition = presentation.position
        let capturedBounds = presentation.bounds
        let capturedCornerRadius = presentation.cornerRadius
        let capturedOpacity = presentation.opacity
        XCTAssertNotEqual(presentation.frame, geometry.collapsedFrame)

        coordinator.updateReduceMotionEnabled(true)

        XCTAssertEqual(coordinator.activeGeometryAnimatorCountForTesting, 1)
        XCTAssertEqual(coordinator.state, .settlingToCollapsed)
        XCTAssertEqual(coordinator.currentContext?.isReduceMotionEnabled, true)
        let handoff = try XCTUnwrap(
            surface.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator
                    .reducedMotionHandoffAnimationKey
            ) as? CAAnimationGroup
        )
        XCTAssertEqual(
            surface.layer.animationKeys(),
            [BottomBarAccessoryTransitionCoordinator
                .reducedMotionHandoffAnimationKey]
        )
        let keyframes = try XCTUnwrap(handoff.animations).compactMap {
            $0 as? CAKeyframeAnimation
        }
        let positions = try XCTUnwrap(
            keyframes.first { $0.keyPath == "position" }?.values as? [NSValue]
        )
        let bounds = try XCTUnwrap(
            keyframes.first { $0.keyPath == "bounds" }?.values as? [NSValue]
        )
        let radii = try XCTUnwrap(
            keyframes.first { $0.keyPath == "cornerRadius" }?.values as? [NSNumber]
        )
        let opacities = try XCTUnwrap(
            keyframes.first { $0.keyPath == "opacity" }?.values as? [NSNumber]
        )
        XCTAssertEqual(positions[0].cgPointValue.x, capturedPosition.x, accuracy: 0.001)
        XCTAssertEqual(positions[0].cgPointValue.y, capturedPosition.y, accuracy: 0.001)
        XCTAssertEqual(bounds[0].cgRectValue, capturedBounds)
        XCTAssertEqual(
            CGFloat(radii[0].doubleValue),
            capturedCornerRadius,
            accuracy: 0.001
        )
        XCTAssertEqual(opacities[0].floatValue, capturedOpacity, accuracy: 0.001)

        coordinator.reset(to: .expanded)
    }

    @MainActor
    func testProgrammaticRetargetInheritsInterruptedSpringVelocity() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let geometry = makeGeometry()
        let surface = UIView(frame: geometry.collapsedFrame)
        let collapsedHost = UIView(frame: surface.bounds)
        let expandedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.expandedFrame.size)
        )
        let sharedHost = UIView(frame: container.bounds)
        surface.addSubview(collapsedHost)
        surface.addSubview(expandedHost)
        container.addSubview(surface)
        container.addSubview(sharedHost)

        let coordinator = BottomBarAccessoryTransitionCoordinator(
            containerView: container,
            surfaceView: surface,
            collapsedContentHost: collapsedHost,
            expandedContentHost: expandedHost,
            sharedElementHost: sharedHost
        )
        XCTAssertTrue(coordinator.beginExpansion(
            geometry: geometry,
            dockingContext: BottomBarAccessoryDockingContext(
                mode: .regular,
                isTabBarVisible: true,
                isSearchActive: false
            ),
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        coordinator.reset(to: .expanded)
        coordinator.settle(to: .collapsed, initialVelocity: 900)
        XCTAssertEqual(coordinator.resolvedSettlingInitialVelocityY, 900, accuracy: 0.001)

        coordinator.settle(to: .expanded)

        XCTAssertEqual(coordinator.state, .settlingToExpanded)
        XCTAssertEqual(coordinator.resolvedSettlingInitialVelocityY, 900, accuracy: 0.001)
        coordinator.reset(to: .expanded)
    }

    @MainActor
    func testSettlingBackToExpandedPreservesContentAlphaAtRelease() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let geometry = makeGeometry()
        let surface = UIView(frame: geometry.collapsedFrame)
        let collapsedHost = UIView(frame: surface.bounds)
        let expandedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.expandedFrame.size)
        )
        let sharedHost = UIView(frame: container.bounds)
        surface.addSubview(collapsedHost)
        surface.addSubview(expandedHost)
        container.addSubview(surface)
        container.addSubview(sharedHost)

        let coordinator = BottomBarAccessoryTransitionCoordinator(
            containerView: container,
            surfaceView: surface,
            collapsedContentHost: collapsedHost,
            expandedContentHost: expandedHost,
            sharedElementHost: sharedHost
        )
        XCTAssertTrue(coordinator.beginExpansion(
            geometry: geometry,
            dockingContext: BottomBarAccessoryDockingContext(
                mode: .regular,
                isTabBarVisible: true,
                isSearchActive: false
            ),
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        coordinator.reset(to: .expanded)
        XCTAssertTrue(coordinator.beginDrag())
        coordinator.updateDrag(translationY: 70)

        let collapsedAlphaAtRelease = collapsedHost.alpha
        let expandedAlphaAtRelease = expandedHost.alpha
        XCTAssertEqual(
            coordinator.endDrag(
                translationY: 70,
                velocityY: 0,
                reason: .ended
            ),
            .expanded
        )

        XCTAssertEqual(collapsedHost.alpha, collapsedAlphaAtRelease, accuracy: 0.001)
        XCTAssertEqual(expandedHost.alpha, expandedAlphaAtRelease, accuracy: 0.001)
        coordinator.reset(to: .expanded)
    }

    @MainActor
    func testReleaseUsesVisualPositionWhenCatchingAnInFlightCard() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let geometry = makeGeometry()
        let surface = UIView(frame: geometry.collapsedFrame)
        let collapsedHost = UIView(frame: surface.bounds)
        let expandedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.expandedFrame.size)
        )
        let sharedHost = UIView(frame: container.bounds)
        surface.addSubview(collapsedHost)
        surface.addSubview(expandedHost)
        container.addSubview(surface)
        container.addSubview(sharedHost)

        let coordinator = BottomBarAccessoryTransitionCoordinator(
            containerView: container,
            surfaceView: surface,
            collapsedContentHost: collapsedHost,
            expandedContentHost: expandedHost,
            sharedElementHost: sharedHost
        )
        XCTAssertTrue(coordinator.beginExpansion(
            geometry: geometry,
            dockingContext: BottomBarAccessoryDockingContext(
                mode: .regular,
                isTabBarVisible: true,
                isSearchActive: false
            ),
            collapsedParticipant: nil,
            expandedParticipant: nil,
            reduceMotion: false
        ))
        coordinator.reset(to: .expanded)

        // Models a presentation capture after the user catches a collapse
        // spring well below the expanded endpoint.
        surface.frame.origin.y = 240
        XCTAssertTrue(coordinator.beginDrag(translationOriginY: 0))

        XCTAssertEqual(
            coordinator.endDrag(
                translationY: 5,
                velocityY: 0,
                reason: .ended
            ),
            .collapsed
        )
        coordinator.reset(to: .collapsed)
    }

    @MainActor
    func testSharedElementUsesBothSurfaceEndpointCoordinateSpaces() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let geometry = makeGeometry()
        let surface = UIView(frame: geometry.collapsedFrame)
        let collapsedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.collapsedFrame.size)
        )
        let expandedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.expandedFrame.size)
        )
        let collapsedView = UIView(frame: CGRect(x: 8, y: 8, width: 44, height: 44))
        let expandedView = UIView(frame: CGRect(x: 30, y: 100, width: 300, height: 300))
        let overlay = UIView(frame: container.bounds)
        collapsedView.alpha = 0.63
        expandedView.alpha = 0.42
        collapsedHost.addSubview(collapsedView)
        expandedHost.addSubview(expandedView)
        surface.addSubview(collapsedHost)
        surface.addSubview(expandedHost)
        container.addSubview(surface)
        container.addSubview(overlay)

        let collapsedParticipant = SharedElementParticipant(
            view: collapsedView,
            cornerRadius: 12
        )
        let expandedParticipant = SharedElementParticipant(
            view: expandedView,
            cornerRadius: 24
        )
        let context = BottomBarAccessoryTransitionContext(
            sessionIdentifier: UUID(),
            state: .expanding,
            phase: .preparing,
            presentationProgress: 0,
            settleProgress: 0,
            dragProgress: 0,
            isInteractive: false,
            isReduceMotionEnabled: false,
            target: .expanded,
            geometry: geometry,
            dockingContext: BottomBarAccessoryDockingContext(
                mode: .regular,
                isTabBarVisible: true,
                isSearchActive: false
            )
        )
        let transition = BottomBarAccessorySharedElementTransition()
        transition.prepare(
            collapsedParticipant: collapsedParticipant,
            expandedParticipant: expandedParticipant,
            context: context,
            surfaceView: surface,
            containerView: container,
            in: overlay,
            initialEndpoint: .collapsed
        )

        let representation = try XCTUnwrap(overlay.subviews.first)
        XCTAssertEqual(representation.layer.position.x, 50, accuracy: 0.001)
        XCTAssertEqual(representation.layer.position.y, 750, accuracy: 0.001)
        XCTAssertEqual(representation.layer.bounds.width, 44, accuracy: 0.001)
        XCTAssertEqual(representation.layer.bounds.height, 44, accuracy: 0.001)

        transition.beginSettle(
            to: .expanded,
            fromPresentationProgress: 0
        )
        transition.updateSettle(presentationProgress: 0.5)
        XCTAssertEqual(representation.layer.position.x, 115, accuracy: 0.001)
        XCTAssertEqual(representation.layer.position.y, 500, accuracy: 0.001)
        XCTAssertEqual(representation.layer.bounds.width, 172, accuracy: 0.001)
        XCTAssertEqual(representation.layer.bounds.height, 172, accuracy: 0.001)

        transition.updateSettle(presentationProgress: 1)
        XCTAssertEqual(representation.layer.position.x, 180, accuracy: 0.001)
        XCTAssertEqual(representation.layer.position.y, 250, accuracy: 0.001)
        XCTAssertEqual(representation.layer.bounds.width, 300, accuracy: 0.001)
        XCTAssertEqual(representation.layer.bounds.height, 300, accuracy: 0.001)

        transition.complete(at: .expanded)
        XCTAssertTrue(overlay.subviews.isEmpty)
        XCTAssertEqual(collapsedView.alpha, 0.63, accuracy: 0.001)
        XCTAssertEqual(expandedView.alpha, 0.42, accuracy: 0.001)
    }

    @MainActor
    func testSharedElementRefreshWaitsForMatchingSignaturesAndCancelRestoresVisibility() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let geometry = makeGeometry()
        let surface = UIView(frame: geometry.collapsedFrame)
        let collapsedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.collapsedFrame.size)
        )
        let expandedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.expandedFrame.size)
        )
        let collapsedView = UIView(frame: CGRect(x: 8, y: 8, width: 44, height: 44))
        let expandedView = UIView(frame: CGRect(x: 30, y: 100, width: 300, height: 300))
        let overlay = UIView(frame: container.bounds)
        collapsedView.alpha = 0.63
        expandedView.alpha = 0.42
        collapsedView.accessibilityIdentifier = "content-a"
        expandedView.accessibilityIdentifier = "content-a"
        collapsedHost.addSubview(collapsedView)
        expandedHost.addSubview(expandedView)
        surface.addSubview(collapsedHost)
        surface.addSubview(expandedHost)
        container.addSubview(surface)
        container.addSubview(overlay)

        let collapsedSignature = MutableContentSignature("content-a")
        let expandedSignature = MutableContentSignature("content-a")
        let refreshCounter = MutableCounter()
        let collapsedParticipant = RefreshableSharedElementParticipant(
            view: collapsedView,
            signature: collapsedSignature,
            refreshCounter: refreshCounter
        )
        let expandedParticipant = RefreshableSharedElementParticipant(
            view: expandedView,
            signature: expandedSignature,
            refreshCounter: refreshCounter
        )
        let transition = BottomBarAccessorySharedElementTransition()
        transition.prepare(
            collapsedParticipant: collapsedParticipant,
            expandedParticipant: expandedParticipant,
            context: makeTransitionContext(geometry: geometry),
            surfaceView: surface,
            containerView: container,
            in: overlay,
            initialEndpoint: .collapsed
        )

        let representation = try XCTUnwrap(
            overlay.subviews.first as? MarkerRepresentationView
        )
        XCTAssertEqual(representation.marker, "content-a")
        XCTAssertEqual(collapsedView.alpha, 0, accuracy: 0.001)
        XCTAssertEqual(expandedView.alpha, 0, accuracy: 0.001)

        // Independent endpoint trees can observe one model mutation on
        // adjacent turns. Do not expose the first endpoint's new content while
        // the other endpoint is still stale.
        collapsedView.accessibilityIdentifier = "content-b"
        collapsedSignature.value = "content-b"
        transition.samplePresentation()
        XCTAssertEqual(refreshCounter.value, 0)
        XCTAssertEqual(representation.marker, "content-a")

        expandedView.accessibilityIdentifier = "content-b"
        expandedSignature.value = "content-b"
        transition.samplePresentation()
        XCTAssertEqual(refreshCounter.value, 1)
        XCTAssertEqual(representation.marker, "content-b")
        // The deliberately hostile hook mutates source visibility. The
        // transition must immediately put it back into its hidden state.
        XCTAssertEqual(collapsedView.alpha, 0, accuracy: 0.001)
        XCTAssertEqual(expandedView.alpha, 0, accuracy: 0.001)
        XCTAssertFalse(collapsedView.isHidden)
        XCTAssertFalse(expandedView.isHidden)

        transition.samplePresentation()
        XCTAssertEqual(refreshCounter.value, 1, "same signature must not refresh per frame")

        transition.cancel()
        XCTAssertTrue(overlay.subviews.isEmpty)
        XCTAssertEqual(collapsedView.alpha, 0.63, accuracy: 0.001)
        XCTAssertEqual(expandedView.alpha, 0.42, accuracy: 0.001)
        XCTAssertFalse(collapsedView.isHidden)
        XCTAssertFalse(expandedView.isHidden)
    }

    @MainActor
    func testDefaultRasterizedRepresentationRefreshesOnlyOncePerSignature() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let geometry = makeGeometry()
        let surface = UIView(frame: geometry.collapsedFrame)
        let collapsedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.collapsedFrame.size)
        )
        let expandedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.expandedFrame.size)
        )
        let collapsedView = UIView(frame: CGRect(x: 8, y: 8, width: 44, height: 44))
        let expandedView = UIView(frame: CGRect(x: 30, y: 100, width: 300, height: 300))
        let overlay = UIView(frame: container.bounds)
        collapsedView.backgroundColor = .red
        expandedView.backgroundColor = .red
        collapsedHost.addSubview(collapsedView)
        expandedHost.addSubview(expandedView)
        surface.addSubview(collapsedHost)
        surface.addSubview(expandedHost)
        container.addSubview(surface)
        container.addSubview(overlay)

        let collapsedSignature = MutableContentSignature("content-a")
        let expandedSignature = MutableContentSignature("content-a")
        let collapsedParticipant = SignatureSharedElementParticipant(
            view: collapsedView,
            signature: collapsedSignature
        )
        let expandedParticipant = SignatureSharedElementParticipant(
            view: expandedView,
            signature: expandedSignature
        )
        let transition = BottomBarAccessorySharedElementTransition()
        transition.prepare(
            collapsedParticipant: collapsedParticipant,
            expandedParticipant: expandedParticipant,
            context: makeTransitionContext(geometry: geometry),
            surfaceView: surface,
            containerView: container,
            in: overlay,
            initialEndpoint: .collapsed
        )

        let representation = try XCTUnwrap(overlay.subviews.first as? UIImageView)
        let initialImage = try XCTUnwrap(representation.image)
        collapsedView.backgroundColor = .blue
        expandedView.backgroundColor = .blue
        collapsedSignature.value = "content-b"
        expandedSignature.value = "content-b"

        transition.samplePresentation()
        let refreshedImage = try XCTUnwrap(representation.image)
        XCTAssertFalse(initialImage === refreshedImage)

        transition.samplePresentation()
        XCTAssertTrue(refreshedImage === representation.image)
        transition.cancel()
    }

    func testStateMachineSupportsEveryInterruptiblePath() {
        var machine = BottomBarAccessoryTransitionStateMachine()
        XCTAssertEqual(machine.state, .collapsed)

        XCTAssertTrue(machine.handle(.requestExpansion))
        XCTAssertEqual(machine.state, .expanding)
        XCTAssertTrue(machine.handle(.beginDrag))
        XCTAssertEqual(machine.state, .dragging)
        XCTAssertTrue(machine.handle(.settle(.expanded)))
        XCTAssertEqual(machine.state, .settlingToExpanded)
        XCTAssertTrue(machine.handle(.beginDrag))
        XCTAssertEqual(machine.state, .dragging)
        XCTAssertTrue(machine.handle(.settle(.collapsed)))
        XCTAssertEqual(machine.state, .settlingToCollapsed)
        XCTAssertTrue(machine.handle(.beginDrag))
        XCTAssertEqual(machine.state, .dragging)
        XCTAssertTrue(machine.handle(.settle(.expanded)))
        XCTAssertTrue(machine.handle(.complete(.expanded)))
        XCTAssertEqual(machine.state, .expanded)
    }

    func testCollapsedStateRejectsDrag() {
        var machine = BottomBarAccessoryTransitionStateMachine()
        XCTAssertFalse(machine.handle(.beginDrag))
        XCTAssertEqual(machine.state, .collapsed)
    }

    func testGeometryInterpolatesInContainerCoordinates() {
        let geometry = makeGeometry()
        let midpoint = geometry.surfaceGeometry(at: 0.5)

        XCTAssertEqual(midpoint.frame.minX, 10, accuracy: 0.001)
        XCTAssertEqual(midpoint.frame.minY, 360, accuracy: 0.001)
        XCTAssertEqual(midpoint.frame.width, 370, accuracy: 0.001)
        XCTAssertEqual(midpoint.frame.height, 430, accuracy: 0.001)
        XCTAssertEqual(midpoint.cornerRadius, 18, accuracy: 0.001)
        XCTAssertEqual(
            geometry.presentationProgress(for: midpoint),
            0.5,
            accuracy: 0.001
        )
    }

    func testZeroTargetGeometryIsInvalid() {
        var geometry = makeGeometry()
        geometry.collapsedFrame = .zero
        XCTAssertFalse(geometry.isValid)
    }

    private struct RuntimeMotionFixture {
        let window: UIWindow
        let container: UIView
        let surface: UIView
        let collapsedHost: UIView
        let expandedHost: UIView
        let sharedHost: UIView
        let coordinator: BottomBarAccessoryTransitionCoordinator
        let geometry: BottomBarAccessoryTransitionGeometry
    }

    private struct SurfaceKeyframeTracks {
        let position: CAKeyframeAnimation
        let bounds: CAKeyframeAnimation
        let cornerRadius: CAKeyframeAnimation
    }

    private struct ReferenceVelocityCollapse {
        let releaseFrame: CGRect
        let geometryTrack: CAAnimationGroup
    }

    private struct RuntimeFrameSample {
        let elapsed: TimeInterval
        let frame: CGRect
    }

    private var runtimeDockingContext: BottomBarAccessoryDockingContext {
        BottomBarAccessoryDockingContext(
            mode: .regular,
            isTabBarVisible: true,
            isSearchActive: false
        )
    }

    @MainActor
    private func makeRuntimeMotionFixture(
        configuration: BottomBarAccessoryTransitionConfiguration = .default
    ) -> RuntimeMotionFixture {
        let layoutSize = CGSize(width: 402, height: 874)
        let geometry = BottomBarAccessoryTransitionGeometry(
            collapsedFrame: CGRect(x: 20, y: 735, width: 362, height: 48),
            expandedFrame: CGRect(origin: .zero, size: layoutSize),
            collapsedCornerRadius: 24,
            expandedCornerRadius: 0,
            safeInsets: .zero,
            layoutSize: layoutSize
        )
        let window = UIWindow(frame: CGRect(origin: .zero, size: layoutSize))
        let container = UIView(frame: window.bounds)
        let surface = UIView(frame: geometry.collapsedFrame)
        let collapsedHost = UIView(frame: surface.bounds)
        let expandedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.expandedFrame.size)
        )
        let sharedHost = UIView(frame: container.bounds)
        surface.addSubview(collapsedHost)
        surface.addSubview(expandedHost)
        container.addSubview(surface)
        container.addSubview(sharedHost)
        window.addSubview(container)
        window.isHidden = false
        window.layoutIfNeeded()

        let coordinator = BottomBarAccessoryTransitionCoordinator(
            containerView: container,
            surfaceView: surface,
            collapsedContentHost: collapsedHost,
            expandedContentHost: expandedHost,
            sharedElementHost: sharedHost,
            configuration: configuration
        )
        return RuntimeMotionFixture(
            window: window,
            container: container,
            surface: surface,
            collapsedHost: collapsedHost,
            expandedHost: expandedHost,
            sharedHost: sharedHost,
            coordinator: coordinator,
            geometry: geometry
        )
    }

    @MainActor
    private func makeRuntimeGlassMotionFixture() -> (
        fixture: RuntimeMotionFixture,
        glass: GlassBackgroundView
    ) {
        let layoutSize = CGSize(width: 402, height: 874)
        let geometry = BottomBarAccessoryTransitionGeometry(
            collapsedFrame: CGRect(x: 20, y: 735, width: 362, height: 48),
            expandedFrame: CGRect(origin: .zero, size: layoutSize),
            collapsedCornerRadius: 24,
            expandedCornerRadius: 0,
            safeInsets: .zero,
            layoutSize: layoutSize
        )
        let previousRendererOverride = GlassBackgroundView.useCustomGlassImpl
        GlassBackgroundView.useCustomGlassImpl = false
        let glass = GlassBackgroundView(style: .regular)
        GlassBackgroundView.useCustomGlassImpl = previousRendererOverride
        glass.strokeAppearance = .hairline(color: .white, opacity: 0.5)
        glass.frame = geometry.collapsedFrame
        glass.update(
            size: geometry.collapsedFrame.size,
            cornerRadius: geometry.collapsedCornerRadius,
            transition: .immediate
        )

        let window = UIWindow(frame: CGRect(origin: .zero, size: layoutSize))
        let container = UIView(frame: window.bounds)
        let collapsedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.collapsedFrame.size)
        )
        let expandedHost = UIView(
            frame: CGRect(origin: .zero, size: geometry.expandedFrame.size)
        )
        let sharedHost = UIView(frame: container.bounds)
        glass.transitionContentView.addSubview(collapsedHost)
        glass.transitionContentView.addSubview(expandedHost)
        container.addSubview(glass)
        container.addSubview(sharedHost)
        window.addSubview(container)
        window.isHidden = false
        window.layoutIfNeeded()

        let coordinator = BottomBarAccessoryTransitionCoordinator(
            containerView: container,
            surfaceView: glass,
            collapsedContentHost: collapsedHost,
            expandedContentHost: expandedHost,
            sharedElementHost: sharedHost
        )
        return (
            RuntimeMotionFixture(
                window: window,
                container: container,
                surface: glass,
                collapsedHost: collapsedHost,
                expandedHost: expandedHost,
                sharedHost: sharedHost,
                coordinator: coordinator,
                geometry: geometry
            ),
            glass
        )
    }

    @MainActor
    private func beginReferenceVelocityCollapse(
        in fixture: RuntimeMotionFixture,
        collapsedParticipant: BottomBarAccessoryTransitionParticipant? = nil,
        expandedParticipant: BottomBarAccessoryTransitionParticipant? = nil
    ) throws -> ReferenceVelocityCollapse {
        XCTAssertTrue(fixture.coordinator.beginExpansion(
            geometry: fixture.geometry,
            dockingContext: runtimeDockingContext,
            collapsedParticipant: collapsedParticipant,
            expandedParticipant: expandedParticipant,
            reduceMotion: false
        ))
        fixture.coordinator.reset(to: .expanded)
        XCTAssertTrue(fixture.coordinator.beginDrag())
        fixture.coordinator.updateDrag(translationY: 313)

        let releaseFrame = fixture.surface.frame
        let signedBottomDistance = fixture.geometry.collapsedFrame.maxY
            - releaseFrame.maxY
        fixture.coordinator.settle(
            to: .collapsed,
            initialVelocity: -15 * signedBottomDistance
        )
        let group = try XCTUnwrap(
            fixture.surface.layer.animation(
                forKey: BottomBarAccessoryTransitionCoordinator
                    .surfaceGeometryAnimationKey
            ) as? CAAnimationGroup,
            "the normal-motion settle must install one compositor surface group"
        )
        return ReferenceVelocityCollapse(
            releaseFrame: releaseFrame,
            geometryTrack: group
        )
    }

    @MainActor
    private func sampleRuntimeFrames(
        surface: UIView,
        coordinator: BottomBarAccessoryTransitionCoordinator,
        until endpoint: BottomBarAccessoryReleaseTarget,
        timeout: TimeInterval = 1.6
    ) -> [RuntimeFrameSample] {
        CATransaction.flush()
        let start = CACurrentMediaTime()
        var samples = [
            RuntimeFrameSample(elapsed: 0, frame: visibleFrame(of: surface)),
        ]
        let targetState: BottomBarAccessoryPresentationState = endpoint == .collapsed
            ? .collapsed
            : .expanded

        while coordinator.state != targetState,
              CACurrentMediaTime() - start < timeout {
            RunLoop.main.run(until: Date().addingTimeInterval(1 / 120))
            samples.append(RuntimeFrameSample(
                elapsed: CACurrentMediaTime() - start,
                frame: visibleFrame(of: surface)
            ))
        }
        if samples.last?.frame != surface.frame {
            samples.append(RuntimeFrameSample(
                elapsed: CACurrentMediaTime() - start,
                frame: surface.frame
            ))
        }
        return samples
    }

    @MainActor
    private func visibleFrame(of view: UIView) -> CGRect {
        view.layer.presentation()?.frame ?? view.frame
    }

    private func frame(
        in samples: [RuntimeFrameSample],
        atFraction fraction: CGFloat
    ) -> CGRect {
        guard let last = samples.last, last.elapsed > 0 else {
            return samples.last?.frame ?? .zero
        }
        let requestedTime = last.elapsed * TimeInterval(fraction.clamped(to: 0 ... 1))
        return samples.min { lhs, rhs in
            abs(lhs.elapsed - requestedTime) < abs(rhs.elapsed - requestedTime)
        }?.frame ?? last.frame
    }

    private func normalizedEdgeProgress(
        _ value: CGFloat,
        from origin: CGFloat,
        to target: CGFloat
    ) -> CGFloat {
        let distance = target - origin
        guard abs(distance) > 0.001 else { return 1 }
        return (value - origin) / distance
    }

    private func referenceArtworkArcOffset(at rawProgress: CGFloat) -> CGFloat {
        let progress = rawProgress.clamped(to: 0 ... 1)
        return 2.0 * 16
            * progress * progress
            * (1 - progress) * (1 - progress)
    }

    private func unitTangentForArtworkTest(
        from origin: CGPoint,
        to target: CGPoint
    ) -> CGPoint {
        let delta = CGPoint(x: target.x - origin.x, y: target.y - origin.y)
        let length = hypot(delta.x, delta.y)
        guard length.isFinite, length > 0.001 else { return .zero }
        return CGPoint(x: delta.x / length, y: delta.y / length)
    }

    private func screenRightNormalForArtworkTest(
        from origin: CGPoint,
        to target: CGPoint
    ) -> CGPoint {
        let tangent = unitTangentForArtworkTest(from: origin, to: target)
        var normal = CGPoint(x: tangent.y, y: -tangent.x)
        if normal.x < 0 {
            normal.x = -normal.x
            normal.y = -normal.y
        }
        return normal
    }

    private func assertRightwardArtworkArc(
        positions: [CGPoint],
        bounds: [CGRect],
        from originPosition: CGPoint,
        originBounds: CGRect,
        to targetPosition: CGPoint,
        targetBounds: CGRect,
        label: String,
        allowsVelocityDrivenReversal: Bool = false,
        maximumVelocityDrivenYReversals: Int = 1,
        canonicalOriginPosition: CGPoint? = nil,
        absoluteArcPhases: [CGFloat]? = nil,
        positionXResiduals: [CGFloat]? = nil
    ) {
        XCTAssertEqual(positions.count, bounds.count, "\(label) track counts")
        XCTAssertGreaterThanOrEqual(positions.count, 3, "\(label) sample count")
        guard positions.count == bounds.count, positions.count >= 3 else { return }
        if let absoluteArcPhases {
            XCTAssertEqual(
                absoluteArcPhases.count,
                positions.count,
                "\(label) absolute arc phase count"
            )
            guard absoluteArcPhases.count == positions.count else { return }
        }
        if let positionXResiduals {
            XCTAssertEqual(
                positionXResiduals.count,
                positions.count,
                "\(label) screen-x velocity residual count"
            )
            guard positionXResiduals.count == positions.count else { return }
        }

        let pathChord = CGPoint(
            x: targetPosition.x - originPosition.x,
            y: targetPosition.y - originPosition.y
        )
        let chordLength = hypot(pathChord.x, pathChord.y)
        XCTAssertGreaterThan(chordLength, 1, "\(label) needs distinct endpoints")
        guard chordLength > 1 else { return }
        let tangent = CGPoint(
            x: pathChord.x / chordLength,
            y: pathChord.y / chordLength
        )
        let rightNormal = screenRightNormalForArtworkTest(
            from: canonicalOriginPosition ?? originPosition,
            to: targetPosition
        )
        XCTAssertGreaterThan(
            rightNormal.x,
            0.1,
            "\(label) fixture must expose the screen-right component"
        )

        let boundsProgress = bounds.map {
            normalizedEdgeProgress(
                $0.width,
                from: originBounds.width,
                to: targetBounds.width
            )
        }
        let projectedProgress = positions.map { position in
            let displacement = CGPoint(
                x: position.x - originPosition.x,
                y: position.y - originPosition.y
            )
            return (
                displacement.x * pathChord.x
                    + displacement.y * pathChord.y
            ) / (chordLength * chordLength)
        }
        var normalOffsets: [CGFloat] = []
        var tangentialOffsets: [CGFloat] = []
        var horizontalOffsets: [CGFloat] = []
        var additiveArcOffsets: [CGFloat] = []
        for index in positions.indices {
            // Position may carry real release velocity before it converges with
            // the independent bounds/corner clock. Measure the visible bow
            // against position's own projection onto the endpoint chord; using
            // bounds progress here would misclassify a valid C1 handoff as a
            // tangential artwork jump.
            let q = projectedProgress[index]
            let baseline = CGPoint(
                x: originPosition.x + pathChord.x * q,
                y: originPosition.y + pathChord.y * q
            )
            let residual = CGPoint(
                x: positions[index].x - baseline.x,
                y: positions[index].y - baseline.y
            )
            let normalOffset = residual.x * rightNormal.x
                + residual.y * rightNormal.y
            let tangentialOffset = residual.x * tangent.x
                + residual.y * tangent.y
            normalOffsets.append(normalOffset)
            tangentialOffsets.append(tangentialOffset)
            horizontalOffsets.append(residual.x)

            // X and bounds retain the deliberately slow artwork clock. The
            // remaining X displacement therefore isolates the fixed additive
            // bow even when release velocity gives Y its own inertial track.
            let boundsQ = boundsProgress[index].clamped(to: 0 ... 1)
            let initialAbsoluteArc = absoluteArcPhases.map {
                referenceArtworkArcOffset(at: $0[0])
            } ?? 0
            let unarcedOriginX = originPosition.x
                - rightNormal.x * initialAbsoluteArc
            let slowClockBaselineX = unarcedOriginX
                + (targetPosition.x - unarcedOriginX) * boundsQ
            let additiveOffset = (
                positions[index].x - slowClockBaselineX
                    - (positionXResiduals?[index] ?? 0)
            ) / rightNormal.x
            additiveArcOffsets.append(additiveOffset)
            let expectedAdditiveOffset = referenceArtworkArcOffset(
                at: absoluteArcPhases?[index] ?? boundsQ
            )
            if absoluteArcPhases == nil || positionXResiduals != nil {
                XCTAssertEqual(
                    additiveOffset,
                    expectedAdditiveOffset,
                    accuracy: 0.12,
                    "\(label) fixed arc must be the C1-safe 2pt quartic envelope, sample \(index)"
                )
            }

            XCTAssertEqual(
                tangentialOffset,
                0,
                accuracy: 0.15,
                "\(label) arc must stay perpendicular to its endpoint chord"
            )
            XCTAssertTrue(
                positions[index].y.isFinite,
                "\(label) velocity-driven Y must stay finite at sample \(index)"
            )
        }

        XCTAssertEqual(normalOffsets[0], 0, accuracy: 0.25)
        XCTAssertEqual(normalOffsets[normalOffsets.count - 1], 0, accuracy: 0.25)
        let peakIndex = normalOffsets.indices.max {
            normalOffsets[$0] < normalOffsets[$1]
        } ?? 0
        if !allowsVelocityDrivenReversal {
            XCTAssertGreaterThan(
                normalOffsets[peakIndex],
                0.5,
                "\(label) combined absolute-Y path and fixed quartic must retain a visible right-normal bow"
            )
        }

        if absoluteArcPhases == nil || positionXResiduals != nil {
            XCTAssertEqual(
                additiveArcOffsets[0],
                referenceArtworkArcOffset(
                    at: absoluteArcPhases?.first ?? 0
                ),
                accuracy: 0.08
            )
        }
        XCTAssertEqual(
            additiveArcOffsets[additiveArcOffsets.count - 1],
            0,
            accuracy: 0.08
        )
        if absoluteArcPhases == nil {
            XCTAssertLessThanOrEqual(
                abs(additiveArcOffsets[1]),
                0.08,
                "\(label) quartic arc must leave its endpoint with zero visible derivative"
            )
        }
        let additivePeakIndex = additiveArcOffsets.indices.max {
            additiveArcOffsets[$0] < additiveArcOffsets[$1]
        } ?? 0
        if let absoluteArcPhases, positionXResiduals != nil {
            let expectedPeak = absoluteArcPhases.map {
                referenceArtworkArcOffset(at: $0)
            }.max() ?? 0
            XCTAssertEqual(
                additiveArcOffsets[additivePeakIndex],
                expectedPeak,
                accuracy: 0.12
            )
        } else if absoluteArcPhases == nil {
            XCTAssertGreaterThanOrEqual(
                additiveArcOffsets[additivePeakIndex],
                1.75
            )
            XCTAssertLessThanOrEqual(
                additiveArcOffsets[additivePeakIndex],
                2.25
            )
            XCTAssertGreaterThanOrEqual(boundsProgress[additivePeakIndex], 0.4)
            XCTAssertLessThanOrEqual(boundsProgress[additivePeakIndex], 0.6)
        }
        if absoluteArcPhases == nil || positionXResiduals != nil {
            let expectedPeakScreenX = absoluteArcPhases.map { phases in
                (phases.map {
                    referenceArtworkArcOffset(at: $0)
                }.max() ?? 0) * rightNormal.x
            } ?? 0.5
            XCTAssertGreaterThanOrEqual(
                additiveArcOffsets[additivePeakIndex] * rightNormal.x,
                min(0.5, expectedPeakScreenX) - 0.08,
                "\(label) fixed quartic envelope must remain on its canonical positive screen-x side"
            )
        }

        let verticalTravel = max(
            1,
            abs(targetPosition.y - originPosition.y)
        )
        let yChords = zip(positions.dropFirst(), positions).map {
            ($0.0.y - $0.1.y) / verticalTravel
        }
        if allowsVelocityDrivenReversal {
            let directions = yChords.compactMap { chord -> Int? in
                guard abs(chord) > 0.000_5 else { return nil }
                return chord > 0 ? 1 : -1
            }
            let reversals = zip(directions.dropFirst(), directions).reduce(0) {
                $0 + ($1.0 == $1.1 ? 0 : 1)
            }
            XCTAssertLessThanOrEqual(
                reversals,
                maximumVelocityDrivenYReversals,
                "\(label) physical Y may turn only for release handoff and an optional endpoint return; it may not wobble; directions=\(directions), chords=\(yChords)"
            )
        } else {
            let targetDirection: CGFloat = targetPosition.y >= originPosition.y
                ? 1
                : -1
            for chord in yChords {
                XCTAssertGreaterThanOrEqual(
                    chord * targetDirection,
                    -0.000_5,
                    "\(label) may not move backward on its physical Y path"
                )
            }
        }
        for pair in zip(boundsProgress.dropFirst(), boundsProgress) {
            XCTAssertGreaterThanOrEqual(
                pair.0,
                pair.1 - 0.000_5,
                "\(label) bounds may not move backward while position carries release velocity"
            )
        }

        for series in [
            positions.map(\.x),
            positions.map(\.y),
            projectedProgress,
        ] {
            let normalized = series.map { $0 / max(1, chordLength) }
            XCTAssertLessThanOrEqual(
                holdThenJumpCount(in: normalized),
                1,
                "\(label) must not replay paired 60 Hz chords at 120 Hz"
            )
            XCTAssertLessThanOrEqual(
                stationaryThenMovingChordCount(in: normalized),
                1,
                "\(label) must not hold for one compositor frame and then jump"
            )
        }
    }

    @MainActor
    private func surfaceFrames(in group: CAAnimationGroup) throws -> [CGRect] {
        let keyframes = try XCTUnwrap(group.animations).compactMap {
            $0 as? CAKeyframeAnimation
        }
        let position = try XCTUnwrap(
            keyframes.first { $0.keyPath == "position" }
        )
        let bounds = try XCTUnwrap(
            keyframes.first { $0.keyPath == "bounds" }
        )
        let positions = try XCTUnwrap(position.values as? [NSValue])
        let boundsValues = try XCTUnwrap(bounds.values as? [NSValue])
        XCTAssertEqual(position.calculationMode, .linear)
        XCTAssertEqual(bounds.calculationMode, .linear)
        XCTAssertEqual(position.keyTimes?.count, positions.count)
        XCTAssertEqual(bounds.keyTimes?.count, boundsValues.count)
        XCTAssertEqual(positions.count, boundsValues.count)
        return zip(positions, boundsValues).map { pair in
            let center = pair.0.cgPointValue
            let size = pair.1.cgRectValue.size
            return CGRect(
                x: center.x - size.width * 0.5,
                y: center.y - size.height * 0.5,
                width: size.width,
                height: size.height
            )
        }
    }

    @MainActor
    private func surfaceKeyframeTracks(
        in group: CAAnimationGroup
    ) throws -> SurfaceKeyframeTracks {
        let keyframes = try XCTUnwrap(group.animations).compactMap {
            $0 as? CAKeyframeAnimation
        }
        let position = try XCTUnwrap(
            keyframes.first { $0.keyPath == "position" }
        )
        let bounds = try XCTUnwrap(
            keyframes.first { $0.keyPath == "bounds" }
        )
        let cornerRadius = try XCTUnwrap(
            keyframes.first { $0.keyPath == "cornerRadius" }
        )
        for keyframe in [position, bounds, cornerRadius] {
            XCTAssertEqual(keyframe.calculationMode, .linear)
            XCTAssertEqual(keyframe.duration, group.duration, accuracy: 0.000_001)
            XCTAssertEqual(keyframe.keyTimes?.count, keyframe.values?.count)
        }
        return SurfaceKeyframeTracks(
            position: position,
            bounds: bounds,
            cornerRadius: cornerRadius
        )
    }

    @MainActor
    private func surfaceGeometries(
        in group: CAAnimationGroup
    ) throws -> [BottomBarAccessorySurfaceGeometry] {
        let tracks = try surfaceKeyframeTracks(in: group)
        let positions = try XCTUnwrap(
            tracks.position.values as? [NSValue]
        ).map(\.cgPointValue)
        let bounds = try XCTUnwrap(
            tracks.bounds.values as? [NSValue]
        ).map(\.cgRectValue)
        let corners = try XCTUnwrap(
            tracks.cornerRadius.values as? [NSNumber]
        ).map { CGFloat($0.doubleValue) }
        XCTAssertEqual(positions.count, bounds.count)
        XCTAssertEqual(positions.count, corners.count)
        return positions.indices.map { index in
            BottomBarAccessorySurfaceGeometry(
                position: positions[index],
                bounds: bounds[index],
                cornerRadius: corners[index]
            )
        }
    }

    @MainActor
    private func animationGroup(
        on layer: CALayer,
        containing requiredKeyPaths: Set<String>
    ) -> CAAnimationGroup? {
        for key in layer.animationKeys() ?? [] {
            guard let group = layer.animation(forKey: key) as? CAAnimationGroup else {
                continue
            }
            let keyPaths = Set(
                flattenedKeyframeAnimations(in: group).compactMap(\.keyPath)
            )
            if requiredKeyPaths.isSubset(of: keyPaths) {
                return group
            }
        }
        return nil
    }

    @MainActor
    private func keyframeAnimation(
        on layer: CALayer,
        keyPath: String
    ) -> CAKeyframeAnimation? {
        for key in layer.animationKeys() ?? [] {
            guard let animation = layer.animation(forKey: key) else { continue }
            if let match = flattenedKeyframeAnimations(in: animation).first(
                where: { $0.keyPath == keyPath }
            ) {
                return match
            }
        }
        return nil
    }

    private func flattenedKeyframeAnimations(
        in animation: CAAnimation
    ) -> [CAKeyframeAnimation] {
        if let keyframe = animation as? CAKeyframeAnimation {
            return [keyframe]
        }
        guard let group = animation as? CAAnimationGroup else { return [] }
        return (group.animations ?? []).flatMap(flattenedKeyframeAnimations(in:))
    }

    private func flattenedPropertyKeyPaths(in animation: CAAnimation) -> [String] {
        if let property = animation as? CAPropertyAnimation,
           let keyPath = property.keyPath {
            return [keyPath]
        }
        guard let group = animation as? CAAnimationGroup else { return [] }
        return (group.animations ?? []).flatMap(flattenedPropertyKeyPaths(in:))
    }

    private func synchronizedKeyframeGroup(
        _ animation: CAAnimation?,
        requiredKeyPaths: Set<String>,
        keyTimes: [NSNumber],
        duration: TimeInterval,
        localBeginTime: CFTimeInterval,
        maximumFramesPerSecond: Int
    ) throws -> [String: CAKeyframeAnimation] {
        let group = try XCTUnwrap(
            animation as? CAAnimationGroup,
            "native glass layer is missing its compositor settle group"
        )
        XCTAssertEqual(group.duration, duration, accuracy: 0.000_1)
        XCTAssertEqual(group.beginTime, localBeginTime, accuracy: 0.000_1)
        assertExactFrameRateRange(
            group,
            maximumFramesPerSecond: maximumFramesPerSecond
        )
        let keyframes = flattenedKeyframeAnimations(in: group)
        let keyed = Dictionary(
            uniqueKeysWithValues: keyframes.compactMap { keyframe in
                keyframe.keyPath.map { ($0, keyframe) }
            }
        )
        XCTAssertTrue(requiredKeyPaths.isSubset(of: Set(keyed.keys)))
        for keyPath in requiredKeyPaths {
            let keyframe = try XCTUnwrap(keyed[keyPath])
            XCTAssertEqual(keyframe.keyTimes, keyTimes)
            XCTAssertEqual(keyframe.values?.count, keyTimes.count)
            XCTAssertEqual(keyframe.duration, duration, accuracy: 0.000_1)
            XCTAssertEqual(keyframe.calculationMode, .linear)
            assertExactFrameRateRange(
                keyframe,
                maximumFramesPerSecond: maximumFramesPerSecond
            )
        }
        return keyed
    }

    private func normalizedScalarValues(
        in animation: CAKeyframeAnimation,
        keyPath: String
    ) throws -> [CGFloat] {
        let rawValues: [CGFloat]
        switch keyPath {
        case "position":
            rawValues = try XCTUnwrap(
                animation.values as? [NSValue]
            ).map(\.cgPointValue.y)
        case "bounds":
            rawValues = try XCTUnwrap(
                animation.values as? [NSValue]
            ).map(\.cgRectValue.width)
        case "cornerRadius", "opacity":
            rawValues = try XCTUnwrap(
                animation.values as? [NSNumber]
            ).map { CGFloat($0.doubleValue) }
        default:
            XCTFail("unsupported scalar key path \(keyPath)")
            return []
        }
        guard let origin = rawValues.first else { return [] }
        let scale = max(
            1,
            (rawValues.max() ?? origin) - (rawValues.min() ?? origin)
        )
        return rawValues.map { ($0 - origin) / scale }
    }

    private func assertExactFrameRateRange(
        _ animation: CAAnimation,
        maximumFramesPerSecond: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let resolvedMaximum = maximumFramesPerSecond > 0
            ? min(120, maximumFramesPerSecond)
            : 120
        let expected = Float(resolvedMaximum)
        let range = animation.preferredFrameRateRange
        XCTAssertEqual(range.minimum, expected, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(range.maximum, expected, accuracy: 0.001, file: file, line: line)
        XCTAssertNotNil(range.preferred, file: file, line: line)
        if let preferred = range.preferred {
            XCTAssertEqual(preferred, expected, accuracy: 0.001, file: file, line: line)
        }
    }

    @MainActor
    private func explicitMediaBeginTime(
        of animation: CAAnimation,
        on layer: CALayer
    ) throws -> CFTimeInterval {
        let localBeginTime = try XCTUnwrap(
            animation.beginTime > 0 ? animation.beginTime : nil,
            "synchronized compositor tracks require one explicit media-time origin"
        )
        return layer.convertTime(localBeginTime, to: nil)
    }

    private func assertFiniteMotionBounds(
        _ values: [CGFloat],
        sampleInterval: CGFloat,
        maximumVelocity: CGFloat = 40,
        maximumAcceleration: CGFloat = 2_500,
        maximumJerk: CGFloat = 50_000,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThan(sampleInterval, 0, file: file, line: line)
        XCTAssertTrue(values.allSatisfy(\.isFinite), "\(label) contains a non-finite keyframe", file: file, line: line)
        guard sampleInterval > 0, values.count >= 4 else { return }
        let velocities = zip(values.dropFirst(), values).map {
            ($0.0 - $0.1) / sampleInterval
        }
        let accelerations = zip(velocities.dropFirst(), velocities).map {
            ($0.0 - $0.1) / sampleInterval
        }
        let jerks = zip(accelerations.dropFirst(), accelerations).map {
            ($0.0 - $0.1) / sampleInterval
        }
        XCTAssertTrue(velocities.allSatisfy(\.isFinite), file: file, line: line)
        XCTAssertTrue(accelerations.allSatisfy(\.isFinite), file: file, line: line)
        XCTAssertTrue(jerks.allSatisfy(\.isFinite), file: file, line: line)
        let maximumVelocitySample = velocities.enumerated().max {
            abs($0.element) < abs($1.element)
        }
        let maximumAccelerationSample = accelerations.enumerated().max {
            abs($0.element) < abs($1.element)
        }
        let maximumJerkSample = jerks.enumerated().max {
            abs($0.element) < abs($1.element)
        }
        XCTAssertLessThanOrEqual(
            abs(maximumVelocitySample?.element ?? 0),
            maximumVelocity,
            "\(label) has an implausible one-frame velocity spike at chord \(maximumVelocitySample?.offset ?? -1)",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            abs(maximumAccelerationSample?.element ?? 0),
            maximumAcceleration,
            "\(label) has an acceleration step visible at 120 Hz around frames \(maximumAccelerationSample?.offset ?? -1)...\((maximumAccelerationSample?.offset ?? -1) + 2)",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            abs(maximumJerkSample?.element ?? 0),
            maximumJerk,
            "\(label) has a keyframe jerk spike visible at 120 Hz around frames \(maximumJerkSample?.offset ?? -1)...\((maximumJerkSample?.offset ?? -1) + 3)",
            file: file,
            line: line
        )
    }

    private func holdThenJumpCount(in values: [CGFloat]) -> Int {
        let chords = zip(values.dropFirst(), values).map { pair in
            pair.0 - pair.1
        }
        guard chords.count >= 3 else { return 0 }
        return (1 ..< chords.count - 1).reduce(into: 0) { count, index in
            let heldVelocity = abs(chords[index] - chords[index - 1])
                <= 0.000_001
            let followingVelocityJump = abs(chords[index + 1] - chords[index])
                >= 0.000_25
            if heldVelocity && followingVelocityJump {
                count += 1
            }
        }
    }

    private func stationaryThenMovingChordCount(in values: [CGFloat]) -> Int {
        let chords = zip(values.dropFirst(), values).map { pair in
            pair.0 - pair.1
        }
        guard chords.count >= 2 else { return 0 }
        return (0 ..< chords.count - 1).reduce(into: 0) { count, index in
            let held = abs(chords[index]) <= 0.000_001
            let movedNext = abs(chords[index + 1]) >= 0.000_025
            if held && movedNext {
                count += 1
            }
        }
    }

    private func longestStationaryChordRun(
        in values: [CGFloat],
        tolerance: CGFloat
    ) -> Int {
        var longestRun = 0
        var currentRun = 0
        for pair in zip(values.dropFirst(), values) {
            if abs(pair.0 - pair.1) <= tolerance {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        return longestRun
    }

    @MainActor
    private func assertBoundaryC1Retarget(
        source: BottomBarAccessorySurfaceGeometry,
        firstTarget: BottomBarAccessorySurfaceGeometry,
        firstReleaseTarget: BottomBarAccessoryReleaseTarget,
        firstDuration: TimeInterval,
        firstInitialVelocity: CGFloat,
        sampleTime: TimeInterval,
        reverseTarget: BottomBarAccessorySurfaceGeometry,
        reverseReleaseTarget: BottomBarAccessoryReleaseTarget,
        reverseBaseDuration: TimeInterval,
        opposite: BottomBarAccessorySurfaceGeometry,
        configuration: BottomBarAccessoryTransitionConfiguration
    ) {
        let deltaTime = TimeInterval(0.000_005)
        let current = BottomBarAccessoryTransitionCoordinator
            .settleSurfaceGeometry(
                from: source,
                to: firstTarget,
                target: firstReleaseTarget,
                linearProgress: CGFloat(sampleTime / firstDuration),
                initialVelocityY: firstInitialVelocity,
                configuration: configuration,
                settleDuration: firstDuration
            )
        let previous = BottomBarAccessoryTransitionCoordinator
            .settleSurfaceGeometry(
                from: source,
                to: firstTarget,
                target: firstReleaseTarget,
                linearProgress: CGFloat((sampleTime - deltaTime) / firstDuration),
                initialVelocityY: firstInitialVelocity,
                configuration: configuration,
                settleDuration: firstDuration
            )
        let incomingTopVelocity = (current.frame.minY - previous.frame.minY)
            / CGFloat(deltaTime)
        let incomingBottomVelocity = (current.frame.maxY - previous.frame.maxY)
            / CGFloat(deltaTime)
        let incomingCenterVelocity = (
            incomingTopVelocity + incomingBottomVelocity
        ) * 0.5
        let reverseDuration = BottomBarAccessoryTransitionCoordinator
            .resolvedSettleDuration(
                from: current,
                to: reverseTarget,
                opposite: opposite,
                baseDuration: reverseBaseDuration,
                initialVelocityY: incomingCenterVelocity
            )
        for hardwareRate in [120, 60] {
            let cadence = TimeInterval(1) / TimeInterval(hardwareRate)
            let productionHandoffWindow = BottomBarAccessoryTransitionCoordinator
                .resolvedVelocityHandoffSampleInterval(
                    keyframesPerSecond: configuration.geometryKeyframesPerSecond,
                    maximumFramesPerSecond: hardwareRate
                )
            XCTAssertEqual(
                productionHandoffWindow,
                cadence,
                accuracy: 0.000_001,
                "the C1 window must use the panel's actual 120/60 Hz first chord"
            )
            let corrected = BottomBarAccessoryTransitionCoordinator
                .settleSurfaceGeometry(
                    from: current,
                    to: reverseTarget,
                    target: reverseReleaseTarget,
                    linearProgress: CGFloat(cadence / reverseDuration),
                    initialVelocityY: incomingCenterVelocity,
                    initialTopVelocityY: incomingTopVelocity,
                    initialBottomVelocityY: incomingBottomVelocity,
                    configuration: configuration,
                    settleDuration: reverseDuration,
                    preservesBoundaryVelocities: true,
                    preservesTopBoundaryVelocity: true,
                    preservesBottomBoundaryVelocity: true,
                    velocityHandoffSampleInterval: productionHandoffWindow
                )
            let uncorrected = BottomBarAccessoryTransitionCoordinator
                .settleSurfaceGeometry(
                    from: current,
                    to: reverseTarget,
                    target: reverseReleaseTarget,
                    linearProgress: CGFloat(cadence / reverseDuration),
                    initialVelocityY: incomingCenterVelocity,
                    initialTopVelocityY: incomingTopVelocity,
                    initialBottomVelocityY: incomingBottomVelocity,
                    configuration: configuration,
                    settleDuration: reverseDuration,
                    preservesBoundaryVelocities: false
                )
            let correctedTopVelocity = (
                corrected.frame.minY - current.frame.minY
            ) / CGFloat(cadence)
            let correctedBottomVelocity = (
                corrected.frame.maxY - current.frame.maxY
            ) / CGFloat(cadence)
            let uncorrectedTopVelocity = (
                uncorrected.frame.minY - current.frame.minY
            ) / CGFloat(cadence)
            let uncorrectedBottomVelocity = (
                uncorrected.frame.maxY - current.frame.maxY
            ) / CGFloat(cadence)
            let beforeDelta = max(
                abs(uncorrectedTopVelocity - incomingTopVelocity),
                abs(uncorrectedBottomVelocity - incomingBottomVelocity)
            )
            let afterDelta = max(
                abs(correctedTopVelocity - incomingTopVelocity),
                abs(correctedBottomVelocity - incomingBottomVelocity)
            )
            XCTAssertGreaterThan(beforeDelta, 40)
            XCTAssertLessThan(
                afterDelta,
                0.1,
                "retarget \(firstReleaseTarget)->\(reverseReleaseTarget) @\(hardwareRate)Hz captured top/bottom \(incomingTopVelocity)/\(incomingBottomVelocity) pt/s but first compositor chord produced \(correctedTopVelocity)/\(correctedBottomVelocity) pt/s"
            )
        }
    }

    private func makeGeometry() -> BottomBarAccessoryTransitionGeometry {
        BottomBarAccessoryTransitionGeometry(
            collapsedFrame: CGRect(x: 20, y: 720, width: 350, height: 60),
            expandedFrame: CGRect(x: 0, y: 0, width: 390, height: 800),
            collapsedCornerRadius: 28,
            expandedCornerRadius: 8,
            safeInsets: .zero,
            layoutSize: CGSize(width: 390, height: 844)
        )
    }

    private func makeTransitionContext(
        geometry: BottomBarAccessoryTransitionGeometry
    ) -> BottomBarAccessoryTransitionContext {
        BottomBarAccessoryTransitionContext(
            sessionIdentifier: UUID(),
            state: .expanding,
            phase: .preparing,
            presentationProgress: 0,
            settleProgress: 0,
            dragProgress: 0,
            isInteractive: false,
            isReduceMotionEnabled: false,
            target: .expanded,
            geometry: geometry,
            dockingContext: BottomBarAccessoryDockingContext(
                mode: .regular,
                isTabBarVisible: true,
                isSearchActive: false
            )
        )
    }
}

final class GlassBackgroundInteractiveGeometryTests: XCTestCase {
    @MainActor
    func testRepeatedInteractiveGeometryReusesSyntheticStrokePath() {
        let glass = GlassBackgroundView()
        glass.strokeAppearance = .hairline(color: .white, opacity: 0.5)
        glass.frame = CGRect(x: 0, y: 0, width: 360, height: 64)
        glass.update(
            size: glass.bounds.size,
            cornerRadius: 28,
            transition: .immediate
        )
        let initialUpdateCount = glass.syntheticStrokePathUpdateCount

        glass.beginInteractiveGeometryUpdates()
        for _ in 0 ..< 20 {
            glass.updateInteractiveGeometry(
                size: CGSize(width: 360, height: 64),
                cornerRadius: 28
            )
        }
        XCTAssertEqual(
            glass.syntheticStrokePathUpdateCount,
            initialUpdateCount,
            "duplicate display-link samples must reuse the cached path"
        )

        glass.updateInteractiveGeometry(
            size: CGSize(width: 350, height: 63),
            cornerRadius: 29
        )
        XCTAssertEqual(
            glass.syntheticStrokePathUpdateCount,
            initialUpdateCount + 1
        )
        glass.updateInteractiveGeometry(
            size: CGSize(width: 350, height: 63),
            cornerRadius: 29
        )
        XCTAssertEqual(
            glass.syntheticStrokePathUpdateCount,
            initialUpdateCount + 1
        )

        glass.endInteractiveGeometryUpdates(
            size: CGSize(width: 350, height: 63),
            cornerRadius: 29
        )
    }
}

@MainActor
private final class SharedElementParticipant: BottomBarAccessoryTransitionParticipant {
    private let element: BottomBarAccessoryTransitionSharedElement

    init(view: UIView, cornerRadius: CGFloat) {
        element = BottomBarAccessoryTransitionSharedElement(
            identifier: "shared-element",
            view: view,
            cornerRadius: cornerRadius,
            representationProvider: { _ in UIView() }
        )
    }

    func bottomBarAccessoryTransitionSharedElements(
        in context: BottomBarAccessoryTransitionContext
    ) -> [BottomBarAccessoryTransitionSharedElement] {
        [element]
    }
}

@MainActor
private final class SignatureSharedElementParticipant: BottomBarAccessoryTransitionParticipant {
    private let element: BottomBarAccessoryTransitionSharedElement

    init(view: UIView, signature: MutableContentSignature) {
        element = BottomBarAccessoryTransitionSharedElement(
            identifier: "shared-element",
            view: view,
            contentSignatureProvider: { _ in signature.value }
        )
    }

    func bottomBarAccessoryTransitionSharedElements(
        in context: BottomBarAccessoryTransitionContext
    ) -> [BottomBarAccessoryTransitionSharedElement] {
        [element]
    }
}

@MainActor
private final class RefreshableSharedElementParticipant: BottomBarAccessoryTransitionParticipant {
    private let element: BottomBarAccessoryTransitionSharedElement

    init(
        view: UIView,
        signature: MutableContentSignature,
        refreshCounter: MutableCounter
    ) {
        element = BottomBarAccessoryTransitionSharedElement(
            identifier: "shared-element",
            view: view,
            contentSignatureProvider: { _ in signature.value },
            representationProvider: { source in
                let representation = MarkerRepresentationView()
                representation.marker = source.accessibilityIdentifier
                return representation
            },
            representationRefreshHandler: { source, representation in
                refreshCounter.value += 1
                (representation as? MarkerRepresentationView)?.marker =
                    source.accessibilityIdentifier
                // Verify that AetherUI owns and protects endpoint visibility,
                // even if a participant hook accidentally mutates it.
                source.alpha = 0.91
                source.isHidden = true
            }
        )
    }

    func bottomBarAccessoryTransitionSharedElements(
        in context: BottomBarAccessoryTransitionContext
    ) -> [BottomBarAccessoryTransitionSharedElement] {
        [element]
    }
}

@MainActor
private final class MarkerRepresentationView: UIView {
    var marker: String?
}

@MainActor
private final class MutableContentSignature {
    var value: AnyHashable

    init(_ value: AnyHashable) {
        self.value = value
    }
}

@MainActor
private final class MutableCounter {
    var value = 0
}
