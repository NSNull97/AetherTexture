import UIKit

/// Base class for `AetherTabBarController.bottomBarAccessory` views —
/// sits directly above the tab bar, wrapped in a style-aware material surface
/// by the controller.
///
/// Mirrors the `NavigationBarContentView` pattern on the bottom chrome
/// side: subclass, override `nominalHeight` to size your content and
/// `updateLayout(size:transition:)` to position internal subviews. The
/// parent tab-bar controller handles the style-aware material background and
/// geometry. Legacy uses 16pt side insets with a 4pt bottom gap; Liquid Glass
/// follows the tab-bar metrics and keeps its floating gap.
///
/// ## Resizing when content changes
///
/// Two common patterns for `nominalHeight`:
///
/// 1. **Auto Layout** — return a measured size:
///    ```
///    open override var nominalHeight: CGFloat {
///        return systemLayoutSizeFitting(
///            UIView.layoutFittingCompressedSize,
///            withHorizontalFittingPriority: .defaultLow,
///            verticalFittingPriority: .fittingSizeLevel
///        ).height
///    }
///    ```
///    Call `invalidateLayout()` whenever constraints change so the
///    hosting tab bar re-measures.
///
/// 2. **Frame-based / state-driven** — return a computed value:
///    ```
///    open override var nominalHeight: CGFloat {
///        return isExpanded ? 96.0 : 56.0
///    }
///    ```
///    Call `invalidateLayout()` whenever state changes.
open class TabBarAccessoryView: UIView {
    /// Natural height of this accessory. Override to return a specific
    /// value; default is `48pt`. Legacy presentation resolves this to at least
    /// the 58pt classic mini-player height, while Liquid Glass keeps the
    /// accessory's own requested height.
    open var nominalHeight: CGFloat {
        return 48.0
    }

    /// Requested content height. Defaults to `nominalHeight`; override when a
    /// subclass needs to distinguish between the two (for example, animating
    /// between collapsed and expanded forms). The Legacy host may resolve a
    /// smaller positive value up to its 58pt minimum; `updateLayout` receives
    /// that final rendered size.
    open var height: CGFloat {
        return nominalHeight
    }

    /// Lay out internal content given the material surface's resolved size.
    /// Subclasses that use frame-based layout should override; Auto
    /// Layout-based subclasses can ignore it.
    open func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
    }

    /// Plumbed by `AetherTabBarController` when the accessory is
    /// installed. Subclasses should prefer `invalidateLayout(transition:)`
    /// instead of calling this directly — it's public for the framework
    /// wiring.
    open var requestLayout: (ContainedViewLayoutTransition) -> Void = { _ in }

    /// When non-`nil`, taps on the accessory's material surface trigger a
    /// fluid morph that expands the accessory pill into a full-screen
    /// presentation of the returned view controller (Apple-Music-style
    /// "open the player" gesture). Returning `nil` from the closure
    /// suppresses the expansion for that tap.
    ///
    /// The returned controller is added as a child of
    /// `AetherTabBarController` and its full-size view is hosted beside the
    /// collapsed accessory content inside the same morphing glass surface.
    /// Mini and expanded content remain independent layout trees; they may
    /// optionally conform to `TabBarAccessoryTransitionParticipant` to provide
    /// shared elements and progress-driven choreography. Restore the accessory
    /// by calling `AetherTabBarController.dismissExpandedAccessory(animated:)`
    /// or wire an in-controller dismiss button to that method.
    ///
    /// Returning a freshly-built controller per call lets you treat the
    /// expanded form as ephemeral state. If you want to preserve state
    /// across collapses, cache the controller yourself and return the
    /// same instance.
    open var expandedViewControllerProvider: (() -> UIViewController?)?

    /// Notify the hosting tab bar that this view's reported height
    /// (`height` / `nominalHeight`) has changed — the parent will re-run
    /// its layout pass, re-read the new value, repositions the glass
    /// wrapper, updates `additionalSafeAreaInsets` for descendants, and
    /// re-extends the progressive tab-bar blur to match. Call from subclasses
    /// whenever adding/removing/mutating content in a way that should
    /// visibly resize the accessory.
    ///
    /// The default transition is a compact, slightly under-damped spring, so
    /// height changes get a subtle over/under-scale settle; pass `.immediate`
    /// for synchronous updates (e.g. inside an enclosing animation block).
    public func invalidateLayout(
        transition: ContainedViewLayoutTransition = .animated(
            duration: AetherMotion.bottomBarAccessoryResize.duration,
            curve: .customSpring(
                damping: AetherMotion.bottomBarAccessoryResize.dampingRatio,
                initialVelocity: AetherMotion.bottomBarAccessoryResize.initialVelocity
            )
        )
    ) {
        requestLayout(transition)
    }
}
