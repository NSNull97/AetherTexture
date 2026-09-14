import UIKit

/// The stable endpoint selected after an expanded bottom-bar accessory gesture.
public enum BottomBarAccessoryReleaseTarget: Equatable, Sendable {
    case expanded
    case collapsed
}

/// Why an interactive gesture stopped. Cancelled and failed gestures always
/// resolve back to the expanded endpoint.
public enum BottomBarAccessoryGestureEndReason: Equatable, Sendable {
    case ended
    case cancelled
    case failed
}

/// Tunable physics and interaction thresholds for the generic bottom-bar
/// accessory transition. All release thresholds live here so the hosting tab
/// controller does not accumulate unrelated magic numbers.
public struct BottomBarAccessoryTransitionConfiguration: Equatable, Sendable {
    /// A unit cubic Bezier used to shape geometry independently from the
    /// property animator that owns interruption and completion. X control
    /// points are resolved as time, Y control points as normalized travel.
    public struct CubicBezierCurve: Equatable, Sendable {
        public var controlPoint1: CGPoint
        public var controlPoint2: CGPoint

        public init(controlPoint1: CGPoint, controlPoint2: CGPoint) {
            self.controlPoint1 = controlPoint1
            self.controlPoint2 = controlPoint2
        }

        /// Resolves the curve at linear wall-clock progress. Invalid control
        /// points fall back to linear timing instead of poisoning layer values.
        public func progress(at linearProgress: CGFloat) -> CGFloat {
            let time = linearProgress.isFinite
                ? linearProgress.clamped(to: 0 ... 1)
                : 0
            guard controlPoint1.x.isFinite,
                  controlPoint1.y.isFinite,
                  controlPoint2.x.isFinite,
                  controlPoint2.y.isFinite else {
                return time
            }

            let x1 = controlPoint1.x.clamped(to: 0 ... 1)
            let x2 = controlPoint2.x.clamped(to: 0 ... 1)
            var lower: CGFloat = 0
            var upper: CGFloat = 1
            // Unit Beziers are monotonic in x after clamping both controls,
            // so a short binary solve is deterministic and stable at 120 Hz.
            // Keep sub-frame C1/C2 evaluation smooth as well as the visible
            // 120 Hz samples. Eighteen bisections quantized derivatives when
            // a transition was captured between native frames.
            for _ in 0 ..< 32 {
                let parameter = (lower + upper) * 0.5
                if Self.unitBezier(parameter, x1, x2) < time {
                    lower = parameter
                } else {
                    upper = parameter
                }
            }
            let parameter = (lower + upper) * 0.5
            return Self.unitBezier(
                parameter,
                controlPoint1.y,
                controlPoint2.y
            ).clamped(to: 0 ... 1)
        }

        private static func unitBezier(
            _ parameter: CGFloat,
            _ control1: CGFloat,
            _ control2: CGFloat
        ) -> CGFloat {
            let inverse = 1 - parameter
            return 3 * inverse * inverse * parameter * control1
                + 3 * inverse * parameter * parameter * control2
                + parameter * parameter * parameter
        }
    }

    public struct Spring: Equatable, Sendable {
        public var mass: CGFloat
        public var stiffness: CGFloat
        public var damping: CGFloat

        public init(
            mass: CGFloat,
            stiffness: CGFloat,
            damping: CGFloat
        ) {
            self.mass = mass
            self.stiffness = stiffness
            self.damping = damping
        }

        @MainActor
        func timingParameters(initialVelocity: CGVector) -> UISpringTimingParameters {
            let resolvedMass = mass.isFinite ? max(0.001, mass) : 1
            let resolvedStiffness = stiffness.isFinite ? max(0.001, stiffness) : 380
            let resolvedDamping = damping.isFinite ? max(0.001, damping) : 36
            return UISpringTimingParameters(
                mass: resolvedMass,
                stiffness: resolvedStiffness,
                damping: resolvedDamping,
                initialVelocity: initialVelocity
            )
        }
    }

    public var projectionTime: CGFloat
    public var commitDistanceFactor: CGFloat
    public var minimumCommitDistance: CGFloat
    public var maximumCommitDistance: CGFloat
    public var flickVelocity: CGFloat
    public var upwardCancelVelocity: CGFloat
    public var minimumFlickTranslation: CGFloat
    public var maximumResolvedVelocity: CGFloat

    public var rubberBandCoefficient: CGFloat
    public var maximumLinearDragFactor: CGFloat
    public var minimumDragScale: CGFloat
    public var reduceMotionMinimumDragScale: CGFloat
    /// Maximum post-release travel while Reduce Motion is enabled. The
    /// endpoint geometry is committed after the crossfade, so the visible
    /// settle never performs a full-screen-to-pill spatial morph.
    public var reduceMotionMaximumSettleTranslation: CGFloat
    /// Maximum proportional bounds change during the reduced-motion settle.
    /// `1` keeps the captured size exactly; values just below one provide a
    /// small acknowledgement without a large zoom.
    public var reduceMotionSettleScale: CGFloat
    public var reduceMotionMaximumCornerRadiusChange: CGFloat
    public var dragCornerRadiusIncrease: CGFloat
    public var maximumDragBackgroundFade: CGFloat
    public var maximumDragContentFade: CGFloat
    public var dragSharedElementPreview: CGFloat

    public var collapseCaptureProgress: CGFloat
    public var collapsedInteractionProgress: CGFloat
    public var expandedInteractionProgress: CGFloat
    public var maximumNormalizedSpringVelocity: CGFloat
    /// Duration of the horizontal compacting phase during collapse. Width,
    /// horizontal position, and corner radius may dock before the independent
    /// vertical edges finish folding and performing their small terminal dip.
    public var collapseShapeDuration: TimeInterval

    /// Geometry curves are intentionally independent from the spring clock.
    /// During collapse the top and bottom edges therefore have genuinely
    /// different trajectories rather than being side effects of animating a
    /// centre point and a height with unrelated APIs.
    public var expansionGeometryCurve: CubicBezierCurve
    /// Retained for source compatibility with the original sampled opening.
    /// The coordinator now evaluates a continuous second-order response, so
    /// 60 Hz reference checkpoints are not replayed as velocity stairs on a
    /// 120 Hz display.
    public var expansionProgressSamples: [CGFloat]
    public var collapseShapeGeometryCurve: CubicBezierCurve
    /// Native-duration targets measured from the reference transition.
    public var expansionDuration: TimeInterval
    public var expansionGeometryDuration: TimeInterval
    public var collapseDuration: TimeInterval
    /// Retained as the monotonic width/radius fold exponent. The lower edge
    /// itself now uses `collapseBottomSpring`, preserving its release velocity
    /// instead of reversing direction on the first post-release frame.
    public var collapseBottomPower: CGFloat
    /// Maximum overshoot of the single release-owned top flight. Runtime
    /// resolves the underdamped amplitude against a critically damped
    /// companion, so this spatial limit introduces no clamp or docking shelf.
    public var collapseTopOvershoot: CGFloat
    /// Keyframe density for the custom surface geometry tracks. Rendering is
    /// still synchronized by Core Animation to the actual display cadence.
    public var geometryKeyframesPerSecond: CGFloat

    public var expandSpring: Spring
    public var collapseSpring: Spring
    /// Independent lower-edge response for collapse. Its initial velocity is
    /// normalized by the signed remaining maxY distance only for an animator
    /// retarget, so captured outward motion can carry once before this
    /// critically damped spring folds monotonically. Ordinary closes use rest.
    public var collapseBottomSpring: Spring
    /// Physical vertical response of the transition-only shared element.
    /// Horizontal travel, size, and corner radius keep the slower measured
    /// artwork clock; only `position.y` inherits release velocity.
    public var sharedElementVerticalSpring: Spring
    public var cancelSpring: Spring
    public var reduceMotionSpring: Spring

    public init(
        projectionTime: CGFloat = 0.18,
        commitDistanceFactor: CGFloat = 0.22,
        minimumCommitDistance: CGFloat = 110,
        maximumCommitDistance: CGFloat = 175,
        flickVelocity: CGFloat = 1_050,
        upwardCancelVelocity: CGFloat = 220,
        minimumFlickTranslation: CGFloat = 28,
        maximumResolvedVelocity: CGFloat = 7_000,
        rubberBandCoefficient: CGFloat = 0.52,
        maximumLinearDragFactor: CGFloat = 1.05,
        minimumDragScale: CGFloat = 1,
        reduceMotionMinimumDragScale: CGFloat = 0.99,
        reduceMotionMaximumSettleTranslation: CGFloat = 44,
        reduceMotionSettleScale: CGFloat = 0.995,
        reduceMotionMaximumCornerRadiusChange: CGFloat = 2,
        dragCornerRadiusIncrease: CGFloat = 60,
        maximumDragBackgroundFade: CGFloat = 0,
        maximumDragContentFade: CGFloat = 0,
        dragSharedElementPreview: CGFloat = 0,
        collapseCaptureProgress: CGFloat = 0.06,
        collapsedInteractionProgress: CGFloat = 0.12,
        expandedInteractionProgress: CGFloat = 0.85,
        maximumNormalizedSpringVelocity: CGFloat = 18,
        collapseShapeDuration: TimeInterval = 12.0 / 60.0,
        expansionGeometryCurve: CubicBezierCurve = CubicBezierCurve(
            controlPoint1: CGPoint(x: 0.20, y: 0.05),
            controlPoint2: CGPoint(x: 0.20, y: 1)
        ),
        expansionProgressSamples: [CGFloat] = [
            0, 0.034, 0.093, 0.195, 0.308, 0.422, 0.520, 0.608,
            0.681, 0.745, 0.797, 0.844, 0.876, 0.899, 0.922, 0.940,
            0.954, 0.966, 0.975, 0.985, 0.992, 0.997, 1,
        ],
        collapseShapeGeometryCurve: CubicBezierCurve = CubicBezierCurve(
            controlPoint1: CGPoint(x: 0.200_5, y: 0.046_0),
            controlPoint2: CGPoint(x: 0.381_7, y: 0.684_2)
        ),
        expansionDuration: TimeInterval = 0.40,
        expansionGeometryDuration: TimeInterval = 0.40,
        collapseDuration: TimeInterval = 32.0 / 60.0,
        collapseBottomPower: CGFloat = 2,
        collapseTopOvershoot: CGFloat = 6,
        geometryKeyframesPerSecond: CGFloat = 120,
        expandSpring: Spring = Spring(mass: 1, stiffness: 276, damping: 30.9),
        collapseSpring: Spring = Spring(
            mass: 1,
            stiffness: 276.287_6,
            damping: 26.800_1
        ),
        collapseBottomSpring: Spring = Spring(
            mass: 1,
            stiffness: 238.7,
            damping: 30.899_838_187_3
        ),
        sharedElementVerticalSpring: Spring = Spring(
            mass: 1,
            stiffness: 222.01,
            damping: 21.754
        ),
        cancelSpring: Spring = Spring(mass: 1, stiffness: 370, damping: 33),
        reduceMotionSpring: Spring = Spring(mass: 1, stiffness: 900, damping: 65)
    ) {
        self.projectionTime = projectionTime
        self.commitDistanceFactor = commitDistanceFactor
        self.minimumCommitDistance = minimumCommitDistance
        self.maximumCommitDistance = maximumCommitDistance
        self.flickVelocity = flickVelocity
        self.upwardCancelVelocity = upwardCancelVelocity
        self.minimumFlickTranslation = minimumFlickTranslation
        self.maximumResolvedVelocity = maximumResolvedVelocity
        self.rubberBandCoefficient = rubberBandCoefficient
        self.maximumLinearDragFactor = maximumLinearDragFactor
        self.minimumDragScale = minimumDragScale
        self.reduceMotionMinimumDragScale = reduceMotionMinimumDragScale
        self.reduceMotionMaximumSettleTranslation = reduceMotionMaximumSettleTranslation
        self.reduceMotionSettleScale = reduceMotionSettleScale
        self.reduceMotionMaximumCornerRadiusChange = reduceMotionMaximumCornerRadiusChange
        self.dragCornerRadiusIncrease = dragCornerRadiusIncrease
        self.maximumDragBackgroundFade = maximumDragBackgroundFade
        self.maximumDragContentFade = maximumDragContentFade
        self.dragSharedElementPreview = dragSharedElementPreview
        self.collapseCaptureProgress = collapseCaptureProgress
        self.collapsedInteractionProgress = collapsedInteractionProgress
        self.expandedInteractionProgress = expandedInteractionProgress
        self.maximumNormalizedSpringVelocity = maximumNormalizedSpringVelocity
        self.collapseShapeDuration = collapseShapeDuration
        self.expansionGeometryCurve = expansionGeometryCurve
        self.expansionProgressSamples = expansionProgressSamples
        self.collapseShapeGeometryCurve = collapseShapeGeometryCurve
        self.expansionDuration = expansionDuration
        self.expansionGeometryDuration = expansionGeometryDuration
        self.collapseDuration = collapseDuration
        self.collapseBottomPower = collapseBottomPower
        self.collapseTopOvershoot = collapseTopOvershoot
        self.geometryKeyframesPerSecond = geometryKeyframesPerSecond
        self.expandSpring = expandSpring
        self.collapseSpring = collapseSpring
        self.collapseBottomSpring = collapseBottomSpring
        self.sharedElementVerticalSpring = sharedElementVerticalSpring
        self.cancelSpring = cancelSpring
        self.reduceMotionSpring = reduceMotionSpring
    }

    public static let `default` = BottomBarAccessoryTransitionConfiguration()
}

extension BottomBarAccessoryTransitionConfiguration {
    /// Produces the deliberately small visible geometry change used before a
    /// reduced-motion transition commits its real endpoint. Content hosts
    /// crossfade while this surface travels; the endpoint swap is therefore a
    /// discrete layout change rather than a large animated morph.
    func reducedMotionSettleSurface(
        from current: BottomBarAccessorySurfaceGeometry,
        toward endpoint: BottomBarAccessorySurfaceGeometry
    ) -> BottomBarAccessorySurfaceGeometry {
        let maximumTranslation = finiteNonnegative(
            reduceMotionMaximumSettleTranslation,
            fallback: 44
        )
        let deltaY = endpoint.position.y - current.position.y
        let translatedY = current.position.y + deltaY.clamped(
            to: -maximumTranslation ... maximumTranslation
        )

        let scale = finiteValue(reduceMotionSettleScale, fallback: 0.995)
            .clamped(to: 0.95 ... 1)
        let maximumWidthChange = current.bounds.width * (1 - scale)
        let maximumHeightChange = current.bounds.height * (1 - scale)
        let width = current.bounds.width + (endpoint.bounds.width - current.bounds.width)
            .clamped(to: -maximumWidthChange ... maximumWidthChange)
        let height = current.bounds.height + (endpoint.bounds.height - current.bounds.height)
            .clamped(to: -maximumHeightChange ... maximumHeightChange)

        let maximumCornerChange = finiteNonnegative(
            reduceMotionMaximumCornerRadiusChange,
            fallback: 2
        )
        let cornerRadius = current.cornerRadius
            + (endpoint.cornerRadius - current.cornerRadius).clamped(
                to: -maximumCornerChange ... maximumCornerChange
            )

        return BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: current.position.x, y: translatedY),
            bounds: CGRect(
                origin: current.bounds.origin,
                size: CGSize(width: max(1, width), height: max(1, height))
            ),
            cornerRadius: max(0, cornerRadius)
        )
    }

    private func finiteValue(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isFinite ? value : fallback
    }

    private func finiteNonnegative(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        max(0, finiteValue(value, fallback: fallback))
    }
}

extension BottomBarAccessoryGestureEndReason {
    init(gestureState: UIGestureRecognizer.State) {
        switch gestureState {
        case .ended:
            self = .ended
        case .failed:
            self = .failed
        default:
            self = .cancelled
        }
    }
}
