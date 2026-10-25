import UIKit

public enum AetherNavigationTransitionOperation {
    case push
    case pop
}

/// Everything a custom stack transition can rely on.
///
/// Both controller views are installed at their settled frames before
/// `prepare(context:)` is called: the incoming view is above the outgoing one
/// on push, and below it on pop. Nothing slides; the transition owns every
/// visual change until it calls the completion it is given.
public final class AetherNavigationTransitionContext {
    public let operation: AetherNavigationTransitionOperation
    public let containerView: UIView
    public let fromController: AetherViewController
    public let toController: AetherViewController
    public let isInteractive: Bool

    init(
        operation: AetherNavigationTransitionOperation,
        containerView: UIView,
        fromController: AetherViewController,
        toController: AetherViewController,
        isInteractive: Bool
    ) {
        self.operation = operation
        self.containerView = containerView
        self.fromController = fromController
        self.toController = toController
        self.isInteractive = isInteractive
    }
}

/// A push/pop rendered by the controllers themselves instead of the default
/// slide. Provided by `AetherViewController.customNavigationTransition(...)`.
///
/// Non-interactive transitions: `prepare` → `animate`.
/// Interactive pops: `prepare` → `updateInteractive`… → either
/// `finishInteractive` or `cancelInteractive`.
/// `didEnd` is always called once the container has settled the stack.
public protocol AetherCustomNavigationTransition: AnyObject {
    func prepare(context: AetherNavigationTransitionContext)

    /// Runs a complete, non-interactive transition.
    func animate(completion: @escaping () -> Void)

    /// Pan progress of an interactive pop, in container coordinates.
    func updateInteractive(translation: CGPoint, location: CGPoint)

    func shouldCompleteInteractive(translation: CGPoint, velocity: CGPoint) -> Bool

    /// The pan was released and the pop commits.
    func finishInteractive(velocity: CGPoint, completion: @escaping () -> Void)

    /// The pan was released or cancelled and the pop is abandoned.
    func cancelInteractive(velocity: CGPoint, completion: @escaping () -> Void)

    func didEnd(completed: Bool)
}

public extension UIScreen {
    /// Physical bezel radius of the display, or `0` when it is unavailable.
    /// Custom transitions use it to keep a full-screen surface flush with
    /// the device corners while it is scaled or reshaped.
    var aetherDisplayCornerRadius: CGFloat {
        #if APPSTORE_SAFE
        return 0.0
        #else
        let key = ObfuscatedSymbols.displayCornerRadius
        guard responds(to: NSSelectorFromString(key)) else { return 0.0 }
        return (value(forKey: key) as? CGFloat) ?? 0.0
        #endif
    }
}

public extension AetherCustomNavigationTransition {
    func updateInteractive(translation: CGPoint, location: CGPoint) {}

    func shouldCompleteInteractive(translation: CGPoint, velocity: CGPoint) -> Bool {
        return velocity.x > 500.0 || (translation.x > 0.0 && velocity.x > -100.0 && translation.x > 120.0)
    }

    func finishInteractive(velocity: CGPoint, completion: @escaping () -> Void) {
        animate(completion: completion)
    }

    func cancelInteractive(velocity: CGPoint, completion: @escaping () -> Void) {
        completion()
    }

    func didEnd(completed: Bool) {}
}
