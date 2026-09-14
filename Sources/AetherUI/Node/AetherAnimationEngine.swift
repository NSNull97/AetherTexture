import Foundation
import CoreGraphics
import UIKit
import AsyncDisplayKit

public enum AetherAnimationCurve: Equatable {
    case linear
    case easeInOut
    case spring(damping: CGFloat, initialVelocity: CGFloat)
}

public struct AetherNodeAnimation: Equatable {
    public var duration: TimeInterval
    public var curve: AetherAnimationCurve
    public var delay: TimeInterval
    public var isInterruptible: Bool

    public init(
        duration: TimeInterval,
        curve: AetherAnimationCurve = .easeInOut,
        delay: TimeInterval = 0.0,
        isInterruptible: Bool = true
    ) {
        self.duration = duration
        self.curve = curve
        self.delay = delay
        self.isInterruptible = isInterruptible
    }

    public static let immediate = AetherNodeAnimation(duration: 0.0, curve: .linear, isInterruptible: false)
}

public struct AetherNodeTransition: Equatable {
    public var animation: AetherNodeAnimation

    public init(animation: AetherNodeAnimation) {
        self.animation = animation
    }

    public static let immediate = AetherNodeTransition(animation: .immediate)
}

public final class AetherAnimationEngine {
    public static let shared = AetherAnimationEngine()

    public init() {}

    public func animate(
        _ animation: AetherNodeAnimation,
        changes: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        _AetherUIKitAnimationBridge.animate(animation, changes: changes, completion: completion)
    }
}

public final class AetherInteractiveTransition {
    public private(set) var progress: CGFloat = 0.0
    public let animation: AetherNodeAnimation
    private let applyProgress: (CGFloat) -> Void
    private let completion: (Bool) -> Void

    public init(
        animation: AetherNodeAnimation,
        applyProgress: @escaping (CGFloat) -> Void,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        self.animation = animation
        self.applyProgress = applyProgress
        self.completion = completion
    }

    public func update(progress: CGFloat) {
        self.progress = max(0.0, min(1.0, progress))
        applyProgress(self.progress)
    }

    public func finish() {
        update(progress: 1.0)
        completion(true)
    }

    public func cancel() {
        update(progress: 0.0)
        completion(false)
    }
}

public protocol AetherGestureTransitionDriver: AnyObject {
    var progress: CGFloat { get }
    func cancel()
    func finish()
}

internal enum _AetherUIKitAnimationBridge {
    static func animate(
        _ animation: AetherNodeAnimation,
        changes: @escaping () -> Void,
        completion: ((Bool) -> Void)?
    ) {
        guard animation.duration > 0.0 else {
            changes()
            completion?(true)
            return
        }

        let animator: UIViewPropertyAnimator
        switch animation.curve {
        case .linear:
            animator = UIViewPropertyAnimator(duration: animation.duration, curve: .linear, animations: changes)
        case .easeInOut:
            animator = UIViewPropertyAnimator(duration: animation.duration, curve: .easeInOut, animations: changes)
        case let .spring(damping, initialVelocity):
            let timing = UISpringTimingParameters(
                dampingRatio: max(0.01, damping),
                initialVelocity: CGVector(dx: initialVelocity, dy: initialVelocity)
            )
            animator = UIViewPropertyAnimator(duration: animation.duration, timingParameters: timing)
            animator.addAnimations(changes)
        }

        animator.isInterruptible = animation.isInterruptible
        animator.addCompletion { position in
            completion?(position == .end)
        }
        animator.startAnimation(afterDelay: animation.delay)
    }
}

