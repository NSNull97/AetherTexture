import UIKit

@MainActor
protocol BottomBarAccessoryTransitionCoordinatorDelegate: AnyObject {
    func bottomBarAccessoryTransitionCoordinator(
        _ coordinator: BottomBarAccessoryTransitionCoordinator,
        didChangeState state: BottomBarAccessoryPresentationState
    )

    func bottomBarAccessoryTransitionCoordinator(
        _ coordinator: BottomBarAccessoryTransitionCoordinator,
        didUpdateSurfaceGeometry surfaceGeometry: BottomBarAccessorySurfaceGeometry,
        context: BottomBarAccessoryTransitionContext
    )

    func bottomBarAccessoryTransitionCoordinator(
        _ coordinator: BottomBarAccessoryTransitionCoordinator,
        didComplete target: BottomBarAccessoryReleaseTarget
    )
}

extension BottomBarAccessoryTransitionCoordinatorDelegate {
    func bottomBarAccessoryTransitionCoordinator(
        _ coordinator: BottomBarAccessoryTransitionCoordinator,
        didChangeState state: BottomBarAccessoryPresentationState
    ) {}

    func bottomBarAccessoryTransitionCoordinator(
        _ coordinator: BottomBarAccessoryTransitionCoordinator,
        didUpdateSurfaceGeometry surfaceGeometry: BottomBarAccessorySurfaceGeometry,
        context: BottomBarAccessoryTransitionContext
    ) {}

    func bottomBarAccessoryTransitionCoordinator(
        _ coordinator: BottomBarAccessoryTransitionCoordinator,
        didComplete target: BottomBarAccessoryReleaseTarget
    ) {}
}

/// Interruptible transition engine for a single morphing bottom-bar accessory
/// surface with independent collapsed and expanded content hosts.
///
/// The coordinator owns one interruptible UIKit completion clock and at most
/// one synchronized Core Animation geometry track. Its public geometry is
/// expressed in `containerView` coordinates, while the implementation converts
/// layer positions to the surface's actual superview coordinate space.
@MainActor
final class BottomBarAccessoryTransitionCoordinator {
    static let reducedMotionHandoffAnimationKey =
        "aether.bottomBarAccessory.reduceMotion.handoff"
    static let surfaceGeometryAnimationKey =
        "aether.bottomBarAccessory.surfaceGeometry"
    static let collapsedContentOpacityAnimationKey =
        "aether.bottomBarAccessory.collapsedContent.opacity"
    static let expandedContentOpacityAnimationKey =
        "aether.bottomBarAccessory.expandedContent.opacity"
    // Keep the cover's path visibly bowed without turning the motion into a
    // sideways detour. The quartic envelope below still has zero offset and
    // zero derivative at both endpoints, so the slightly stronger arc cannot
    // introduce a release or landing kick.
    static let sharedElementPositionArcAmplitude: CGFloat = 2

    /// Absolute close-phase arc. The phase is owned by the surface top edge,
    /// because that is the edge which remains 1:1 with the grabber gesture.
    /// Using an averaged bounds/centre progress makes the bow disappear while
    /// the finger is still moving the full-height sheet toward Mini.
    static func sharedElementArcPhase(
        for surface: BottomBarAccessorySurfaceGeometry,
        geometry: BottomBarAccessoryTransitionGeometry
    ) -> CGFloat {
        let distance = geometry.collapsedFrame.minY
            - geometry.expandedFrame.minY
        guard distance.isFinite, abs(distance) > 0.001 else { return 0 }
        return ((surface.frame.minY - geometry.expandedFrame.minY) / distance)
            .clamped(to: 0 ... 1)
    }

    static func sharedElementPositionArcOffset(
        atCollapsePhase rawPhase: CGFloat
    ) -> CGFloat {
        let phase = rawPhase.isFinite
            ? rawPhase.clamped(to: 0 ... 1)
            : 0
        return sharedElementPositionArcAmplitude
            * 16 * phase * phase
            * (1 - phase) * (1 - phase)
    }

    weak var delegate: BottomBarAccessoryTransitionCoordinatorDelegate?

    var state: BottomBarAccessoryPresentationState {
        stateMachine.state
    }

    private(set) var currentContext: BottomBarAccessoryTransitionContext?

    private weak var containerView: UIView?
    private weak var surfaceView: UIView?
    private weak var collapsedContentHost: UIView?
    private weak var expandedContentHost: UIView?
    private weak var sharedElementHost: UIView?

    private let configuration: BottomBarAccessoryTransitionConfiguration
    private let animationClockView = UIView(frame: .zero)
    /// Stable ownership identity for native Glass compositor tracks. The
    /// wrapper outlives a presentation coordinator and may be reused from a
    /// dismiss completion before the retired coordinator deinitializes.
    private let glassCompositorOwnerToken = NSObject()
    private var glassCompositorOwner: ObjectIdentifier {
        ObjectIdentifier(glassCompositorOwnerToken)
    }
    private var stateMachine = BottomBarAccessoryTransitionStateMachine()
    private var session: BottomBarAccessoryTransitionSession?
    private var geometryAnimator: UIViewPropertyAnimator?
    private let sharedElementTransition = BottomBarAccessorySharedElementTransition()

    private var displayLink: CADisplayLink?
    private var displayLinkProxy: BottomBarAccessoryDisplayLinkProxy?
    private var lastSampleTimestamp: CFTimeInterval?
    private var lastSamplePositionY: CGFloat?
    private var lastSampleMinY: CGFloat?
    private var lastSampleMaxY: CGFloat?
    private var estimatedVelocityY: CGFloat = 0
    private var estimatedTopVelocityY: CGFloat = 0
    private var estimatedBottomVelocityY: CGFloat = 0
    private var isParticipantTransitionActive = false
    private var currentSettleProgress: CGFloat = 0
    private var dragOriginCollapsedAlpha: CGFloat = 0
    private var dragOriginExpandedAlpha: CGFloat = 1
    private var settleOriginCollapsedAlpha: CGFloat = 0
    private var settleOriginExpandedAlpha: CGFloat = 1
    private var lastPresentedSurfaceGeometry: BottomBarAccessorySurfaceGeometry?
    private var hasCompositorContentTrack = false

    /// The velocity actually handed to the newest settle. Internal visibility
    /// keeps this useful for deterministic physics tests without exposing a
    /// production tuning API.
    private(set) var resolvedSettlingInitialVelocityY: CGFloat = 0
    private(set) var resolvedSettlingInitialTopVelocityY: CGFloat = 0
    private(set) var resolvedSettlingInitialBottomVelocityY: CGFloat = 0
    private(set) var reducedMotionHandoffDuration: TimeInterval?

    /// A coordinator owns at most one authoritative UIKit timing clock. Kept
    /// internal so regression tests can verify an accessibility retarget does
    /// not leave the interrupted animator alive beside its replacement.
    var activeGeometryAnimatorCountForTesting: Int {
        geometryAnimator == nil ? 0 : 1
    }

    var displayLinkFrameRateRangeForTesting: CAFrameRateRange? {
        displayLink?.preferredFrameRateRange
    }

    init(
        containerView: UIView,
        surfaceView: UIView,
        collapsedContentHost: UIView,
        expandedContentHost: UIView,
        sharedElementHost: UIView,
        configuration: BottomBarAccessoryTransitionConfiguration = .default
    ) {
        self.containerView = containerView
        self.surfaceView = surfaceView
        self.collapsedContentHost = collapsedContentHost
        self.expandedContentHost = expandedContentHost
        self.sharedElementHost = sharedElementHost
        self.configuration = configuration

        // A property animator whose only target is detached completes almost
        // immediately on device. Keep this zero-sized, noninteractive clock
        // attached to the same hierarchy as the surface so its configured
        // The physical transition lifetime remains authoritative without drawing or
        // participating in layout/hit testing.
        animationClockView.frame = CGRect(x: -10, y: -10, width: 1, height: 1)
        animationClockView.backgroundColor = .black
        animationClockView.isOpaque = true
        animationClockView.isUserInteractionEnabled = false
        animationClockView.isAccessibilityElement = false
        animationClockView.accessibilityElementsHidden = true
        containerView.addSubview(animationClockView)
    }

    deinit {
        MainActor.assumeIsolated {
            displayLink?.invalidate()
            geometryAnimator?.stopAnimation(true)
            sharedElementTransition.cancel()
            if let glass = surfaceView as? GlassBackgroundView {
                _ = glass.captureTransitionCompositorPresentation(
                    owner: glassCompositorOwner
                )
                _ = glass.discardPendingTransitionCompositorPresentation(
                    owner: glassCompositorOwner
                )
            }
            animationClockView.removeFromSuperview()
        }
    }

    /// Starts the collapsed-to-expanded transition after the caller has added
    /// and fully laid out the expanded content in its final layout space.
    @discardableResult
    func beginExpansion(
        geometry: BottomBarAccessoryTransitionGeometry,
        dockingContext: BottomBarAccessoryDockingContext,
        collapsedParticipant: BottomBarAccessoryTransitionParticipant?,
        expandedParticipant: BottomBarAccessoryTransitionParticipant?,
        reduceMotion: Bool,
        initialSurfaceGeometry: BottomBarAccessorySurfaceGeometry? = nil
    ) -> Bool {
        guard geometry.isValid,
              let surfaceView,
              let containerView,
              surfaceView.isDescendant(of: containerView),
              state == .collapsed else {
            return false
        }

        abandonCurrentSession(restoringVisibility: true)
        let session = BottomBarAccessoryTransitionSession(
            geometry: geometry,
            dockingContext: dockingContext,
            isReduceMotionEnabled: reduceMotion,
            collapsedParticipant: collapsedParticipant,
            expandedParticipant: expandedParticipant
        )
        self.session = session
        session.target = .expanded

        let initialSurface = initialSurfaceGeometry.flatMap { candidate in
            candidate.isValid ? candidate : nil
        } ?? geometry.surfaceGeometry(at: 0)
        // `geometry.collapsedFrame` remains the canonical return target, while
        // an interrupted compact morph may provide a different visual source
        // for expansion. Keeping those concepts separate prevents dismissal
        // from returning to a stale mid-morph frame and snapping afterward.
        applySurfaceGeometry(initialSurface)
        applyStableContentState(.collapsed)
        guard transitionState(with: .requestExpansion) else { return false }

        prepareParticipants(initialEndpoint: .collapsed)
        startAnimator(
            to: .expanded,
            initialVelocityY: 0
        )
        return true
    }

    /// Applies a live Reduce Motion preference change to the current session.
    /// Stable endpoints only republish their context. An in-flight spring is
    /// captured from its presentation layer (including opacity), invalidated,
    /// and retargeted from that exact visual state with the sampled velocity.
    /// This preserves continuity while keeping one property animator clock.
    func updateReduceMotionEnabled(_ isEnabled: Bool) {
        guard let session,
              session.isReduceMotionEnabled != isEnabled else {
            return
        }

        let activeTarget = session.target
        let wasAnimating = geometryAnimator != nil
        let inheritedVelocityY = estimatedVelocityY
        let inheritedTopVelocityY = estimatedTopVelocityY
        let inheritedBottomVelocityY = estimatedBottomVelocityY
        let capturedSurface = wasAnimating
            ? (captureCurrentPresentation() ?? currentSurfaceGeometry())
            : currentSurfaceGeometry()

        session.isReduceMotionEnabled = isEnabled

        if isEnabled {
            // A generic shared representation is part of the spatial morph.
            // Restore the independent endpoint views before the reduced-
            // motion fade-through takes ownership of visual continuity.
            sharedElementTransition.cancel()
        } else if isParticipantTransitionActive,
                  let capturedSurface,
                  capturedSurface.isValid {
            // A reduced-motion transition intentionally prepared no shared
            // representation. If the preference turns off mid-flight or
            // mid-drag, recreate that generic representation at the current
            // endpoint space so the normal morph can continue coherently.
            let initialEndpoint: BottomBarAccessoryReleaseTarget = session
                .geometry.presentationProgress(for: capturedSurface) >= 0.5
                ? .expanded
                : .collapsed
            prepareSharedElements(
                surface: capturedSurface,
                initialEndpoint: initialEndpoint
            )
            if state == .dragging {
                let arcPhase = Self.sharedElementArcPhase(
                    for: capturedSurface,
                    geometry: session.geometry
                )
                session.dragOriginArcPhase = arcPhase
                session.dragArcPhase = arcPhase
                sharedElementTransition.beginInteractiveDrag(
                    collapseArcPhase: arcPhase
                )
            }
        }

        if wasAnimating,
           let activeTarget,
           let capturedSurface,
           capturedSurface.isValid {
            applySurfaceGeometry(capturedSurface, removingAnimations: true)
            startAnimator(
                to: activeTarget,
                initialVelocityY: inheritedVelocityY,
                initialTopVelocityY: inheritedTopVelocityY,
                initialBottomVelocityY: inheritedBottomVelocityY,
                preservesBoundaryVelocities: true,
                preservesTopBoundaryVelocity: true,
                preservesBottomBoundaryVelocity: true
            )
            return
        }

        if let capturedSurface, capturedSurface.isValid {
            publishCurrentState(surface: capturedSurface)
        }
    }

    /// Interrupts any running expand/settle animation and starts a direct drag
    /// from its current presentation geometry. `translationOriginY` supports a
    /// handoff from a nested scroll view without replaying accumulated motion.
    @discardableResult
    func beginDrag(translationOriginY: CGFloat = 0) -> Bool {
        guard let session,
              state != .collapsed,
              state != .dragging else {
            return false
        }

        let capturedSurface = captureCurrentPresentation()
            ?? currentSurfaceGeometry()
        guard let capturedSurface, capturedSurface.isValid else { return false }
        guard transitionState(with: .beginDrag) else { return false }

        session.target = nil
        session.dragOriginSurface = capturedSurface
        session.dragOriginPresentationProgress = session.geometry
            .presentationProgress(for: capturedSurface)
        let dragArcPhase = Self.sharedElementArcPhase(
            for: capturedSurface,
            geometry: session.geometry
        )
        session.dragOriginArcPhase = dragArcPhase
        session.dragArcPhase = dragArcPhase
        session.dragTranslationOrigin = finite(translationOriginY)
        session.latestRawDragTranslation = finite(translationOriginY)
        session.dragProgress = 0
        currentSettleProgress = 0

        dragOriginCollapsedAlpha = collapsedContentHost?.alpha ?? 0
        dragOriginExpandedAlpha = expandedContentHost?.alpha ?? 1
        if !isParticipantTransitionActive {
            prepareParticipants(
                initialEndpoint: session.dragOriginPresentationProgress >= 0.5
                    ? .expanded
                    : .collapsed
            )
        }
        sharedElementTransition.beginInteractiveDrag(
            collapseArcPhase: dragArcPhase
        )
        publishCurrentState(surface: capturedSurface)
        return true
    }

    /// Applies immediate drag geometry. This method never starts an animator
    /// and never commits a release target while the finger remains down.
    func updateDrag(translationY: CGFloat) {
        guard state == .dragging,
              let session,
              let origin = session.dragOriginSurface else {
            return
        }

        let rawTranslation = finite(translationY)
        session.latestRawDragTranslation = rawTranslation
        let relativeTranslation = rawTranslation - session.dragTranslationOrigin
        let referenceDistance = max(
            1,
            session.geometry.collapsedFrame.midY
                - session.geometry.expandedFrame.midY
        )
        // `referenceDistance` is intentionally based on endpoint centres for
        // release/progress math, but it is far too short to bound the direct
        // sheet movement (roughly half a screen on a phone). Keep the card
        // under the finger until its top has travelled to the dock; only then
        // introduce downward rubber-band resistance.
        let linearDragDistance = max(
            referenceDistance,
            session.geometry.collapsedFrame.maxY
                - session.geometry.expandedFrame.minY
        )
        let adjustedTranslation = adjustedDragTranslation(
            relativeTranslation,
            referenceDistance: referenceDistance,
            linearDragDistance: linearDragDistance
        )
        let positiveProgress = max(0, relativeTranslation) / referenceDistance
        let dragProgress = positiveProgress.clamped(to: 0 ... 1)
        session.dragProgress = dragProgress

        let minimumScale = session.isReduceMotionEnabled
            ? configuration.reduceMotionMinimumDragScale
            : configuration.minimumDragScale
        let scaleProgress = smoothstep(0, 0.78, dragProgress)
        let resolvedMinimumScale = finite(minimumScale, fallback: 1)
            .clamped(to: 0.8 ... 1)
        let scale = 1 - (1 - resolvedMinimumScale) * scaleProgress
        let scaledWidth = max(1, origin.bounds.width * scale)
        let scaledHeight = max(1, origin.bounds.height * scale)
        // Keep the surface's top edge (and therefore a top grabber) under the
        // finger. Center-scaling would add half the height loss to the visible
        // translation and make a nominally 1:1 drag feel slippery.
        let topAnchoringOffset = (origin.bounds.height - scaledHeight) * 0.5
        let dragCornerProgress = smoothstep(0, 0.065, dragProgress)
        let surface = BottomBarAccessorySurfaceGeometry(
            position: CGPoint(
                x: origin.position.x,
                y: origin.position.y + adjustedTranslation - topAnchoringOffset
            ),
            bounds: CGRect(
                origin: origin.bounds.origin,
                size: CGSize(
                    width: scaledWidth,
                    height: scaledHeight
                )
            ),
            cornerRadius: max(
                0,
                origin.cornerRadius
                    + finite(
                        configuration.dragCornerRadiusIncrease,
                        fallback: 0
                    ) * dragCornerProgress
            )
        )

        let arcPhase = Self.sharedElementArcPhase(
            for: surface,
            geometry: session.geometry
        )
        session.dragArcPhase = arcPhase

        applySurfaceGeometry(surface)
        sharedElementTransition.updateInteractiveDrag(
            progress: dragProgress,
            previewAmount: finite(
                configuration.dragSharedElementPreview,
                fallback: 0
            ),
            collapseArcPhase: arcPhase,
            surfaceOriginDeltaInContainer: CGPoint(
                x: surface.frame.minX - origin.frame.minX,
                y: surface.frame.minY - origin.frame.minY
            )
        )
        publishCurrentState(surface: surface)
    }

    /// Resolves only after gesture release, then continues from the captured
    /// presentation geometry with the real gesture velocity.
    @discardableResult
    func endDrag(
        translationY: CGFloat,
        velocityY: CGFloat,
        reason: BottomBarAccessoryGestureEndReason
    ) -> BottomBarAccessoryReleaseTarget {
        guard state == .dragging, let session else {
            return state == .collapsed ? .collapsed : .expanded
        }

        updateDrag(translationY: translationY)
        let gestureTranslation = finite(translationY)
            - session.dragTranslationOrigin
        // A gesture may catch an already moving settle, or its translation
        // origin may be rebased during a scroll/rotation handoff. Resolve from
        // the card's actual final top edge when available so a card caught
        // near the collapsed slot does not incorrectly spring all the way back
        // merely because the newest recognizer translation is small.
        let visualTranslation = currentSurfaceGeometry().map {
            $0.frame.minY - session.geometry.expandedFrame.minY
        }
        let releaseTranslation = visualTranslation.flatMap { value in
            value.isFinite ? value : nil
        } ?? gestureTranslation
        let input = BottomBarAccessoryReleaseInput(
            translationY: releaseTranslation,
            velocityY: finite(velocityY),
            expandedFrame: session.geometry.expandedFrame,
            collapsedFrame: session.geometry.collapsedFrame,
            containerSize: session.geometry.layoutSize,
            endReason: reason
        )
        let target = BottomBarAccessoryReleaseResolver.resolve(
            input,
            configuration: configuration
        )
        settle(to: target, initialVelocity: finite(velocityY))
        return target
    }

    /// Programmatic and gesture releases share this single settle path.
    func settle(
        to target: BottomBarAccessoryReleaseTarget,
        initialVelocity: CGFloat = 0
    ) {
        guard let session else { return }

        let wasRetargetingAnimator = geometryAnimator != nil
        let inheritedVelocityY = estimatedVelocityY
        let inheritedTopVelocityY = estimatedTopVelocityY
        let inheritedBottomVelocityY = estimatedBottomVelocityY
        let stateBeforeSettle = state
        let captured = captureCurrentPresentation() ?? currentSurfaceGeometry()
        guard captured?.isValid == true else { return }

        // Programmatic reversals do not have a fresh gesture velocity. Inherit
        // the presentation velocity of the interrupted spring so the surface
        // remains C1-continuous instead of visibly pausing at the retarget.
        // A gesture release comes from `.dragging`, where no animator is
        // active, so an explicit zero remains an intentional zero.
        let requestedVelocityY = finite(initialVelocity)
        let resolvedVelocityY: CGFloat
        let resolvedTopVelocityY: CGFloat
        let resolvedBottomVelocityY: CGFloat
        if wasRetargetingAnimator,
           abs(requestedVelocityY) <= 0.001,
           inheritedVelocityY.isFinite {
            resolvedVelocityY = inheritedVelocityY
            resolvedTopVelocityY = inheritedTopVelocityY
            resolvedBottomVelocityY = inheritedBottomVelocityY
        } else if stateBeforeSettle == .dragging,
                  let visualVelocity = resolvedDragBoundaryVelocities(
                      rawVelocityY: requestedVelocityY,
                      session: session
                  ) {
            // The recognizer reports finger velocity before Aether's
            // rubber-band and optional bounds scaling. Seed the settle with
            // the derivative of the geometry that was actually under the
            // finger. Opening/cancel paths inherit that derivative; an
            // ordinary collapse intentionally switches both boundaries to
            // their fixed measured reference responses.
            resolvedTopVelocityY = visualVelocity.top
            resolvedBottomVelocityY = visualVelocity.bottom
            resolvedVelocityY = (visualVelocity.top + visualVelocity.bottom) * 0.5
        } else {
            resolvedVelocityY = requestedVelocityY
            resolvedTopVelocityY = requestedVelocityY
            resolvedBottomVelocityY = requestedVelocityY
        }
        let seedsProgrammaticCollapseLaunch = target == .collapsed
            && stateBeforeSettle == .expanded
            && !wasRetargetingAnimator
            && abs(requestedVelocityY) <= 0.001
        let preservesBoundaryVelocities = wasRetargetingAnimator
            || stateBeforeSettle == .dragging
        // A finger release always replays the measured collapse responses.
        // Only a running animator retarget has presentation derivatives that
        // must remain C1 on the independent top and bottom edges.
        let preservesTopBoundaryVelocity = wasRetargetingAnimator
        let preservesBottomBoundaryVelocity = wasRetargetingAnimator

        session.target = target

        let event: BottomBarAccessoryTransitionStateEvent
        if state == .dragging {
            event = .settle(target)
        } else {
            event = target == .expanded ? .requestExpansion : .requestCollapse
        }
        guard transitionState(with: event) else { return }

        if !isParticipantTransitionActive {
            let currentProgress = session.geometry.presentationProgress(for: captured!)
            prepareParticipants(
                initialEndpoint: currentProgress >= 0.5 ? .expanded : .collapsed
            )
        }
        startAnimator(
            to: target,
            initialVelocityY: resolvedVelocityY,
            initialTopVelocityY: resolvedTopVelocityY,
            initialBottomVelocityY: resolvedBottomVelocityY,
            preservesBoundaryVelocities: preservesBoundaryVelocities,
            preservesTopBoundaryVelocity: preservesTopBoundaryVelocity,
            preservesBottomBoundaryVelocity: preservesBottomBoundaryVelocity,
            seedsProgrammaticCollapseLaunch: seedsProgrammaticCollapseLaunch,
            prefersProvidedSharedElementVelocity: stateBeforeSettle == .dragging,
            sharedElementArcOriginPhase: stateBeforeSettle == .dragging
                ? session.dragArcPhase
                : nil
        )
    }

    /// Replaces endpoint geometry after rotation/resize. Active animation and
    /// drag paths preserve their current on-screen position before retargeting.
    func updateGeometry(
        _ geometry: BottomBarAccessoryTransitionGeometry,
        preservingVisualState: Bool = true
    ) {
        guard geometry.isValid, let session else { return }

        let activeTarget = session.target
        let wasAnimating = geometryAnimator != nil
        let wasDragging = state == .dragging
        let preservedVelocity = estimatedVelocityY
        let preservedTopVelocity = estimatedTopVelocityY
        let preservedBottomVelocity = estimatedBottomVelocityY
        let shouldCapture = preservingVisualState || wasAnimating || wasDragging
        let capturedVisual = shouldCapture
            ? (captureCurrentPresentation() ?? currentSurfaceGeometry())
            : nil
        let oldPresentationProgress = capturedVisual.map {
            session.geometry.presentationProgress(for: $0)
        }
        let captured: BottomBarAccessorySurfaceGeometry?
        if preservingVisualState {
            captured = capturedVisual
        } else if let oldPresentationProgress {
            captured = geometry.surfaceGeometry(at: oldPresentationProgress)
        } else {
            captured = nil
        }

        session.geometry = geometry
        if let surfaceView, let containerView {
            sharedElementTransition.refreshEndpointGeometry(
                geometry,
                surfaceView: surfaceView,
                containerView: containerView
            )
        }

        if wasDragging, let captured, captured.isValid {
            session.dragOriginSurface = captured
            session.dragOriginPresentationProgress = geometry
                .presentationProgress(for: captured)
            let arcPhase = Self.sharedElementArcPhase(
                for: captured,
                geometry: geometry
            )
            session.dragOriginArcPhase = arcPhase
            session.dragArcPhase = arcPhase
            session.dragTranslationOrigin = session.latestRawDragTranslation
            session.dragProgress = 0
            sharedElementTransition.beginInteractiveDrag(
                collapseArcPhase: arcPhase
            )
            applySurfaceGeometry(captured)
            publishCurrentState(surface: captured)
            return
        }

        if wasAnimating, let target = activeTarget, let captured, captured.isValid {
            applySurfaceGeometry(captured)
            startAnimator(
                to: target,
                initialVelocityY: preservedVelocity,
                initialTopVelocityY: preservedTopVelocity,
                initialBottomVelocityY: preservedBottomVelocity,
                preservesBoundaryVelocities: true,
                preservesTopBoundaryVelocity: true,
                preservesBottomBoundaryVelocity: true
            )
            return
        }

        let endpoint: BottomBarAccessoryReleaseTarget = state == .collapsed
            ? .collapsed
            : .expanded
        let endpointSurface = geometry.surfaceGeometry(
            at: endpoint == .expanded ? 1 : 0
        )
        applySurfaceGeometry(endpointSurface)
        applyStableContentState(endpoint)
        publishCurrentState(surface: endpointSurface)
    }

    /// Commits presentation values into the model layer and invalidates the
    /// current animator without running its stale completion.
    @discardableResult
    func captureCurrentPresentation() -> BottomBarAccessorySurfaceGeometry? {
        let captured = currentSurfaceGeometry()
        let capturedOpacity = currentSurfaceOpacity()
        // Native glass children own synchronized compositor groups beside the
        // outer surface. Capture them before any root animation is removed so
        // a reversal starts from the exact visible material geometry/opacity.
        (surfaceView as? GlassBackgroundView)?
            .captureTransitionCompositorPresentation(
                owner: glassCompositorOwner
            )
        captureEndpointContentPresentation()
        let animator = geometryAnimator
        geometryAnimator = nil

        if animator?.state == .active {
            animator?.pauseAnimation()
        }
        if let captured,
           let session,
           !session.isReduceMotionEnabled {
            // Bring the single transition representation to the exact same
            // presentation sample before an interrupt/retarget takes over.
            // This closes the sub-frame gap between the last display-link tick
            // and the surface capture without creating a second animation.
            sharedElementTransition.updateSettle(
                presentationProgress: session.geometry
                    .presentationProgress(for: captured)
            )
        }
        sharedElementTransition.captureCurrentPresentation()
        hasCompositorContentTrack = false
        animator?.stopAnimation(true)
        stopDisplayLink()

        if let captured, captured.isValid {
            applySurfaceGeometry(captured, removingAnimations: true)
        }
        if let capturedOpacity {
            applySurfaceOpacity(capturedOpacity)
        }
        return captured
    }

    /// Immediately terminates the active session at a deterministic endpoint.
    func reset(to target: BottomBarAccessoryReleaseTarget) {
        let oldSession = session
        _ = captureCurrentPresentation()
        stateMachine.handle(.reset(target))
        oldSession?.target = target

        if let geometry = oldSession?.geometry, geometry.isValid {
            applySurfaceGeometry(
                geometry.surfaceGeometry(at: target == .expanded ? 1 : 0),
                removingAnimations: true
            )
        }
        applySurfaceOpacity(1)
        applyStableContentState(target)
        if let geometry = oldSession?.geometry {
            let surface = geometry.surfaceGeometry(at: target == .expanded ? 1 : 0)
            publishCurrentState(surface: surface, phaseOverride: .completed)
        }
        sharedElementTransition.complete(at: target)
        completeParticipants(at: target)
        delegate?.bottomBarAccessoryTransitionCoordinator(
            self,
            didChangeState: state
        )
        delegate?.bottomBarAccessoryTransitionCoordinator(self, didComplete: target)
    }

    // MARK: - Animator

    private func startAnimator(
        to target: BottomBarAccessoryReleaseTarget,
        initialVelocityY: CGFloat,
        initialTopVelocityY: CGFloat? = nil,
        initialBottomVelocityY: CGFloat? = nil,
        preservesBoundaryVelocities: Bool = false,
        preservesTopBoundaryVelocity: Bool = false,
        preservesBottomBoundaryVelocity: Bool = false,
        seedsProgrammaticCollapseLaunch: Bool = false,
        prefersProvidedSharedElementVelocity: Bool = false,
        sharedElementArcOriginPhase: CGFloat? = nil
    ) {
        guard let session,
              let current = currentSurfaceGeometry(),
              current.isValid else {
            return
        }

        if geometryAnimator != nil {
            _ = captureCurrentPresentation()
        }
        let configuredMaximumVelocity = configuration.maximumResolvedVelocity
        let maximumVelocity = configuredMaximumVelocity.isFinite
            ? max(0, configuredMaximumVelocity)
            : 7_000
        let velocityRange = -maximumVelocity ... maximumVelocity
        let resolvedInitialVelocityY = finite(initialVelocityY)
            .clamped(to: velocityRange)
        let resolvedInitialTopVelocityY = finite(
            initialTopVelocityY ?? resolvedInitialVelocityY
        ).clamped(to: velocityRange)
        let resolvedInitialBottomVelocityY = finite(
            initialBottomVelocityY ?? resolvedInitialVelocityY
        ).clamped(to: velocityRange)
        session.target = target
        settleOriginCollapsedAlpha = collapsedContentHost?.alpha ?? 0
        settleOriginExpandedAlpha = expandedContentHost?.alpha ?? 1
        hasCompositorContentTrack = false
        currentSettleProgress = 0
        resetVelocitySampling(
            surface: current,
            initialVelocityY: resolvedInitialVelocityY,
            initialTopVelocityY: resolvedInitialTopVelocityY,
            initialBottomVelocityY: resolvedInitialBottomVelocityY
        )

        let targetSurface = session.geometry.surfaceGeometry(
            at: target == .expanded ? 1 : 0
        )
        let animatedTargetSurface = session.isReduceMotionEnabled
            ? configuration.reducedMotionSettleSurface(
                from: current,
                toward: targetSurface
            )
            : targetSurface
        let nonReducedDuration: TimeInterval?
        if session.isReduceMotionEnabled {
            nonReducedDuration = nil
        } else {
            let oppositeSurface = session.geometry.surfaceGeometry(
                at: target == .collapsed ? 1 : 0
            )
            let configuredDuration = target == .collapsed
                ? configuration.collapseDuration
                : configuration.expansionDuration
            let fallbackDuration: TimeInterval = 0.40
            let baseDuration = configuredDuration.isFinite
                ? max(0.01, configuredDuration)
                : fallbackDuration

            if Self.maximumGeometryDelta(from: current, to: targetSurface) <= 1,
               abs(resolvedInitialVelocityY) <= 60 {
                // A caught transition can be released when its presentation
                // is already indistinguishable from Mini. Committing now
                // avoids leaving a visually absent surface as a 433ms input
                // shield while preserving the full reference clock for every
                // release whose bottom/width/height still has real work.
                finish(at: target)
                return
            }
            nonReducedDuration = Self.resolvedSettleDuration(
                from: current,
                to: targetSurface,
                opposite: oppositeSurface,
                baseDuration: baseDuration,
                initialVelocityY: resolvedInitialVelocityY
            )
        }
        if !session.isReduceMotionEnabled {
            let resolvedArcOriginPhase = sharedElementArcOriginPhase.flatMap {
                $0.isFinite ? $0.clamped(to: 0 ... 1) : nil
            } ?? Self.sharedElementArcPhase(
                for: current,
                geometry: session.geometry
            )
            sharedElementTransition.beginSettle(
                to: target,
                fromPresentationProgress: session.geometry
                    .presentationProgress(for: current),
                fromCollapseArcPhase: resolvedArcOriginPhase,
                initialVelocityY: resolvedInitialTopVelocityY,
                prefersProvidedInitialVelocity:
                    prefersProvidedSharedElementVelocity
                        || preservesBoundaryVelocities,
                usesReferenceCollapseLaunch: target == .collapsed
                    && (!preservesBoundaryVelocities
                        || prefersProvidedSharedElementVelocity),
                verticalSpring: configuration.sharedElementVerticalSpring
            )
        }
        resolvedSettlingInitialVelocityY = resolvedInitialVelocityY
        resolvedSettlingInitialTopVelocityY = resolvedInitialTopVelocityY
        resolvedSettlingInitialBottomVelocityY = resolvedInitialBottomVelocityY
        var deferredSurfaceGeometryTrack: (
            origin: BottomBarAccessorySurfaceGeometry,
            target: BottomBarAccessorySurfaceGeometry,
            releaseTarget: BottomBarAccessoryReleaseTarget,
            initialVelocityY: CGFloat,
            initialTopVelocityY: CGFloat,
            initialBottomVelocityY: CGFloat,
            preservesBoundaryVelocities: Bool,
            preservesTopBoundaryVelocity: Bool,
            preservesBottomBoundaryVelocity: Bool,
            seedsProgrammaticCollapseLaunch: Bool,
            duration: TimeInterval
        )?
        let animator: UIViewPropertyAnimator
        if session.isReduceMotionEnabled {
            let remainingY = max(
                abs(animatedTargetSurface.position.y - current.position.y),
                1
            )
            let maximumNormalizedVelocity = max(
                0,
                finite(
                    configuration.maximumNormalizedSpringVelocity,
                    fallback: 12
                )
            )
            let normalizedVelocityY = (resolvedInitialVelocityY / remainingY)
                .clamped(
                    to: -maximumNormalizedVelocity ... maximumNormalizedVelocity
                )
            let timing = configuration.reduceMotionSpring.timingParameters(
                initialVelocity: CGVector(dx: 0, dy: normalizedVelocityY)
            )
            animator = UIViewPropertyAnimator(duration: 0, timingParameters: timing)
        } else {
            let duration = nonReducedDuration ?? 0.01
            animator = UIViewPropertyAnimator(
                duration: duration,
                curve: .linear
            )
        }
        animator.isInterruptible = true
        animator.isUserInteractionEnabled = true
        animator.scrubsLinearly = false
        reducedMotionHandoffDuration = nil
        animationClockView.layer.removeAllAnimations()
        animationClockView.alpha = 0
        // A real property animation keeps the coordinator's sole timing
        // animator authoritative even though Reduce Motion renders geometry
        // with one synchronized CAAnimationGroup on the surface layer.
        animator.addAnimations { [weak self] in
            self?.animationClockView.alpha = 1
        }

        if session.isReduceMotionEnabled {
            (surfaceView as? GlassBackgroundView)?
                .discardPendingTransitionCompositorPresentation(
                    owner: glassCompositorOwner
                )
            reducedMotionHandoffDuration = max(animator.duration, 0.01)
            installReducedMotionHandoff(
                from: current,
                through: animatedTargetSurface,
                to: targetSurface,
                duration: reducedMotionHandoffDuration ?? 0.01
            )
        } else {
            // UIKit remains the one interruptible completion clock. Surface
            // geometry is installed as a single synchronized keyframe group
            // after that clock starts, allowing the two vertical boundaries
            // to follow different curves without introducing a second view or
            // a second lifecycle owner.
            deferredSurfaceGeometryTrack = (
                current,
                animatedTargetSurface,
                target,
                resolvedInitialVelocityY,
                resolvedInitialTopVelocityY,
                resolvedInitialBottomVelocityY,
                preservesBoundaryVelocities,
                preservesTopBoundaryVelocity,
                preservesBottomBoundaryVelocity,
                seedsProgrammaticCollapseLaunch,
                max(animator.duration, 0.01)
            )
            // Prevent the display-link publication immediately below from
            // replacing the captured host opacities. The synchronized
            // compositor track is installed with the surface after UIKit's
            // authoritative lifecycle clock starts.
            hasCompositorContentTrack = true
        }

        animator.addCompletion { [weak self, weak animator] position in
            guard let self,
                  let animator,
                  self.geometryAnimator === animator else {
                return
            }
            self.geometryAnimator = nil
            self.stopDisplayLink()
            guard position == .end else { return }
            self.finish(at: target)
        }

        geometryAnimator = animator
        startDisplayLink()
        publishCurrentState(surface: current)
        animator.startAnimation()
        // Start the authoritative clock first: UIKit commits property animator
        // transactions at this point and could otherwise discard a surface
        // group installed in the same transaction. The first group keyframe is
        // the exact captured presentation geometry, so this remains visually
        // continuous on release, reversal, rotation, and Reduce Motion changes.
        if let deferredSurfaceGeometryTrack {
            installSurfaceGeometryTrack(
                from: deferredSurfaceGeometryTrack.origin,
                to: deferredSurfaceGeometryTrack.target,
                target: deferredSurfaceGeometryTrack.releaseTarget,
                initialVelocityY: deferredSurfaceGeometryTrack.initialVelocityY,
                initialTopVelocityY: deferredSurfaceGeometryTrack.initialTopVelocityY,
                initialBottomVelocityY: deferredSurfaceGeometryTrack.initialBottomVelocityY,
                preservesBoundaryVelocities: deferredSurfaceGeometryTrack
                    .preservesBoundaryVelocities,
                preservesTopBoundaryVelocity: deferredSurfaceGeometryTrack
                    .preservesTopBoundaryVelocity,
                preservesBottomBoundaryVelocity: deferredSurfaceGeometryTrack
                    .preservesBottomBoundaryVelocity,
                seedsProgrammaticCollapseLaunch: deferredSurfaceGeometryTrack
                    .seedsProgrammaticCollapseLaunch,
                duration: deferredSurfaceGeometryTrack.duration
            )
        }
    }

    private func finish(at target: BottomBarAccessoryReleaseTarget) {
        guard let session else { return }
        stateMachine.handle(.complete(target))
        session.target = target
        currentSettleProgress = 1
        hasCompositorContentTrack = false

        let surface = session.geometry.surfaceGeometry(
            at: target == .expanded ? 1 : 0
        )
        applySurfaceGeometry(surface, removingAnimations: true)
        applySurfaceOpacity(1)
        applyStableContentState(target)
        publishCurrentState(surface: surface, phaseOverride: .completed)
        (surfaceView as? GlassBackgroundView)?
            .completeTransitionCompositorSettleTrack(
                owner: glassCompositorOwner
            )
        sharedElementTransition.complete(at: target)
        completeParticipants(at: target)

        delegate?.bottomBarAccessoryTransitionCoordinator(
            self,
            didChangeState: state
        )
        delegate?.bottomBarAccessoryTransitionCoordinator(self, didComplete: target)
    }

    // MARK: - Participants and sampling

    private func prepareParticipants(initialEndpoint: BottomBarAccessoryReleaseTarget) {
        guard let session else { return }
        let surface = currentSurfaceGeometry()
            ?? session.geometry.surfaceGeometry(
                at: initialEndpoint == .expanded ? 1 : 0
            )
        let context = makeContext(surface: surface, phaseOverride: .preparing)
        session.collapsedParticipant?.prepareBottomBarAccessoryTransition(context)
        session.expandedParticipant?.prepareBottomBarAccessoryTransition(context)
        prepareSharedElements(
            surface: surface,
            initialEndpoint: initialEndpoint,
            context: context
        )
        isParticipantTransitionActive = true
    }

    private func prepareSharedElements(
        surface: BottomBarAccessorySurfaceGeometry,
        initialEndpoint: BottomBarAccessoryReleaseTarget,
        context providedContext: BottomBarAccessoryTransitionContext? = nil
    ) {
        guard let session,
              let sharedElementHost,
              let surfaceView,
              let containerView else {
            return
        }
        let context = providedContext
            ?? makeContext(surface: surface, phaseOverride: .preparing)
        sharedElementHost.layoutIfNeeded()
        sharedElementTransition.prepare(
            collapsedParticipant: session.collapsedParticipant,
            expandedParticipant: session.expandedParticipant,
            context: context,
            surfaceView: surfaceView,
            containerView: containerView,
            in: sharedElementHost,
            initialEndpoint: initialEndpoint
        )
    }

    private func completeParticipants(at target: BottomBarAccessoryReleaseTarget) {
        guard isParticipantTransitionActive,
              let session else { return }
        let surface = session.geometry.surfaceGeometry(
            at: target == .expanded ? 1 : 0
        )
        let context = makeContext(surface: surface, phaseOverride: .completed)
        session.collapsedParticipant?.completeBottomBarAccessoryTransition(context)
        session.expandedParticipant?.completeBottomBarAccessoryTransition(context)
        isParticipantTransitionActive = false
    }

    fileprivate func displayLinkDidFire(_ displayLink: CADisplayLink) {
        guard let surface = currentSurfaceGeometry() else { return }
        if let session, !session.isReduceMotionEnabled {
            // Geometry for the transition representation is compositor-owned.
            // The display link only samples it for interruption continuity and
            // refreshes content identity; it never writes artwork geometry.
            _ = session
            sharedElementTransition.samplePresentation()
        } else {
            sharedElementTransition.samplePresentation()
        }
        if let previousTimestamp = lastSampleTimestamp,
           let previousPositionY = lastSamplePositionY,
           let previousMinY = lastSampleMinY,
           let previousMaxY = lastSampleMaxY {
            let deltaTime = displayLink.timestamp - previousTimestamp
            if deltaTime > 0.000_1 {
                estimatedVelocityY = (surface.position.y - previousPositionY)
                    / CGFloat(deltaTime)
                estimatedTopVelocityY = (surface.frame.minY - previousMinY)
                    / CGFloat(deltaTime)
                estimatedBottomVelocityY = (surface.frame.maxY - previousMaxY)
                    / CGFloat(deltaTime)
            }
        }
        lastSampleTimestamp = displayLink.timestamp
        lastSamplePositionY = surface.position.y
        lastSampleMinY = surface.frame.minY
        lastSampleMaxY = surface.frame.maxY
        currentSettleProgress = geometryAnimator?.fractionComplete
            .clamped(to: 0 ... 1) ?? currentSettleProgress
        publishCurrentState(surface: surface)
    }

    private func publishCurrentState(
        surface: BottomBarAccessorySurfaceGeometry,
        phaseOverride: BottomBarAccessoryTransitionPhase? = nil
    ) {
        guard session != nil else { return }
        lastPresentedSurfaceGeometry = surface
        let context = makeContext(surface: surface, phaseOverride: phaseOverride)
        currentContext = context
        applyContentChoreography(context)
        session?.collapsedParticipant?.updateBottomBarAccessoryTransition(context)
        session?.expandedParticipant?.updateBottomBarAccessoryTransition(context)
        delegate?.bottomBarAccessoryTransitionCoordinator(
            self,
            didUpdateSurfaceGeometry: surface,
            context: context
        )
    }

    private func makeContext(
        surface: BottomBarAccessorySurfaceGeometry,
        phaseOverride: BottomBarAccessoryTransitionPhase? = nil
    ) -> BottomBarAccessoryTransitionContext {
        guard let session else {
            preconditionFailure("A transition context requires an active session")
        }
        return BottomBarAccessoryTransitionContext(
            sessionIdentifier: session.identifier,
            state: state,
            phase: phaseOverride ?? phase(for: state),
            presentationProgress: session.geometry.presentationProgress(for: surface),
            settleProgress: currentSettleProgress,
            dragProgress: session.dragProgress,
            isInteractive: state == .dragging,
            isReduceMotionEnabled: session.isReduceMotionEnabled,
            target: session.target,
            geometry: session.geometry,
            dockingContext: session.dockingContext
        )
    }

    private func applyContentChoreography(
        _ context: BottomBarAccessoryTransitionContext
    ) {
        let collapsedAlpha: CGFloat
        let expandedAlpha: CGFloat

        if context.isReduceMotionEnabled,
           !context.isInteractive,
           context.state != .collapsed,
           context.state != .expanded {
            // In reduced motion the two independent endpoint trees provide
            // the visual continuity. Crossfade them across the entire short
            // settle rather than staging an artwork/card morph.
            let progress = smoothstep(0, 1, context.settleProgress)
            switch context.target {
            case .collapsed:
                expandedAlpha = settleOriginExpandedAlpha * (1 - progress)
                collapsedAlpha = settleOriginCollapsedAlpha
                    + (1 - settleOriginCollapsedAlpha) * progress
            case .expanded:
                collapsedAlpha = settleOriginCollapsedAlpha * (1 - progress)
                expandedAlpha = settleOriginExpandedAlpha
                    + (1 - settleOriginExpandedAlpha) * progress
            case nil:
                collapsedAlpha = settleOriginCollapsedAlpha
                expandedAlpha = settleOriginExpandedAlpha
            }
        } else {
        switch context.state {
        case .collapsed:
            collapsedAlpha = 1
            expandedAlpha = 0
        case .expanded:
            collapsedAlpha = 0
            expandedAlpha = 1
        case .dragging:
            collapsedAlpha = dragOriginCollapsedAlpha
                * (1 - context.dragProgress)
            // Keep the non-art expanded plane on the same geometry-owned C2
            // clock used by settle. Pinning it to its drag-origin alpha left a
            // deep drag at alpha one and forced a corrective fade immediately
            // after release, which read as another velocity stop.
            expandedAlpha = Self.expandedContentPlaneAlpha(
                presentationProgress: context.presentationProgress
            )
        case .settlingToCollapsed:
            expandedAlpha = Self.expandedContentPlaneAlpha(
                presentationProgress: context.presentationProgress
            )
            collapsedAlpha = Self.collapsedContentPlaneAlpha(
                presentationProgress: context.presentationProgress
            )
        case .expanding, .settlingToExpanded:
            collapsedAlpha = Self.collapsedContentPlaneAlpha(
                presentationProgress: context.presentationProgress
            )
            expandedAlpha = Self.expandedContentPlaneAlpha(
                presentationProgress: context.presentationProgress
            )
        }
        }

        if !hasCompositorContentTrack {
            withoutImplicitAnimations {
                collapsedContentHost?.alpha = collapsedAlpha.clamped(to: 0 ... 1)
                expandedContentHost?.alpha = expandedAlpha.clamped(to: 0 ... 1)
            }
        }
        updateInteraction(context)
    }

    private func updateInteraction(_ context: BottomBarAccessoryTransitionContext) {
        let collapsedIsInteractive = context.state == .collapsed
            && context.presentationProgress
                <= finite(
                    configuration.collapsedInteractionProgress,
                    fallback: 0.12
                ).clamped(to: 0 ... 1)
        let expandedIsInteractive = context.state == .expanded
            && context.presentationProgress
                >= finite(
                    configuration.expandedInteractionProgress,
                    fallback: 0.85
                ).clamped(to: 0 ... 1)

        if collapsedContentHost?.isUserInteractionEnabled != collapsedIsInteractive {
            collapsedContentHost?.isUserInteractionEnabled = collapsedIsInteractive
        }
        if collapsedContentHost?.accessibilityElementsHidden
            != !collapsedIsInteractive {
            collapsedContentHost?.accessibilityElementsHidden = !collapsedIsInteractive
        }
        if expandedContentHost?.isUserInteractionEnabled != expandedIsInteractive {
            expandedContentHost?.isUserInteractionEnabled = expandedIsInteractive
        }
        if expandedContentHost?.accessibilityElementsHidden
            != !expandedIsInteractive {
            expandedContentHost?.accessibilityElementsHidden = !expandedIsInteractive
        }
    }

    /// The expanded endpoint tree is a clear layout plane whose participant
    /// owns its own backdrop/content staging. Its C2 fade completes before the
    /// compact material starts leaving, avoiding both a tab-screen gap and a
    /// fullscreen white-glass veil.
    static func expandedContentPlaneAlpha(
        presentationProgress: CGFloat
    ) -> CGFloat {
        smootherstep(
            (presentationProgress / 0.08).clamped(to: 0 ... 1)
        )
    }

    /// The compact controls remain readable through the first half of the
    /// morph, as in the system player, and return before the collapsing card
    /// reaches its dock. Geometry—not elapsed wall time—owns this handoff.
    static func collapsedContentPlaneAlpha(
        presentationProgress: CGFloat
    ) -> CGFloat {
        1 - transitionSmoothstep(
            0.40,
            0.72,
            presentationProgress
        )
    }

    static func resolvedCollapsedContentPlaneAlpha(
        presentationProgress: CGFloat,
        originAlpha: CGFloat,
        settleProgress: CGFloat
    ) -> CGFloat {
        // Retargeting captures the same presentation geometry, so a
        // geometry-owned alpha is already continuous. Gating it on the
        // animator's separate timing fraction made endpoint planes freeze and
        // then snap in on completion.
        collapsedContentPlaneAlpha(
            presentationProgress: presentationProgress
        )
    }

    /// Retargets keep the exact captured alpha on their first sample, then
    /// converge quickly to the geometry-owned plane. This avoids a flash when
    /// a spring is interrupted, reversed, or rebuilt after a lifecycle change.
    static func resolvedExpandedContentPlaneAlpha(
        presentationProgress: CGFloat,
        originAlpha: CGFloat,
        settleProgress: CGFloat
    ) -> CGFloat {
        expandedContentPlaneAlpha(
            presentationProgress: presentationProgress
        )
    }

    private static func transitionSmoothstep(
        _ lowerBound: CGFloat,
        _ upperBound: CGFloat,
        _ value: CGFloat
    ) -> CGFloat {
        guard upperBound > lowerBound else {
            return value >= upperBound ? 1 : 0
        }
        let progress = min(
            max((value - lowerBound) / (upperBound - lowerBound), 0),
            1
        )
        return progress * progress * (3 - 2 * progress)
    }

    /// Optical glass uses one broad C2 handoff after the expanded backdrop is
    /// fully available. The former `.30 ... .38` pulse crossed in only a few
    /// native frames and looked like the blur radius itself changed; carrying
    /// material as far as the compact-content `.40 ... .72` fade instead made
    /// a large/fullscreen white veil. This interval avoids both artifacts.
    static func transitionMaterialAlpha(
        presentationProgress: CGFloat
    ) -> CGFloat {
        1 - smootherstep(
            ((presentationProgress - 0.08) / 0.32)
                .clamped(to: 0 ... 1)
        )
    }

    private static func smootherstep(_ value: CGFloat) -> CGFloat {
        let progress = value.clamped(to: 0 ... 1)
        return progress * progress * progress
            * (progress * (progress * 6 - 15) + 10)
    }

    // MARK: - Geometry

    private func currentSurfaceGeometry() -> BottomBarAccessorySurfaceGeometry? {
        guard let surfaceView,
              let containerView,
              let superview = surfaceView.superview else {
            return nil
        }
        let layer: CALayer
        if let presentation = surfaceView.layer.presentation() {
            layer = presentation
        } else if geometryAnimator != nil,
                  let lastPresentedSurfaceGeometry {
            return lastPresentedSurfaceGeometry
        } else {
            layer = surfaceView.layer
        }
        let position = superview.convert(layer.position, to: containerView)
        let geometry = BottomBarAccessorySurfaceGeometry(
            position: position,
            bounds: layer.bounds,
            cornerRadius: layer.cornerRadius
        )
        return geometry.isValid ? geometry : nil
    }

    static func expansionGeometryProgress(
        at linearProgress: CGFloat,
        configuration: BottomBarAccessoryTransitionConfiguration = .default
    ) -> CGFloat {
        let masterProgress = linearProgress.isFinite
            ? linearProgress.clamped(to: 0 ... 1)
            : 0
        let masterDuration = configuration.expansionDuration.isFinite
            ? max(0.01, configuration.expansionDuration)
            : 0.40
        let geometryDuration = configuration.expansionGeometryDuration.isFinite
            ? max(0.01, configuration.expansionGeometryDuration)
            : 0.40
        let settleTime = min(masterDuration, geometryDuration)
        let tailStart = min(16.0 / 60.0, settleTime * 0.70)
        return terminallySettledSpringProgress(
            at: TimeInterval(masterProgress) * masterDuration,
            spring: configuration.expandSpring,
            delay: 0,
            tailStart: tailStart,
            settleTime: settleTime
        )
        .clamped(to: 0 ... 1)
    }

    /// The lower opening edge is an independent overdamped response. A short
    /// sub-frame delay anchors it during the top edge's launch; a quintic
    /// terminal segment then lands position, velocity, and acceleration at the
    /// same real endpoint instead of stretching sampled checkpoints to 0.50s.
    static func expansionBottomProgress(
        at linearProgress: CGFloat,
        configuration: BottomBarAccessoryTransitionConfiguration = .default
    ) -> CGFloat {
        let progress = linearProgress.isFinite
            ? linearProgress.clamped(to: 0 ... 1)
            : 0
        let masterDuration = configuration.expansionDuration.isFinite
            ? max(0.01, configuration.expansionDuration)
            : 0.40
        let geometryDuration = configuration.expansionGeometryDuration.isFinite
            ? max(0.01, configuration.expansionGeometryDuration)
            : 0.40
        let settleTime = min(masterDuration, geometryDuration)
        let anchorDelay = min(0.8 / 60.0, settleTime * 0.08)
        let tailStart = min(13.0 / 60.0, settleTime * 0.62)
        return terminallySettledSpringProgress(
            at: TimeInterval(progress) * masterDuration,
            spring: .init(mass: 1, stiffness: 423, damping: 46.8),
            delay: anchorDelay,
            tailStart: tailStart,
            settleTime: settleTime
        ).clamped(to: 0 ... 1)
    }

    static func maximumGeometryDelta(
        from current: BottomBarAccessorySurfaceGeometry,
        to target: BottomBarAccessorySurfaceGeometry
    ) -> CGFloat {
        let currentFrame = current.frame
        let targetFrame = target.frame
        return [
            abs(currentFrame.minX - targetFrame.minX),
            abs(currentFrame.minY - targetFrame.minY),
            abs(currentFrame.maxX - targetFrame.maxX),
            abs(currentFrame.maxY - targetFrame.maxY),
            abs(currentFrame.width - targetFrame.width),
            abs(currentFrame.height - targetFrame.height),
            abs(current.bounds.origin.x - target.bounds.origin.x),
            abs(current.bounds.origin.y - target.bounds.origin.y),
            abs(current.cornerRadius - target.cornerRadius),
        ].filter { $0.isFinite }.max() ?? .greatestFiniteMagnitude
    }

    /// Measures remaining work against the complete endpoint delta. Using both
    /// edges plus shape prevents a normally held Full card from receiving a
    /// short clock merely because its top is already close to Mini: its bottom,
    /// height, width, or radius still keeps the complete fold alive.
    static func remainingGeometryFraction(
        from current: BottomBarAccessorySurfaceGeometry,
        to target: BottomBarAccessorySurfaceGeometry,
        opposite: BottomBarAccessorySurfaceGeometry
    ) -> CGFloat {
        let currentFrame = current.frame
        let targetFrame = target.frame
        let oppositeFrame = opposite.frame
        let residualAndReference: [(CGFloat, CGFloat)] = [
            (
                abs(currentFrame.minX - targetFrame.minX),
                abs(oppositeFrame.minX - targetFrame.minX)
            ),
            (
                abs(currentFrame.minY - targetFrame.minY),
                abs(oppositeFrame.minY - targetFrame.minY)
            ),
            (
                abs(currentFrame.maxX - targetFrame.maxX),
                abs(oppositeFrame.maxX - targetFrame.maxX)
            ),
            (
                abs(currentFrame.maxY - targetFrame.maxY),
                abs(oppositeFrame.maxY - targetFrame.maxY)
            ),
            (
                abs(currentFrame.width - targetFrame.width),
                abs(oppositeFrame.width - targetFrame.width)
            ),
            (
                abs(currentFrame.height - targetFrame.height),
                abs(oppositeFrame.height - targetFrame.height)
            ),
            (
                abs(current.bounds.origin.x - target.bounds.origin.x),
                abs(opposite.bounds.origin.x - target.bounds.origin.x)
            ),
            (
                abs(current.bounds.origin.y - target.bounds.origin.y),
                abs(opposite.bounds.origin.y - target.bounds.origin.y)
            ),
            (
                abs(current.cornerRadius - target.cornerRadius),
                abs(opposite.cornerRadius - target.cornerRadius)
            ),
        ]
        return residualAndReference.reduce(CGFloat.zero) { result, pair in
            guard pair.0.isFinite, pair.1.isFinite else { return 1 }
            let normalized = pair.0 / max(1, pair.1)
            return max(result, normalized.clamped(to: 0 ... 1))
        }
    }

    static func resolvedSettleDuration(
        from current: BottomBarAccessorySurfaceGeometry,
        to target: BottomBarAccessorySurfaceGeometry,
        opposite: BottomBarAccessorySurfaceGeometry,
        baseDuration: TimeInterval,
        initialVelocityY: CGFloat
    ) -> TimeInterval {
        let resolvedBase = baseDuration.isFinite ? max(0.01, baseDuration) : 0.40
        let remaining = remainingGeometryFraction(
            from: current,
            to: target,
            opposite: opposite
        )
        let velocityFraction = initialVelocityY.isFinite
            ? min(abs(initialVelocityY) / 7_000, 1)
            : 0
        let scale = max(0.18, max(sqrt(remaining), velocityFraction))
            .clamped(to: 0.18 ... 1)
        return resolvedBase * TimeInterval(scale)
    }

    /// Analytic initial velocity of the original card's single 32-frame top
    /// response. Programmatic closes use this measured launch; an inward
    /// gesture instead seeds the same response with its captured derivative.
    static let referenceCollapseTopNormalizedVelocity: CGFloat = 9.128_67

    private struct CollapseTopVelocitySeed {
        var response: CGFloat
        var excess: CGFloat
    }

    /// A critically damped companion remains monotonic only while its initial
    /// velocity does not exceed its natural frequency. Feed every ordinary
    /// inward capture directly into both responses up to that physical bound.
    /// The very small policy-only excess is handed off separately below.
    private static func collapseTopVelocitySeed(
        requestedVelocity: CGFloat,
        preservesCapturedVelocity: Bool,
        configuration: BottomBarAccessoryTransitionConfiguration
    ) -> CollapseTopVelocitySeed {
        guard preservesCapturedVelocity else {
            return .init(
                response: referenceCollapseTopNormalizedVelocity,
                excess: 0
            )
        }
        let maximumVelocity = configuration.maximumNormalizedSpringVelocity
            .isFinite
            ? max(0, configuration.maximumNormalizedSpringVelocity)
            : 18
        let requested = requestedVelocity.isFinite
            ? requestedVelocity.clamped(to: 0 ... maximumVelocity)
            : 0
        let spring = configuration.collapseSpring
        let mass = spring.mass.isFinite ? max(0.001, spring.mass) : 1
        let stiffness = spring.stiffness.isFinite
            ? max(0.001, spring.stiffness)
            : 276.287_6
        let monotonicVelocityLimit = sqrt(stiffness / mass) * 0.999_9
        let responseVelocity = min(requested, monotonicVelocityLimit)
        return .init(
            response: responseVelocity,
            excess: requested - responseVelocity
        )
    }

    /// C3 velocity-only handoff reserved for the small amount above the
    /// critically-damped monotonicity bound. Ordinary captured velocities are
    /// carried by the two analytic responses themselves, so they never incur
    /// the old one-frame acceleration/jerk pulse.
    private static func excessVelocityResidual(
        elapsed: TimeInterval,
        duration: TimeInterval,
        velocityDelta: CGFloat
    ) -> CGFloat {
        guard elapsed.isFinite,
              duration.isFinite,
              velocityDelta.isFinite,
              elapsed > 0,
              duration > 0,
              elapsed < duration else {
            return 0
        }
        let u = CGFloat(elapsed / duration).clamped(to: 0 ... 1)
        let u2 = u * u
        let u4 = u2 * u2
        let u5 = u4 * u
        let u6 = u5 * u
        let u7 = u6 * u
        let c3Window = 1 - (35 * u4 - 84 * u5 + 70 * u6 - 20 * u7)
        return velocityDelta * CGFloat(elapsed) * c3Window
    }

    private static func criticallyDampedSpring(
        matching spring: BottomBarAccessoryTransitionConfiguration.Spring
    ) -> BottomBarAccessoryTransitionConfiguration.Spring {
        let mass = spring.mass.isFinite ? max(0.001, spring.mass) : 1
        let stiffness = spring.stiffness.isFinite
            ? max(0.001, spring.stiffness)
            : 276.287_6
        return .init(
            mass: mass,
            stiffness: stiffness,
            damping: 2 * sqrt(stiffness * mass)
        )
    }

    private static func collapseTopResponseProgress(
        at elapsed: TimeInterval,
        spring: BottomBarAccessoryTransitionConfiguration.Spring,
        duration: TimeInterval,
        normalizedInitialVelocity: CGFloat
    ) -> CGFloat {
        terminallySettledSpringProgressC3(
            at: elapsed,
            spring: spring,
            delay: 0,
            tailStart: min(duration * 0.75, 0.30),
            settleTime: duration,
            normalizedInitialVelocity: normalizedInitialVelocity
        )
    }

    /// Evaluates the measured shape cubic unchanged through 75% of its clock,
    /// then gives it an exact C2 endpoint instead of cutting its nonzero
    /// derivative when the twelve-frame width fold finishes.
    private static func collapseShapeProgress(
        at normalizedTime: CGFloat,
        curve: BottomBarAccessoryTransitionConfiguration.CubicBezierCurve
    ) -> CGFloat {
        let time = normalizedTime.clamped(to: 0 ... 1)
        let tailStart: CGFloat = 0.75
        guard time > tailStart else { return curve.progress(at: time) }

        let step: CGFloat = 0.000_5
        let startPosition = curve.progress(at: tailStart)
        let before = curve.progress(at: tailStart - step)
        let after = curve.progress(at: tailStart + step)
        let startVelocity = (after - before) / (2 * step)
        let startAcceleration = (after - 2 * startPosition + before)
            / (step * step)
        let duration = 1 - tailStart
        return quinticHermite(
            at: (time - tailStart) / duration,
            duration: duration,
            startPosition: startPosition,
            startVelocity: startVelocity,
            startAcceleration: startAcceleration,
            endPosition: 1,
            endVelocity: 0,
            endAcceleration: 0
        ).clamped(to: 0 ... 1)
    }

    static func collapseBoundaryProgress(
        at linearProgress: CGFloat,
        normalizedInitialTopVelocity: CGFloat = 0,
        normalizedInitialBottomVelocity: CGFloat = 0,
        velocitySampleInterval: TimeInterval? = nil,
        preservesInitialTopVelocity: Bool = false,
        configuration: BottomBarAccessoryTransitionConfiguration = .default
    ) -> (top: CGFloat, bottom: CGFloat, shape: CGFloat) {
        let time = linearProgress.isFinite
            ? linearProgress.clamped(to: 0 ... 1)
            : 0
        let totalDuration = configuration.collapseDuration.isFinite
            ? max(0.01, configuration.collapseDuration)
            : 0.40
        let elapsed = TimeInterval(time) * totalDuration
        let topSeed = collapseTopVelocitySeed(
            requestedVelocity: normalizedInitialTopVelocity,
            preservesCapturedVelocity: preservesInitialTopVelocity,
            configuration: configuration
        )
        let topResponse = collapseTopResponseProgress(
            at: elapsed,
            spring: configuration.collapseSpring,
            duration: totalDuration,
            normalizedInitialVelocity: topSeed.response
        )
        let sampleInterval = velocitySampleInterval.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        } ?? 1.0 / 120.0
        let excessHandoffDuration = min(
            totalDuration,
            max(3.0 / 120.0, sampleInterval * 3)
        )
        let top = topResponse + excessVelocityResidual(
            elapsed: elapsed,
            duration: excessHandoffDuration,
            velocityDelta: topSeed.excess
        )

        let bottomSpring = configuration.collapseBottomSpring
        let maximumNormalizedVelocity = configuration
            .maximumNormalizedSpringVelocity.isFinite
            ? max(0, configuration.maximumNormalizedSpringVelocity)
            : 18
        let requestedBottomVelocity = normalizedInitialBottomVelocity.isFinite
            ? normalizedInitialBottomVelocity.clamped(
                to: -maximumNormalizedVelocity ... maximumNormalizedVelocity
            )
            : 0
        // The analytic derivative itself is the captured visual velocity.
        // Calibrating this seed to a finite 60/120 Hz chord made release speed
        // cadence-dependent and recreated the perceptible handoff seam.
        let bottomSeed = requestedBottomVelocity
        let bottom = terminallySettledSpringProgressC3(
            at: elapsed,
            spring: bottomSpring,
            delay: 0,
            tailStart: min(totalDuration * 0.75, 0.30),
            settleTime: totalDuration,
            normalizedInitialVelocity: bottomSeed
        )
        _ = configuration.collapseBottomPower
        let configuredShapeDuration = configuration.collapseShapeDuration
        let shapeDuration = configuredShapeDuration.isFinite
            ? min(totalDuration, max(0.01, configuredShapeDuration))
            : min(totalDuration, 0.20)
        let shapeTime = CGFloat(
            min(elapsed, shapeDuration) / shapeDuration
        )
        let shape = collapseShapeProgress(
            at: shapeTime,
            curve: configuration.collapseShapeGeometryCurve
        )
        return (top, bottom, shape)
    }

    /// Spatial amplitude of the underdamped member in the collapse top's
    /// response blend. `S` is the measured spring and `M` is its critically
    /// damped companion with the same release derivative and C3 terminal
    /// landing. Since `P = M + a(S - M)` is affine in `a`, every instant that
    /// could overshoot provides an upper bound for `a`; the global minimum of
    /// those bounds gives an exact six-point crest without flattening any
    /// chord into a spatial clamp.
    static func collapseTopResponseBlendAmplitude(
        travelDistance: CGFloat,
        maximumOvershoot: CGFloat,
        normalizedInitialVelocity: CGFloat,
        configuration: BottomBarAccessoryTransitionConfiguration = .default
    ) -> CGFloat {
        let distance = travelDistance.isFinite ? abs(travelDistance) : 0
        guard distance > 0.001 else { return 1 }
        let requestedOvershoot = maximumOvershoot.isFinite
            ? max(0, maximumOvershoot)
            : 6
        let normalizedLimit = requestedOvershoot / distance
        let duration = configuration.collapseDuration.isFinite
            ? max(0.01, configuration.collapseDuration)
            : 32.0 / 60.0
        let seed = normalizedInitialVelocity.isFinite
            ? normalizedInitialVelocity
            : referenceCollapseTopNormalizedVelocity
        let underdampedSpring = configuration.collapseSpring
        let monotonicSpring = criticallyDampedSpring(
            matching: underdampedSpring
        )

        func amplitudeBound(at elapsed: TimeInterval) -> CGFloat {
            let underdamped = collapseTopResponseProgress(
                at: elapsed,
                spring: underdampedSpring,
                duration: duration,
                normalizedInitialVelocity: seed
            )
            let monotonic = collapseTopResponseProgress(
                at: elapsed,
                spring: monotonicSpring,
                duration: duration,
                normalizedInitialVelocity: seed
            )
            let responseDifference = underdamped - monotonic
            guard responseDifference > 0.000_000_001 else {
                return .greatestFiniteMagnitude
            }
            return (1 + normalizedLimit - monotonic)
                / responseDifference
        }

        // Find the global basin first. The ratio is smooth but its minimum
        // moves later as the permitted normalized overshoot becomes smaller.
        let coarseSampleCount = 128
        var bestIndex = 0
        var bestBound = CGFloat.greatestFiniteMagnitude
        for index in 1 ..< coarseSampleCount {
            let elapsed = duration * Double(index)
                / Double(coarseSampleCount)
            let bound = amplitudeBound(at: elapsed)
            if bound < bestBound {
                bestBound = bound
                bestIndex = index
            }
        }
        guard bestBound.isFinite else { return 1 }

        let step = duration / Double(coarseSampleCount)
        var lower = max(0, Double(bestIndex - 1) * step)
        var upper = min(duration, Double(bestIndex + 1) * step)
        let inverseGoldenRatio = (sqrt(5.0) - 1) * 0.5
        var left = upper - inverseGoldenRatio * (upper - lower)
        var right = lower + inverseGoldenRatio * (upper - lower)
        var leftBound = amplitudeBound(at: left)
        var rightBound = amplitudeBound(at: right)
        for _ in 0 ..< 36 {
            if leftBound < rightBound {
                upper = right
                right = left
                rightBound = leftBound
                left = upper - inverseGoldenRatio * (upper - lower)
                leftBound = amplitudeBound(at: left)
            } else {
                lower = left
                left = right
                leftBound = rightBound
                right = lower + inverseGoldenRatio * (upper - lower)
                rightBound = amplitudeBound(at: right)
            }
        }
        return min(bestBound, leftBound, rightBound).clamped(to: 0 ... 1)
    }

    /// Shared artwork has its own measured flight: it keeps shrinking through
    /// the late surface fold instead of arriving with the much faster compact
    /// top edge. Open and close use the same endpoint interpolation clock.
    static func sharedElementGeometryProgress(
        at linearProgress: CGFloat,
        settleDuration: TimeInterval,
        target: BottomBarAccessoryReleaseTarget = .expanded
    ) -> CGFloat {
        let progress = linearProgress.isFinite
            ? linearProgress.clamped(to: 0 ... 1)
            : 0
        let resolvedDuration = settleDuration.isFinite
            ? max(0.01, settleDuration)
            : 0.40
        let elapsed = TimeInterval(progress) * resolvedDuration
        if target == .collapsed {
            // The original cover's x and bounds share one full 32-frame,
            // nearly critical response. Keeping both properties on this same
            // scalar is what removes the former sideways plateau.
            return terminallySettledSpringProgressC3(
                at: elapsed,
                spring: .init(
                    mass: 1,
                    stiffness: 336.6,
                    damping: 36.69
                ),
                delay: 0,
                tailStart: min(resolvedDuration * 0.75, 0.30),
                settleTime: resolvedDuration,
                normalizedInitialVelocity: 0.82
            ).clamped(to: 0 ... 1)
        }

        // Opening keeps its established 22-frame artwork clock.
        let artworkDuration = min(resolvedDuration, 22.0 / 60.0)
        guard elapsed < artworkDuration else { return 1 }
        let curve = BottomBarAccessoryTransitionConfiguration.CubicBezierCurve(
            controlPoint1: CGPoint(x: 0.239_7, y: 0.114_7),
            controlPoint2: CGPoint(x: 0.178_8, y: 1)
        )
        return curve.progress(at: CGFloat(elapsed / artworkDuration))
    }

    /// Analytic t=0 derivative of the measured artwork clock, expressed as
    /// normalized progress per second. The surface-relative y guide uses this
    /// to reconcile its own derivative with the freshly sampled artwork
    /// derivative without changing x/size/corner timing.
    static func sharedElementGeometryInitialVelocity(
        settleDuration: TimeInterval,
        target: BottomBarAccessoryReleaseTarget = .expanded
    ) -> CGFloat {
        let resolvedDuration = settleDuration.isFinite
            ? max(0.01, settleDuration)
            : 0.40
        if target == .collapsed { return 0.82 }
        let artworkDuration = min(resolvedDuration, 22.0 / 60.0)
        guard artworkDuration > 0 else { return 0 }
        return (0.114_7 / 0.239_7) / CGFloat(artworkDuration)
    }

    struct SharedElementVerticalMotion {
        var spring: BottomBarAccessoryTransitionConfiguration.Spring
        var velocitySeed: CGFloat
    }

    /// Legacy vertical-response resolver retained for source-compatible custom
    /// tracks that do not provide the absolute surface guide. Production
    /// artwork now follows the surface-relative path, so no velocity-dependent
    /// damping or fixed overshoot cap is applied here.
    static func resolvedSharedElementVerticalMotion(
        normalizedInitialVelocity: CGFloat,
        travelDistance: CGFloat,
        duration: TimeInterval,
        sampleInterval: TimeInterval,
        spring: BottomBarAccessoryTransitionConfiguration.Spring
    ) -> SharedElementVerticalMotion {
        let requestedVelocity = normalizedInitialVelocity.isFinite
            ? normalizedInitialVelocity.clamped(to: -80 ... 80)
            : 0
        _ = travelDistance
        _ = duration
        _ = sampleInterval
        let mass = spring.mass.isFinite ? max(0.001, spring.mass) : 1
        let stiffness = spring.stiffness.isFinite
            ? max(0.001, spring.stiffness)
            : 213
        let baseDamping = spring.damping.isFinite
            ? max(0.001, spring.damping)
            : 24.975
        return .init(
            spring: BottomBarAccessoryTransitionConfiguration.Spring(
                mass: mass,
                stiffness: stiffness,
                damping: baseDamping
            ),
            velocitySeed: requestedVelocity
        )
    }

    static func sharedElementVerticalProgress(
        at linearProgress: CGFloat,
        settleDuration: TimeInterval,
        spring: BottomBarAccessoryTransitionConfiguration.Spring,
        normalizedInitialVelocity: CGFloat
    ) -> CGFloat {
        let progress = linearProgress.isFinite
            ? linearProgress.clamped(to: 0 ... 1)
            : 0
        let resolvedDuration = settleDuration.isFinite
            ? max(0.01, settleDuration)
            : 0.40
        return terminallySettledSpringProgressC3(
            at: TimeInterval(progress) * resolvedDuration,
            spring: spring,
            delay: 0,
            tailStart: min(resolvedDuration * 0.75, 0.30),
            settleTime: resolvedDuration,
            normalizedInitialVelocity: normalizedInitialVelocity
        )
    }

    static func settleSurfaceGeometry(
        from origin: BottomBarAccessorySurfaceGeometry,
        to target: BottomBarAccessorySurfaceGeometry,
        target releaseTarget: BottomBarAccessoryReleaseTarget,
        linearProgress: CGFloat,
        initialVelocityY: CGFloat = 0,
        initialTopVelocityY: CGFloat? = nil,
        initialBottomVelocityY: CGFloat? = nil,
        configuration: BottomBarAccessoryTransitionConfiguration = .default,
        settleDuration: TimeInterval? = nil,
        preservesBoundaryVelocities: Bool = false,
        preservesTopBoundaryVelocity: Bool = false,
        preservesBottomBoundaryVelocity: Bool = false,
        seedsProgrammaticCollapseLaunch: Bool = false,
        velocityHandoffSampleInterval: TimeInterval? = nil,
        minimumSurfaceHeight: CGFloat? = nil
    ) -> BottomBarAccessorySurfaceGeometry {
        let time = linearProgress.isFinite
            ? linearProgress.clamped(to: 0 ... 1)
            : 0
        if time <= 0 { return origin }
        if time >= 1 { return target }

        switch releaseTarget {
        case .expanded:
            let geometry = expandedSurfaceGeometry(
                from: origin,
                to: target,
                linearProgress: time,
                configuration: configuration
            )
            let configuredDuration = configuration.expansionDuration.isFinite
                ? max(0.01, configuration.expansionDuration)
                : 0.40
            let resolvedDuration = settleDuration.flatMap {
                $0.isFinite ? max(0.01, $0) : nil
            } ?? configuredDuration
            guard preservesBoundaryVelocities else { return geometry }

            // A reversal inherits each captured boundary velocity. The
            // measured opening gives top and bottom different derivatives, so
            // hand them off independently instead of coercing the centre
            // sample into both edges. The compact Hermite residual is zero at
            // both ends and has exactly the missing derivative at t=0.
            return applyingBoundaryVelocityHandoff(
                to: geometry,
                from: origin,
                linearProgress: time,
                duration: resolvedDuration,
                sampleInterval: velocityHandoffSampleInterval,
                initialTopVelocityY: initialTopVelocityY ?? initialVelocityY,
                initialBottomVelocityY: initialBottomVelocityY ?? initialVelocityY,
                minimumHeight: minimumSurfaceHeight.flatMap {
                    $0.isFinite ? max(1, $0) : nil
                } ?? 1,
                baseGeometryAtProgress: { progress in
                    expandedSurfaceGeometry(
                        from: origin,
                        to: target,
                        linearProgress: progress,
                        configuration: configuration
                    )
                }
            )

        case .collapsed:
            let topDistance = target.frame.minY - origin.frame.minY
            let configuredDuration = configuration.collapseDuration.isFinite
                ? max(0.01, configuration.collapseDuration)
                : 0.40
            let resolvedDuration = settleDuration.flatMap {
                $0.isFinite ? max(0.01, $0) : nil
            } ?? configuredDuration
            let resolvedInitialTopVelocityY = initialTopVelocityY
                ?? initialVelocityY
            let resolvedInitialBottomVelocityY = initialBottomVelocityY
                ?? initialVelocityY
            var normalizedInitialTopVelocity = abs(topDistance) > 0.001
                ? resolvedInitialTopVelocityY / topDistance
                : 0
            let bottomDistance = target.frame.maxY - origin.frame.maxY
            var normalizedInitialBottomVelocity = abs(bottomDistance) > 0.001
                ? resolvedInitialBottomVelocityY / bottomDistance
                : 0
            // `collapseBoundaryProgress` is expressed on the configured
            // physical clock. Compensate adaptive retarget clocks so its first
            // real-time derivative remains the captured boundary velocity.
            // Programmatic and ordinary gesture closes use the measured
            // reference launch. Only an animator retarget opts into the
            // captured top derivative below.
            normalizedInitialTopVelocity *= CGFloat(
                resolvedDuration / configuredDuration
            )
            normalizedInitialBottomVelocity *= CGFloat(
                resolvedDuration / configuredDuration
            )
            _ = seedsProgrammaticCollapseLaunch
            let normalizedVelocitySampleInterval = velocityHandoffSampleInterval.map {
                $0 * configuredDuration / resolvedDuration
            }
            let preservesInitialTopVelocity = preservesTopBoundaryVelocity
                && topDistance * resolvedInitialTopVelocityY >= 0
            let progresses = collapseBoundaryProgress(
                at: time,
                normalizedInitialTopVelocity: normalizedInitialTopVelocity,
                normalizedInitialBottomVelocity: preservesBottomBoundaryVelocity
                    ? normalizedInitialBottomVelocity
                    : 0,
                velocitySampleInterval: normalizedVelocitySampleInterval,
                preservesInitialTopVelocity: preservesInitialTopVelocity,
                configuration: configuration
            )
            let topSeed = collapseTopVelocitySeed(
                requestedVelocity: normalizedInitialTopVelocity,
                preservesCapturedVelocity: preservesInitialTopVelocity,
                configuration: configuration
            )
            let elapsed = TimeInterval(time) * configuredDuration
            let monotonicTopResponse = collapseTopResponseProgress(
                at: elapsed,
                spring: criticallyDampedSpring(
                    matching: configuration.collapseSpring
                ),
                duration: configuredDuration,
                normalizedInitialVelocity: topSeed.response
            )
            let topSampleInterval = normalizedVelocitySampleInterval.flatMap {
                $0.isFinite && $0 > 0 ? $0 : nil
            } ?? 1.0 / 120.0
            let excessHandoffDuration = min(
                configuredDuration,
                max(3.0 / 120.0, topSampleInterval * 3)
            )
            let monotonicTop = monotonicTopResponse
                + excessVelocityResidual(
                    elapsed: elapsed,
                    duration: excessHandoffDuration,
                    velocityDelta: topSeed.excess
                )
            let topBlendAmplitude = collapseTopResponseBlendAmplitude(
                travelDistance: topDistance,
                maximumOvershoot: configuration.collapseTopOvershoot,
                normalizedInitialVelocity: topSeed.response,
                configuration: configuration
            )
            let blendedTopProgress = monotonicTop
                + topBlendAmplitude * (progresses.top - monotonicTop)
            let originFrame = origin.frame
            let targetFrame = target.frame
            // One S/M response blend owns the complete top flight, its Mini
            // crossing, and return. Limiting the underdamped amplitude before
            // interpolation preserves a nonzero slope everywhere except the
            // single physical crest; no spatial postprocessor can form a
            // force- or distance-dependent shelf.
            let top = interpolate(
                originFrame.minY,
                targetFrame.minY,
                blendedTopProgress
            )

            // The bottom owns an independent absolute trajectory. With the
            // release-owned top and endpoint-bounded bottom, the nominal path
            // is already at least one Mini height tall through the fold.
            // Keep that raw path authoritative: smoothing a positive-part
            // contact band here changes its velocity near the endpoint and is
            // visible as a late lower-edge acceleration.
            let bottomCandidate = interpolate(
                originFrame.maxY,
                targetFrame.maxY,
                progresses.bottom
            )
            // Do not clamp to the release maxY: a downward release genuinely
            // carries this edge farther down for roughly two native frames
            // before the independent spring reverses into its fold.
            let rawBottom = bottomCandidate
            let minimumHeight = max(1, targetFrame.height)
            let minimumBottom = top + minimumHeight
            // Let the independent lower spring carry a little more folding
            // energy. Once it tries to cross the Mini-height floor, convert
            // that penetration into a bounded rigid translation of both
            // edges instead of clipping it into a frozen plateau. The capsule
            // keeps its exact height, dips as one object, and returns to the
            // exact endpoint when the C3 bottom track lands.
            let rawClearance = rawBottom - minimumBottom
            // A hard max at the instant the lower edge reaches Mini height
            // changes its velocity in one compositor sample. Anticipate that
            // contact over roughly one point so clearance, velocity and
            // acceleration all join the rigid capsule continuously across
            // two or three 120 Hz chords. The band remains too narrow to
            // alter the measured fold timing.
            let contactBlendDistance = min(
                1,
                max(0.25, minimumHeight * 0.02)
            )
            let safeClearance = c2PositivePart(
                rawClearance,
                transitionDistance: contactBlendDistance
            )
            let bottom = minimumBottom + safeClearance

            let width = interpolate(
                originFrame.width,
                targetFrame.width,
                progresses.shape
            ).clamped(
                to: min(originFrame.width, targetFrame.width)
                    ... max(originFrame.width, targetFrame.width)
            )
            let minX = interpolate(
                originFrame.minX,
                targetFrame.minX,
                progresses.shape
            )
            let frame = CGRect(
                x: minX,
                y: top,
                width: max(1, width),
                height: max(minimumHeight, bottom - top)
            )
            let boundsOrigin = CGPoint(
                x: interpolate(
                    origin.bounds.origin.x,
                    target.bounds.origin.x,
                    progresses.shape
                ),
                y: interpolate(
                    origin.bounds.origin.y,
                    target.bounds.origin.y,
                    progresses.shape
                )
            )
            let cornerRadius = interpolate(
                origin.cornerRadius,
                target.cornerRadius,
                progresses.shape
            ).clamped(
                to: min(origin.cornerRadius, target.cornerRadius)
                    ... max(origin.cornerRadius, target.cornerRadius)
            )
            let geometry = BottomBarAccessorySurfaceGeometry(
                position: CGPoint(x: frame.midX, y: frame.midY),
                bounds: CGRect(origin: boundsOrigin, size: frame.size),
                cornerRadius: cornerRadius
            )
            // An ordinary downward drag is already velocity-seeded directly
            // into both analytic springs above. Keep the legacy boundary
            // bridge only for an interrupted animation whose captured top is
            // still travelling away from the newly selected compact target;
            // a monotonic spring cannot represent that one retarget case.
            let needsOutwardRetargetHandoff = preservesTopBoundaryVelocity
                && topDistance * resolvedInitialTopVelocityY < 0
            guard needsOutwardRetargetHandoff else { return geometry }
            return applyingBoundaryVelocityHandoff(
                to: geometry,
                from: origin,
                linearProgress: time,
                duration: resolvedDuration,
                sampleInterval: velocityHandoffSampleInterval,
                // The base curve is monotonic, but a retarget handoff must use
                // the captured physical velocity. In particular, an
                // expand->collapse reversal can initially move away from Mini;
                // zeroing that velocity creates a one-frame C1 discontinuity.
                initialTopVelocityY: resolvedInitialTopVelocityY,
                initialBottomVelocityY: initialBottomVelocityY ?? initialVelocityY,
                minimumHeight: target.frame.height,
                dissipativeTopTargetY: targetFrame.minY,
                baseGeometryAtProgress: { progress in
                    settleSurfaceGeometry(
                        from: origin,
                        to: target,
                        target: .collapsed,
                        linearProgress: progress,
                        initialVelocityY: initialVelocityY,
                        initialTopVelocityY: initialTopVelocityY,
                        initialBottomVelocityY: initialBottomVelocityY,
                        configuration: configuration,
                        settleDuration: resolvedDuration,
                        preservesBoundaryVelocities: false,
                        preservesTopBoundaryVelocity: false,
                        preservesBottomBoundaryVelocity:
                            preservesBottomBoundaryVelocity,
                        seedsProgrammaticCollapseLaunch: seedsProgrammaticCollapseLaunch
                    )
                }
            )
        }
    }

    /// Legacy diagnostic retained for source/test compatibility. Runtime
    /// collapse no longer composes this second lobe; the single underdamped
    /// top response above owns both overshoot and return.
    static func resolvedRigidDockingDip(
        linearProgress: CGFloat,
        configuredMaximum: CGFloat
    ) -> CGFloat {
        let progress = linearProgress.isFinite
            ? linearProgress.clamped(to: 0 ... 1)
            : 0
        let requestedMaximum = configuredMaximum.isFinite
            ? max(0, configuredMaximum)
            : 3
        guard requestedMaximum > 0,
              progress > 0,
              progress < 1 else {
            return 0
        }

        let launchStart: CGFloat = 12.0 / 32.0
        let peak = collapseRigidDockingDipPeakProgress
        if progress < peak {
            guard progress > launchStart else { return 0 }
            let launch = ((progress - launchStart) / (peak - launchStart))
                .clamped(to: 0 ... 1)
            return requestedMaximum * smootherstep(launch)
        }

        // This beta-like return is the analytic fit of the reference's
        // remaining dip: 0.555 at 20/32, 0.167 at 24/32, and effectively zero
        // by 28/32. Both value and velocity join the peak continuously, and
        // the endpoint is exact rather than removed with a model-layer snap.
        let returnProgress = ((progress - peak) / (1 - peak))
            .clamped(to: 0 ... 1)
        let remaining = pow(
            max(0, 1 - pow(returnProgress, 1.382_5)),
            3.700_071
        )
        return requestedMaximum * remaining
    }

    static let collapseRigidDockingDipPeakProgress: CGFloat = 0.5

    private struct BoundaryKinematics {
        var position: CGFloat
        var velocity: CGFloat
        var acceleration: CGFloat
        var jerk: CGFloat
    }

    private static func boundaryKinematics(
        at elapsed: CGFloat,
        duration: CGFloat,
        edge: (BottomBarAccessorySurfaceGeometry) -> CGFloat,
        baseGeometryAtProgress: (CGFloat) -> BottomBarAccessorySurfaceGeometry
    ) -> BoundaryKinematics {
        let resolvedDuration = max(0.01, duration)
        let resolvedElapsed = elapsed.clamped(to: 0 ... resolvedDuration)
        func position(at sampleTime: CGFloat) -> CGFloat {
            edge(baseGeometryAtProgress(
                (sampleTime / resolvedDuration).clamped(to: 0 ... 1)
            ))
        }

        let center = position(at: resolvedElapsed)
        // The analytic base tracks all land with zero velocity/acceleration.
        // Avoid a clamped finite-difference stencil when an adaptive handoff
        // itself ends at the transition endpoint.
        if resolvedDuration - resolvedElapsed <= 0.002 {
            return .init(
                position: center,
                velocity: 0,
                acceleration: 0,
                jerk: 0
            )
        }

        let availableRadius = min(
            resolvedElapsed,
            resolvedDuration - resolvedElapsed
        )
        let step = min(
            max(resolvedDuration / 192, 0.000_5),
            max(0.000_1, availableRadius / 2.1)
        )
        let minusTwo = position(at: resolvedElapsed - 2 * step)
        let minusOne = position(at: resolvedElapsed - step)
        let plusOne = position(at: resolvedElapsed + step)
        let plusTwo = position(at: resolvedElapsed + 2 * step)
        let velocity = (
            minusTwo - 8 * minusOne + 8 * plusOne - plusTwo
        ) / (12 * step)
        let acceleration = (
            -plusTwo + 16 * plusOne - 30 * center
                + 16 * minusOne - minusTwo
        ) / (12 * step * step)
        let jerk = (
            plusTwo - 2 * plusOne + 2 * minusOne - minusTwo
        ) / (2 * step * step * step)
        return .init(
            position: center,
            velocity: velocity.isFinite ? velocity : 0,
            acceleration: acceleration.isFinite ? acceleration : 0,
            jerk: jerk.isFinite ? jerk : 0
        )
    }

    private static func applyingBoundaryVelocityHandoff(
        to geometry: BottomBarAccessorySurfaceGeometry,
        from origin: BottomBarAccessorySurfaceGeometry,
        linearProgress: CGFloat,
        duration: TimeInterval,
        sampleInterval: TimeInterval?,
        initialTopVelocityY: CGFloat,
        initialBottomVelocityY: CGFloat,
        minimumHeight: CGFloat,
        dissipativeTopTargetY: CGFloat? = nil,
        baseGeometryAtProgress: (CGFloat) -> BottomBarAccessorySurfaceGeometry
    ) -> BottomBarAccessorySurfaceGeometry {
        let resolvedDuration = duration.isFinite ? max(0.01, duration) : 0.40
        let originFrame = origin.frame
        let elapsed = linearProgress * CGFloat(resolvedDuration)
        let configuredSampleInterval = sampleInterval.flatMap {
            $0.isFinite && $0 > 0 ? CGFloat($0) : nil
        } ?? min(1.0 / 120.0, CGFloat(resolvedDuration))
        let firstSampleTime = min(
            configuredSampleInterval,
            CGFloat(resolvedDuration)
        )
        let isCollapsing = dissipativeTopTargetY != nil
        let topTailDuration: CGFloat
        if isCollapsing {
            // The measured compact top sheds most of its launch velocity
            // between native frames one and two. Its short C2 join preserves
            // that timing; stretching it to the lower edge's flight would put
            // the top tens of points ahead of the reference at s2.
            topTailDuration = configuredSampleInterval >= 1.0 / 30.0
                ? 0.067
                : 0.027_333
        } else {
            topTailDuration = 0.103_333
        }
        let topHandoffDuration = min(
            CGFloat(resolvedDuration),
            firstSampleTime + topTailDuration
        )
        let bottomHandoffDuration = min(
            CGFloat(resolvedDuration),
            max(0.122, configuredSampleInterval * 4.5)
        )
        guard elapsed < max(topHandoffDuration, bottomHandoffDuration) else {
            return geometry
        }

        let frame = geometry.frame
        // The first chord is deliberately linear because Core Animation's
        // visible velocity is the finite difference between keyframes rather
        // than the infinitesimal derivative at t=0. Each edge then follows its
        // own quintic Hermite bridge into the analytic base path. Position,
        // velocity, and acceleration agree at both joins, eliminating the old
        // ballistic-hold -> fade corner and its one-frame 100+ pt reversal.
        let rawTop = handedOffBoundaryPosition(
            basePosition: frame.minY,
            originPosition: originFrame.minY,
            initialVelocity: initialTopVelocityY,
            elapsed: elapsed,
            firstSampleTime: firstSampleTime,
            handoffDuration: topHandoffDuration,
            transitionDuration: CGFloat(resolvedDuration),
            edge: { $0.frame.minY },
            baseGeometryAtProgress: baseGeometryAtProgress
        )
        let rawBottom = handedOffBoundaryPosition(
            basePosition: frame.maxY,
            originPosition: originFrame.maxY,
            initialVelocity: initialBottomVelocityY,
            elapsed: elapsed,
            firstSampleTime: firstSampleTime,
            handoffDuration: bottomHandoffDuration,
            transitionDuration: CGFloat(resolvedDuration),
            edge: { $0.frame.maxY },
            baseGeometryAtProgress: baseGeometryAtProgress
        )

        var top = rawTop
        if let targetY = dissipativeTopTargetY,
           targetY.isFinite {
            // Permit the captured velocity to carry a reversal briefly away
            // from its origin. Only the destination side is bounded, which
            // preserves C1 while guaranteeing that close never passes below
            // the stable Mini top edge.
            top = targetY >= originFrame.minY
                ? min(top, targetY)
                : max(top, targetY)
        }
        let resolvedMinimumHeight = max(1, minimumHeight)
        let rawClearance = rawBottom - top - resolvedMinimumHeight
        let safeClearance: CGFloat
        if dissipativeTopTargetY == nil {
            let originClearance = max(
                0,
                originFrame.height - resolvedMinimumHeight
            )
            // Expanded retarget boundary tracks are independent and can
            // briefly cross even though both endpoint surfaces are valid.
            // Form a C2 contact with the compact-height floor instead of
            // hard-clamping one edge. The transition band never exceeds the
            // captured clearance, so geometry and its first two derivatives
            // are unchanged at t=0; outside the narrow contact region the
            // original physical tracks remain exact.
            let contactDistance = min(8, max(0.001, originClearance))
            safeClearance = c2PositivePart(
                rawClearance,
                transitionDistance: contactDistance
            )
        } else {
            // Preserve the already-validated collapse retarget path exactly.
            safeClearance = max(0, rawClearance)
        }
        let bottom = top + resolvedMinimumHeight + safeClearance
        let correctedFrame = CGRect(
            x: frame.minX,
            y: top,
            width: frame.width,
            height: bottom - top
        )
        return BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: correctedFrame.midX, y: correctedFrame.midY),
            bounds: CGRect(
                origin: geometry.bounds.origin,
                size: correctedFrame.size
            ),
            cornerRadius: geometry.cornerRadius
        )
    }

    private static func handedOffBoundaryPosition(
        basePosition: CGFloat,
        originPosition: CGFloat,
        initialVelocity: CGFloat,
        elapsed: CGFloat,
        firstSampleTime: CGFloat,
        handoffDuration: CGFloat,
        transitionDuration: CGFloat,
        edge: (BottomBarAccessorySurfaceGeometry) -> CGFloat,
        baseGeometryAtProgress: (CGFloat) -> BottomBarAccessorySurfaceGeometry
    ) -> CGFloat {
        let targetPosition = edge(baseGeometryAtProgress(1))
        let targetDelta = targetPosition - originPosition
        let firstChordTravel = abs(initialVelocity) * firstSampleTime
        let isMovingAwayFromTarget = targetDelta * initialVelocity <= 0
        let isNearTarget = abs(targetDelta) <= firstChordTravel + 20
        let resolvedHandoffDuration: CGFloat
        if isMovingAwayFromTarget,
           isNearTarget,
           firstChordTravel > 0.001 {
            // A retarget can capture a velocity at its configured 7k ceiling
            // while presentation geometry is already at the opposite
            // endpoint. Keeping the normal .12s bridge in that state lets a
            // mathematically smooth polynomial travel hundreds of points off
            // screen. Preserve the exact first visible chord, then use the
            // shortest C2 bridge with one additional display chord of braking.
            // Normal drags have hundreds of points of remaining geometry and
            // therefore retain their measured top/bottom handoff durations.
            resolvedHandoffDuration = min(
                handoffDuration,
                max(firstSampleTime * 2, firstSampleTime + 0.001)
            )
        } else {
            resolvedHandoffDuration = handoffDuration
        }

        guard elapsed < resolvedHandoffDuration else { return basePosition }
        if elapsed <= firstSampleTime {
            return originPosition + initialVelocity * elapsed
        }

        let terminal = boundaryKinematics(
            at: resolvedHandoffDuration,
            duration: transitionDuration,
            edge: edge,
            baseGeometryAtProgress: baseGeometryAtProgress
        )
        let segmentDuration = max(
            0.001,
            resolvedHandoffDuration - firstSampleTime
        )
        let segmentProgress = (
            (elapsed - firstSampleTime) / segmentDuration
        ).clamped(to: 0 ... 1)
        return quinticHermite(
            at: segmentProgress,
            duration: segmentDuration,
            startPosition: originPosition
                + initialVelocity * firstSampleTime,
            startVelocity: initialVelocity,
            startAcceleration: 0,
            endPosition: terminal.position,
            endVelocity: terminal.velocity,
            endAcceleration: terminal.acceleration
        )
    }

    private static func expandedSurfaceGeometry(
        from origin: BottomBarAccessorySurfaceGeometry,
        to target: BottomBarAccessorySurfaceGeometry,
        linearProgress: CGFloat,
        configuration: BottomBarAccessoryTransitionConfiguration
    ) -> BottomBarAccessorySurfaceGeometry {
        let topProgress = expansionGeometryProgress(
            at: linearProgress,
            configuration: configuration
        )
        let bottomProgress = expansionBottomProgress(
            at: linearProgress,
            configuration: configuration
        )
        let originFrame = origin.frame
        let targetFrame = target.frame
        let top = interpolate(originFrame.minY, targetFrame.minY, topProgress)
        let bottom = interpolate(
            originFrame.maxY,
            targetFrame.maxY,
            bottomProgress
        )
        let width = interpolate(originFrame.width, targetFrame.width, topProgress)
        let minX = interpolate(originFrame.minX, targetFrame.minX, topProgress)
        let frame = CGRect(
            x: minX,
            y: top,
            width: max(1, width),
            height: max(1, bottom - top)
        )
        let boundsOrigin = CGPoint(
            x: interpolate(
                origin.bounds.origin.x,
                target.bounds.origin.x,
                topProgress
            ),
            y: interpolate(
                origin.bounds.origin.y,
                target.bounds.origin.y,
                topProgress
            )
        )
        return BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: frame.midX, y: frame.midY),
            bounds: CGRect(origin: boundsOrigin, size: frame.size),
            cornerRadius: interpolate(
                origin.cornerRadius,
                target.cornerRadius,
                topProgress
            )
        )
    }

    private func installSurfaceGeometryTrack(
        from origin: BottomBarAccessorySurfaceGeometry,
        to target: BottomBarAccessorySurfaceGeometry,
        target releaseTarget: BottomBarAccessoryReleaseTarget,
        initialVelocityY: CGFloat,
        initialTopVelocityY: CGFloat,
        initialBottomVelocityY: CGFloat,
        preservesBoundaryVelocities: Bool,
        preservesTopBoundaryVelocity: Bool,
        preservesBottomBoundaryVelocity: Bool,
        seedsProgrammaticCollapseLaunch: Bool,
        duration: TimeInterval
    ) {
        guard let surfaceView,
              let containerView,
              let superview = surfaceView.superview else {
            return
        }
        let configuredDensity = configuration.geometryKeyframesPerSecond
        let density = configuredDensity.isFinite
            ? configuredDensity.clamped(to: 60 ... 240)
            : 120
        let resolvedDuration = max(duration, 0.01)
        let rawIntervalCount = resolvedDuration * TimeInterval(density)
        let nearestIntervalCount = rawIntervalCount.rounded()
        let intervalCount = abs(rawIntervalCount - nearestIntervalCount)
            <= 0.000_001
            ? Int(nearestIntervalCount)
            : Int(ceil(rawIntervalCount))
        let sampleCount = max(
            31,
            intervalCount + 1
        )
        let screenMaximum = surfaceView.window?.screen.maximumFramesPerSecond
            ?? UIScreen.main.maximumFramesPerSecond
        let visibleSampleInterval = Self.resolvedVelocityHandoffSampleInterval(
            keyframesPerSecond: density,
            maximumFramesPerSecond: screenMaximum
        )
        let minimumSurfaceHeight = session?.geometry.collapsedFrame.height
        let keyTimes = (0 ..< sampleCount).map { index in
            NSNumber(value: Double(index) / Double(sampleCount - 1))
        }
        let geometries = keyTimes.map { keyTime in
            Self.settleSurfaceGeometry(
                from: origin,
                to: target,
                target: releaseTarget,
                linearProgress: CGFloat(truncating: keyTime),
                initialVelocityY: initialVelocityY,
                initialTopVelocityY: initialTopVelocityY,
                initialBottomVelocityY: initialBottomVelocityY,
                configuration: configuration,
                settleDuration: resolvedDuration,
                preservesBoundaryVelocities: preservesBoundaryVelocities,
                preservesTopBoundaryVelocity: preservesTopBoundaryVelocity,
                preservesBottomBoundaryVelocity: preservesBottomBoundaryVelocity,
                seedsProgrammaticCollapseLaunch: seedsProgrammaticCollapseLaunch,
                velocityHandoffSampleInterval: visibleSampleInterval,
                minimumSurfaceHeight: minimumSurfaceHeight
            )
        }
        let positionValues = geometries.map { geometry in
            NSValue(
                cgPoint: containerView.convert(geometry.position, to: superview)
            )
        }
        let boundsValues = geometries.map { NSValue(cgRect: $0.bounds) }
        let cornerValues = geometries.map { NSNumber(value: $0.cornerRadius) }
        let presentationProgressValues: [CGFloat]
        if let session {
            presentationProgressValues = geometries.map {
                session.geometry.presentationProgress(for: $0)
            }
        } else {
            presentationProgressValues = keyTimes.map {
                CGFloat(truncating: $0)
            }
        }
        let sharedElementProgressValues = keyTimes.map { keyTime in
            Self.sharedElementGeometryProgress(
                at: CGFloat(truncating: keyTime),
                settleDuration: resolvedDuration,
                target: releaseTarget
            )
        }
        let frameRateRange = Self.resolvedPreferredFrameRateRange(
            maximumFramesPerSecond: screenMaximum
        )
        let mediaBeginTime = CACurrentMediaTime()
        let compositorTrack = BottomBarAccessoryCompositorSettleTrack(
            duration: resolvedDuration,
            keyTimes: keyTimes,
            presentationProgressValues: presentationProgressValues,
            sharedElementProgressValues: sharedElementProgressValues,
            surfaceMinYValues: geometries.map { $0.frame.minY },
            surfaceInitialMinYVelocity: initialTopVelocityY,
            sharedElementPositionArcOffsets: releaseTarget == .collapsed
                ? Array(repeating: 0, count: sharedElementProgressValues.count)
                : sharedElementProgressValues.map {
                    let progress = $0.clamped(to: 0 ... 1)
                    return Self.sharedElementPositionArcAmplitude
                        * 16 * progress * progress
                        * (1 - progress) * (1 - progress)
                },
            mediaBeginTime: mediaBeginTime,
            preferredFrameRateRange: frameRateRange
        )
        let glassTrack = GlassBackgroundCompositorSettleTrack(
            owner: glassCompositorOwner,
            duration: resolvedDuration,
            keyTimes: keyTimes,
            sizes: geometries.map { $0.bounds.size },
            cornerRadii: geometries.map { $0.cornerRadius },
            materialAlphaValues: presentationProgressValues.map {
                Self.transitionMaterialAlpha(
                    presentationProgress: $0
                )
            },
            mediaBeginTime: mediaBeginTime,
            preferredFrameRateRange: frameRateRange
        )
        let positionAnimation = CAKeyframeAnimation(keyPath: "position")
        positionAnimation.values = positionValues
        positionAnimation.keyTimes = keyTimes
        positionAnimation.calculationMode = .linear
        positionAnimation.duration = resolvedDuration
        let boundsAnimation = CAKeyframeAnimation(keyPath: "bounds")
        boundsAnimation.values = boundsValues
        boundsAnimation.keyTimes = keyTimes
        boundsAnimation.calculationMode = .linear
        boundsAnimation.duration = resolvedDuration
        let cornerAnimation = CAKeyframeAnimation(keyPath: "cornerRadius")
        cornerAnimation.values = cornerValues
        cornerAnimation.keyTimes = keyTimes
        cornerAnimation.calculationMode = .linear
        cornerAnimation.duration = resolvedDuration

        let group = CAAnimationGroup()
        group.animations = [positionAnimation, boundsAnimation, cornerAnimation]
        group.duration = resolvedDuration
        group.beginTime = surfaceView.layer.convertTime(
            mediaBeginTime,
            from: nil
        )
        group.isRemovedOnCompletion = true
        group.preferredFrameRateRange = frameRateRange

        // Install all compositor participants after the UIKit lifecycle clock
        // has started and before adding the surface group. A shared host-time
        // origin keeps artwork, endpoint opacity, and glass on the exact same
        // 120 Hz keyframe lattice.
        sharedElementTransition.installSettleTrack(compositorTrack)
        installEndpointContentOpacityTrack(
            compositorTrack,
            target: releaseTarget
        )
        (surfaceView as? GlassBackgroundView)?
            .installTransitionCompositorSettleTrack(glassTrack)
        withoutImplicitAnimations {
            surfaceView.layer.position = containerView.convert(
                target.position,
                to: superview
            )
            surfaceView.layer.bounds = target.bounds
            surfaceView.layer.cornerRadius = target.cornerRadius
            surfaceView.layer.opacity = 1
        }
        surfaceView.layer.add(group, forKey: Self.surfaceGeometryAnimationKey)
    }

    private func installEndpointContentOpacityTrack(
        _ track: BottomBarAccessoryCompositorSettleTrack,
        target: BottomBarAccessoryReleaseTarget
    ) {
        guard track.isValid else {
            hasCompositorContentTrack = false
            return
        }

        let collapsedOrigin = settleOriginCollapsedAlpha.clamped(to: 0 ... 1)
        let expandedOrigin = settleOriginExpandedAlpha.clamped(to: 0 ... 1)
        let handoffDuration = min(0.06, max(1.0 / 120.0, track.duration * 0.18))
        var collapsedValues: [NSNumber] = []
        var expandedValues: [NSNumber] = []
        collapsedValues.reserveCapacity(track.keyTimes.count)
        expandedValues.reserveCapacity(track.keyTimes.count)

        for (index, presentationProgress) in track
            .presentationProgressValues.enumerated() {
            let normalizedTime = CGFloat(truncating: track.keyTimes[index])
            let elapsed = TimeInterval(normalizedTime) * track.duration
            let handoff = Self.smootherstep(
                CGFloat(elapsed / max(0.000_1, handoffDuration))
            )
            let desiredCollapsed = Self.collapsedContentPlaneAlpha(
                presentationProgress: presentationProgress
            )
            let desiredExpanded = Self.expandedContentPlaneAlpha(
                presentationProgress: presentationProgress
            )
            collapsedValues.append(
                NSNumber(
                    value: collapsedOrigin
                        + (desiredCollapsed - collapsedOrigin) * handoff
                )
            )
            expandedValues.append(
                NSNumber(
                    value: expandedOrigin
                        + (desiredExpanded - expandedOrigin) * handoff
                )
            )
        }

        installOpacityTrack(
            on: collapsedContentHost,
            values: collapsedValues,
            modelValue: target == .collapsed ? 1 : 0,
            animationKey: Self.collapsedContentOpacityAnimationKey,
            track: track
        )
        installOpacityTrack(
            on: expandedContentHost,
            values: expandedValues,
            modelValue: target == .expanded ? 1 : 0,
            animationKey: Self.expandedContentOpacityAnimationKey,
            track: track
        )
    }

    private func installOpacityTrack(
        on view: UIView?,
        values: [NSNumber],
        modelValue: CGFloat,
        animationKey: String,
        track: BottomBarAccessoryCompositorSettleTrack
    ) {
        guard let view, values.count == track.keyTimes.count else { return }
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = values
        animation.keyTimes = track.keyTimes
        animation.duration = track.duration
        animation.beginTime = view.layer.convertTime(
            track.mediaBeginTime,
            from: nil
        )
        animation.calculationMode = .linear
        animation.isRemovedOnCompletion = true
        animation.preferredFrameRateRange = track.preferredFrameRateRange
        withoutImplicitAnimations {
            view.alpha = modelValue.clamped(to: 0 ... 1)
        }
        view.layer.add(animation, forKey: animationKey)
    }

    private struct SecondOrderMotionSample {
        var progress: CGFloat
        var velocity: CGFloat
        var acceleration: CGFloat
        var jerk: CGFloat
    }

    /// Closed-form second-order response for a boundary. Release velocity is
    /// normalized by the remaining edge distance before this function is
    /// called, preserving visibly different fast and slow takes without
    /// replaying a fixed keyframe path.
    private static func springMotionSample(
        at elapsedTime: TimeInterval,
        spring: BottomBarAccessoryTransitionConfiguration.Spring,
        normalizedInitialVelocity: CGFloat
    ) -> SecondOrderMotionSample {
        let mass = spring.mass.isFinite ? max(0.001, spring.mass) : 1
        let stiffness = spring.stiffness.isFinite
            ? max(0.001, spring.stiffness)
            : 308
        let damping = spring.damping.isFinite
            ? max(0.001, spring.damping)
            : 28.8
        let time = elapsedTime.isFinite ? max(0, CGFloat(elapsedTime)) : 0
        let initialVelocity = normalizedInitialVelocity.isFinite
            ? normalizedInitialVelocity
            : 0
        let naturalFrequency = sqrt(stiffness / mass)
        let dampingRatio = damping / (2 * sqrt(stiffness * mass))
        let decay = dampingRatio * naturalFrequency
        let error: CGFloat
        let velocity: CGFloat

        if dampingRatio < 1 - 0.000_1 {
            let dampedFrequency = naturalFrequency
                * sqrt(max(0.000_1, 1 - dampingRatio * dampingRatio))
            let sineCoefficient = (
                decay - initialVelocity
            ) / dampedFrequency
            let cosine = cos(dampedFrequency * time)
            let sine = sin(dampedFrequency * time)
            let exponential = exp(-decay * time)
            let oscillation = cosine + sineCoefficient * sine
            error = exponential * oscillation
            velocity = exponential * (
                decay * oscillation
                    + dampedFrequency * sine
                    - sineCoefficient * dampedFrequency * cosine
            )
        } else if dampingRatio <= 1 + 0.000_1 {
            let exponential = exp(-naturalFrequency * time)
            let linearCoefficient = naturalFrequency - initialVelocity
            error = exponential * (1 + linearCoefficient * time)
            velocity = exponential * (
                initialVelocity
                    + naturalFrequency * linearCoefficient * time
            )
        } else {
            let root = naturalFrequency * sqrt(dampingRatio * dampingRatio - 1)
            let firstRoot = -decay + root
            let secondRoot = -decay - root
            let denominator = firstRoot - secondRoot
            let firstCoefficient = (-initialVelocity - secondRoot) / denominator
            let secondCoefficient = 1 - firstCoefficient
            let firstTerm = firstCoefficient * exp(firstRoot * time)
            let secondTerm = secondCoefficient * exp(secondRoot * time)
            error = firstTerm + secondTerm
            velocity = -(firstRoot * firstTerm + secondRoot * secondTerm)
        }

        let progress = 1 - error
        let acceleration = stiffness / mass * (1 - progress)
            - damping / mass * velocity
        guard progress.isFinite,
              velocity.isFinite,
              acceleration.isFinite else {
            return .init(progress: 0, velocity: 0, acceleration: 0, jerk: 0)
        }
        let jerk = -stiffness / mass * velocity
            - damping / mass * acceleration
        return .init(
            progress: progress,
            velocity: velocity,
            acceleration: acceleration,
            jerk: jerk.isFinite ? jerk : 0
        )
    }

    /// C3 terminal landing used by the compact top edge. Matching jerk as well
    /// as position/velocity/acceleration removes the perceptible acceleration
    /// corner that a quintic tail can expose on a 120 Hz compositor track.
    private static func terminallySettledSpringProgressC3(
        at elapsedTime: TimeInterval,
        spring: BottomBarAccessoryTransitionConfiguration.Spring,
        delay: TimeInterval,
        tailStart: TimeInterval,
        settleTime: TimeInterval,
        normalizedInitialVelocity: CGFloat = 0
    ) -> CGFloat {
        let elapsed = elapsedTime.isFinite ? max(0, elapsedTime) : 0
        let resolvedDelay = delay.isFinite ? max(0, delay) : 0
        let resolvedSettle = settleTime.isFinite
            ? max(resolvedDelay + 0.001, settleTime)
            : max(resolvedDelay + 0.001, 0.40)
        let resolvedTailStart = tailStart.isFinite
            ? min(max(resolvedDelay, tailStart), resolvedSettle - 0.001)
            : max(resolvedDelay, resolvedSettle * 0.75)
        if elapsed <= resolvedDelay { return 0 }
        if elapsed >= resolvedSettle { return 1 }

        let responseTime = elapsed - resolvedDelay
        if elapsed <= resolvedTailStart {
            return springMotionSample(
                at: responseTime,
                spring: spring,
                normalizedInitialVelocity: normalizedInitialVelocity
            ).progress
        }

        let tailOrigin = springMotionSample(
            at: resolvedTailStart - resolvedDelay,
            spring: spring,
            normalizedInitialVelocity: normalizedInitialVelocity
        )
        let tailDuration = resolvedSettle - resolvedTailStart
        let tailProgress = CGFloat(
            (elapsed - resolvedTailStart) / tailDuration
        ).clamped(to: 0 ... 1)
        return septicHermite(
            at: tailProgress,
            duration: CGFloat(tailDuration),
            startPosition: tailOrigin.progress,
            startVelocity: tailOrigin.velocity,
            startAcceleration: tailOrigin.acceleration,
            startJerk: tailOrigin.jerk,
            endPosition: 1
        )
    }

    /// Runs the physical response unchanged through its measured flight, then
    /// uses a quintic Hermite tail to arrive with zero velocity and zero
    /// acceleration. Sampling this analytic trajectory at 120 Hz produces no
    /// duplicated 60 Hz chords and no terminal endpoint snap.
    private static func terminallySettledSpringProgress(
        at elapsedTime: TimeInterval,
        spring: BottomBarAccessoryTransitionConfiguration.Spring,
        delay: TimeInterval,
        tailStart: TimeInterval,
        settleTime: TimeInterval,
        normalizedInitialVelocity: CGFloat = 0
    ) -> CGFloat {
        let elapsed = elapsedTime.isFinite ? max(0, elapsedTime) : 0
        let resolvedDelay = delay.isFinite ? max(0, delay) : 0
        let resolvedSettle = settleTime.isFinite
            ? max(resolvedDelay + 0.001, settleTime)
            : max(resolvedDelay + 0.001, 0.40)
        let resolvedTailStart = tailStart.isFinite
            ? min(max(resolvedDelay, tailStart), resolvedSettle - 0.001)
            : max(resolvedDelay, resolvedSettle * 0.67)
        if elapsed <= resolvedDelay { return 0 }
        if elapsed >= resolvedSettle { return 1 }

        let responseTime = elapsed - resolvedDelay
        if elapsed <= resolvedTailStart {
            return springMotionSample(
                at: responseTime,
                spring: spring,
                normalizedInitialVelocity: normalizedInitialVelocity
            ).progress
        }

        let tailOrigin = springMotionSample(
            at: resolvedTailStart - resolvedDelay,
            spring: spring,
            normalizedInitialVelocity: normalizedInitialVelocity
        )
        let tailDuration = resolvedSettle - resolvedTailStart
        let tailProgress = CGFloat(
            (elapsed - resolvedTailStart) / tailDuration
        ).clamped(to: 0 ... 1)
        return quinticHermite(
            at: tailProgress,
            duration: CGFloat(tailDuration),
            startPosition: tailOrigin.progress,
            startVelocity: tailOrigin.velocity,
            startAcceleration: tailOrigin.acceleration,
            endPosition: 1,
            endVelocity: 0,
            endAcceleration: 0
        )
    }

    static func springProgress(
        at elapsedTime: TimeInterval,
        spring: BottomBarAccessoryTransitionConfiguration.Spring,
        normalizedInitialVelocity: CGFloat
    ) -> CGFloat {
        let progress = springMotionSample(
            at: elapsedTime,
            spring: spring,
            normalizedInitialVelocity: normalizedInitialVelocity
        ).progress
        return progress.isFinite
            ? progress.clamped(to: -0.25 ... 1.25)
            : 0
    }

    private static func c2PowerEaseOutProgress(
        at progress: CGFloat,
        power: CGFloat,
        tailStart: CGFloat
    ) -> CGFloat {
        let time = progress.clamped(to: 0 ... 1)
        let resolvedPower = power.isFinite ? power.clamped(to: 0.25 ... 8) : 2
        let start = tailStart.clamped(to: 0.25 ... 0.90)
        if time <= start {
            return 1 - pow(1 - time, resolvedPower)
        }
        let remaining = max(0.000_1, 1 - start)
        let residual = max(0.000_1, 1 - start)
        let startPosition = 1 - pow(residual, resolvedPower)
        let startVelocity = resolvedPower * pow(residual, resolvedPower - 1)
        let startAcceleration = -resolvedPower * (resolvedPower - 1)
            * pow(residual, resolvedPower - 2)
        return quinticHermite(
            at: (time - start) / remaining,
            duration: remaining,
            startPosition: startPosition,
            startVelocity: startVelocity,
            startAcceleration: startAcceleration,
            endPosition: 1,
            endVelocity: 0,
            endAcceleration: 0
        ).clamped(to: 0 ... 1)
    }

    private static func quinticHermite(
        at progress: CGFloat,
        duration: CGFloat,
        startPosition: CGFloat,
        startVelocity: CGFloat,
        startAcceleration: CGFloat,
        endPosition: CGFloat,
        endVelocity: CGFloat,
        endAcceleration: CGFloat
    ) -> CGFloat {
        let time = progress.clamped(to: 0 ... 1)
        let resolvedDuration = max(0.000_1, duration)
        let durationSquared = resolvedDuration * resolvedDuration
        let delta = endPosition - startPosition
        let c0 = startPosition
        let c1 = startVelocity * resolvedDuration
        let c2 = 0.5 * startAcceleration * durationSquared
        let c3 = 10 * delta
            - (6 * startVelocity + 4 * endVelocity) * resolvedDuration
            - (1.5 * startAcceleration - 0.5 * endAcceleration)
                * durationSquared
        let c4 = -15 * delta
            + (8 * startVelocity + 7 * endVelocity) * resolvedDuration
            + (1.5 * startAcceleration - endAcceleration) * durationSquared
        let c5 = 6 * delta
            - (3 * startVelocity + 3 * endVelocity) * resolvedDuration
            - (0.5 * startAcceleration - 0.5 * endAcceleration)
                * durationSquared
        return c0 + time * (
            c1 + time * (c2 + time * (c3 + time * (c4 + time * c5)))
        )
    }

    private static func septicHermite(
        at progress: CGFloat,
        duration: CGFloat,
        startPosition: CGFloat,
        startVelocity: CGFloat,
        startAcceleration: CGFloat,
        startJerk: CGFloat,
        endPosition: CGFloat,
        endVelocity: CGFloat = 0,
        endAcceleration: CGFloat = 0,
        endJerk: CGFloat = 0
    ) -> CGFloat {
        let time = progress.clamped(to: 0 ... 1)
        let resolvedDuration = max(0.000_1, duration)
        let durationSquared = resolvedDuration * resolvedDuration
        let durationCubed = durationSquared * resolvedDuration
        let startVelocityTerm = startVelocity * resolvedDuration
        let startAccelerationTerm = startAcceleration * durationSquared
        let startJerkTerm = startJerk * durationCubed
        let endVelocityTerm = endVelocity * resolvedDuration
        let endAccelerationTerm = endAcceleration * durationSquared
        let endJerkTerm = endJerk * durationCubed
        let delta = endPosition - startPosition
        let c0 = startPosition
        let c1 = startVelocityTerm
        let c2 = startAccelerationTerm * 0.5
        let c3 = startJerkTerm / 6
        let c4 = 35 * delta
            - 20 * startVelocityTerm - 15 * endVelocityTerm
            - 5 * startAccelerationTerm + 2.5 * endAccelerationTerm
            - (2.0 / 3.0) * startJerkTerm - endJerkTerm / 6
        let c5 = -84 * delta
            + 45 * startVelocityTerm + 39 * endVelocityTerm
            + 10 * startAccelerationTerm - 7 * endAccelerationTerm
            + startJerkTerm + endJerkTerm / 2
        let c6 = 70 * delta
            - 36 * startVelocityTerm - 34 * endVelocityTerm
            - 7.5 * startAccelerationTerm + 6.5 * endAccelerationTerm
            - (2.0 / 3.0) * startJerkTerm - endJerkTerm / 2
        let c7 = -20 * delta
            + 10 * startVelocityTerm + 10 * endVelocityTerm
            + 2 * startAccelerationTerm - 2 * endAccelerationTerm
            + startJerkTerm / 6 + endJerkTerm / 6
        return c0 + time * (
            c1 + time * (
                c2 + time * (
                    c3 + time * (c4 + time * (c5 + time * (c6 + time * c7)))
                )
            )
        )
    }

    /// C2-continuous positive part. Outside the narrow contact interval it is
    /// exactly `max(value, 0)`; within it, value/slope/acceleration match both
    /// branches. That makes the lower edge join a formed Mini without the
    /// wooden kink caused by clamping the authoritative top edge.
    private static func c2PositivePart(
        _ value: CGFloat,
        transitionDistance: CGFloat
    ) -> CGFloat {
        let epsilon = max(0.001, transitionDistance)
        if value <= 0 { return 0 }
        if value >= epsilon { return value }
        let unit = value / epsilon
        return epsilon * unit * unit * unit * (
            6 - 8 * unit + 3 * unit * unit
        )
    }

    private static func sampledProgress(
        _ samples: [CGFloat],
        at progress: CGFloat
    ) -> CGFloat {
        let finiteSamples = samples.map { sample in
            sample.isFinite ? sample : 0
        }
        guard finiteSamples.count >= 2 else {
            return progress.clamped(to: 0 ... 1)
        }
        let scaledIndex = progress.clamped(to: 0 ... 1)
            * CGFloat(finiteSamples.count - 1)
        let lowerIndex = min(Int(floor(scaledIndex)), finiteSamples.count - 1)
        let upperIndex = min(lowerIndex + 1, finiteSamples.count - 1)
        let fraction = scaledIndex - CGFloat(lowerIndex)
        return interpolate(
            finiteSamples[lowerIndex],
            finiteSamples[upperIndex],
            fraction
        )
    }

    private static func interpolatedSurfaceGeometry(
        from origin: BottomBarAccessorySurfaceGeometry,
        to target: BottomBarAccessorySurfaceGeometry,
        progress: CGFloat
    ) -> BottomBarAccessorySurfaceGeometry {
        BottomBarAccessorySurfaceGeometry(
            position: CGPoint(
                x: interpolate(origin.position.x, target.position.x, progress),
                y: interpolate(origin.position.y, target.position.y, progress)
            ),
            bounds: CGRect(
                x: interpolate(
                    origin.bounds.origin.x,
                    target.bounds.origin.x,
                    progress
                ),
                y: interpolate(
                    origin.bounds.origin.y,
                    target.bounds.origin.y,
                    progress
                ),
                width: interpolate(origin.bounds.width, target.bounds.width, progress),
                height: interpolate(origin.bounds.height, target.bounds.height, progress)
            ),
            cornerRadius: interpolate(
                origin.cornerRadius,
                target.cornerRadius,
                progress
            )
        )
    }

    private static func interpolate(
        _ origin: CGFloat,
        _ target: CGFloat,
        _ progress: CGFloat
    ) -> CGFloat {
        origin + (target - origin) * progress
    }

    private func applySurfaceGeometry(
        _ geometry: BottomBarAccessorySurfaceGeometry,
        removingAnimations: Bool = false
    ) {
        guard geometry.isValid,
              let surfaceView,
              let containerView,
              let superview = surfaceView.superview else {
            return
        }
        withoutImplicitAnimations {
            if removingAnimations {
                surfaceView.layer.removeAllAnimations()
            }
            surfaceView.layer.position = containerView.convert(
                geometry.position,
                to: superview
            )
            surfaceView.layer.bounds = geometry.bounds
            surfaceView.layer.cornerRadius = geometry.cornerRadius
        }
    }

    /// Reduce Motion preserves direct finger tracking, then hides the large
    /// endpoint geometry change behind one short fade-through handoff. The
    /// visible part only travels to `nearby` (bounded by configuration); the
    /// surface reaches its real endpoint while opacity is exactly zero and
    /// fades back in without allocating a second glass surface or chaining a
    /// follow-up animator.
    private func installReducedMotionHandoff(
        from current: BottomBarAccessorySurfaceGeometry,
        through nearby: BottomBarAccessorySurfaceGeometry,
        to endpoint: BottomBarAccessorySurfaceGeometry,
        duration: TimeInterval
    ) {
        guard let surfaceView,
              let containerView,
              let superview = surfaceView.superview else {
            return
        }

        let initialOpacity = currentSurfaceOpacity() ?? 1
        let currentPosition = containerView.convert(current.position, to: superview)
        let nearbyPosition = containerView.convert(nearby.position, to: superview)
        let endpointPosition = containerView.convert(endpoint.position, to: superview)
        let keyTimes = [0, 0.34, 0.42, 0.54, 1].map(NSNumber.init(value:))

        withoutImplicitAnimations {
            surfaceView.layer.position = endpointPosition
            surfaceView.layer.bounds = endpoint.bounds
            surfaceView.layer.cornerRadius = endpoint.cornerRadius
            surfaceView.layer.opacity = 1
        }

        let positionAnimation = reducedMotionKeyframeAnimation(
            keyPath: "position",
            values: [
                NSValue(cgPoint: currentPosition),
                NSValue(cgPoint: nearbyPosition),
                NSValue(cgPoint: nearbyPosition),
                NSValue(cgPoint: endpointPosition),
                NSValue(cgPoint: endpointPosition),
            ],
            keyTimes: keyTimes,
            duration: duration
        )
        let boundsAnimation = reducedMotionKeyframeAnimation(
            keyPath: "bounds",
            values: [
                NSValue(cgRect: current.bounds),
                NSValue(cgRect: nearby.bounds),
                NSValue(cgRect: nearby.bounds),
                NSValue(cgRect: endpoint.bounds),
                NSValue(cgRect: endpoint.bounds),
            ],
            keyTimes: keyTimes,
            duration: duration
        )
        let cornerRadiusAnimation = reducedMotionKeyframeAnimation(
            keyPath: "cornerRadius",
            values: [
                current.cornerRadius,
                nearby.cornerRadius,
                nearby.cornerRadius,
                endpoint.cornerRadius,
                endpoint.cornerRadius,
            ],
            keyTimes: keyTimes,
            duration: duration
        )
        let opacityAnimation = reducedMotionKeyframeAnimation(
            keyPath: "opacity",
            values: [
                NSNumber(value: initialOpacity),
                NSNumber(value: 0),
                NSNumber(value: 0),
                NSNumber(value: 0),
                NSNumber(value: 1),
            ],
            keyTimes: keyTimes,
            duration: duration
        )
        let handoff = CAAnimationGroup()
        handoff.animations = [
            positionAnimation,
            boundsAnimation,
            cornerRadiusAnimation,
            opacityAnimation,
        ]
        handoff.duration = duration
        handoff.isRemovedOnCompletion = true
        surfaceView.layer.add(
            handoff,
            forKey: Self.reducedMotionHandoffAnimationKey
        )
    }

    private func reducedMotionKeyframeAnimation(
        keyPath: String,
        values: [Any],
        keyTimes: [NSNumber],
        duration: TimeInterval
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes
        animation.duration = duration
        animation.calculationMode = .linear
        animation.timingFunctions = Array(
            repeating: CAMediaTimingFunction(name: .easeInEaseOut),
            count: max(0, values.count - 1)
        )
        animation.isRemovedOnCompletion = true
        return animation
    }

    private func currentSurfaceOpacity() -> Float? {
        guard let surfaceView else { return nil }
        return surfaceView.layer.presentation()?.opacity
            ?? surfaceView.layer.opacity
    }

    /// Commits both endpoint planes from their presentation layers before any
    /// compositor animations are removed. A reversal therefore starts from the
    /// exact visible crossfade instead of the already-committed endpoint model.
    private func captureEndpointContentPresentation() {
        withoutImplicitAnimations {
            if let collapsedContentHost {
                let opacity = collapsedContentHost.layer.presentation()?.opacity
                    ?? collapsedContentHost.layer.opacity
                collapsedContentHost.layer.removeAnimation(
                    forKey: Self.collapsedContentOpacityAnimationKey
                )
                if opacity.isFinite {
                    collapsedContentHost.alpha = CGFloat(opacity)
                        .clamped(to: 0 ... 1)
                }
            }
            if let expandedContentHost {
                let opacity = expandedContentHost.layer.presentation()?.opacity
                    ?? expandedContentHost.layer.opacity
                expandedContentHost.layer.removeAnimation(
                    forKey: Self.expandedContentOpacityAnimationKey
                )
                if opacity.isFinite {
                    expandedContentHost.alpha = CGFloat(opacity)
                        .clamped(to: 0 ... 1)
                }
            }
        }
    }

    private func applySurfaceOpacity(_ opacity: Float) {
        guard opacity.isFinite else { return }
        withoutImplicitAnimations {
            surfaceView?.layer.opacity = min(max(opacity, 0), 1)
        }
    }

    private func adjustedDragTranslation(
        _ translation: CGFloat,
        referenceDistance: CGFloat,
        linearDragDistance: CGFloat
    ) -> CGFloat {
        if translation < 0 {
            return -rubberBand(
                distance: abs(translation),
                dimension: max(1, referenceDistance * 0.45)
            )
        }

        let linearLimit = max(
            1,
            linearDragDistance * max(
                0,
                finite(
                    configuration.maximumLinearDragFactor,
                    fallback: 1.05
                )
            )
        )
        guard translation > linearLimit else { return translation }
        return linearLimit + rubberBand(
            distance: translation - linearLimit,
            dimension: max(1, referenceDistance * 0.35)
        )
    }

    /// Resolves the derivative of the exact held-drag geometry. This mirrors
    /// `updateDrag` analytically, including rubber-band resistance and the
    /// top-anchored height change, instead of treating recognizer velocity as
    /// if the surface were still moving linearly.
    private func resolvedDragBoundaryVelocities(
        rawVelocityY: CGFloat,
        session: BottomBarAccessoryTransitionSession
    ) -> (top: CGFloat, bottom: CGFloat)? {
        guard let origin = session.dragOriginSurface else { return nil }
        let rawVelocity = finite(rawVelocityY)
        let relativeTranslation = session.latestRawDragTranslation
            - session.dragTranslationOrigin
        let referenceDistance = max(
            1,
            session.geometry.collapsedFrame.midY
                - session.geometry.expandedFrame.midY
        )
        let linearDragDistance = max(
            referenceDistance,
            session.geometry.collapsedFrame.maxY
                - session.geometry.expandedFrame.minY
        )
        let adjustedDerivative = adjustedDragTranslationDerivative(
            relativeTranslation,
            referenceDistance: referenceDistance,
            linearDragDistance: linearDragDistance
        )
        let topVelocity = rawVelocity * adjustedDerivative

        let minimumScale = session.isReduceMotionEnabled
            ? configuration.reduceMotionMinimumDragScale
            : configuration.minimumDragScale
        let resolvedMinimumScale = finite(minimumScale, fallback: 1)
            .clamped(to: 0.8 ... 1)
        let rawProgress = max(0, relativeTranslation) / referenceDistance
        let scaleProgressUpperBound: CGFloat = 0.78
        let scaleDerivative: CGFloat
        if rawProgress > 0, rawProgress < scaleProgressUpperBound {
            let unit = rawProgress / scaleProgressUpperBound
            let smoothstepDerivative = 6 * unit * (1 - unit)
                / scaleProgressUpperBound
            scaleDerivative = -(1 - resolvedMinimumScale)
                * smoothstepDerivative / referenceDistance
        } else {
            scaleDerivative = 0
        }
        let bottomVelocity = topVelocity
            + origin.bounds.height * scaleDerivative * rawVelocity
        guard topVelocity.isFinite, bottomVelocity.isFinite else { return nil }
        return (topVelocity, bottomVelocity)
    }

    private func adjustedDragTranslationDerivative(
        _ translation: CGFloat,
        referenceDistance: CGFloat,
        linearDragDistance: CGFloat
    ) -> CGFloat {
        if translation < 0 {
            return rubberBandDerivative(
                distance: abs(translation),
                dimension: max(1, referenceDistance * 0.45)
            )
        }

        let linearLimit = max(
            1,
            linearDragDistance * max(
                0,
                finite(
                    configuration.maximumLinearDragFactor,
                    fallback: 1.05
                )
            )
        )
        guard translation > linearLimit else { return 1 }
        return rubberBandDerivative(
            distance: translation - linearLimit,
            dimension: max(1, referenceDistance * 0.35)
        )
    }

    private func rubberBandDerivative(
        distance: CGFloat,
        dimension: CGFloat
    ) -> CGFloat {
        let coefficient = max(
            0,
            finite(configuration.rubberBandCoefficient, fallback: 0.52)
        )
        guard coefficient > 0, distance > 0, dimension > 0 else {
            return distance <= 0 ? 1 : 0
        }
        let denominator = 1 + distance * coefficient / dimension
        return coefficient / (denominator * denominator)
    }

    private func rubberBand(distance: CGFloat, dimension: CGFloat) -> CGFloat {
        let coefficient = max(
            0,
            finite(configuration.rubberBandCoefficient, fallback: 0.52)
        )
        guard coefficient > 0, distance > 0, dimension > 0 else { return 0 }
        return (1 - 1 / (distance * coefficient / dimension + 1)) * dimension
    }

    private func resolvedCaptureProgress(
        currentSurface: BottomBarAccessorySurfaceGeometry,
        session: BottomBarAccessoryTransitionSession
    ) -> CGFloat {
        let base = finite(
            configuration.collapseCaptureProgress,
            fallback: 0.06
        ).clamped(to: 0 ... 0.25)
        let distanceProgress = session.geometry
            .presentationProgress(for: currentSurface)
        let proximityScale = smoothstep(
            0,
            max(
                0.01,
                finite(
                    configuration.collapsedInteractionProgress,
                    fallback: 0.12
                ) * 2
            ),
            distanceProgress
        )
        return base * proximityScale
    }

    // MARK: - Lifecycle helpers

    @discardableResult
    private func transitionState(
        with event: BottomBarAccessoryTransitionStateEvent
    ) -> Bool {
        let previousState = state
        guard stateMachine.handle(event) else { return false }
        if state != previousState {
            delegate?.bottomBarAccessoryTransitionCoordinator(
                self,
                didChangeState: state
            )
        }
        return true
    }

    private func abandonCurrentSession(restoringVisibility: Bool) {
        _ = captureCurrentPresentation()
        if restoringVisibility {
            sharedElementTransition.cancel()
        }
        isParticipantTransitionActive = false
        currentContext = nil
        lastPresentedSurfaceGeometry = nil
        session = nil
    }

    private func applyStableContentState(
        _ target: BottomBarAccessoryReleaseTarget
    ) {
        hasCompositorContentTrack = false
        withoutImplicitAnimations {
            collapsedContentHost?.layer.removeAnimation(
                forKey: Self.collapsedContentOpacityAnimationKey
            )
            expandedContentHost?.layer.removeAnimation(
                forKey: Self.expandedContentOpacityAnimationKey
            )
            collapsedContentHost?.alpha = target == .collapsed ? 1 : 0
            expandedContentHost?.alpha = target == .expanded ? 1 : 0
        }
        if target == .collapsed {
            collapsedContentHost?.isUserInteractionEnabled = true
            collapsedContentHost?.accessibilityElementsHidden = false
            expandedContentHost?.isUserInteractionEnabled = false
            expandedContentHost?.accessibilityElementsHidden = true
        } else {
            collapsedContentHost?.isUserInteractionEnabled = false
            collapsedContentHost?.accessibilityElementsHidden = true
            expandedContentHost?.isUserInteractionEnabled = true
            expandedContentHost?.accessibilityElementsHidden = false
        }
    }

    private func phase(
        for state: BottomBarAccessoryPresentationState
    ) -> BottomBarAccessoryTransitionPhase {
        switch state {
        case .collapsed, .expanded:
            return .completed
        case .expanding:
            return .expanding
        case .dragging:
            return .dragging
        case .settlingToExpanded:
            return .settlingToExpanded
        case .settlingToCollapsed:
            return .settlingToCollapsed
        }
    }

    static func resolvedPreferredFrameRateRange(
        maximumFramesPerSecond: Int
    ) -> CAFrameRateRange {
        let hardwareMaximum = maximumFramesPerSecond > 0
            ? maximumFramesPerSecond
            : 120
        let preferred = Float(min(120, hardwareMaximum))
        return CAFrameRateRange(
            minimum: preferred,
            maximum: preferred,
            preferred: preferred
        )
    }

    static func resolvedVelocityHandoffSampleInterval(
        keyframesPerSecond: CGFloat,
        maximumFramesPerSecond: Int
    ) -> TimeInterval {
        let resolvedKeyframeRate = keyframesPerSecond.isFinite
            ? keyframesPerSecond.clamped(to: 60 ... 240)
            : 120
        let hardwareRate = maximumFramesPerSecond > 0
            ? CGFloat(maximumFramesPerSecond)
            : 120
        // This transition requests one exact cadence rather than a 60...120
        // range, so the first visible chord is the real hardware-clamped
        // period: 1/120 on ProMotion and 1/60 (or 1/30) on fallback panels.
        let visibleRate = min(
            resolvedKeyframeRate,
            min(120, hardwareRate)
        )
        return 1 / TimeInterval(max(1, visibleRate))
    }

    private func startDisplayLink() {
        stopDisplayLink()
        let proxy = BottomBarAccessoryDisplayLinkProxy(owner: self)
        let displayLink = CADisplayLink(target: proxy, selector: #selector(proxy.tick(_:)))
        let screenMaximum = surfaceView?.window?.screen.maximumFramesPerSecond
            ?? containerView?.window?.screen.maximumFramesPerSecond
            ?? UIScreen.main.maximumFramesPerSecond
        displayLink.preferredFrameRateRange = Self.resolvedPreferredFrameRateRange(
            maximumFramesPerSecond: screenMaximum
        )
        displayLink.add(to: .main, forMode: .common)
        displayLinkProxy = proxy
        self.displayLink = displayLink
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
        lastSampleTimestamp = nil
        lastSamplePositionY = nil
        lastSampleMinY = nil
        lastSampleMaxY = nil
    }

    private func resetVelocitySampling(
        surface: BottomBarAccessorySurfaceGeometry,
        initialVelocityY: CGFloat,
        initialTopVelocityY: CGFloat,
        initialBottomVelocityY: CGFloat
    ) {
        lastSampleTimestamp = nil
        lastSamplePositionY = surface.position.y
        lastSampleMinY = surface.frame.minY
        lastSampleMaxY = surface.frame.maxY
        estimatedVelocityY = initialVelocityY
        estimatedTopVelocityY = initialTopVelocityY
        estimatedBottomVelocityY = initialBottomVelocityY
    }

    private func smoothstep(
        _ lowerBound: CGFloat,
        _ upperBound: CGFloat,
        _ value: CGFloat
    ) -> CGFloat {
        guard upperBound > lowerBound else {
            return value >= upperBound ? 1 : 0
        }
        let progress = ((value - lowerBound) / (upperBound - lowerBound))
            .clamped(to: 0 ... 1)
        return progress * progress * (3 - 2 * progress)
    }

    private func finite(
        _ value: CGFloat,
        fallback: CGFloat = 0
    ) -> CGFloat {
        value.isFinite ? value : fallback
    }

    private func withoutImplicitAnimations(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}

@MainActor
private final class BottomBarAccessoryDisplayLinkProxy: NSObject {
    private weak var owner: BottomBarAccessoryTransitionCoordinator?

    init(owner: BottomBarAccessoryTransitionCoordinator) {
        self.owner = owner
    }

    @objc func tick(_ displayLink: CADisplayLink) {
        owner?.displayLinkDidFire(displayLink)
    }
}
