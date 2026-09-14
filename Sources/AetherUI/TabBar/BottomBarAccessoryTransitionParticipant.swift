import UIKit

/// A generic shared element supplied by one side of a bottom-bar accessory
/// transition. A transition matches elements by `identifier`; AetherUI never
/// assigns semantic meaning to the represented view.
@MainActor
public final class BottomBarAccessoryTransitionSharedElement {
    public let identifier: AnyHashable
    public private(set) weak var view: UIView?
    public let cornerRadius: CGFloat?
    public let contentMode: UIView.ContentMode

    private let contentSignatureProvider: ((UIView) -> AnyHashable?)?
    private let representationProvider: ((UIView) -> UIView?)?
    private let representationRefreshHandler: ((UIView, UIView) -> Void)?

    /// - Parameter representationProvider: An optional factory for a disposable
    ///   transition-only representation. The returned view must not be one of
    ///   the live endpoint views and should not already belong to a hierarchy.
    /// - Parameter contentSignatureProvider: An optional, cheap and
    ///   side-effect-free content identity provider. When both endpoints with
    ///   the same `identifier` report the same new signature, AetherUI refreshes
    ///   the transition representation once. This lets content change during
    ///   an interrupted transition without creating snapshots every frame.
    /// - Parameter representationRefreshHandler: An optional in-place refresh
    ///   hook. It receives the currently selected live endpoint followed by
    ///   the existing transition representation. Keep the representation in
    ///   its current hierarchy and only replace its visual content so active
    ///   layer animations remain uninterrupted. When omitted, AetherUI can
    ///   refresh its default rasterized representation automatically.
    public init(
        identifier: AnyHashable,
        view: UIView,
        cornerRadius: CGFloat? = nil,
        contentMode: UIView.ContentMode = .scaleToFill,
        contentSignatureProvider: ((UIView) -> AnyHashable?)? = nil,
        representationProvider: ((UIView) -> UIView?)? = nil,
        representationRefreshHandler: ((UIView, UIView) -> Void)? = nil
    ) {
        self.identifier = identifier
        self.view = view
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
        self.contentSignatureProvider = contentSignatureProvider
        self.representationProvider = representationProvider
        self.representationRefreshHandler = representationRefreshHandler
    }

    func makeRepresentation() -> UIView? {
        guard let view else { return nil }
        if let supplied = representationProvider?(view), supplied !== view {
            if supplied.superview == nil {
                return supplied
            }
            return supplied.snapshotView(afterScreenUpdates: true)
        }
        if contentSignatureProvider != nil,
           let representation = BottomBarAccessoryRasterizedRepresentationView(
               capturing: view
           ) {
            return representation
        }
        return view.snapshotView(afterScreenUpdates: false)
    }

    func currentContentSignature() -> AnyHashable? {
        guard let view else { return nil }
        return contentSignatureProvider?(view)
    }

    func refreshRepresentation(_ representation: UIView) -> Bool {
        guard let view else { return false }
        if let representationRefreshHandler {
            representationRefreshHandler(view, representation)
            return true
        }
        guard let representation = representation
            as? BottomBarAccessoryRasterizedRepresentationView else {
            return false
        }
        return representation.refresh(capturing: view)
    }
}

/// The default refreshable representation keeps one UIImageView/layer alive
/// for the entire transition. Content changes update only its image; geometry
/// animations remain attached to the same layer.
@MainActor
private final class BottomBarAccessoryRasterizedRepresentationView: UIImageView {
    convenience init?(capturing view: UIView) {
        guard let image = Self.capture(view) else { return nil }
        self.init(image: image)
        isOpaque = false
        backgroundColor = .clear
    }

    func refresh(capturing view: UIView) -> Bool {
        guard let image = Self.capture(view) else { return false }
        self.image = image
        return true
    }

    private static func capture(_ view: UIView) -> UIImage? {
        let size = view.bounds.size
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = max(
            view.window?.screen.scale
                ?? view.traitCollection.displayScale,
            1
        )
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(
                x: -view.bounds.minX,
                y: -view.bounds.minY
            )
            view.layer.render(in: context.cgContext)
        }
    }
}

/// Optional content choreography and shared-element hooks for either endpoint
/// of a bottom-bar accessory transition.
@MainActor
public protocol BottomBarAccessoryTransitionParticipant: AnyObject {
    func bottomBarAccessoryTransitionSharedElements(
        in context: BottomBarAccessoryTransitionContext
    ) -> [BottomBarAccessoryTransitionSharedElement]

    func prepareBottomBarAccessoryTransition(
        _ context: BottomBarAccessoryTransitionContext
    )

    func updateBottomBarAccessoryTransition(
        _ context: BottomBarAccessoryTransitionContext
    )

    func completeBottomBarAccessoryTransition(
        _ context: BottomBarAccessoryTransitionContext
    )
}

public extension BottomBarAccessoryTransitionParticipant {
    func bottomBarAccessoryTransitionSharedElements(
        in context: BottomBarAccessoryTransitionContext
    ) -> [BottomBarAccessoryTransitionSharedElement] {
        []
    }

    func prepareBottomBarAccessoryTransition(
        _ context: BottomBarAccessoryTransitionContext
    ) {}

    func updateBottomBarAccessoryTransition(
        _ context: BottomBarAccessoryTransitionContext
    ) {}

    func completeBottomBarAccessoryTransition(
        _ context: BottomBarAccessoryTransitionContext
    ) {}
}

@MainActor
struct BottomBarAccessoryCompositorSettleTrack {
    let duration: TimeInterval
    let keyTimes: [NSNumber]
    let presentationProgressValues: [CGFloat]
    let sharedElementProgressValues: [CGFloat]
    /// Absolute surface top-edge samples in the coordinator's container
    /// space. Shared artwork uses their displacement as its physical y guide
    /// while x, size, and radius retain the slower artwork clock.
    let surfaceMinYValues: [CGFloat]
    let surfaceInitialMinYVelocity: CGFloat
    /// Screen-space distance, in points, applied along each element's
    /// endpoint-chord normal. The participant orients that normal toward
    /// positive screen x, giving open and close the same subtle rightward arc.
    let sharedElementPositionArcOffsets: [CGFloat]
    let mediaBeginTime: CFTimeInterval
    let preferredFrameRateRange: CAFrameRateRange

    init(
        duration: TimeInterval,
        keyTimes: [NSNumber],
        presentationProgressValues: [CGFloat],
        sharedElementProgressValues: [CGFloat],
        surfaceMinYValues: [CGFloat] = [],
        surfaceInitialMinYVelocity: CGFloat = 0,
        sharedElementPositionArcOffsets: [CGFloat],
        mediaBeginTime: CFTimeInterval,
        preferredFrameRateRange: CAFrameRateRange
    ) {
        self.duration = duration
        self.keyTimes = keyTimes
        self.presentationProgressValues = presentationProgressValues
        self.sharedElementProgressValues = sharedElementProgressValues
        self.surfaceMinYValues = surfaceMinYValues
        self.surfaceInitialMinYVelocity = surfaceInitialMinYVelocity
        self.sharedElementPositionArcOffsets = sharedElementPositionArcOffsets
        self.mediaBeginTime = mediaBeginTime
        self.preferredFrameRateRange = preferredFrameRateRange
    }

    var isValid: Bool {
        duration.isFinite
            && duration > 0
            && keyTimes.count >= 2
            && keyTimes.count == presentationProgressValues.count
            && keyTimes.count == sharedElementProgressValues.count
            && (surfaceMinYValues.isEmpty
                || keyTimes.count == surfaceMinYValues.count)
            && surfaceMinYValues.allSatisfy { $0.isFinite }
            && surfaceInitialMinYVelocity.isFinite
            && keyTimes.count == sharedElementPositionArcOffsets.count
            && sharedElementPositionArcOffsets.allSatisfy {
                $0.isFinite && $0 >= 0
            }
            && mediaBeginTime.isFinite
    }
}

@MainActor
final class BottomBarAccessorySharedElementTransition {
    static let compositorSettleAnimationKey =
        "aether.bottomBarAccessory.sharedElement.settle"

    @MainActor
    private struct ElementGeometry {
        var position: CGPoint
        var bounds: CGRect
        var cornerRadius: CGFloat

        init?(
            view: UIView,
            endpointFrameInContainer: CGRect,
            surfaceView: UIView,
            containerView: UIView,
            coordinateView: UIView,
            cornerRadius: CGFloat?
        ) {
            guard view === surfaceView || view.isDescendant(of: surfaceView),
                  endpointFrameInContainer.width.isFinite,
                  endpointFrameInContainer.height.isFinite,
                  endpointFrameInContainer.width > 0,
                  endpointFrameInContainer.height > 0 else {
                return nil
            }

            // Endpoint views keep independent, stable layout spaces inside the
            // one morphing surface. Converting either live endpoint directly
            // to the overlay would bake in the surface's *current* frame and
            // make the other endpoint wrong. Resolve the descendant locally,
            // then place that local rect into the requested surface endpoint.
            let localFrame = view.convert(view.bounds, to: surfaceView)
            let localBoundsOrigin = surfaceView.bounds.origin
            let frameInContainer = CGRect(
                x: endpointFrameInContainer.minX
                    + localFrame.minX - localBoundsOrigin.x,
                y: endpointFrameInContainer.minY
                    + localFrame.minY - localBoundsOrigin.y,
                width: localFrame.width,
                height: localFrame.height
            )
            let frame = containerView.convert(frameInContainer, to: coordinateView)
            position = CGPoint(x: frame.midX, y: frame.midY)
            bounds = CGRect(origin: .zero, size: frame.size)
            self.cornerRadius = max(
                0,
                cornerRadius
                    ?? view.layer.presentation()?.cornerRadius
                    ?? view.layer.cornerRadius
            )
        }

        init(layer: CALayer) {
            position = layer.position
            bounds = layer.bounds
            cornerRadius = max(0, layer.cornerRadius)
        }

        var isValid: Bool {
            position.x.isFinite
                && position.y.isFinite
                && bounds.width.isFinite
                && bounds.height.isFinite
                && bounds.width > 0
                && bounds.height > 0
                && cornerRadius.isFinite
        }

        func interpolated(to other: ElementGeometry, progress: CGFloat) -> ElementGeometry {
            let t = progress.clamped(to: 0 ... 1)
            return ElementGeometry(
                position: CGPoint(
                    x: position.x + (other.position.x - position.x) * t,
                    y: position.y + (other.position.y - position.y) * t
                ),
                bounds: CGRect(
                    x: bounds.origin.x + (other.bounds.origin.x - bounds.origin.x) * t,
                    y: bounds.origin.y + (other.bounds.origin.y - bounds.origin.y) * t,
                    width: bounds.width + (other.bounds.width - bounds.width) * t,
                    height: bounds.height + (other.bounds.height - bounds.height) * t
                ),
                cornerRadius: cornerRadius
                    + (other.cornerRadius - cornerRadius) * t
            )
        }

        /// Position.y follows its own release-velocity response while x,
        /// bounds, and radius retain the slower measured artwork clock.
        func interpolated(
            to other: ElementGeometry,
            geometryProgress: CGFloat,
            verticalProgress: CGFloat
        ) -> ElementGeometry {
            let geometryTime = geometryProgress.clamped(to: 0 ... 1)
            let verticalTime = verticalProgress.isFinite
                ? verticalProgress
                : geometryTime
            return ElementGeometry(
                position: CGPoint(
                    x: position.x
                        + (other.position.x - position.x) * geometryTime,
                    y: position.y
                        + (other.position.y - position.y) * verticalTime
                ),
                bounds: CGRect(
                    x: bounds.origin.x
                        + (other.bounds.origin.x - bounds.origin.x) * geometryTime,
                    y: bounds.origin.y
                        + (other.bounds.origin.y - bounds.origin.y) * geometryTime,
                    width: bounds.width
                        + (other.bounds.width - bounds.width) * geometryTime,
                    height: bounds.height
                        + (other.bounds.height - bounds.height) * geometryTime
                ),
                cornerRadius: cornerRadius
                    + (other.cornerRadius - cornerRadius) * geometryTime
            )
        }

        func offsetBy(_ delta: CGPoint) -> ElementGeometry {
            ElementGeometry(
                position: CGPoint(
                    x: position.x + delta.x,
                    y: position.y + delta.y
                ),
                bounds: bounds,
                cornerRadius: cornerRadius
            )
        }

        private init(position: CGPoint, bounds: CGRect, cornerRadius: CGFloat) {
            self.position = position
            self.bounds = bounds
            self.cornerRadius = cornerRadius
        }
    }

    @MainActor
    private final class VisibilityRecord {
        weak var view: UIView?
        let alpha: CGFloat
        let isHidden: Bool

        init(view: UIView) {
            self.view = view
            alpha = view.alpha
            isHidden = view.isHidden
        }

        func hide() {
            view?.alpha = 0
        }

        func restore() {
            guard let view else { return }
            view.alpha = alpha
            view.isHidden = isHidden
        }
    }

    @MainActor
    private final class Entry {
        let identifier: AnyHashable
        let collapsedElement: BottomBarAccessoryTransitionSharedElement
        let expandedElement: BottomBarAccessoryTransitionSharedElement
        let preferredRefreshEndpoint: BottomBarAccessoryReleaseTarget
        weak var collapsedView: UIView?
        weak var expandedView: UIView?
        let collapsedCornerRadius: CGFloat?
        let expandedCornerRadius: CGFloat?
        let representation: UIView
        var collapsedGeometry: ElementGeometry
        var expandedGeometry: ElementGeometry
        var dragOriginGeometry: ElementGeometry?
        var dragOriginArcPhase: CGFloat = 0
        var settleOriginGeometry: ElementGeometry?
        var settleInitialVelocityX: CGFloat = 0
        var settleInitialVelocityY: CGFloat = 0
        var settleInitialTopEdgeVelocityY: CGFloat = 0
        var lastPresentationGeometry: ElementGeometry
        var lastMotionSamplePosition: CGPoint?
        var lastMotionSampleTopEdgeY: CGFloat?
        var lastMotionSampleTimestamp: CFTimeInterval?
        var estimatedPositionVelocity: CGPoint = .zero
        var estimatedTopEdgeVelocityY: CGFloat = 0
        var estimatedPositionVelocityTimestamp: CFTimeInterval?
        var representedContentSignature: AnyHashable?
        var lastRefreshAttemptSignature: AnyHashable?

        init(
            identifier: AnyHashable,
            collapsedElement: BottomBarAccessoryTransitionSharedElement,
            expandedElement: BottomBarAccessoryTransitionSharedElement,
            representation: UIView,
            collapsedGeometry: ElementGeometry,
            expandedGeometry: ElementGeometry,
            initialGeometry: ElementGeometry,
            preferredRefreshEndpoint: BottomBarAccessoryReleaseTarget
        ) {
            self.identifier = identifier
            self.collapsedElement = collapsedElement
            self.expandedElement = expandedElement
            self.preferredRefreshEndpoint = preferredRefreshEndpoint
            collapsedView = collapsedElement.view
            expandedView = expandedElement.view
            collapsedCornerRadius = collapsedElement.cornerRadius
            expandedCornerRadius = expandedElement.cornerRadius
            self.representation = representation
            self.collapsedGeometry = collapsedGeometry
            self.expandedGeometry = expandedGeometry
            lastPresentationGeometry = initialGeometry
            let sourceElement = preferredRefreshEndpoint == .collapsed
                ? collapsedElement
                : expandedElement
            representedContentSignature = sourceElement.currentContentSignature()
            lastRefreshAttemptSignature = representedContentSignature
        }
    }

    private weak var coordinateView: UIView?
    private weak var containerView: UIView?
    private var entries: [Entry] = []
    private var visibilityRecords: [ObjectIdentifier: VisibilityRecord] = [:]
    private var settleOriginPresentationProgress: CGFloat?
    private var settleArcOriginPhase: CGFloat = 0
    private var settleTarget: BottomBarAccessoryReleaseTarget?
    private var settlePreservesInitialVelocity = false
    private var settleUsesReferenceCollapseLaunch = false
    private var settleVerticalSpring =
        BottomBarAccessoryTransitionConfiguration.default
            .sharedElementVerticalSpring
    private var hasCompositorSettleTrack = false

    var isActive: Bool { !entries.isEmpty }

    func prepare(
        collapsedParticipant: BottomBarAccessoryTransitionParticipant?,
        expandedParticipant: BottomBarAccessoryTransitionParticipant?,
        context: BottomBarAccessoryTransitionContext,
        surfaceView: UIView,
        containerView: UIView,
        in coordinateView: UIView,
        initialEndpoint: BottomBarAccessoryReleaseTarget
    ) {
        cleanup(restoringVisibility: true)
        self.coordinateView = coordinateView
        self.containerView = containerView

        guard !context.isReduceMotionEnabled,
              let collapsedParticipant,
              let expandedParticipant else {
            return
        }

        let collapsedElements = collapsedParticipant
            .bottomBarAccessoryTransitionSharedElements(in: context)
        let expandedElements = expandedParticipant
            .bottomBarAccessoryTransitionSharedElements(in: context)
        var collapsedByIdentifier: [AnyHashable: BottomBarAccessoryTransitionSharedElement] = [:]
        for element in collapsedElements where collapsedByIdentifier[element.identifier] == nil {
            collapsedByIdentifier[element.identifier] = element
        }

        var processedIdentifiers = Set<AnyHashable>()
        for expandedElement in expandedElements {
            guard processedIdentifiers.insert(expandedElement.identifier).inserted else {
                continue
            }
            guard let collapsedElement = collapsedByIdentifier[expandedElement.identifier],
                  let collapsedView = collapsedElement.view,
                  let expandedView = expandedElement.view else {
                continue
            }

            // Equal signatures guarantee that both trees represent the same
            // visual content. Prefer the larger endpoint as the snapshot
            // source in that case so a compact source is not rasterized and
            // visibly upscaled across the expanded artwork geometry.
            let collapsedSignature = collapsedElement.currentContentSignature()
            let expandedSignature = expandedElement.currentContentSignature()
            let hasMatchingSignatures = collapsedSignature != nil
                && collapsedSignature == expandedSignature
            let collapsedArea = collapsedView.bounds.width
                * collapsedView.bounds.height
            let expandedArea = expandedView.bounds.width
                * expandedView.bounds.height
            let representationEndpoint: BottomBarAccessoryReleaseTarget
            if hasMatchingSignatures, expandedArea > collapsedArea {
                representationEndpoint = .expanded
            } else {
                representationEndpoint = initialEndpoint
            }
            let sourceElement = representationEndpoint == .collapsed
                ? collapsedElement
                : expandedElement
            guard let representation = sourceElement.makeRepresentation(),
                  representation !== collapsedView,
                  representation !== expandedView else {
                continue
            }

            guard let collapsedGeometry = ElementGeometry(
                view: collapsedView,
                endpointFrameInContainer: context.geometry.collapsedFrame,
                surfaceView: surfaceView,
                containerView: containerView,
                coordinateView: coordinateView,
                cornerRadius: collapsedElement.cornerRadius
            ), let expandedGeometry = ElementGeometry(
                view: expandedView,
                endpointFrameInContainer: context.geometry.expandedFrame,
                surfaceView: surfaceView,
                containerView: containerView,
                coordinateView: coordinateView,
                cornerRadius: expandedElement.cornerRadius
            ) else {
                continue
            }
            guard collapsedGeometry.isValid, expandedGeometry.isValid else { continue }

            representation.translatesAutoresizingMaskIntoConstraints = true
            representation.autoresizingMask = []
            representation.contentMode = sourceElement.contentMode
            representation.clipsToBounds = true
            representation.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            apply(
                initialEndpoint == .collapsed ? collapsedGeometry : expandedGeometry,
                to: representation.layer
            )
            coordinateView.addSubview(representation)

            preserveAndHide(collapsedView)
            preserveAndHide(expandedView)
            entries.append(
                Entry(
                    identifier: expandedElement.identifier,
                    collapsedElement: collapsedElement,
                    expandedElement: expandedElement,
                    representation: representation,
                    collapsedGeometry: collapsedGeometry,
                    expandedGeometry: expandedGeometry,
                    initialGeometry: initialEndpoint == .collapsed
                        ? collapsedGeometry
                        : expandedGeometry,
                    preferredRefreshEndpoint: representationEndpoint
                )
            )
        }
    }

    func refreshEndpointGeometry(
        _ geometry: BottomBarAccessoryTransitionGeometry,
        surfaceView: UIView,
        containerView: UIView
    ) {
        guard let coordinateView else { return }
        for entry in entries {
            if let collapsedView = entry.collapsedView {
                let resolvedGeometry = ElementGeometry(
                    view: collapsedView,
                    endpointFrameInContainer: geometry.collapsedFrame,
                    surfaceView: surfaceView,
                    containerView: containerView,
                    coordinateView: coordinateView,
                    cornerRadius: entry.collapsedCornerRadius
                )
                if let resolvedGeometry, resolvedGeometry.isValid {
                    entry.collapsedGeometry = resolvedGeometry
                }
            }
            if let expandedView = entry.expandedView {
                let resolvedGeometry = ElementGeometry(
                    view: expandedView,
                    endpointFrameInContainer: geometry.expandedFrame,
                    surfaceView: surfaceView,
                    containerView: containerView,
                    coordinateView: coordinateView,
                    cornerRadius: entry.expandedCornerRadius
                )
                if let resolvedGeometry, resolvedGeometry.isValid {
                    entry.expandedGeometry = resolvedGeometry
                }
            }
        }
    }

    /// Captures one visual origin for the newest settle. The coordinator later
    /// installs a compositor track sampled from the one authoritative surface
    /// trajectory, so artwork and glass share duration, key times, and cadence
    /// without relying on main-thread display-link geometry writes.
    func beginSettle(
        to target: BottomBarAccessoryReleaseTarget,
        fromPresentationProgress rawPresentationProgress: CGFloat,
        fromCollapseArcPhase rawCollapseArcPhase: CGFloat? = nil,
        initialVelocityY: CGFloat = 0,
        prefersProvidedInitialVelocity: Bool = false,
        usesReferenceCollapseLaunch: Bool = false,
        verticalSpring: BottomBarAccessoryTransitionConfiguration.Spring =
            BottomBarAccessoryTransitionConfiguration.default
                .sharedElementVerticalSpring
    ) {
        refreshRepresentationsIfNeeded()
        hasCompositorSettleTrack = false
        settleOriginPresentationProgress = rawPresentationProgress
            .clamped(to: 0 ... 1)
        settleArcOriginPhase = rawCollapseArcPhase.flatMap {
            $0.isFinite ? $0.clamped(to: 0 ... 1) : nil
        } ?? (1 - rawPresentationProgress.clamped(to: 0 ... 1))
        settleTarget = target
        settlePreservesInitialVelocity = prefersProvidedInitialVelocity
        settleUsesReferenceCollapseLaunch = usesReferenceCollapseLaunch
        settleVerticalSpring = verticalSpring
        let sampleTimestamp = CACurrentMediaTime()
        withoutImplicitAnimations {
            for entry in entries {
                let layer = entry.representation.layer
                let geometry: ElementGeometry
                if let presentation = layer.presentation() {
                    let sampled = ElementGeometry(layer: presentation)
                    geometry = sampled.isValid
                        ? sampled
                        : entry.lastPresentationGeometry
                } else {
                    geometry = ElementGeometry(layer: layer)
                }
                guard geometry.isValid else { continue }
                let sampledVelocity = entry.estimatedPositionVelocity
                let sampledVelocityIsFresh: Bool
                if let velocityTimestamp = entry
                    .estimatedPositionVelocityTimestamp {
                    let age = sampleTimestamp - velocityTimestamp
                    sampledVelocityIsFresh = age.isFinite
                        && age >= 0
                        && age <= 0.05
                        && sampledVelocity.x.isFinite
                        && sampledVelocity.y.isFinite
                } else {
                    sampledVelocityIsFresh = false
                }
                let providedVelocity = convertDeltaFromContainer(
                    CGPoint(x: 0, y: initialVelocityY)
                ).y
                // A held representation has a real derivative of its own:
                // drag preview, rubber banding, and coordinate conversion can
                // all make it differ from the surface top. Prefer that fresh
                // visual sample and use the coordinator's analytic top
                // derivative only when sampling was unavailable or stale.
                entry.settleInitialVelocityX = sampledVelocityIsFresh
                    ? sampledVelocity.x
                    : 0
                entry.settleInitialVelocityY = sampledVelocityIsFresh
                    ? sampledVelocity.y
                    : providedVelocity
                entry.settleInitialTopEdgeVelocityY = sampledVelocityIsFresh
                    ? entry.estimatedTopEdgeVelocityY
                    : providedVelocity
                recordMotionSample(
                    geometry,
                    for: entry,
                    timestamp: sampleTimestamp
                )
                if !entry.settleInitialVelocityY.isFinite {
                    entry.settleInitialVelocityY = 0
                }
                if !entry.settleInitialVelocityX.isFinite {
                    entry.settleInitialVelocityX = 0
                }
                if !entry.settleInitialTopEdgeVelocityY.isFinite {
                    entry.settleInitialTopEdgeVelocityY = 0
                }
                layer.removeAllAnimations()
                apply(geometry, to: layer)
                entry.settleOriginGeometry = geometry
                entry.lastPresentationGeometry = geometry
            }
        }
    }

    /// Installs representation geometry on Core Animation using the exact
    /// sampled presentation progress of the surface track. Every entry keeps
    /// its own endpoint layout space, but all entries and the surface share one
    /// host-time origin and one keyframe clock.
    func installSettleTrack(_ track: BottomBarAccessoryCompositorSettleTrack) {
        guard track.isValid,
              let settleTarget,
              settleOriginPresentationProgress != nil else {
            return
        }

        for entry in entries {
            let origin = entry.settleOriginGeometry
                ?? entry.lastPresentationGeometry
            let target = settleTarget == .collapsed
                ? entry.collapsedGeometry
                : entry.expandedGeometry
            // One stable endpoint normal owns every phase. Recomputing it
            // from a deeply dragged transient origin can flip normal.y after
            // the cover passes below its Mini slot, visibly inverting the
            // grabber-close curve.
            let canonicalArcNormal = Self.screenRightChordNormal(
                from: entry.expandedGeometry.position,
                to: entry.collapsedGeometry.position
            )
            let arcOriginPhase = settleArcOriginPhase.clamped(to: 0 ... 1)
            let arcTargetPhase: CGFloat = settleTarget == .collapsed ? 1 : 0
            let arcOriginOffset = BottomBarAccessoryTransitionCoordinator
                .sharedElementPositionArcOffset(
                    atCollapsePhase: arcOriginPhase
                )
            let arcTargetOffset = BottomBarAccessoryTransitionCoordinator
                .sharedElementPositionArcOffset(
                    atCollapsePhase: arcTargetPhase
                )
            let verticalDistance = target.position.y - origin.position.y
            let normalizedInitialVelocity = abs(verticalDistance) > 0.001
                ? entry.settleInitialVelocityY / verticalDistance
                : 0
            let originTopEdgeY = origin.position.y - 0.5 * origin.bounds.height
            let targetTopEdgeY = target.position.y - 0.5 * target.bounds.height
            let topEdgeDistance = targetTopEdgeY - originTopEdgeY
            let capturedTopEdgeVelocity = entry.settleInitialTopEdgeVelocityY
            let normalizedTopEdgeVelocity = abs(topEdgeDistance) > 0.001
                ? capturedTopEdgeVelocity / topEdgeDistance
                : 0
            let collapseTopVelocitySeed: CGFloat
            if settleUsesReferenceCollapseLaunch {
                collapseTopVelocitySeed = Self
                    .referenceCollapseTopEdgeNormalizedVelocity
            } else {
                collapseTopVelocitySeed = normalizedTopEdgeVelocity.isFinite
                    ? normalizedTopEdgeVelocity.clamped(
                        to: -Self.maximumCollapseTopEdgeNormalizedVelocity
                            ... Self.maximumCollapseTopEdgeNormalizedVelocity
                    )
                    : 0
            }
            let preferredRate = track.preferredFrameRateRange.preferred.flatMap {
                $0.isFinite ? max(1, $0) : nil
            } ?? 120
            let visibleSampleInterval = TimeInterval(1 / preferredRate)
            let hasSurfaceGuide = track.surfaceMinYValues.count
                == track.keyTimes.count
            // A stable tap-open follows the measured artwork clock directly.
            // Drag releases and interrupted/reversed settles instead inherit
            // the physical surface guide so their captured derivative remains
            // continuous. Collapse always uses that guide because its visible
            // release inertia is part of the Mini docking flight.
            let usesSurfaceRelativeVerticalGuide = hasSurfaceGuide
                && (settleTarget == .collapsed
                    || settlePreservesInitialVelocity)
            let surfaceOriginMinY = track.surfaceMinYValues.first ?? 0
            let surfaceDisplacements = hasSurfaceGuide
                ? track.surfaceMinYValues.map { sample in
                    convertDeltaFromContainer(
                        CGPoint(x: 0, y: sample - surfaceOriginMinY)
                    ).y
                }
                : []
            let surfaceTotalDisplacement = surfaceDisplacements.last ?? 0
            let relativeVerticalDistance = verticalDistance
                - surfaceTotalDisplacement
            let surfaceInitialVelocity = convertDeltaFromContainer(
                CGPoint(x: 0, y: track.surfaceInitialMinYVelocity)
            ).y
            let slowClockInitialVelocity =
                BottomBarAccessoryTransitionCoordinator
                    .sharedElementGeometryInitialVelocity(
                        settleDuration: track.duration,
                        target: settleTarget
                    )
            let arcDerivativeAtOrigin = Self.sharedElementArcDerivative(
                atCollapsePhase: arcOriginPhase
            )
            let arcCorrectionDerivative = arcDerivativeAtOrigin
                * (arcTargetPhase - arcOriginPhase)
                - (arcTargetOffset - arcOriginOffset)
            let baseVerticalVelocity = usesSurfaceRelativeVerticalGuide
                ? surfaceInitialVelocity
                    + relativeVerticalDistance * slowClockInitialVelocity
                : verticalDistance * slowClockInitialVelocity
            let baseInitialVelocity = baseVerticalVelocity
                + canonicalArcNormal.y * arcCorrectionDerivative
                    * slowClockInitialVelocity
            let capturedInitialVelocity = normalizedInitialVelocity.isFinite
                && abs(verticalDistance) > 0.001
                ? normalizedInitialVelocity.clamped(to: -80 ... 80)
                    * verticalDistance
                : entry.settleInitialVelocityY
            let velocityResidual = capturedInitialVelocity.isFinite
                ? capturedInitialVelocity - baseInitialVelocity
                : -baseInitialVelocity
            let surfaceLandingDuration = Self.surfaceLandingDuration(
                values: track.surfaceMinYValues,
                keyTimes: track.keyTimes,
                settleDuration: track.duration
            )
            let opticalLandingDuration = zip(
                track.keyTimes,
                track.sharedElementProgressValues
            ).first { _, progress in
                progress >= 1 - 0.000_001
            }.map { keyTime, _ in
                TimeInterval(CGFloat(truncating: keyTime)) * track.duration
            }
            let residualDuration = Self.sharedElementVelocityResidualDuration(
                surfaceLandingDuration: surfaceLandingDuration,
                sampleInterval: visibleSampleInterval,
                maximumDuration: opticalLandingDuration
            )
            let collapseTopVelocityResidual = settleUsesReferenceCollapseLaunch
                ? 0
                : capturedTopEdgeVelocity
                    - collapseTopVelocitySeed * topEdgeDistance
            let verticalMotion = BottomBarAccessoryTransitionCoordinator
                .resolvedSharedElementVerticalMotion(
                    normalizedInitialVelocity: normalizedInitialVelocity,
                    travelDistance: verticalDistance,
                    duration: track.duration,
                    sampleInterval: visibleSampleInterval,
                    spring: settleVerticalSpring
                )
            let baseGeometries = zip(
                zip(track.keyTimes, track.sharedElementProgressValues),
                track.keyTimes.indices
            ).map { sample, index in
                let (keyTime, progress) = sample
                let linearProgress = CGFloat(truncating: keyTime)
                let elapsed = TimeInterval(linearProgress) * track.duration
                var geometry: ElementGeometry
                if settleTarget == .collapsed {
                    geometry = origin.interpolated(
                        to: target,
                        progress: progress
                    )
                    let topProgress =
                        BottomBarAccessoryTransitionCoordinator
                            .sharedElementVerticalProgress(
                                at: linearProgress,
                                settleDuration: track.duration,
                                spring: settleVerticalSpring,
                                normalizedInitialVelocity:
                                    collapseTopVelocitySeed
                            )
                    let residual = Self.sharedElementVelocityResidual(
                        elapsed: elapsed,
                        duration: residualDuration,
                        velocityDelta: collapseTopVelocityResidual
                    )
                    let topEdgeY = originTopEdgeY
                        + topEdgeDistance * topProgress
                        + residual
                    // Animate the optical top edge directly. Recentring with
                    // this sample's independently shrinking bounds is what
                    // preserves the reference curve; interpolating center-y
                    // would make the resize look like a late position jump.
                    geometry.position.y = topEdgeY
                        + 0.5 * geometry.bounds.height
                } else if usesSurfaceRelativeVerticalGuide {
                    let residual = Self.sharedElementVelocityResidual(
                        elapsed: elapsed,
                        duration: residualDuration,
                        velocityDelta: velocityResidual
                    )
                    geometry = origin.interpolated(
                        to: target,
                        progress: progress
                    )
                    geometry.position.y = origin.position.y
                        + surfaceDisplacements[index]
                        + relativeVerticalDistance * progress
                        + residual
                } else if hasSurfaceGuide {
                    // A normal collapsed -> expanded tap has no incoming
                    // physical velocity to preserve. Keeping its y position
                    // on the same measured clock as x/size/corner avoids
                    // inheriting the slower surface response as visible lag.
                    geometry = origin.interpolated(
                        to: target,
                        progress: progress
                    )
                } else {
                    // Compatibility for custom/testing tracks that predate the
                    // absolute surface guide. Production tracks always take the
                    // surface-relative path above.
                    let verticalProgress =
                        BottomBarAccessoryTransitionCoordinator
                            .sharedElementVerticalProgress(
                                at: CGFloat(truncating: keyTime),
                                settleDuration: track.duration,
                                spring: verticalMotion.spring,
                                normalizedInitialVelocity:
                                    verticalMotion.velocitySeed
                            )
                    geometry = origin.interpolated(
                        to: target,
                        geometryProgress: progress,
                        verticalProgress: verticalProgress
                    )
                }
                // `origin` already contains the absolute arc at c0, and its
                // interpolation toward `target` linearly carries that offset
                // away. Add only the difference between that embedded line
                // and the canonical absolute bow A(c(s)); this gives exact C0
                // at release and cannot restart a second local quartic.
                if settleTarget != .collapsed {
                    let phase = arcOriginPhase
                        + (arcTargetPhase - arcOriginPhase) * progress
                    let desiredArc = BottomBarAccessoryTransitionCoordinator
                        .sharedElementPositionArcOffset(
                            atCollapsePhase: phase
                        )
                    let embeddedArc = arcOriginOffset
                        + (arcTargetOffset - arcOriginOffset) * progress
                    let arcCorrection = desiredArc - embeddedArc
                    geometry.position.x += canonicalArcNormal.x * arcCorrection
                    geometry.position.y += canonicalArcNormal.y * arcCorrection
                }
                if settlePreservesInitialVelocity,
                   settleTarget != .collapsed {
                    let basePositionX = geometry.position.x
                    geometry.position.x += Self
                        .sharedElementHorizontalInertialBridge(
                            elapsed: elapsed,
                            duration: residualDuration,
                            originPosition: origin.position.x,
                            basePosition: basePositionX,
                            capturedVelocity: entry.settleInitialVelocityX
                        )
                }
                return geometry
            }
            // The collapse spring is intentionally allowed to cross the Mini
            // slot once and return. The former one-sided landing postprocessor
            // erased that reference overshoot and introduced a second arrival.
            let geometries = baseGeometries
            guard geometries.count == track.keyTimes.count else { continue }

            let position = Self.keyframeAnimation(
                keyPath: "position",
                values: geometries.map { NSValue(cgPoint: $0.position) },
                track: track
            )
            let bounds = Self.keyframeAnimation(
                keyPath: "bounds",
                values: geometries.map { NSValue(cgRect: $0.bounds) },
                track: track
            )
            let cornerRadius = Self.keyframeAnimation(
                keyPath: "cornerRadius",
                values: geometries.map { NSNumber(value: $0.cornerRadius) },
                track: track
            )
            let group = CAAnimationGroup()
            group.animations = [position, bounds, cornerRadius]
            group.duration = track.duration
            group.beginTime = entry.representation.layer.convertTime(
                track.mediaBeginTime,
                from: nil
            )
            group.isRemovedOnCompletion = true
            group.preferredFrameRateRange = track.preferredFrameRateRange

            withoutImplicitAnimations {
                apply(target, to: entry.representation.layer)
            }
            entry.representation.layer.add(
                group,
                forKey: Self.compositorSettleAnimationKey
            )
        }
        hasCompositorSettleTrack = !entries.isEmpty
    }

    /// Replaces only the terminal screen-y flight with a one-sided quintic.
    ///
    /// A forceful close can carry the artwork's visible top edge beyond its
    /// compact slot before the physical surface starts returning. Keeping the
    /// surface-relative guide authoritative all the way to the endpoint then
    /// makes the cover cross the slot, pause, and approach it a second time.
    /// Preserve that one physical carry/turn, then select the first inbound
    /// sample whose position, velocity and acceleration admit a monotonic
    /// quintic Hermite landing. From that sample onward the visible top edge
    /// stays on the same side of the compact endpoint and reaches it only on
    /// the common final compositor key.
    ///
    /// X, bounds, corner radius, the slow artwork clock, and the rightward arc
    /// remain byte-for-byte those of `baseGeometries`. Solving in terms of the
    /// visible top edge (rather than layer center-y) prevents artwork shrinking
    /// from masquerading as a terminal position reversal.
    private static func oneSidedTerminalArtworkGeometries(
        _ baseGeometries: [ElementGeometry],
        target: ElementGeometry,
        keyTimes: [NSNumber],
        duration: TimeInterval
    ) -> [ElementGeometry] {
        guard baseGeometries.count == keyTimes.count,
              baseGeometries.count >= 6,
              duration.isFinite,
              duration > 0 else {
            return baseGeometries
        }

        let times = keyTimes.map {
            TimeInterval(CGFloat(truncating: $0)) * duration
        }
        guard zip(times, times.dropFirst()).allSatisfy({ lhs, rhs in
            lhs.isFinite && rhs.isFinite && rhs > lhs
        }) else {
            return baseGeometries
        }

        let topValues = baseGeometries.map {
            $0.position.y - 0.5 * $0.bounds.height
        }
        let targetTop = target.position.y - 0.5 * target.bounds.height
        guard targetTop.isFinite,
              topValues.allSatisfy(\.isFinite) else {
            return baseGeometries
        }
        guard let initialResidual = topValues
            .lazy
            .map({ $0 - targetTop })
            .first(where: { abs($0) > 0.001 }) else {
            return baseGeometries
        }
        // Freeze the approach side at release. A candidate found after the
        // base track has already crossed the compact slot would merely hide
        // the first crossing and preserve the visible second landing.
        let landingSide: CGFloat = initialResidual >= 0 ? 1 : -1

        enum LandingCurve {
            case quintic
            case positiveDensity(
                linearExponent: Double,
                quadraticExponent: Double,
                logPrimaryNormalization: Double,
                floorWeight: Double,
                normalization: Double
            )
        }

        struct Landing {
            let index: Int
            let side: CGFloat
            let residual: CGFloat
            let normalizedVelocity: CGFloat
            let normalizedAcceleration: CGFloat
            let curve: LandingCurve
        }

        // Exact monotonicity test for the generalized endpoint quintic:
        //
        // q = h0 + m*h1 + A*h2
        // q' = (1-u)^2 * P(u)
        // P  = m + (2m+A)u + (-30-15m-2.5A)u^2
        //
        // P <= 0 on [0, 1] makes q nonincreasing from one to zero, so the
        // artwork cannot cross the endpoint or introduce another turn.
        func admitsMonotonicLanding(
            normalizedVelocity m: CGFloat,
            normalizedAcceleration a: CGFloat
        ) -> Bool {
            guard m.isFinite, a.isFinite, m <= 0.000_001 else {
                return false
            }
            let b = 2 * m + a
            let c = -30 - 15 * m - 2.5 * a
            var maximum = max(m, m + b + c)
            if c < 0 {
                let vertex = -b / (2 * c)
                if vertex > 0, vertex < 1 {
                    maximum = max(
                        maximum,
                        m + b * vertex + c * vertex * vertex
                    )
                }
            }
            return maximum <= 0.000_001
        }

        // Log-domain composite Simpson integration for
        // (1-u)^2 * exp(a*u + b*u^2). The positive density lets the fallback
        // match arbitrary inbound position/velocity/acceleration while its
        // integral remains strictly one-sided by construction.
        func logPositiveDensityIntegral(
            from lowerBound: CGFloat,
            linearExponent a: Double,
            quadraticExponent b: Double
        ) -> Double? {
            let lower = Double(lowerBound.clamped(to: 0 ... 1))
            guard a.isFinite, b.isFinite, lower < 1 else {
                return lower >= 1 ? -.infinity : nil
            }
            let stepCount = 128
            let step = (1 - lower) / Double(stepCount)
            var terms: [Double] = []
            terms.reserveCapacity(stepCount)
            for index in 0 ..< stepCount {
                let x = lower + Double(index) * step
                let oneMinusX = 1 - x
                guard oneMinusX > 0 else { continue }
                let weight: Double
                if index == 0 {
                    weight = 1
                } else if index.isMultiple(of: 2) {
                    weight = 2
                } else {
                    weight = 4
                }
                terms.append(
                    log(weight)
                        + 2 * log(oneMinusX)
                        + a * x
                        + b * x * x
                )
            }
            guard let maximum = terms.max(), maximum.isFinite else {
                return nil
            }
            let scaledSum = terms.reduce(0.0) {
                $0 + exp($1 - maximum)
            }
            guard scaledSum.isFinite, scaledSum > 0 else { return nil }
            return log(step / 3) + maximum + log(scaledSum)
        }

        func positiveDensityCurve(
            normalizedVelocity m: CGFloat,
            normalizedAcceleration a: CGFloat
        ) -> LandingCurve? {
            guard m.isFinite,
                  a.isFinite,
                  m < -0.000_001 else {
                return nil
            }
            // Keep a small analytic terminal component instead of letting the
            // exponential density collapse to a numeric/visual zero early.
            // It preserves the exact C2 splice, keeps the cover moving through
            // the Mini's one return, and is still strictly one-sided.
            let floorWeight = 0.03
            let resolvedM = Double(m)
            let resolvedA = Double(a)
            let onePlusFloor = 1 + floorWeight
            let linearExponent = 2 * onePlusFloor
                + onePlusFloor * resolvedA / resolvedM
            let normalization = -onePlusFloor / resolvedM
            let primaryNormalization = normalization - floorWeight / 3
            guard linearExponent.isFinite,
                  normalization.isFinite,
                  normalization > 0,
                  primaryNormalization.isFinite,
                  primaryNormalization > 0 else {
                return nil
            }
            let targetLogPrimaryNormalization = log(primaryNormalization)

            func error(at quadraticExponent: Double) -> Double? {
                guard let logIntegral = logPositiveDensityIntegral(
                    from: 0,
                    linearExponent: linearExponent,
                    quadraticExponent: quadraticExponent
                ) else {
                    return nil
                }
                return logIntegral - targetLogPrimaryNormalization
            }

            var lower = -32.0
            var upper = 32.0
            var lowerError = error(at: lower)
            var upperError = error(at: upper)
            for _ in 0 ..< 12 where (lowerError ?? 1) > 0 {
                lower *= 2
                lowerError = error(at: lower)
            }
            for _ in 0 ..< 12 where (upperError ?? -1) < 0 {
                upper *= 2
                upperError = error(at: upper)
            }
            guard let resolvedLowerError = lowerError,
                  let resolvedUpperError = upperError,
                  resolvedLowerError <= 0,
                  resolvedUpperError >= 0 else {
                return nil
            }

            for _ in 0 ..< 64 {
                let middle = 0.5 * (lower + upper)
                guard let middleError = error(at: middle) else {
                    return nil
                }
                if middleError < 0 {
                    lower = middle
                } else {
                    upper = middle
                }
            }
            let quadraticExponent = 0.5 * (lower + upper)
            // The exponential component may have one speed crest, but not a
            // valley followed by a second launch. Adding the monotonic floor
            // cannot create a new valley when this component passes the guard.
            let hasSpeedValley = linearExponent < 2
                && quadraticExponent > 1
                && linearExponent + 2 * quadraticExponent
                    - 4 * sqrt(quadraticExponent) > 0
            guard !hasSpeedValley else { return nil }
            guard let logPrimaryNormalization = logPositiveDensityIntegral(
                from: 0,
                linearExponent: linearExponent,
                quadraticExponent: quadraticExponent
            ) else {
                return nil
            }
            return .positiveDensity(
                linearExponent: linearExponent,
                quadraticExponent: quadraticExponent,
                logPrimaryNormalization: logPrimaryNormalization,
                floorWeight: floorWeight,
                normalization: normalization
            )
        }

        func landingProgress(
            at u: CGFloat,
            curve: LandingCurve,
            normalizedVelocity: CGFloat,
            normalizedAcceleration: CGFloat
        ) -> CGFloat? {
            if u <= 0 { return 1 }
            if u >= 1 { return 0 }
            switch curve {
            case .quintic:
                let u2 = u * u
                let u3 = u2 * u
                let u4 = u3 * u
                let u5 = u4 * u
                let oneMinusU = 1 - u
                let h0 = 1 - 10 * u3 + 15 * u4 - 6 * u5
                let h1 = u - 6 * u3 + 8 * u4 - 3 * u5
                let h2 = 0.5 * u2
                    * oneMinusU * oneMinusU * oneMinusU
                let value = h0
                    + normalizedVelocity * h1
                    + normalizedAcceleration * h2
                return value.isFinite ? value : nil
            case let .positiveDensity(
                linearExponent,
                quadraticExponent,
                logPrimaryNormalization,
                floorWeight,
                normalization
            ):
                guard let logRemaining = logPositiveDensityIntegral(
                    from: u,
                    linearExponent: linearExponent,
                    quadraticExponent: quadraticExponent
                ) else {
                    return nil
                }
                let primaryRemaining = exp(
                    logRemaining - logPrimaryNormalization
                ) * (normalization - floorWeight / 3)
                let oneMinusU = Double(1 - u)
                let floorRemaining = floorWeight
                    * oneMinusU * oneMinusU * oneMinusU / 3
                let value = CGFloat(
                    (primaryRemaining + floorRemaining) / normalization
                )
                return value.isFinite ? value : nil
            }
        }

        let surfacePeakTime = duration * TimeInterval(
            BottomBarAccessoryTransitionCoordinator
                .collapseRigidDockingDipPeakProgress
        )

        func isValidLandingCurve(
            _ curve: LandingCurve,
            index: Int,
            residual: CGFloat,
            normalizedVelocity: CGFloat,
            normalizedAcceleration: CGFloat
        ) -> Bool {
            let startTime = times[index]
            let remainingDuration = duration - startTime
            guard remainingDuration > 0 else { return false }
            var previousProgress: CGFloat = 1
            for sampleIndex in (index + 1) ..< baseGeometries.count {
                let sampleU = CGFloat(
                    (times[sampleIndex] - startTime) / remainingDuration
                ).clamped(to: 0 ... 1)
                guard let sampleProgress = landingProgress(
                    at: sampleU,
                    curve: curve,
                    normalizedVelocity: normalizedVelocity,
                    normalizedAcceleration: normalizedAcceleration
                ), sampleProgress >= 0,
                   sampleProgress <= previousProgress,
                   sampleIndex == baseGeometries.count - 1
                    || sampleProgress > 0 else {
                    return false
                }
                if sampleIndex < baseGeometries.count - 1,
                   sampleProgress == previousProgress {
                    return false
                }
                previousProgress = sampleProgress
            }
            if startTime < surfacePeakTime,
               let peakProgress = landingProgress(
                   at: CGFloat(
                       (surfacePeakTime - startTime) / remainingDuration
                   ),
                   curve: curve,
                   normalizedVelocity: normalizedVelocity,
                   normalizedAcceleration: normalizedAcceleration
               ) {
                return residual * peakProgress >= 0.5
            }
            return true
        }

        var landing: Landing?
        for index in 1 ..< (baseGeometries.count - 1) {
            let previousInterval = times[index] - times[index - 1]
            let nextInterval = times[index + 1] - times[index]
            guard previousInterval > 0, nextInterval > 0 else { continue }

            let rawResidual = topValues[index] - targetTop
            guard rawResidual.isFinite else { continue }
            let previousResidual = (topValues[index - 1] - targetTop)
                * landingSide
            let residual = rawResidual * landingSide
            let nextResidual = (topValues[index + 1] - targetTop)
                * landingSide
            // The three-point derivative must describe an inbound sample on
            // one unchanged side. An outward carry therefore passes through
            // its real turn before it can become a landing candidate.
            guard previousResidual > 0,
                  residual > 0,
                  nextResidual > 0 else {
                continue
            }

            let previousChord = (residual - previousResidual)
                / CGFloat(previousInterval)
            let nextChord = (nextResidual - residual)
                / CGFloat(nextInterval)
            guard previousChord < -0.000_001,
                  nextChord < -0.000_001 else {
                continue
            }
            let intervalSum = previousInterval + nextInterval
            let velocity = (
                CGFloat(nextInterval) * previousChord
                    + CGFloat(previousInterval) * nextChord
            ) / CGFloat(intervalSum)
            let acceleration = 2 * (nextChord - previousChord)
                / CGFloat(intervalSum)
            let remainingDuration = duration - times[index]
            guard velocity.isFinite,
                  acceleration.isFinite,
                  remainingDuration >= 3 * max(
                      previousInterval,
                      nextInterval
                  ) else {
                continue
            }

            let normalizedVelocity = velocity
                * CGFloat(remainingDuration) / residual
            let normalizedAcceleration = acceleration
                * CGFloat(remainingDuration * remainingDuration) / residual
            var candidateCurves: [LandingCurve] = []
            if admitsMonotonicLanding(
                normalizedVelocity: normalizedVelocity,
                normalizedAcceleration: normalizedAcceleration
            ) {
                candidateCurves.append(.quintic)
            }
            if let densityCurve = positiveDensityCurve(
                normalizedVelocity: normalizedVelocity,
                normalizedAcceleration: normalizedAcceleration
            ) {
                candidateCurves.append(densityCurve)
            }
            guard let curve = candidateCurves.first(where: { candidate in
                isValidLandingCurve(
                    candidate,
                    index: index,
                    residual: residual,
                    normalizedVelocity: normalizedVelocity,
                    normalizedAcceleration: normalizedAcceleration
                )
            }) else {
                continue
            }
            landing = Landing(
                index: index,
                side: landingSide,
                residual: residual,
                normalizedVelocity: normalizedVelocity,
                normalizedAcceleration: normalizedAcceleration,
                curve: curve
            )
            break
        }

        guard let landing else { return baseGeometries }
        let startTime = times[landing.index]
        let remainingDuration = duration - startTime
        guard remainingDuration > 0 else { return baseGeometries }

        var result = baseGeometries
        for index in landing.index ..< result.count {
            let u = CGFloat(
                (times[index] - startTime) / remainingDuration
            ).clamped(to: 0 ... 1)
            guard let progress = landingProgress(
                at: u,
                curve: landing.curve,
                normalizedVelocity: landing.normalizedVelocity,
                normalizedAcceleration: landing.normalizedAcceleration
            ) else {
                return baseGeometries
            }
            let top = targetTop
                + landing.side * landing.residual * progress
            result[index].position.y = top
                + 0.5 * result[index].bounds.height
        }
        // Avoid even sub-pixel arithmetic residue at representation teardown.
        result[result.count - 1].position.y = target.position.y
        return result
    }

    /// Returns a unit normal to the endpoint chord whose screen-x component
    /// is nonnegative. Reversing the chord therefore retains the same visual
    /// rightward bow instead of mirroring the arc on close.
    private static func screenRightChordNormal(
        from origin: CGPoint,
        to target: CGPoint
    ) -> CGPoint {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let length = hypot(dx, dy)
        guard length.isFinite, length > 0.001 else { return .zero }
        var normal = CGPoint(x: dy / length, y: -dx / length)
        if normal.x < 0 {
            normal.x = -normal.x
            normal.y = -normal.y
        }
        return normal
    }

    private static func sharedElementArcDerivative(
        atCollapsePhase rawPhase: CGFloat
    ) -> CGFloat {
        let phase = rawPhase.isFinite
            ? rawPhase.clamped(to: 0 ... 1)
            : 0
        // d/dc [2 * 16c²(1-c)²]
        return BottomBarAccessoryTransitionCoordinator
            .sharedElementPositionArcAmplitude
            * 32 * phase * (1 - phase) * (1 - 2 * phase)
    }

    /// Finds the first sample after which the physical surface top is docked.
    /// The artwork's velocity correction is gone by this time, so it cannot
    /// become a fixed phase lag during the slower size/corner tail.
    static func surfaceLandingDuration(
        values: [CGFloat],
        keyTimes: [NSNumber],
        settleDuration: TimeInterval,
        tolerance: CGFloat = 0.25
    ) -> TimeInterval {
        guard values.count == keyTimes.count,
              values.count >= 2,
              let target = values.last,
              target.isFinite else {
            return max(0.01, settleDuration)
        }
        let resolvedTolerance = tolerance.isFinite
            ? max(0, tolerance)
            : 0.25
        for index in values.indices where values[index...].allSatisfy({
            $0.isFinite && abs($0 - target) <= resolvedTolerance
        }) {
            let progress = CGFloat(truncating: keyTimes[index])
                .clamped(to: 0 ... 1)
            return max(0, TimeInterval(progress) * settleDuration)
        }
        return max(0.01, settleDuration)
    }

    /// Keeps the correction through the physical top-edge flight, then lands
    /// it with three continuous derivatives. The slow size/corner clock is not
    /// delayed after the surface has docked.
    static func sharedElementVelocityResidualDuration(
        surfaceLandingDuration: TimeInterval,
        sampleInterval: TimeInterval,
        maximumDuration: TimeInterval? = nil
    ) -> TimeInterval {
        let cadenceFloor = sampleInterval.isFinite
            ? max(1.0 / 240.0, sampleInterval)
            : 1.0 / 120.0
        let physicalDuration = surfaceLandingDuration.isFinite
            ? max(cadenceFloor, surfaceLandingDuration)
            : cadenceFloor
        guard let maximumDuration,
              maximumDuration.isFinite,
              maximumDuration > 0 else {
            return physicalDuration
        }
        // The residual exists only to reconcile the release derivative. Let
        // the surface-relative guide own the terminal flight after the slow
        // optical clock has landed; carrying release residue past that point
        // is perceived as a separate final artwork jump.
        return min(
            physicalDuration,
            max(cadenceFloor, maximumDuration)
        )
    }

    /// Maximum spatial contribution of release-velocity reconciliation. The
    /// physical surface-relative base already supplies the large measured bow;
    /// the residual only removes a release seam and must not grow into a second
    /// force-dependent flight of its own.
    static let sharedElementVelocityResidualSpatialLimit: CGFloat = 10

    /// The reference close launches the cover's *visible top edge* with this
    /// normalized velocity. Together with the configured ζ≈0.73 / ωn≈14.9
    /// spring it reproduces the measured one-pass overshoot and slow return.
    static let referenceCollapseTopEdgeNormalizedVelocity: CGFloat = 12.6
    static let maximumCollapseTopEdgeNormalizedVelocity: CGFloat = 14

    /// C3-compact velocity correction with a smooth spatial limit. Position
    /// and its first three derivatives are zero at the terminal end; at t=0
    /// position is zero and the derivative is exactly `velocityDelta` because
    /// tanh'(0) is one. Smooth saturation retains that C1 handoff while an
    /// accelerating or stale sample can contribute at most ten points.
    static func sharedElementVelocityResidual(
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
        let smootherstep7 = 35 * u4 - 84 * u5 + 70 * u6 - 20 * u7
        let rawResidual = velocityDelta * CGFloat(elapsed)
            * (1 - smootherstep7)
        let limit = sharedElementVelocityResidualSpatialLimit
        return limit * CGFloat(tanh(Double(rawResidual / limit)))
    }

    /// Keeps the first visible horizontal chords on the gesture's captured
    /// tangent, then rejoins the canonical artwork path with three continuous
    /// terminal derivatives.
    ///
    /// Correcting only the infinitesimal velocity is insufficient here: the
    /// measured artwork cubic has enough initial acceleration to reverse x
    /// before the first 120 Hz sample. Comparing the full canonical base
    /// displacement with the captured ballistic tangent cancels that
    /// within-frame curvature without introducing a cadence-specific seed.
    /// The seventh-order window is flat through its third derivative at both
    /// ends, so the bridge is exact C0/C1 at release and C3 when it disappears.
    static func sharedElementHorizontalInertialBridge(
        elapsed: TimeInterval,
        duration: TimeInterval,
        originPosition: CGFloat,
        basePosition: CGFloat,
        capturedVelocity: CGFloat
    ) -> CGFloat {
        guard elapsed.isFinite,
              duration.isFinite,
              originPosition.isFinite,
              basePosition.isFinite,
              capturedVelocity.isFinite,
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
        let window = 1 - (35 * u4 - 84 * u5 + 70 * u6 - 20 * u7)
        let tangentPosition = originPosition
            + capturedVelocity * CGFloat(elapsed)
        let rawBridge = (tangentPosition - basePosition) * window

        // A fourth-order soft limit is indistinguishable from identity around
        // zero (its first deviation is O(x^5)), while remaining smooth and
        // bounded for pathological or stale samples. Unlike a global tanh it
        // does not visibly attenuate the first native-frame correction.
        let limit = sharedElementVelocityResidualSpatialLimit
        guard limit.isFinite, limit > 0 else { return rawBridge }
        let ratio = Double(rawBridge / limit)
        let attenuation = pow(1 + pow(ratio, 4), 0.25)
        guard attenuation.isFinite, attenuation > 0 else { return 0 }
        return rawBridge / CGFloat(attenuation)
    }

    /// Applies geometry only; visual content is refreshed in place when the
    /// independent endpoint trees converge on a new content signature. No
    /// endpoint is reparented and no snapshot is created on display-link ticks.
    func updateSettle(presentationProgress rawPresentationProgress: CGFloat) {
        refreshRepresentationsIfNeeded()
        if hasCompositorSettleTrack {
            samplePresentationGeometry()
            return
        }
        guard let settleTarget,
              let settleOriginPresentationProgress else {
            return
        }

        let targetPresentationProgress: CGFloat = settleTarget == .expanded
            ? 1
            : 0
        let remaining = targetPresentationProgress
            - settleOriginPresentationProgress
        let progress: CGFloat
        if abs(remaining) <= 0.000_1 {
            progress = 1
        } else {
            progress = (
                rawPresentationProgress.clamped(to: 0 ... 1)
                    - settleOriginPresentationProgress
            ) / remaining
        }

        withoutImplicitAnimations {
            for entry in entries {
                let origin = entry.settleOriginGeometry
                    ?? entry.lastPresentationGeometry
                let target = settleTarget == .collapsed
                    ? entry.collapsedGeometry
                    : entry.expandedGeometry
                let geometry = origin.interpolated(
                    to: target,
                    progress: progress
                )
                apply(geometry, to: entry.representation.layer)
                entry.lastPresentationGeometry = geometry
            }
        }
    }

    func beginInteractiveDrag(
        collapseArcPhase rawCollapseArcPhase: CGFloat = 0
    ) {
        refreshRepresentationsIfNeeded()
        captureCurrentPresentation()
        let collapseArcPhase = rawCollapseArcPhase.isFinite
            ? rawCollapseArcPhase.clamped(to: 0 ... 1)
            : 0
        for entry in entries {
            entry.dragOriginGeometry = ElementGeometry(layer: entry.representation.layer)
            entry.dragOriginArcPhase = collapseArcPhase
            entry.lastMotionSamplePosition = entry.dragOriginGeometry?.position
            entry.lastMotionSampleTopEdgeY = entry.dragOriginGeometry.map {
                $0.position.y - 0.5 * $0.bounds.height
            }
            entry.lastMotionSampleTimestamp = CACurrentMediaTime()
            entry.estimatedPositionVelocity = .zero
            entry.estimatedTopEdgeVelocityY = 0
            entry.estimatedPositionVelocityTimestamp = nil
        }
    }

    func updateInteractiveDrag(
        progress: CGFloat,
        previewAmount: CGFloat,
        collapseArcPhase rawCollapseArcPhase: CGFloat = 0,
        surfaceOriginDeltaInContainer: CGPoint
    ) {
        refreshRepresentationsIfNeeded()
        let previewProgress = progress.clamped(to: 0 ... 1)
            * previewAmount.clamped(to: 0 ... 1)
        let surfaceOriginDelta = convertDeltaFromContainer(
            surfaceOriginDeltaInContainer
        )
        _ = rawCollapseArcPhase
        withoutImplicitAnimations {
            let sampleTimestamp = CACurrentMediaTime()
            for entry in entries {
                let origin = entry.dragOriginGeometry
                    ?? ElementGeometry(layer: entry.representation.layer)
                // During a held drag the shared representation belongs to the
                // moving surface first. Preserve that 1:1 displacement before
                // applying the deliberately tiny preview toward the collapsed
                // endpoint; otherwise artwork appears detached from the card.
                let translatedOrigin = origin.offsetBy(surfaceOriginDelta)
                let geometry = translatedOrigin.interpolated(
                    to: entry.collapsedGeometry,
                    progress: previewProgress
                )
                // The reference held cover is rigidly attached to the sheet:
                // its x and bounds remain constant until release. The visible
                // curve belongs to the post-release top-edge spring, not to a
                // synthetic sideways chord-normal offset under the finger.
                apply(geometry, to: entry.representation.layer)
                entry.lastPresentationGeometry = ElementGeometry(
                    layer: entry.representation.layer
                )
                recordMotionSample(
                    entry.lastPresentationGeometry,
                    for: entry,
                    timestamp: sampleTimestamp
                )
            }
        }
    }

    func samplePresentation() {
        refreshRepresentationsIfNeeded()
        samplePresentationGeometry()
    }

    private func samplePresentationGeometry() {
        let sampleTimestamp = CACurrentMediaTime()
        for entry in entries {
            guard let presentation = entry.representation.layer.presentation() else {
                continue
            }
            let geometry = ElementGeometry(layer: presentation)
            if geometry.isValid {
                recordMotionSample(
                    geometry,
                    for: entry,
                    timestamp: sampleTimestamp
                )
                entry.lastPresentationGeometry = geometry
            }
        }
    }

    func captureCurrentPresentation() {
        refreshRepresentationsIfNeeded()
        withoutImplicitAnimations {
            let sampleTimestamp = CACurrentMediaTime()
            for entry in entries {
                let layer = entry.representation.layer
                let geometry: ElementGeometry
                if let presentation = layer.presentation() {
                    let sampled = ElementGeometry(layer: presentation)
                    geometry = sampled.isValid
                        ? sampled
                        : entry.lastPresentationGeometry
                } else {
                    geometry = entry.lastPresentationGeometry
                }
                if geometry.isValid {
                    recordMotionSample(
                        geometry,
                        for: entry,
                        timestamp: sampleTimestamp
                    )
                    apply(geometry, to: layer)
                    entry.lastPresentationGeometry = geometry
                }
                layer.removeAllAnimations()
                entry.settleOriginGeometry = nil
            }
        }
        settleOriginPresentationProgress = nil
        settleArcOriginPhase = 0
        settleTarget = nil
        settlePreservesInitialVelocity = false
        settleUsesReferenceCollapseLaunch = false
        hasCompositorSettleTrack = false
    }

    private func recordMotionSample(
        _ geometry: ElementGeometry,
        for entry: Entry,
        timestamp: CFTimeInterval
    ) {
        let topEdgeY = geometry.position.y - 0.5 * geometry.bounds.height
        defer {
            entry.lastMotionSamplePosition = geometry.position
            entry.lastMotionSampleTopEdgeY = topEdgeY
            entry.lastMotionSampleTimestamp = timestamp
        }
        guard timestamp.isFinite,
              let previousTimestamp = entry.lastMotionSampleTimestamp,
              let previousPosition = entry.lastMotionSamplePosition,
              let previousTopEdgeY = entry.lastMotionSampleTopEdgeY else {
            return
        }
        let interval = timestamp - previousTimestamp
        // Ignore same-transaction captures and stale background gaps. The
        // provided analytic drag derivative remains the deterministic fallback.
        guard interval >= 1.0 / 300.0, interval <= 0.10 else { return }
        let velocity = CGPoint(
            x: (geometry.position.x - previousPosition.x) / CGFloat(interval),
            y: (geometry.position.y - previousPosition.y) / CGFloat(interval)
        )
        guard velocity.x.isFinite, velocity.y.isFinite else { return }
        let topEdgeVelocityY = (topEdgeY - previousTopEdgeY)
            / CGFloat(interval)
        guard topEdgeVelocityY.isFinite else { return }
        entry.estimatedPositionVelocity = velocity
        entry.estimatedTopEdgeVelocityY = topEdgeVelocityY
        entry.estimatedPositionVelocityTimestamp = timestamp
    }

    func complete(at target: BottomBarAccessoryReleaseTarget) {
        withoutImplicitAnimations {
            for entry in entries {
                apply(
                    target == .collapsed
                        ? entry.collapsedGeometry
                        : entry.expandedGeometry,
                    to: entry.representation.layer
                )
                entry.lastPresentationGeometry = target == .collapsed
                    ? entry.collapsedGeometry
                    : entry.expandedGeometry
            }
            restoreVisibility()
            removeRepresentations()
        }
    }

    func cancel() {
        cleanup(restoringVisibility: true)
    }

    private func preserveAndHide(_ view: UIView) {
        let identifier = ObjectIdentifier(view)
        if visibilityRecords[identifier] == nil {
            visibilityRecords[identifier] = VisibilityRecord(view: view)
        }
        visibilityRecords[identifier]?.hide()
    }

    /// Refreshes only after the endpoint pair agrees on a content identity.
    /// A short-lived mismatch is expected when two independent view trees
    /// observe the same model update on adjacent run-loop turns; retaining the
    /// old representation avoids flashing either endpoint's stale content.
    private func refreshRepresentationsIfNeeded() {
        for entry in entries {
            let collapsedSignature = entry.collapsedElement
                .currentContentSignature()
            let expandedSignature = entry.expandedElement
                .currentContentSignature()

            let resolvedSignature: AnyHashable
            if let collapsedSignature, let expandedSignature {
                guard collapsedSignature == expandedSignature else { continue }
                resolvedSignature = collapsedSignature
            } else if let collapsedSignature {
                resolvedSignature = collapsedSignature
            } else if let expandedSignature {
                resolvedSignature = expandedSignature
            } else {
                continue
            }

            if entry.representedContentSignature == resolvedSignature {
                entry.lastRefreshAttemptSignature = resolvedSignature
                continue
            }
            guard entry.lastRefreshAttemptSignature != resolvedSignature else {
                continue
            }
            entry.lastRefreshAttemptSignature = resolvedSignature

            let preferredElement = entry.preferredRefreshEndpoint == .collapsed
                ? entry.collapsedElement
                : entry.expandedElement
            let alternateElement = entry.preferredRefreshEndpoint == .collapsed
                ? entry.expandedElement
                : entry.collapsedElement
            let preferredSignature = entry.preferredRefreshEndpoint == .collapsed
                ? collapsedSignature
                : expandedSignature
            let sourceElement: BottomBarAccessoryTransitionSharedElement
            if preferredSignature == resolvedSignature {
                sourceElement = preferredElement
            } else {
                sourceElement = alternateElement
            }

            guard refreshRepresentation(
                entry.representation,
                from: sourceElement
            ) else {
                continue
            }
            entry.representedContentSignature = resolvedSignature
        }
    }

    /// Endpoint views stay hidden for the complete shared-element lifetime.
    /// The temporary visibility change is committed and reverted inside one
    /// actions-disabled transaction so default raster capture can see the
    /// endpoint without producing an on-screen flash. `defer` also protects
    /// the hidden state from early returns in a custom refresh hook.
    private func refreshRepresentation(
        _ representation: UIView,
        from element: BottomBarAccessoryTransitionSharedElement
    ) -> Bool {
        guard let view = element.view else { return false }
        let hiddenAlpha = view.alpha
        let hiddenState = view.isHidden

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            view.alpha = hiddenAlpha
            view.isHidden = hiddenState
            CATransaction.commit()
        }

        view.alpha = 1
        view.isHidden = false
        return element.refreshRepresentation(representation)
    }

    private func restoreVisibility() {
        for record in visibilityRecords.values {
            record.restore()
        }
        visibilityRecords.removeAll()
    }

    private func removeRepresentations() {
        for entry in entries {
            entry.representation.layer.removeAllAnimations()
            entry.representation.removeFromSuperview()
        }
        entries.removeAll()
        settleOriginPresentationProgress = nil
        settleArcOriginPhase = 0
        settleTarget = nil
        settlePreservesInitialVelocity = false
        settleUsesReferenceCollapseLaunch = false
        hasCompositorSettleTrack = false
        coordinateView = nil
        containerView = nil
    }

    private func cleanup(restoringVisibility: Bool) {
        withoutImplicitAnimations {
            if restoringVisibility {
                restoreVisibility()
            }
            removeRepresentations()
        }
    }

    private func apply(_ geometry: ElementGeometry, to layer: CALayer) {
        layer.position = geometry.position
        layer.bounds = geometry.bounds
        layer.cornerRadius = geometry.cornerRadius
    }

    private static func keyframeAnimation(
        keyPath: String,
        values: [Any],
        track: BottomBarAccessoryCompositorSettleTrack
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = track.keyTimes
        animation.duration = track.duration
        animation.calculationMode = .linear
        return animation
    }

    private func convertDeltaFromContainer(_ delta: CGPoint) -> CGPoint {
        guard delta.x.isFinite, delta.y.isFinite else { return .zero }
        guard let containerView, let coordinateView else { return delta }

        let convertedOrigin = containerView.convert(
            CGPoint.zero,
            to: coordinateView
        )
        let convertedPoint = containerView.convert(delta, to: coordinateView)
        let convertedDelta = CGPoint(
            x: convertedPoint.x - convertedOrigin.x,
            y: convertedPoint.y - convertedOrigin.y
        )
        guard convertedDelta.x.isFinite, convertedDelta.y.isFinite else {
            return .zero
        }
        return convertedDelta
    }

    private func withoutImplicitAnimations(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
