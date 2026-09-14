import UIKit

/// Immutable input to the pure post-gesture release decision.
public struct BottomBarAccessoryReleaseInput: Equatable, Sendable {
    public var translationY: CGFloat
    public var velocityY: CGFloat
    public var expandedFrame: CGRect
    public var collapsedFrame: CGRect
    public var containerSize: CGSize
    public var endReason: BottomBarAccessoryGestureEndReason

    public init(
        translationY: CGFloat,
        velocityY: CGFloat,
        expandedFrame: CGRect,
        collapsedFrame: CGRect,
        containerSize: CGSize,
        endReason: BottomBarAccessoryGestureEndReason = .ended
    ) {
        self.translationY = translationY
        self.velocityY = velocityY
        self.expandedFrame = expandedFrame
        self.collapsedFrame = collapsedFrame
        self.containerSize = containerSize
        self.endReason = endReason
    }
}

/// Pure release resolver shared by gesture and programmatic integration paths.
/// Crossing a threshold while the finger is down never starts a transition;
/// callers invoke this only after the gesture has ended.
public enum BottomBarAccessoryReleaseResolver {
    public static func resolve(
        _ input: BottomBarAccessoryReleaseInput,
        configuration: BottomBarAccessoryTransitionConfiguration = .default
    ) -> BottomBarAccessoryReleaseTarget {
        decision(input, configuration: configuration).target
    }

    static func decision(
        _ input: BottomBarAccessoryReleaseInput,
        configuration: BottomBarAccessoryTransitionConfiguration
    ) -> BottomBarAccessoryReleaseDecision {
        let containerHeight = finite(input.containerSize.height)
        let rawReferenceDistance = finite(
            input.collapsedFrame.midY - input.expandedFrame.midY
        )
        let fallbackReferenceDistance = max(1, containerHeight * 0.5)
        let referenceDistance = rawReferenceDistance > 1
            ? rawReferenceDistance
            : fallbackReferenceDistance

        let minimumCommitDistance = max(
            0,
            min(
                finite(configuration.minimumCommitDistance),
                finite(configuration.maximumCommitDistance)
            )
        )
        let maximumCommitDistance = max(
            minimumCommitDistance,
            max(
                finite(configuration.minimumCommitDistance),
                finite(configuration.maximumCommitDistance)
            )
        )
        let commitDistance = clamp(
            referenceDistance * max(0, finite(configuration.commitDistanceFactor)),
            minimumCommitDistance,
            maximumCommitDistance
        )

        let maximumVelocity = max(0, finite(configuration.maximumResolvedVelocity))
        let clampedVelocity = clamp(
            finite(input.velocityY),
            -maximumVelocity,
            maximumVelocity
        )
        let translation = max(0, finite(input.translationY))
        let projectionTime = max(0, finite(configuration.projectionTime))
        let projectedTranslation = translation + clampedVelocity * projectionTime

        let upwardCancelVelocity = max(
            0,
            finite(configuration.upwardCancelVelocity)
        )
        let flickVelocity = max(0, finite(configuration.flickVelocity))
        let minimumFlickTranslation = max(
            0,
            finite(configuration.minimumFlickTranslation)
        )

        let wasSystemCancelled = input.endReason != .ended
        let hasUpwardCancellationIntent = clampedVelocity <= -upwardCancelVelocity
        let passedDistance = translation >= commitDistance
        let passedProjectedDistance = projectedTranslation >= commitDistance
        let passedFlick = clampedVelocity >= flickVelocity
            && translation >= minimumFlickTranslation

        let target: BottomBarAccessoryReleaseTarget
        if wasSystemCancelled || hasUpwardCancellationIntent {
            target = .expanded
        } else if passedDistance || passedProjectedDistance || passedFlick {
            target = .collapsed
        } else {
            target = .expanded
        }

        return BottomBarAccessoryReleaseDecision(
            target: target,
            referenceDistance: referenceDistance,
            commitDistance: commitDistance,
            clampedVelocityY: clampedVelocity,
            projectedTranslationY: projectedTranslation,
            isCollapseArmed: !wasSystemCancelled
                && !hasUpwardCancellationIntent
                && (passedDistance || passedProjectedDistance || passedFlick)
        )
    }

    private static func finite(_ value: CGFloat) -> CGFloat {
        value.isFinite ? value : 0
    }

    private static func clamp(
        _ value: CGFloat,
        _ lowerBound: CGFloat,
        _ upperBound: CGFloat
    ) -> CGFloat {
        min(max(value, lowerBound), upperBound)
    }
}

struct BottomBarAccessoryReleaseDecision: Equatable {
    let target: BottomBarAccessoryReleaseTarget
    let referenceDistance: CGFloat
    let commitDistance: CGFloat
    let clampedVelocityY: CGFloat
    let projectedTranslationY: CGFloat
    let isCollapseArmed: Bool
}
