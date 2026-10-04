import UIKit

/// Optional protocol for `ViewController`s presented inside
/// `AetherModalNavigationController`. In the default `.perScreen` mode,
/// the modal follows each screen's footer and scroll preferences. The root
/// does not need to conform. Use `.manual` for a caller-owned shared footer.
///
/// Conforming is opt-in. A VC that doesn't conform is presented as-is
/// (no footer; its `primaryScrollViewForChrome` is used for scrolling).
/// All members carry sensible
/// defaults via the extension below, so a VC only declares the bits it
/// actually wants to customize.
///
/// ```swift
/// final class SendPushViewController: ViewController, AetherModalContent {
///     private(set) lazy var sendButton: UIButton = ...
///     private(set) var scroll: UIScrollView?
///
///     var modalFooterView: UIView? { sendButton }
///     var modalFooterHeight: CGFloat { 98 }
///     var modalPrimaryScrollView: UIScrollView? { scroll }
/// }
///
/// // Caller — one line:
/// let modal = AetherModalNavigationController(
///     rootViewController: SendPushViewController(),
///     config: .init(detents: [.stage1, .stage2], initialDetent: .stage2)
/// )
/// present(modal, animated: true)
/// ```
@MainActor
public protocol AetherModalContent: AnyObject {
    /// Stable view instance to install in the modal's footer slot. Return nil
    /// for no footer; do not allocate a new wrapper on each property access.
    var modalFooterView: UIView? { get }
    /// Total height (in points) of the footer including any internal
    /// padding. Drives the modal's edge-effect band height and the
    /// auto-added bottom safe-area inset.
    var modalFooterHeight: CGFloat { get }
    /// Height of the gradient fade above the footer that dissolves the
    /// scroll content into the frost.
    var modalFooterEdgeFadeHeight: CGFloat { get }
    /// Tint colour drawn behind the footer. `nil` → derive from
    /// `config.dimTintColor` with 0.86 alpha.
    var modalFooterEdgeTintColor: UIColor? { get }
    /// Blur radius behind the footer band.
    var modalFooterEdgeBlurRadius: CGFloat { get }
    /// Draw a frosted edge behind the footer. Set to `false` for a floating
    /// glass button without a full-width footer background.
    var modalFooterEdgeEffectEnabled: Bool { get }
    /// Scroll view inside the content the modal should yield to during
    /// drag (gesture arbitration).
    var modalPrimaryScrollView: UIScrollView? { get }
}

public extension AetherModalContent {
    var modalFooterView: UIView? { nil }
    var modalFooterHeight: CGFloat { 0 }
    var modalFooterEdgeFadeHeight: CGFloat { 28 }
    var modalFooterEdgeTintColor: UIColor? { nil }
    var modalFooterEdgeBlurRadius: CGFloat { 2 }
    var modalFooterEdgeEffectEnabled: Bool { true }
    var modalPrimaryScrollView: UIScrollView? { nil }
}
