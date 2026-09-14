import UIKit

/// Deterministic stable and transient states for a bottom-bar accessory.
public enum BottomBarAccessoryPresentationState: Equatable, Sendable {
    case collapsed
    case expanding
    case expanded
    case dragging
    case settlingToExpanded
    case settlingToCollapsed
}

/// More descriptive phase supplied to generic transition participants.
public enum BottomBarAccessoryTransitionPhase: Equatable, Sendable {
    case preparing
    case expanding
    case dragging
    case settlingToExpanded
    case settlingToCollapsed
    case completed
}

public enum BottomBarAccessoryDockingMode: Equatable, Sendable {
    case regular
    case inline
}

/// Tab-bar state captured at the start of a transition session. The hosting
/// controller can restore this state after collapse or replace the geometry if
/// rotation makes the original docking slot invalid.
public struct BottomBarAccessoryDockingContext: Equatable, Sendable {
    public var mode: BottomBarAccessoryDockingMode
    public var isTabBarVisible: Bool
    public var isSearchActive: Bool

    public init(
        mode: BottomBarAccessoryDockingMode,
        isTabBarVisible: Bool,
        isSearchActive: Bool
    ) {
        self.mode = mode
        self.isTabBarVisible = isTabBarVisible
        self.isSearchActive = isSearchActive
    }
}

/// Geometry for one transition session. Both frames use the hosting tab-bar
/// controller's coordinate space. A zero-sized frame is deliberately invalid;
/// callers should wait for layout instead of animating toward `.zero`.
public struct BottomBarAccessoryTransitionGeometry: Equatable, Sendable {
    public var collapsedFrame: CGRect
    public var expandedFrame: CGRect
    public var collapsedCornerRadius: CGFloat
    public var expandedCornerRadius: CGFloat
    public var safeInsets: UIEdgeInsets
    public var layoutSize: CGSize

    public init(
        collapsedFrame: CGRect,
        expandedFrame: CGRect,
        collapsedCornerRadius: CGFloat,
        expandedCornerRadius: CGFloat,
        safeInsets: UIEdgeInsets,
        layoutSize: CGSize
    ) {
        self.collapsedFrame = collapsedFrame
        self.expandedFrame = expandedFrame
        self.collapsedCornerRadius = collapsedCornerRadius
        self.expandedCornerRadius = expandedCornerRadius
        self.safeInsets = safeInsets
        self.layoutSize = layoutSize
    }

    public var isValid: Bool {
        collapsedFrame.isValidBottomBarAccessoryFrame
            && expandedFrame.isValidBottomBarAccessoryFrame
            && layoutSize.isValidBottomBarAccessorySize
            && collapsedCornerRadius.isFinite
            && expandedCornerRadius.isFinite
            && collapsedCornerRadius >= 0
            && expandedCornerRadius >= 0
            && safeInsets.top.isFinite
            && safeInsets.left.isFinite
            && safeInsets.bottom.isFinite
            && safeInsets.right.isFinite
    }

    public func surfaceGeometry(
        at rawProgress: CGFloat
    ) -> BottomBarAccessorySurfaceGeometry {
        let progress = rawProgress.clamped(to: 0 ... 1)
        let frame = CGRect(
            x: collapsedFrame.minX
                + (expandedFrame.minX - collapsedFrame.minX) * progress,
            y: collapsedFrame.minY
                + (expandedFrame.minY - collapsedFrame.minY) * progress,
            width: collapsedFrame.width
                + (expandedFrame.width - collapsedFrame.width) * progress,
            height: collapsedFrame.height
                + (expandedFrame.height - collapsedFrame.height) * progress
        )
        let cornerRadius = collapsedCornerRadius
            + (expandedCornerRadius - collapsedCornerRadius) * progress
        return BottomBarAccessorySurfaceGeometry(
            position: CGPoint(x: frame.midX, y: frame.midY),
            bounds: CGRect(origin: .zero, size: frame.size),
            cornerRadius: max(0, cornerRadius)
        )
    }

    public func presentationProgress(
        for surface: BottomBarAccessorySurfaceGeometry
    ) -> CGFloat {
        var components: [CGFloat] = []
        appendProgressComponent(
            current: surface.bounds.width,
            collapsed: collapsedFrame.width,
            expanded: expandedFrame.width,
            to: &components
        )
        appendProgressComponent(
            current: surface.bounds.height,
            collapsed: collapsedFrame.height,
            expanded: expandedFrame.height,
            to: &components
        )
        appendProgressComponent(
            current: surface.position.y,
            collapsed: collapsedFrame.midY,
            expanded: expandedFrame.midY,
            to: &components
        )
        guard !components.isEmpty else { return 0 }
        return (components.reduce(0, +) / CGFloat(components.count))
            .clamped(to: 0 ... 1)
    }

    private func appendProgressComponent(
        current: CGFloat,
        collapsed: CGFloat,
        expanded: CGFloat,
        to components: inout [CGFloat]
    ) {
        let distance = expanded - collapsed
        guard abs(distance) > 0.001 else { return }
        components.append((current - collapsed) / distance)
    }
}

/// Model/presentation geometry for the one morphing surface. The coordinator
/// exclusively animates these properties and never mixes them with `frame` or
/// a translation transform.
public struct BottomBarAccessorySurfaceGeometry: Equatable, Sendable {
    public var position: CGPoint
    public var bounds: CGRect
    public var cornerRadius: CGFloat

    public init(position: CGPoint, bounds: CGRect, cornerRadius: CGFloat) {
        self.position = position
        self.bounds = bounds
        self.cornerRadius = cornerRadius
    }

    public var frame: CGRect {
        CGRect(
            x: position.x - bounds.width * 0.5,
            y: position.y - bounds.height * 0.5,
            width: bounds.width,
            height: bounds.height
        )
    }

    var isValid: Bool {
        position.x.isFinite
            && position.y.isFinite
            && bounds.isValidBottomBarAccessoryFrame
            && cornerRadius.isFinite
            && cornerRadius >= 0
    }
}

/// Per-sample context sent to transition participants and the coordinator
/// delegate. `presentationProgress` is always `0 = collapsed`, `1 = expanded`;
/// `settleProgress` and `dragProgress` describe the current interaction phase.
public struct BottomBarAccessoryTransitionContext: Equatable, Sendable {
    public let sessionIdentifier: UUID
    public let state: BottomBarAccessoryPresentationState
    public let phase: BottomBarAccessoryTransitionPhase
    public let presentationProgress: CGFloat
    public let settleProgress: CGFloat
    public let dragProgress: CGFloat
    public let isInteractive: Bool
    public let isReduceMotionEnabled: Bool
    public let target: BottomBarAccessoryReleaseTarget?
    public let geometry: BottomBarAccessoryTransitionGeometry
    public let dockingContext: BottomBarAccessoryDockingContext

    public init(
        sessionIdentifier: UUID,
        state: BottomBarAccessoryPresentationState,
        phase: BottomBarAccessoryTransitionPhase,
        presentationProgress: CGFloat,
        settleProgress: CGFloat,
        dragProgress: CGFloat,
        isInteractive: Bool,
        isReduceMotionEnabled: Bool,
        target: BottomBarAccessoryReleaseTarget?,
        geometry: BottomBarAccessoryTransitionGeometry,
        dockingContext: BottomBarAccessoryDockingContext
    ) {
        self.sessionIdentifier = sessionIdentifier
        self.state = state
        self.phase = phase
        self.presentationProgress = presentationProgress.clamped(to: 0 ... 1)
        self.settleProgress = settleProgress.clamped(to: 0 ... 1)
        self.dragProgress = dragProgress.clamped(to: 0 ... 1)
        self.isInteractive = isInteractive
        self.isReduceMotionEnabled = isReduceMotionEnabled
        self.target = target
        self.geometry = geometry
        self.dockingContext = dockingContext
    }

    /// Maps the current presentation progress into a normalized choreography
    /// window without allocating an animator or scheduling delayed work.
    public func progress(from lowerBound: CGFloat, to upperBound: CGFloat) -> CGFloat {
        guard upperBound > lowerBound else {
            return presentationProgress >= upperBound ? 1 : 0
        }
        let linear = (presentationProgress - lowerBound) / (upperBound - lowerBound)
        return linear.clamped(to: 0 ... 1)
    }
}

enum BottomBarAccessoryTransitionStateEvent: Equatable {
    case requestExpansion
    case requestCollapse
    case beginDrag
    case settle(BottomBarAccessoryReleaseTarget)
    case complete(BottomBarAccessoryReleaseTarget)
    case reset(BottomBarAccessoryReleaseTarget)
}

struct BottomBarAccessoryTransitionStateMachine {
    private(set) var state: BottomBarAccessoryPresentationState

    init(initialState: BottomBarAccessoryPresentationState = .collapsed) {
        state = initialState
    }

    @discardableResult
    mutating func handle(_ event: BottomBarAccessoryTransitionStateEvent) -> Bool {
        let nextState: BottomBarAccessoryPresentationState?
        switch event {
        case .requestExpansion:
            switch state {
            case .collapsed:
                nextState = .expanding
            case .settlingToCollapsed, .dragging:
                nextState = .settlingToExpanded
            case .expanding, .expanded, .settlingToExpanded:
                nextState = state
            }

        case .requestCollapse:
            switch state {
            case .collapsed, .settlingToCollapsed:
                nextState = state
            case .expanded, .expanding, .settlingToExpanded, .dragging:
                nextState = .settlingToCollapsed
            }

        case .beginDrag:
            switch state {
            case .expanding, .expanded, .settlingToExpanded, .settlingToCollapsed:
                nextState = .dragging
            case .collapsed, .dragging:
                nextState = nil
            }

        case let .settle(target):
            nextState = target == .expanded
                ? .settlingToExpanded
                : .settlingToCollapsed

        case let .complete(target), let .reset(target):
            nextState = target == .expanded ? .expanded : .collapsed
        }

        guard let nextState else { return false }
        state = nextState
        return true
    }
}

@MainActor
final class BottomBarAccessoryTransitionSession {
    let identifier = UUID()
    var geometry: BottomBarAccessoryTransitionGeometry
    let dockingContext: BottomBarAccessoryDockingContext
    /// Live accessibility preference for this presentation session. The
    /// docking contract and endpoint geometry remain immutable across a
    /// session, but Reduce Motion can change while Full Player is already
    /// open and must affect the very next drag/settle immediately.
    var isReduceMotionEnabled: Bool
    weak var collapsedParticipant: BottomBarAccessoryTransitionParticipant?
    weak var expandedParticipant: BottomBarAccessoryTransitionParticipant?

    var target: BottomBarAccessoryReleaseTarget?
    var dragOriginSurface: BottomBarAccessorySurfaceGeometry?
    var dragOriginPresentationProgress: CGFloat = 1
    /// Absolute close phase used by the shared artwork's canonical arc.
    /// Unlike the averaged presentation progress this follows the surface's
    /// top edge, which is the edge owned directly by the grabber gesture.
    var dragOriginArcPhase: CGFloat = 0
    var dragArcPhase: CGFloat = 0
    var dragTranslationOrigin: CGFloat = 0
    var latestRawDragTranslation: CGFloat = 0
    var dragProgress: CGFloat = 0

    init(
        geometry: BottomBarAccessoryTransitionGeometry,
        dockingContext: BottomBarAccessoryDockingContext,
        isReduceMotionEnabled: Bool,
        collapsedParticipant: BottomBarAccessoryTransitionParticipant?,
        expandedParticipant: BottomBarAccessoryTransitionParticipant?
    ) {
        self.geometry = geometry
        self.dockingContext = dockingContext
        self.isReduceMotionEnabled = isReduceMotionEnabled
        self.collapsedParticipant = collapsedParticipant
        self.expandedParticipant = expandedParticipant
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension CGRect {
    var isValidBottomBarAccessoryFrame: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.isValidBottomBarAccessorySize
    }
}

private extension CGSize {
    var isValidBottomBarAccessorySize: Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
    }
}
