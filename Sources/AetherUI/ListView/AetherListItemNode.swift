import UIKit
import AsyncDisplayKit
import AetherUIBridging

internal let aetherListSwipeRevealBackgroundColor = UIColor { traits in
    if traits.userInterfaceStyle == .dark {
        return UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1.0)
    } else {
        return UIColor(red: 0.91, green: 0.92, blue: 0.94, alpha: 1.0)
    }
}

/// List-owned gestures that may be routed through an item node.
public enum AetherListItemGesture: Equatable {
    case tap
    case reorder
    case swipe
}

/// Current sticky-header presentation state for a list item node.
public struct AetherListStickyHeaderState: Equatable {
    public let affinity: AetherListHeaderAffinity
    public let isPinned: Bool
    public let isFloating: Bool
    public let isFlashing: Bool

    public init(
        affinity: AetherListHeaderAffinity,
        isPinned: Bool,
        isFloating: Bool,
        isFlashing: Bool
    ) {
        self.affinity = affinity
        self.isPinned = isPinned
        self.isFloating = isFloating
        self.isFlashing = isFlashing
    }

    public static let none = AetherListStickyHeaderState(
        affinity: .none,
        isPinned: false,
        isFloating: false,
        isFlashing: false
    )
}

/// Base display node class for items displayed in a `AetherListNode`.
///
/// Subclass this to create custom list item nodes. Override lifecycle hooks
/// to handle animations, highlighting, and selection.
///
/// The node manages its own layout through `contentSize` and `insets`,
/// which the list view uses to compute the total frame.
open class AetherListItemNode: AetherMainActorDisplayNode {
    private struct AccessorySlot {
        var stableId: AnyHashable
        var item: AetherListAccessoryItem
        var node: ASDisplayNode
    }

    private var accessorySlots: [AetherListAccessoryPlacement: AccessorySlot] = [:]
    private var swipeRevealBackgroundNode: ASDisplayNode?
    private var isSwipeRevealBackgroundActive = false
    private var swipeRevealStoredBackgroundColor: UIColor?
    private var swipeRevealStoredCornerRadius: CGFloat?
    private var swipeRevealStoredMasksToBounds: Bool?

    // MARK: - Layout Properties

    /// Index of this node in the list. Kept in sync by the list view
    /// after every transaction.
    public internal(set) var index: Int?

    /// Strong reference to the item model the node is currently
    /// rendering. The list view uses this for object-identity-based
    /// re-indexing across delete / move / insert mutations — looking
    /// items up by previous index breaks the moment several mutations
    /// share a transaction.
    public internal(set) var item: AetherListItem?

    /// Size of the content area (excluding insets).
    public internal(set) var contentSize: CGSize = .zero

    /// Insets around the content.
    public internal(set) var insets: UIEdgeInsets = .zero

    /// Current layout snapshot.
    public internal(set) var currentLayout: AetherListItemNodeLayout = AetherListItemNodeLayout(contentSize: .zero)

    /// Height used during animations (can differ from actual height).
    public var apparentHeight: CGFloat = 0

    /// Vertical offset applied during insertion/deletion transitions.
    public var transitionOffset: CGFloat = 0

    /// Sticky-header state assigned by `AetherListNode`.
    public private(set) var stickyHeaderState: AetherListStickyHeaderState = .none

    /// Extra insets used only for scroll positioning. Telegram rows use this
    /// to align the meaningful visual content instead of the whole backing
    /// node; default is `.zero`.
    public var scrollPositioningInsets: UIEdgeInsets = .zero

    /// Selection state, synced by the list view from
    /// `AetherListNode.selectedIndices`. Subclasses override
    /// `didChangeSelection(animated:)` to render whatever highlight
    /// they want (checkmark, tinted bg, etc.). Animations triggered
    /// at the right moment ride the list-view-supplied flag.
    public internal(set) var isSelected: Bool = false {
        didSet {
            if oldValue != isSelected {
                didChangeSelection(animated: pendingSelectionAnimated)
            }
        }
    }

    /// Set internally by the list view right before flipping
    /// `isSelected` so the override sees the right `animated` flag —
    /// avoids polluting the public setter with a method signature.
    internal var pendingSelectionAnimated: Bool = false

    // MARK: - Computed Properties

    /// Total height including insets.
    public var totalHeight: CGFloat {
        return insets.top + contentSize.height + insets.bottom
    }

    /// Content bounds (frame minus insets).
    public var contentBounds: CGRect {
        return CGRect(
            x: insets.left,
            y: insets.top,
            width: max(0, bounds.width - insets.left - insets.right),
            height: contentSize.height
        )
    }

    /// Frame adjusted for animated height.
    public var apparentFrame: CGRect {
        return CGRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: apparentHeight
        )
    }

    // MARK: - Init

    public override init() {
        super.init()
        clipsToBounds = true
    }

    public init(frame: CGRect) {
        super.init()
        self.frame = AetherListFrameMetrics.sanitizedRect(frame)
        clipsToBounds = true
    }

    public required init?(coder: NSCoder) {
        super.init()
        clipsToBounds = true
    }

    // MARK: - Layout

    open override func layout() {
        super.layout()
        layoutSubviews()
    }

    open func layoutSubviews() {
        if let swipeRevealBackgroundNode {
            swipeRevealBackgroundNode.frame = bounds
            swipeRevealBackgroundNode.layer.cornerRadius = min(26.0, bounds.height / 2.0)
        }
        layoutAccessoryViews()
    }

    open override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return view.hitTest(point, with: event)
    }

    open override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return view.point(inside: point, with: event)
    }

    /// Apply a layout result. Called by the list view after item creation or update.
    public func applyLayout(_ layout: AetherListItemNodeLayout) {
        let sanitizedLayout = AetherListItemNodeLayout(
            contentSize: layout.contentSize,
            insets: layout.insets
        )
        self.currentLayout = sanitizedLayout
        self.contentSize = sanitizedLayout.contentSize
        self.insets = sanitizedLayout.insets
        self.apparentHeight = sanitizedLayout.totalHeight
        setNeedsLayout()
    }

    public final func setAccessoryItem(_ item: AetherListAccessoryItem?, placement: AetherListAccessoryPlacement) {
        guard let item else {
            if let slot = accessorySlots.removeValue(forKey: placement) {
                slot.node.removeFromSupernode()
                setNeedsLayout()
            }
            return
        }

        if var slot = accessorySlots[placement], slot.stableId == item.stableId {
            slot.item = item
            item.updateNode(slot.node)
            accessorySlots[placement] = slot
            setNeedsLayout()
            return
        }

        if let oldSlot = accessorySlots.removeValue(forKey: placement) {
            oldSlot.node.removeFromSupernode()
        }

        let node = item.makeNode()
        item.updateNode(node)
        addSubnode(node)
        accessorySlots[placement] = AccessorySlot(stableId: item.stableId, item: item, node: node)
        setNeedsLayout()
    }

    open func accessoryFrame(
        for placement: AetherListAccessoryPlacement,
        accessorySize: CGSize,
        bounds: CGRect
    ) -> CGRect {
        let size = CGSize(
            width: min(max(0.0, accessorySize.width), bounds.width),
            height: min(max(0.0, accessorySize.height), bounds.height)
        )
        switch placement {
        case .accessory:
            return CGRect(
                x: bounds.maxX - size.width - 16.0,
                y: bounds.midY - size.height / 2.0,
                width: size.width,
                height: size.height
            )
        case .headerAccessory:
            return CGRect(
                x: bounds.maxX - size.width - 16.0,
                y: bounds.minY,
                width: size.width,
                height: size.height
            )
        }
    }

    private func layoutAccessoryViews() {
        guard !accessorySlots.isEmpty else { return }
        for (placement, slot) in accessorySlots {
            let accessorySize = slot.item.size(constrainedTo: bounds.size)
            slot.node.frame = accessoryFrame(
                for: placement,
                accessorySize: accessorySize,
                bounds: bounds
            )
        }
    }

    /// Called before the node enters the reuse pool. Subclasses should cancel
    /// image/text work, clear transient gesture state, and reset content that
    /// is not overwritten by `updateNode`.
    open func prepareForReuse() {
        for slot in accessorySlots.values {
            slot.node.removeFromSupernode()
        }
        accessorySlots.removeAll()
        swipeRevealBackgroundNode?.removeFromSupernode()
        swipeRevealBackgroundNode = nil
        isSwipeRevealBackgroundActive = false
        if let swipeRevealStoredBackgroundColor {
            backgroundColor = swipeRevealStoredBackgroundColor
        }
        if let swipeRevealStoredCornerRadius {
            layer.cornerRadius = swipeRevealStoredCornerRadius
        }
        if let swipeRevealStoredMasksToBounds {
            clipsToBounds = swipeRevealStoredMasksToBounds
        }
        swipeRevealStoredBackgroundColor = nil
        swipeRevealStoredCornerRadius = nil
        swipeRevealStoredMasksToBounds = nil
        updateStickyHeaderState(.none, animated: false)
    }

    internal func setSwipeRevealBackgroundActive(
        _ active: Bool,
        transition: ContainedViewLayoutTransition
    ) {
        if !active, !isSwipeRevealBackgroundActive {
            isSwipeRevealBackgroundActive = false
            return
        }

        if active, !isSwipeRevealBackgroundActive {
            swipeRevealStoredBackgroundColor = backgroundColor
            swipeRevealStoredCornerRadius = layer.cornerRadius
            swipeRevealStoredMasksToBounds = clipsToBounds
        }
        isSwipeRevealBackgroundActive = active
        let activeCornerRadius = min(26.0, bounds.height / 2.0)

        if active {
            backgroundColor = aetherListSwipeRevealBackgroundColor
            layer.cornerCurve = .continuous
            layer.cornerRadius = activeCornerRadius
            clipsToBounds = true
        } else {
            backgroundColor = swipeRevealStoredBackgroundColor
            layer.cornerRadius = swipeRevealStoredCornerRadius ?? 0.0
            clipsToBounds = swipeRevealStoredMasksToBounds ?? false
            swipeRevealStoredBackgroundColor = nil
            swipeRevealStoredCornerRadius = nil
            swipeRevealStoredMasksToBounds = nil
        }

        let backgroundNode: ASDisplayNode
        if let current = swipeRevealBackgroundNode {
            backgroundNode = current
        } else {
            let current = ASDisplayNode()
            current.frame = bounds
            current.backgroundColor = aetherListSwipeRevealBackgroundColor
            current.layer.cornerCurve = .continuous
            current.layer.cornerRadius = activeCornerRadius
            current.alpha = 0.0
            insertSubnode(current, at: 0)
            swipeRevealBackgroundNode = current
            backgroundNode = current
        }

        backgroundNode.frame = bounds
        backgroundNode.backgroundColor = aetherListSwipeRevealBackgroundColor
        backgroundNode.layer.cornerRadius = activeCornerRadius

        transition.updateAlpha(view: backgroundNode.view, alpha: active ? 1.0 : 0.0) { [weak self, weak backgroundNode] _ in
            guard let self, let backgroundNode, !self.isSwipeRevealBackgroundActive else {
                return
            }
            backgroundNode.removeFromSupernode()
            if self.swipeRevealBackgroundNode === backgroundNode {
                self.swipeRevealBackgroundNode = nil
            }
        }
    }

    internal func updateStickyHeaderState(_ state: AetherListStickyHeaderState, animated: Bool) {
        guard stickyHeaderState != state else { return }
        stickyHeaderState = state
        stickyHeaderStateDidChange(state, animated: animated)
    }

    // MARK: - Lifecycle Hooks (Override in Subclasses)

    /// Called when the node's absolute position within the list changes.
    /// Use for visibility tracking, parallax effects, etc.
    open func updateAbsoluteRect(_ rect: CGRect, within containerSize: CGSize) {
    }

    /// Called whenever `isSelected` flips. Override to render the
    /// highlight / checkmark / accessory. Default is a no-op.
    open func didChangeSelection(animated: Bool) {
    }

    /// Called when the node starts/stops acting as a sticky header. `isFlashing`
    /// is true while the header is temporarily overlaid outside its natural slot
    /// during pin/push transitions.
    open func stickyHeaderStateDidChange(_ state: AetherListStickyHeaderState, animated: Bool) {
    }

    /// Node that owns the visual the particle-dissolve delete animation should
    /// target. Default is the row node itself; overrides return a tighter
    /// sub-region such as the chat bubble inside a padded row.
    open var particleDissolveTargetNode: ASDisplayNode { self }

    /// View that owns the visual the particle-dissolve delete animation should
    /// target. UIKit-backed row nodes can override this without creating a
    /// synthetic `ASDisplayNode` just to expose an existing content view.
    open var particleDissolveTargetView: UIView { particleDissolveTargetNode.view }

    /// Called when the node is being inserted with animation.
    /// Default treatment is a soft slide-down from a quarter-row
    /// above its final slot, paired with an alpha fade in — same
    /// shape iMessage / Telegram use for incoming rows. Override
    /// for custom directions or to cut to a plain fade.
    open func animateInsertion(duration: Double) {
        animateInsertion(duration: duration, directionHint: nil, invertOffsetDirection: false)
    }

    /// Called when the node is being inserted with animation. The extended
    /// signature lets the list pass Telegram-style operation hints while
    /// preserving the old override point above.
    open func animateInsertion(duration: Double, directionHint: AetherListItemOperationDirectionHint?, invertOffsetDirection: Bool) {
        let dy = -bounds.height * 0.25
        let directionMultiplier: CGFloat
        switch directionHint {
        case .up:
            directionMultiplier = -1.0
        case .down:
            directionMultiplier = 1.0
        case nil:
            directionMultiplier = 1.0
        }
        let resolvedDy = dy * directionMultiplier * (invertOffsetDirection ? -1.0 : 1.0)
        alpha = 0
        view.transform = CGAffineTransform(translationX: 0, y: resolvedDy)
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0.2,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: {
                self.alpha = 1
                self.view.transform = .identity
            },
            completion: nil
        )
    }

    /// Called when the node is being removed with animation.
    open func animateRemoval(duration: Double, completion: @escaping () -> Void) {
        UIView.animate(withDuration: duration, animations: {
            self.alpha = 0
        }, completion: { _ in
            completion()
        })
    }

    // MARK: - Interaction Hooks

    /// Insets applied to the node frame before list-level gesture hit testing.
    /// Positive values shrink the active row area, negative values expand it.
    open func listGestureHitTestInsets(for gesture: AetherListItemGesture) -> UIEdgeInsets {
        return .zero
    }

    /// Return `false` to let nested controls or custom gestures own the touch.
    /// The default blocks list-level tap/reorder when the touched descendant is
    /// a `UIControl`, `UITextView`, nested `UIScrollView`, or has its own
    /// gesture recognizer.
    open func allowsListGesture(_ gesture: AetherListItemGesture, at point: CGPoint) -> Bool {
        return !containsInteractiveDescendantForListGesture(at: point)
    }

    /// Called when the node is highlighted (touch down).
    open func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) {
    }

    /// Called when the node is tapped.
    open func tapped() {
    }

    /// Called when the node is long-pressed.
    open func longTapped() {
    }

    /// Called when the node's item is selected.
    open func selected() {
    }

    private func containsInteractiveDescendantForListGesture(at point: CGPoint) -> Bool {
        guard bounds.contains(point), let hitView = hitTest(point, with: nil) else {
            return false
        }

        var current: UIView? = hitView
        while let view = current, view !== self.view {
            if view is UIControl || view is UITextView || view is UIScrollView {
                return true
            }
            if let recognizers = view.gestureRecognizers, !recognizers.isEmpty {
                return true
            }
            current = view.superview
        }
        return false
    }
}
