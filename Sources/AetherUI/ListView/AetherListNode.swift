import UIKit
import AsyncDisplayKit
import AetherUIBridging

/// Texture-native list container.
///
/// `AetherListNode` is the new home for list logic. It keeps Aether's
/// transaction/item API, and materializes rows as Texture subnodes inside an
/// `ASScrollNode`.
public enum AetherListKeyboardDismissBehavior: Equatable {
    case none
    case onDrag
    case interactive
    case onDragWithAccessory
    case interactiveWithAccessory

    fileprivate init(_ keyboardDismissMode: UIScrollView.KeyboardDismissMode) {
        switch keyboardDismissMode {
        case .none:
            self = .none
        case .onDrag:
            self = .onDrag
        case .interactive:
            self = .interactive
        case .onDragWithAccessory:
            self = .onDragWithAccessory
        case .interactiveWithAccessory:
            self = .interactiveWithAccessory
        @unknown default:
            self = .none
        }
    }

    fileprivate var keyboardDismissMode: UIScrollView.KeyboardDismissMode {
        switch self {
        case .none:
            return .none
        case .onDrag:
            return .onDrag
        case .interactive:
            return .interactive
        case .onDragWithAccessory:
            return .onDragWithAccessory
        case .interactiveWithAccessory:
            return .interactiveWithAccessory
        }
    }
}

public struct AetherListAutomaticInsetEdges: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let top = AetherListAutomaticInsetEdges(rawValue: 1 << 0)
    public static let left = AetherListAutomaticInsetEdges(rawValue: 1 << 1)
    public static let bottom = AetherListAutomaticInsetEdges(rawValue: 1 << 2)
    public static let right = AetherListAutomaticInsetEdges(rawValue: 1 << 3)
    public static let vertical: AetherListAutomaticInsetEdges = [.top, .bottom]
    public static let horizontal: AetherListAutomaticInsetEdges = [.left, .right]
    public static let all: AetherListAutomaticInsetEdges = [.vertical, .horizontal]
}

private final class AetherListNodeDelegateProxy: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    weak var listNode: AetherListNode?

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        listNode?.scrollViewDidScroll(scrollView)
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        listNode?.scrollViewShouldScrollToTop(scrollView) ?? false
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        listNode?.scrollViewWillBeginDragging(scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        listNode?.scrollViewDidEndDragging(scrollView, willDecelerate: decelerate)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        listNode?.scrollViewDidEndDecelerating(scrollView)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        listNode?.gestureRecognizer(gestureRecognizer, shouldReceive: touch) ?? true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        listNode?.gestureRecognizer(
            gestureRecognizer,
            shouldRecognizeSimultaneouslyWith: otherGestureRecognizer
        ) ?? false
    }
}

private final class AetherListSwipeActionsNode: ASDisplayNode {
    private final class ActionButtonNode: ASControlNode {
        let action: AetherListSwipeAction
        private let circleNode = ASDisplayNode()
        private let titleNode = ASTextNode()
        private let imageNode = ASImageNode()
        private let onSelected: (AetherListSwipeAction) -> Void

        init(action: AetherListSwipeAction, selected: @escaping (AetherListSwipeAction) -> Void) {
            self.action = action
            self.onSelected = selected
            super.init()
            addSubnode(circleNode)
            addSubnode(titleNode)
            circleNode.addSubnode(imageNode)
            addTarget(self, action: #selector(pressed), forControlEvents: .touchUpInside)
            backgroundColor = .clear
            clipsToBounds = false
            isAccessibilityElement = true
            accessibilityLabel = action.accessibilityLabel ?? action.title

            circleNode.backgroundColor = action.backgroundColor
            circleNode.cornerRoundingType = .precomposited
            circleNode.clipsToBounds = true
            circleNode.layer.masksToBounds = true

            titleNode.maximumNumberOfLines = 1
            titleNode.truncationMode = .byTruncatingTail
            titleNode.attributedText = NSAttributedString(
                string: action.title,
                attributes: [
                    .font: UIFont.aetherScaledSystemFont(ofSize: 11.0, weight: .semibold),
                    .foregroundColor: action.textColor ?? UIColor.label
                ]
            )
            switch action.icon {
            case .none:
                imageNode.image = nil
                imageNode.isHidden = true
            case let .image(image):
                imageNode.image = image.withRenderingMode(.alwaysTemplate)
                imageNode.tintColor = action.foregroundColor
                imageNode.isHidden = false
            }
        }

        override func layout() {
            super.layout()
            let titleSize = titleNode.layoutThatFits(
                ASSizeRange(min: .zero, max: CGSize(width: bounds.width - 4.0, height: bounds.height))
            ).size
            let spacing: CGFloat = titleSize.height > 0.0 ? 4.0 : 0.0
            let availableCircleSide = max(
                28.0,
                min(bounds.width - 8.0, bounds.height - titleSize.height - spacing - 4.0)
            )
            let circleSide = min(
                48.0,
                availableCircleSide
            )
            let contentHeight = circleSide + spacing + titleSize.height
            var y = floor((bounds.height - contentHeight) / 2.0)

            circleNode.frame = CGRect(
                x: floor((bounds.width - circleSide) / 2.0),
                y: y,
                width: circleSide,
                height: circleSide
            )
            circleNode.cornerRadius = circleSide / 2.0
            circleNode.layer.cornerRadius = circleSide / 2.0
            circleNode.layer.masksToBounds = true
            if #available(iOS 13.0, *) {
                circleNode.layer.cornerCurve = .continuous
            }

            let hasImage = imageNode.image != nil
            let imageSide: CGFloat = hasImage ? min(22.0, circleSide * 0.48) : 0.0

            if hasImage {
                imageNode.frame = CGRect(
                    x: floor((circleSide - imageSide) / 2.0),
                    y: floor((circleSide - imageSide) / 2.0),
                    width: imageSide,
                    height: imageSide
                )
            } else {
                imageNode.frame = .zero
            }
            y += circleSide + spacing
            titleNode.frame = CGRect(
                x: floor((bounds.width - titleSize.width) / 2.0),
                y: y,
                width: titleSize.width,
                height: titleSize.height
            )
        }

        @objc private func pressed() {
            onSelected(action)
        }
    }

    private let actionSelected: (AetherListSwipeAction) -> Void
    private let expandedStateChanged: () -> Void
    private var swipeActions: AetherListSwipeActions = .none
    private var leftButtons: [ActionButtonNode] = []
    private var rightButtons: [ActionButtonNode] = []
    private var lastExpandedSide: AetherListSwipeActionsSide?

    private(set) var revealOffset: CGFloat = 0.0

    init(
        actionSelected: @escaping (AetherListSwipeAction) -> Void,
        expandedStateChanged: @escaping () -> Void
    ) {
        self.actionSelected = actionSelected
        self.expandedStateChanged = expandedStateChanged
        super.init()
        isUserInteractionEnabled = true
        clipsToBounds = false
    }

    func setActions(_ actions: AetherListSwipeActions) {
        guard swipeActions != actions else { return }
        swipeActions = actions
        rebuildButtons()
        setNeedsLayout()
    }

    func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat) {
        let sanitizedSize = AetherListFrameMetrics.sanitizedSize(size)
        frame = CGRect(
            origin: AetherListFrameMetrics.sanitizedPoint(frame.origin),
            size: sanitizedSize
        )
        layoutButtons(
            size: sanitizedSize,
            leftInset: AetherListFrameMetrics.sanitizedCoordinate(leftInset),
            rightInset: AetherListFrameMetrics.sanitizedCoordinate(rightInset)
        )
    }

    func updateRevealOffset(
        _ offset: CGFloat,
        transition: ContainedViewLayoutTransition,
        completion: (() -> Void)? = nil
    ) {
        revealOffset = offset
        let targetAlpha: CGFloat = offset.isZero ? 0.0 : 1.0
        transition.updateAlpha(view: view, alpha: targetAlpha) { _ in
            completion?()
        }
        layoutButtons(size: bounds.size, leftInset: 0.0, rightInset: 0.0)

        let side: AetherListSwipeActionsSide? = offset > 0.0 ? .left : (offset < 0.0 ? .right : nil)
        if let side {
            let width = revealWidth(for: swipeActions.actions(for: side), height: bounds.height)
            let expanded = abs(offset) > width + min(max(48.0, width * 0.35), bounds.width * 0.32)
            if expanded, lastExpandedSide != side {
                lastExpandedSide = side
                expandedStateChanged()
            } else if !expanded {
                lastExpandedSide = nil
            }
        } else {
            lastExpandedSide = nil
        }
    }

    func containsInteractiveAction(at point: CGPoint) -> Bool {
        let buttons = revealOffset >= 0.0 ? leftButtons : rightButtons
        return buttons.contains { !$0.isHidden && $0.frame.contains(point) }
    }

    override func layout() {
        super.layout()
        layoutButtons(size: bounds.size, leftInset: 0.0, rightInset: 0.0)
    }

    private func rebuildButtons() {
        for button in leftButtons + rightButtons {
            button.removeFromSupernode()
        }
        leftButtons = swipeActions.left.map(makeButton)
        rightButtons = swipeActions.right.map(makeButton)
        for button in leftButtons + rightButtons {
            addSubnode(button)
        }
    }

    private func makeButton(for action: AetherListSwipeAction) -> ActionButtonNode {
        ActionButtonNode(action: action) { [weak self] action in
            self?.actionSelected(action)
        }
    }

    private func layoutButtons(size: CGSize, leftInset: CGFloat, rightInset: CGFloat) {
        let leftWidth = revealWidth(for: swipeActions.left, height: size.height)
        let rightWidth = revealWidth(for: swipeActions.right, height: size.height)
        layout(
            buttons: leftButtons,
            actions: swipeActions.left,
            side: .left,
            revealWidth: leftWidth,
            size: size,
            horizontalInset: leftInset
        )
        layout(
            buttons: rightButtons,
            actions: swipeActions.right,
            side: .right,
            revealWidth: rightWidth,
            size: size,
            horizontalInset: rightInset
        )
    }

    private func layout(
        buttons: [ActionButtonNode],
        actions: [AetherListSwipeAction],
        side: AetherListSwipeActionsSide,
        revealWidth: CGFloat,
        size: CGSize,
        horizontalInset: CGFloat
    ) {
        guard !buttons.isEmpty else { return }
        let shapeWidth: CGFloat = size.height < 72.0 ? 64.0 : 60.0
        let spacing: CGFloat = 10.0
        let edgeInset: CGFloat = 10.0
        let visibleSide: AetherListSwipeActionsSide? = revealOffset > 0.0 ? .left : (revealOffset < 0.0 ? .right : nil)

        for (index, button) in buttons.enumerated() {
            let x: CGFloat
            switch side {
            case .left:
                x = horizontalInset + edgeInset + CGFloat(index) * (shapeWidth + spacing)
            case .right:
                let reversedIndex = CGFloat(buttons.count - 1 - index)
                x = size.width - horizontalInset - edgeInset - shapeWidth - reversedIndex * (shapeWidth + spacing)
            }
            button.frame = CGRect(
                x: x,
                y: 0.0,
                width: shapeWidth,
                height: size.height
            )
            button.isHidden = visibleSide != side || revealWidth.isZero
            button.alpha = button.isHidden ? 0.0 : 1.0
        }
    }

    private func revealWidth(for actions: [AetherListSwipeAction], height: CGFloat) -> CGFloat {
        guard !actions.isEmpty else { return 0.0 }
        let shapeWidth: CGFloat = height < 72.0 ? 64.0 : 60.0
        let spacing: CGFloat = 10.0
        let edgeInset: CGFloat = 10.0
        return edgeInset * 2.0 + shapeWidth * CGFloat(actions.count) + spacing * CGFloat(actions.count - 1)
    }
}

open class AetherListNode: AetherMainActorDisplayNode {
    private let scrollNode = ASScrollNode()
    private let contentNode = ASDisplayNode()
    private let delegateProxy = AetherListNodeDelegateProxy()

    private var items: [AetherListItem] = []
    private var itemNodes: [AetherListItemNode] = []
    private var itemHeights: [CGFloat] = []
    private var itemOffsets: [CGFloat] = []
    private var stickyHeaderItemIndices: [Int] = []
    private var totalContentHeight: CGFloat = 0.0
    private var reusePool: [String: [AetherListItemNode]] = [:]
    private let maxReusableNodesPerIdentifier = 32
    private var layoutCache: [AnyHashable: AetherListItemNodeLayout] = [:]
    private var layoutCacheOrder: [AnyHashable] = []
    private var preparedLayoutCache: [AnyHashable: AetherListPreparedItemLayout] = [:]
    private var pendingLayoutTasks: [AnyHashable: AetherListLayoutTask] = [:]
    private var synchronousLayoutIdentifiers = Set<String>()
    private let maxLayoutCacheEntries = 512
    private var lastLayoutSize: CGSize = .zero
    private var _insets: UIEdgeInsets = .zero
    private var automaticSafeAreaInsets: UIEdgeInsets = .zero
    private var keyboardBottomInset: CGFloat = 0.0
    private var _headerInsets: UIEdgeInsets?
    private var _scrollIndicatorInsets: UIEdgeInsets?
    private var _itemOffsetInsets: UIEdgeInsets?
    private var _virtualContentInsets: AetherListVirtualContentInsets = .zero
    private var revealedSwipeItemId: AnyHashable?
    private var revealedSwipeOffset: CGFloat = 0.0
    private var selectedItemIds = Set<ObjectIdentifier>()
    private weak var tapRecognizer: UITapGestureRecognizer?
    private weak var swipeRecognizer: AetherListSwipeGestureRecognizer?
    private weak var reorderRecognizer: UILongPressGestureRecognizer?
    private var swipeActionNodes: [ObjectIdentifier: AetherListSwipeActionsNode] = [:]
    private var swipeState: SwipeState?
    private var reorderState: ReorderState?
    private var swipeHapticFeedbackGenerator: UIImpactFeedbackGenerator?
    private var previousDidScrollContentOffsetY: CGFloat?
    private var tapSelectionSuppressedUntil: TimeInterval = 0.0
    private var boundaryTriggerSignatures: [AetherListBoundaryEdge: BoundaryTriggerSignature] = [:]
    private var accessibilityNodeOrder: [ObjectIdentifier] = []
    private weak var refreshControl: UIRefreshControl?
    private weak var customScrollIndicatorView: UIView?
    private weak var debugOverlayLabel: AetherTextNodeOverlayView?
    private weak var _particleDissolveOverlayHostNode: ASDisplayNode?
    private weak var _particleDissolveOverlayHostView: UIView?
    private var dustEffectView: AetherDustEffectView?
    private var customScrollIndicatorFadeWorkItem: DispatchWorkItem?
    private var contentSizeCategoryRelayoutGeneration: UInt = 0
    private var _topOverscrollBackgroundNode: ASDisplayNode?
    private var _bottomOverscrollBackgroundNode: ASDisplayNode?
    private let transactionAnimationDuration: Double = 0.32
    private let particleDissolveVisualDuration: Double = 0.8
    private let particleDissolveDustAnimationSpeed: Float = 2.0

    private struct BoundaryTriggerSignature: Equatable {
        let itemCount: Int
        let loadedLowerBound: Int?
        let loadedUpperBound: Int?
        let visibleLowerBound: Int?
        let visibleUpperBound: Int?
    }

    private struct SwipeState {
        let itemId: AnyHashable
        weak var node: AetherListItemNode?
        let initialRevealOffset: CGFloat
        var didNotifyOpen: Bool
    }

    private struct ReorderState {
        let originalIndex: Int
        var currentIndex: Int
        let touchOffsetY: CGFloat
        let draggingNode: AetherListItemNode
        let originalAlpha: CGFloat
        let dragHeight: CGFloat
    }

    private struct TransactionRemovingNode {
        let node: AetherListItemNode
        let reuseIdentifier: String?
        let animation: AetherListItemDeleteAnimation
        let hint: AetherListItemOperationDirectionHint?
    }

    public let debugInstrumentation = AetherListDebugInstrumentation()

    public override init() {
        super.init()
        delegateProxy.listNode = self
        backgroundColor = .clear
        scrollNode.scrollableDirections = ASScrollDirectionVerticalDirections
        scrollNode.automaticallyManagesContentSize = false
        addSubnode(scrollNode)
        scrollNode.addSubnode(contentNode)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UIContentSizeCategory.didChangeNotification, object: nil)
    }

    open override func didLoad() {
        super.didLoad()
        scrollNode.view.alwaysBounceVertical = true
        scrollNode.view.showsHorizontalScrollIndicator = false
        scrollNode.view.contentInsetAdjustmentBehavior = .never
        scrollNode.view.delegate = delegateProxy
        setupSwipeRecognizer()
        setupReorderRecognizer()
        setupTapRecognizer()
        _ = applyScrollInsets()
        syncRefreshControl()
        syncCustomScrollIndicator()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleContentSizeCategoryDidChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil
        )
        syncDebugOverlay()
    }

    open override func layout() {
        super.layout()
        let previousLayoutSize = lastLayoutSize
        let sanitizedBounds = AetherListFrameMetrics.sanitizedRect(bounds)
        lastLayoutSize = sanitizedBounds.size
        scrollNode.frame = sanitizedBounds
        if abs(previousLayoutSize.width - sanitizedBounds.width) > 0.5 {
            clearLayoutCaches(cancelPending: true)
            relayoutLoadedNodes(params: layoutParams())
        }
        relayoutContent()
        updateCustomScrollIndicator()
        updateOverscrollState()
        layoutDebugOverlay()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let currentOffsetY = scrollView.contentOffset.y
        let deltaY = currentOffsetY - (previousDidScrollContentOffsetY ?? currentOffsetY)
        previousDidScrollContentOffsetY = currentOffsetY
        let isUserInitiated = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        if scrollView.isDecelerating {
            suppressTapSelectionAfterScrollMomentum()
        }
        updateVisibleNodes()
        applyStickyHeaderLayout()
        applyVisibilityLifecycle(isUserInitiated: isUserInitiated)
        updateOverscrollState()
        flashCustomScrollIndicator()
        visibleContentOffsetChanged?(visibleContentOffset())
        didScrollWithOffset?(deltaY, .immediate, nil, isUserInitiated)
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        scrollToTopInPages(animated: true)
        return false
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if revealedSwipeItemId != nil {
            closeSwipeActions(animated: true)
        }
        beganInteractiveDragging?()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            suppressTapSelectionAfterScrollMomentum(duration: 0.08)
            didEndScrolling?()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        suppressTapSelectionAfterScrollMomentum(duration: 0.18)
        didEndScrolling?()
    }

    private func suppressTapSelectionAfterScrollMomentum(duration: TimeInterval = 0.28) {
        tapSelectionSuppressedUntil = max(
            tapSelectionSuppressedUntil,
            CACurrentMediaTime() + duration
        )
    }

    private func isTapSelectionSuppressedByScrollMomentum() -> Bool {
        scrollNode.view.isDragging
            || scrollNode.view.isDecelerating
            || CACurrentMediaTime() < tapSelectionSuppressedUntil
    }

    public var debugInfo: Bool {
        get { debugInstrumentation.isEnabled }
        set {
            debugInstrumentation.isEnabled = newValue
            syncDebugOverlay()
        }
    }

    public var showsDebugOverlay: Bool = false {
        didSet { syncDebugOverlay() }
    }

    public var dynamicTypeInvalidated: (() -> Void)?

    public var preloadPages: CGFloat = 1.0

    /// Optional preload window used only for materializing item nodes. When
    /// nil, node creation follows `preloadPages` for legacy behaviour.
    public var nodePreloadPages: CGFloat?

    public var scrollEnabled: Bool {
        get { scrollNode.view.isScrollEnabled }
        set { scrollNode.view.isScrollEnabled = newValue }
    }

    public var scroller: UIScrollView {
        scrollNode.view
    }

    public var stackFromBottom: Bool = false {
        didSet { relayoutContent() }
    }

    public var stackFromBottomAutoAnchorTolerance: CGFloat = 60.0

    public var compensatesBottomInsetChanges: Bool = false

    public var automaticInsetEdges: AetherListAutomaticInsetEdges = [] {
        didSet {
            guard oldValue != automaticInsetEdges else { return }
            _ = applyScrollInsets()
            relayoutContent()
        }
    }

    public var insets: UIEdgeInsets {
        get { _insets }
        set {
            _insets = AetherListFrameMetrics.sanitizedInsets(newValue)
            _ = applyScrollInsets()
        }
    }

    public var headerInsets: UIEdgeInsets? {
        get { _headerInsets }
        set {
            _headerInsets = newValue.map(AetherListFrameMetrics.sanitizedInsets)
            relayoutContent()
        }
    }

    public var scrollIndicatorInsets: UIEdgeInsets? {
        get { _scrollIndicatorInsets }
        set {
            _scrollIndicatorInsets = newValue.map(AetherListFrameMetrics.sanitizedInsets)
            _ = applyScrollInsets(adjustsContentOffsetForTopInsetChange: false)
        }
    }

    public var itemOffsetInsets: UIEdgeInsets? {
        get { _itemOffsetInsets }
        set {
            _itemOffsetInsets = newValue.map(AetherListFrameMetrics.sanitizedInsets)
            rebuildOffsets()
            relayoutContent()
        }
    }

    public var virtualContentInsets: AetherListVirtualContentInsets {
        get { _virtualContentInsets }
        set {
            updateVirtualContentInsets(newValue, transition: .immediate)
        }
    }

    public func updateVirtualContentInsets(
        _ virtualContentInsets: AetherListVirtualContentInsets,
        transition: ContainedViewLayoutTransition = .immediate
    ) {
        let previousOffsetInsets = AetherListContentMetricsPlanner.effectiveOffsetInsets(
            itemOffsetInsets: _itemOffsetInsets,
            virtualContentInsets: _virtualContentInsets
        )
        let updatedOffsetInsets = AetherListContentMetricsPlanner.effectiveOffsetInsets(
            itemOffsetInsets: _itemOffsetInsets,
            virtualContentInsets: virtualContentInsets
        )
        let topDelta = AetherListContentMetricsPlanner.topDelta(
            from: previousOffsetInsets,
            to: updatedOffsetInsets
        )

        _virtualContentInsets = virtualContentInsets
        rebuildOffsets()
        if isNodeLoaded, !topDelta.isZero {
            let targetOffset = AetherListFrameMetrics.sanitizedPoint(
                CGPoint(x: scrollNode.view.contentOffset.x, y: scrollNode.view.contentOffset.y + topDelta)
            )
            transition.updateScrollViewInsetsAndOffset(
                scrollView: scrollNode.view,
                contentInset: scrollNode.view.contentInset,
                scrollIndicatorInsets: scrollIndicatorInsets ?? scrollNode.view.contentInset,
                contentOffset: targetOffset
            )
        }
        relayoutContent()
    }

    public func updateAutomaticSafeAreaInsets(
        _ safeAreaInsets: UIEdgeInsets,
        transition: ContainedViewLayoutTransition = .immediate
    ) {
        let sanitizedSafeAreaInsets = AetherListFrameMetrics.sanitizedInsets(safeAreaInsets)
        guard automaticSafeAreaInsets != sanitizedSafeAreaInsets else { return }
        automaticSafeAreaInsets = sanitizedSafeAreaInsets
        _ = applyScrollInsets(transition: transition)
        relayoutContent()
    }

    public func updateInsets(
        _ insets: UIEdgeInsets,
        transition: ContainedViewLayoutTransition,
        compensatesBottomInsetChanges: Bool? = nil,
        preserveContentOffset: Bool = false
    ) {
        let sanitizedInsets = AetherListFrameMetrics.sanitizedInsets(insets)
        let previousBottomInset = effectiveScrollInsets().bottom
        let scrollOffsetDeltaY: CGFloat?
        _insets = sanitizedInsets
        if preserveContentOffset {
            scrollOffsetDeltaY = nil
        } else {
            let bottomDelta = effectiveScrollInsets().bottom - previousBottomInset
            scrollOffsetDeltaY = (compensatesBottomInsetChanges ?? self.compensatesBottomInsetChanges) && !bottomDelta.isZero
                ? bottomDelta
                : nil
        }
        let adjustedTopOffset = applyScrollInsets(
            transition: transition,
            adjustsContentOffsetForTopInsetChange: !preserveContentOffset,
            additionalContentOffsetDeltaY: scrollOffsetDeltaY
        )
        if preserveContentOffset {
            // Keep the current raw content offset unchanged.
        } else if adjustedTopOffset {
            // Top anchoring wins over bottom compensation when both change.
        }
        relayoutContent()
    }

    public func keyboardBottomInset(for layout: ContainerViewLayout, in containerView: UIView) -> CGFloat {
        let keyboardHeight = max(0.0, layout.inputHeight ?? 0.0)
        guard keyboardHeight > 0.0, bounds.height > 0.0 else {
            return 0.0
        }

        let keyboardTopInContainer = layout.size.height - keyboardHeight
        let keyboardTopInList = view.convert(
            CGPoint(x: containerView.bounds.midX, y: keyboardTopInContainer),
            from: containerView
        ).y
        return max(0.0, bounds.maxY - keyboardTopInList)
    }

    public func updateInsets(
        _ insets: UIEdgeInsets,
        keyboardBottomInset: CGFloat,
        transition: ContainedViewLayoutTransition,
        compensatesBottomInsetChanges: Bool = true,
        preserveContentOffset: Bool = false
    ) {
        let sanitizedInsets = AetherListFrameMetrics.sanitizedInsets(insets)
        let previousBottomInset = effectiveScrollInsets().bottom
        let scrollOffsetDeltaY: CGFloat?
        _insets = sanitizedInsets
        self.keyboardBottomInset = AetherListFrameMetrics.sanitizedLength(keyboardBottomInset)
        if preserveContentOffset {
            scrollOffsetDeltaY = nil
        } else {
            let bottomDelta = effectiveScrollInsets().bottom - previousBottomInset
            scrollOffsetDeltaY = compensatesBottomInsetChanges && !bottomDelta.isZero ? bottomDelta : nil
        }
        let adjustedTopOffset = applyScrollInsets(
            transition: transition,
            adjustsContentOffsetForTopInsetChange: !preserveContentOffset,
            additionalContentOffsetDeltaY: scrollOffsetDeltaY
        )
        if adjustedTopOffset {
            // Top anchoring wins over bottom compensation when both change.
        }
        relayoutContent()
    }

    public func updateInsets(
        _ insets: UIEdgeInsets,
        keyboardLayout layout: ContainerViewLayout,
        in containerView: UIView,
        transition: ContainedViewLayoutTransition
    ) {
        let keyboardInset = keyboardBottomInset(for: layout, in: containerView)
        updateInsets(
            insets,
            keyboardBottomInset: keyboardInset,
            transition: transition,
            compensatesBottomInsetChanges: true,
            preserveContentOffset: false
        )
    }

    public var itemCount: Int {
        items.count
    }

    public var displayedItemRangeChanged: ((AetherListDisplayedItemRange) -> Void)?

    public var displayedItemRange: AetherListDisplayedItemRange {
        computeDisplayedRange()
    }

    public var visibleSize: CGSize {
        scrollNode.bounds.size
    }

    var backingScrollViewForTesting: UIScrollView {
        scrollNode.view
    }

    public var isTracking: Bool {
        scrollNode.view.isTracking
    }

    public var isDragging: Bool {
        scrollNode.view.isDragging
    }

    public var isDecelerating: Bool {
        scrollNode.view.isDecelerating
    }

    public var isScrolling: Bool {
        isTracking || isDragging || isDecelerating
    }

    public var minimumVisibleContentOffset: CGFloat = 0.0

    public var keyboardDismissBehavior: AetherListKeyboardDismissBehavior {
        get { AetherListKeyboardDismissBehavior(scrollNode.view.keyboardDismissMode) }
        set { scrollNode.view.keyboardDismissMode = newValue.keyboardDismissMode }
    }

    public var keyboardDismissMode: UIScrollView.KeyboardDismissMode {
        get { scrollNode.view.keyboardDismissMode }
        set { scrollNode.view.keyboardDismissMode = newValue }
    }

    public var visibleContentOffsetChanged: ((CGFloat) -> Void)?

    public var boundaryTriggerConfiguration: AetherListBoundaryTriggerConfiguration? {
        didSet {
            guard boundaryTriggerConfiguration != oldValue else { return }
            resetBoundaryTriggers()
            evaluateBoundaryTriggers(displayedRange: displayedItemRange, isUserInitiated: false)
        }
    }

    public var boundaryReached: ((AetherListBoundaryTriggerContext) -> Void)?

    public var didScrollWithOffset: ((CGFloat, ContainedViewLayoutTransition, AetherListItemNode?, Bool) -> Void)?

    public var beganInteractiveDragging: (() -> Void)?

    public var didEndScrolling: (() -> Void)?

    public var swipeActionSelected: ((_ index: Int, _ action: AetherListSwipeAction, _ isFullSwipe: Bool) -> Void)?

    public var swipeActionsInteractivelyOpened: ((_ index: Int) -> Void)?

    public var swipeActionsInteractivelyClosed: ((_ index: Int?) -> Void)?

    public var swipeActionHapticFeedback: (() -> Void)?

    public var usesCustomScrollIndicator: Bool = false {
        didSet { syncCustomScrollIndicator() }
    }

    public var customScrollIndicatorFollowsOverscroll: Bool = false {
        didSet { updateCustomScrollIndicator() }
    }

    public var topOverscrollChanged: ((CGFloat) -> Void)?

    public var bottomOverscrollChanged: ((CGFloat) -> Void)?

    public var topOverscrollBackgroundNode: ASDisplayNode? {
        get { _topOverscrollBackgroundNode }
        set {
            _topOverscrollBackgroundNode?.removeFromSupernode()
            _topOverscrollBackgroundNode = newValue
            if let newValue {
                insertSubnode(newValue, belowSubnode: scrollNode)
            }
            updateOverscrollState()
        }
    }

    public var bottomOverscrollBackgroundNode: ASDisplayNode? {
        get { _bottomOverscrollBackgroundNode }
        set {
            _bottomOverscrollBackgroundNode?.removeFromSupernode()
            _bottomOverscrollBackgroundNode = newValue
            if let newValue {
                insertSubnode(newValue, belowSubnode: scrollNode)
            }
            updateOverscrollState()
        }
    }

    public var particleDissolveOverlayHostNode: ASDisplayNode? {
        get { _particleDissolveOverlayHostNode }
        set { _particleDissolveOverlayHostNode = newValue }
    }

    public var particleDissolveOverlayHost: UIView? {
        get { _particleDissolveOverlayHostView }
        set { _particleDissolveOverlayHostView = newValue }
    }

    public var refreshHandler: ((_ done: @escaping () -> Void) -> Void)? {
        didSet { syncRefreshControl() }
    }

    public var isRefreshing: Bool {
        refreshControl?.isRefreshing ?? false
    }

    public var allowsReorder: Bool = false {
        didSet {
            reorderRecognizer?.isEnabled = allowsReorder
        }
    }

    public var canMoveItem: ((_ from: Int, _ to: Int) -> Bool)?

    public var validateReorder: ((_ from: Int, _ to: Int, _ completion: @escaping (Bool) -> Void) -> Void)?

    public var didMoveItem: ((_ from: Int, _ to: Int) -> Void)?

    public var willBeginReorder: ((_ index: Int) -> Void)?

    public var reorderDidBegin: ((_ index: Int) -> Void)?

    public var reorderItem: ((_ from: Int, _ to: Int) -> Void)?

    public var reorderCompleted: ((_ from: Int, _ to: Int, _ finished: Bool) -> Void)?

    public var reorderHapticFeedback: (() -> Void)?

    public var itemTapped: ((Int) -> Void)?

    public var itemGestureShouldBegin: ((_ gesture: AetherListItemGesture, _ index: Int, _ node: AetherListItemNode, _ pointInNode: CGPoint) -> Bool)?

    public var limitsListGestureHitTestingToVisibleItemNodes: Bool = true

    public var selectionMode: AetherListSelectionMode = .none {
        didSet {
            guard selectionMode != oldValue else { return }
            if selectionMode == .none {
                clearSelection(animated: false)
            } else if selectionMode == .single, selectedItemIds.count > 1 {
                if let first = selectedItemIds.first {
                    selectedItemIds = [first]
                    syncSelectionToNodes(animated: false)
                    notifySelectionChanged()
                }
            }
        }
    }

    public var selectedIndices: [Int] {
        guard !selectedItemIds.isEmpty else { return [] }
        return items.enumerated()
            .filter { selectedItemIds.contains(ObjectIdentifier($0.element)) }
            .map(\.offset)
            .sorted()
    }

    public var selectionChanged: ((_ indices: [Int]) -> Void)?

    public var revealedSwipeItemIndex: Int? {
        guard let revealedSwipeItemId else { return nil }
        return items.firstIndex { $0.stableId == revealedSwipeItemId }
    }

    public var state: AetherListState {
        let displayed = computeDisplayedRange()
        return AetherListState(
            itemCount: items.count,
            visibleSize: scrollNode.bounds.size,
            insets: _insets,
            visualInsets: scrollNode.view.contentInset,
            headerInsets: _headerInsets,
            scrollIndicatorInsets: scrollIndicatorInsets,
            virtualContentInsets: _virtualContentInsets,
            totalContentHeight: totalContentHeight,
            virtualOffset: scrollNode.view.contentOffset.y + scrollNode.view.contentInset.top,
            visibleRange: displayed.visibleRange,
            loadedRange: displayed.loadedRange,
            visibleViewCount: itemNodes.count,
            layoutCacheCount: layoutCache.count,
            reusePoolCount: reusePool.reduce(0) { $0 + $1.value.count },
            pendingTransactionCount: 0
        )
    }

    public func transaction(
        deleteIndices: [AetherListDeleteItem] = [],
        moveIndices: [AetherListMoveItem] = [],
        insertIndicesAndItems: [AetherListInsertItem] = [],
        updateIndicesAndItems: [AetherListUpdateItem] = [],
        options: AetherListTransactionOptions = [],
        scrollToItem: AetherListScrollToItem? = nil,
        additionalScrollDistance: CGFloat = 0.0,
        updateSizeAndInsets: AetherListUpdateSizeAndInsets? = nil,
        stationaryItemRange: (Int, Int)? = nil,
        updateOpaqueState: Any? = nil,
        completion: ((AetherListDisplayedItemRange) -> Void)? = nil
    ) {
        debugInstrumentation.recordTransaction()
        debugInstrumentation.measure("AetherListNodeTransaction") {
            executeTransaction(
                deleteIndices: deleteIndices,
                moveIndices: moveIndices,
                insertIndicesAndItems: insertIndicesAndItems,
                updateIndicesAndItems: updateIndicesAndItems,
                options: options,
                updateSizeAndInsets: updateSizeAndInsets,
                scrollToItem: scrollToItem,
                additionalScrollDistance: additionalScrollDistance,
                stationaryItemRange: stationaryItemRange
            )
        }
        completion?(computeDisplayedRange())
    }

    public func transaction(
        _ transaction: AetherListTransaction,
        completion: ((AetherListDisplayedItemRange) -> Void)? = nil
    ) {
        self.transaction(
            deleteIndices: transaction.deleteIndices,
            moveIndices: transaction.moveIndices,
            insertIndicesAndItems: transaction.insertIndicesAndItems,
            updateIndicesAndItems: transaction.updateIndicesAndItems,
            options: transaction.options,
            scrollToItem: transaction.scrollToItem,
            additionalScrollDistance: transaction.additionalScrollDistance,
            updateSizeAndInsets: transaction.updateSizeAndInsets,
            stationaryItemRange: transaction.stationaryItemRange,
            updateOpaqueState: transaction.updateOpaqueState,
            completion: completion
        )
    }

    public func scrollToItem(at index: Int, position: AetherListScrollPosition, animated: Bool) {
        guard index >= 0, index < itemOffsets.count, index < itemHeights.count else { return }
        let nodeInsets = nodeForItem(at: index)?.scrollPositioningInsets ?? .zero
        let customOverflow: CGFloat?
        if case .centerWithOverflow(.custom(let getOverflow)) = position,
           let node = nodeForItem(at: index) {
            customOverflow = getOverflow(node)
        } else {
            customOverflow = nil
        }
        let offset = AetherListFrameMetrics.scrollOffset(
            index: index,
            position: position,
            offsets: itemOffsets,
            heights: itemHeights,
            nodeInsets: nodeInsets,
            viewportHeight: bounds.height,
            insets: scrollNode.view.contentInset,
            currentOffset: scrollNode.view.contentOffset.y,
            customOverflow: customOverflow
        )
        setRawContentOffsetY(offset, animated: animated)
    }

    public func scrollToBottom(animated: Bool) {
        let bottomY = max(
            -scrollNode.view.contentInset.top,
            scrollNode.view.contentSize.height + scrollNode.view.contentInset.bottom - bounds.height
        )
        setRawContentOffsetY(bottomY, animated: animated)
    }

    public func scrollToTop(animated: Bool) {
        setRawContentOffsetY(-scrollNode.view.contentInset.top, animated: animated)
    }

    @discardableResult
    public func scrollToTopInPages(animated: Bool, distance: CGFloat? = nil) -> Bool {
        let visibleHeight = max(0.0, bounds.height - scrollNode.view.contentInset.top - scrollNode.view.contentInset.bottom)
        let pageDistance = distance ?? visibleHeight * 2.0
        let target = max(-scrollNode.view.contentInset.top, scrollNode.view.contentOffset.y - pageDistance)
        guard abs(scrollNode.view.contentOffset.y - target) > CGFloat.ulpOfOne else { return false }
        setRawContentOffsetY(target, animated: animated)
        return true
    }

    @discardableResult
    public func setVisibleContentOffset(_ offset: CGFloat, animated: Bool) -> Bool {
        let clampedOffset = max(minimumVisibleContentOffset, offset)
        let target = clampedOffset - scrollNode.view.contentInset.top
        guard abs(scrollNode.view.contentOffset.y - target) > CGFloat.ulpOfOne else { return false }
        setRawContentOffsetY(target, animated: animated)
        return true
    }

    public func stopScrolling() {
        setRawContentOffsetY(scrollNode.view.contentOffset.y, animated: false)
    }

    public func visibleContentOffset() -> CGFloat {
        scrollNode.view.contentOffset.y + scrollNode.view.contentInset.top
    }

    public func visibleBottomContentOffset() -> CGFloat {
        scrollNode.view.contentSize.height + scrollNode.view.contentInset.bottom - scrollNode.view.bounds.height - scrollNode.view.contentOffset.y
    }

    public func resetBoundaryTriggers(edge: AetherListBoundaryEdge? = nil) {
        if let edge {
            boundaryTriggerSignatures.removeValue(forKey: edge)
        } else {
            boundaryTriggerSignatures.removeAll()
        }
    }

    public func beginRefreshing() {
        guard let control = refreshControl, refreshHandler != nil else { return }
        control.beginRefreshing()
        let target = -(scrollNode.view.adjustedContentInset.top + control.frame.height)
        if scrollNode.view.contentOffset.y > target {
            scrollNode.view.setContentOffset(CGPoint(x: 0.0, y: target), animated: true)
        }
        triggerRefresh()
    }

    public func setSelected(_ selected: Bool, at index: Int, animated: Bool) {
        guard selectionMode != .none else { return }
        guard index >= 0, index < items.count else { return }
        let id = ObjectIdentifier(items[index])
        let before = selectedItemIds
        if selected {
            if selectionMode == .single {
                selectedItemIds = [id]
            } else {
                selectedItemIds.insert(id)
            }
        } else {
            selectedItemIds.remove(id)
        }
        if selectedItemIds != before {
            syncSelectionToNodes(animated: animated)
            notifySelectionChanged()
        }
    }

    public func clearSelection(animated: Bool = true) {
        guard !selectedItemIds.isEmpty else { return }
        selectedItemIds = []
        syncSelectionToNodes(animated: animated)
        notifySelectionChanged()
    }

    public func nodeForItem(at index: Int) -> AetherListItemNode? {
        itemNodes.first { $0.index == index }
    }

    public func forEachVisibleItemNode(_ body: (AetherListItemNode) -> Void) {
        for node in itemNodes {
            body(node)
        }
    }

    public func forEachItemNode(_ body: (AetherListItemNode) -> Void) {
        forEachVisibleItemNode(body)
    }

    public func enumerateItemNodes(_ body: (AetherListItemNode) -> Bool) {
        for node in itemNodes {
            if !body(node) {
                break
            }
        }
    }

    public func panVelocity(relativeTo node: ASDisplayNode? = nil) -> CGPoint {
        scrollNode.view.panGestureRecognizer.velocity(in: node?.view)
    }

    public func addAfterTransactionsCompleted(_ f: @escaping () -> Void) {
        f()
    }

    public func transferVelocity(_ velocity: CGFloat) {
        guard !velocity.isZero else { return }
        setRawContentOffsetY(scrollNode.view.contentOffset.y - velocity / 60.0, animated: false)
    }

    public func resetScrolledToItem() {
        scrollNode.view.layer.removeAllAnimations()
    }

    @discardableResult
    public func ensureItemNodeVisible(
        _ node: AetherListItemNode,
        animated: Bool,
        overflow: CGFloat = 0.0,
        allowIntersection: Bool = true,
        atTop: Bool = false
    ) -> Bool {
        guard itemNodes.contains(where: { $0 === node }) else { return false }
        let contentOffsetY = AetherListFrameMetrics.sanitizedCoordinate(scrollNode.view.contentOffset.y)
        let contentInset = AetherListFrameMetrics.sanitizedInsets(scrollNode.view.contentInset)
        let viewportTop = contentOffsetY + contentInset.top
        let viewportBottom = contentOffsetY + AetherListFrameMetrics.sanitizedLength(bounds.height) - contentInset.bottom
        let frame = AetherListFrameMetrics.sanitizedRect(node.frame.inset(by: node.scrollPositioningInsets))
        if allowIntersection, frame.maxY > viewportTop, frame.minY < viewportBottom {
            return false
        }
        let targetY: CGFloat
        if atTop {
            targetY = frame.minY - contentInset.top - AetherListFrameMetrics.sanitizedCoordinate(overflow)
        } else {
            targetY = frame.maxY - AetherListFrameMetrics.sanitizedLength(bounds.height) + contentInset.bottom + AetherListFrameMetrics.sanitizedCoordinate(overflow)
        }
        setRawContentOffsetY(targetY, animated: animated)
        return true
    }

    public func setSwipeActionsOpened(_ side: AetherListSwipeActionsSide, at index: Int, animated: Bool) {
        guard index >= 0, index < items.count else { return }
        let actions = items[index].swipeActions.actions(for: side)
        guard !actions.isEmpty else { return }
        let itemId = items[index].stableId
        if revealedSwipeItemId != nil, revealedSwipeItemId != itemId {
            closeSwipeActions(animated: animated)
        }
        let width = swipeRevealWidth(for: actions, at: index)
        let offset = side == .left ? width : -width
        revealedSwipeItemId = itemId
        revealedSwipeOffset = offset
        guard let node = nodeForItem(at: index) else { return }
        updateSwipeRevealOffset(offset, for: node, animated: animated)
    }

    public func closeSwipeActions(animated: Bool) {
        guard let revealedSwipeItemIndex, let node = nodeForItem(at: revealedSwipeItemIndex) else {
            revealedSwipeItemId = nil
            revealedSwipeOffset = 0.0
            return
        }
        updateSwipeRevealOffset(0.0, for: node, animated: animated)
        revealedSwipeItemId = nil
        revealedSwipeOffset = 0.0
    }

    public func selectSwipeAction(_ actionKey: AnyHashable, at index: Int, isFullSwipe: Bool = false) {
        guard index >= 0, index < items.count else { return }
        let actions = items[index].swipeActions.left + items[index].swipeActions.right
        guard let action = actions.first(where: { $0.key == actionKey }) else { return }
        performSwipeAction(action, at: index, isFullSwipe: isFullSwipe)
    }

    public func swipeRevealOffset(at index: Int) -> CGFloat {
        guard index >= 0,
              index < items.count,
              items[index].stableId == revealedSwipeItemId else {
            return 0.0
        }
        return revealedSwipeOffset
    }

    private func executeTransaction(
        deleteIndices: [AetherListDeleteItem],
        moveIndices: [AetherListMoveItem],
        insertIndicesAndItems: [AetherListInsertItem],
        updateIndicesAndItems: [AetherListUpdateItem],
        options: AetherListTransactionOptions,
        updateSizeAndInsets: AetherListUpdateSizeAndInsets?,
        scrollToItem: AetherListScrollToItem?,
        additionalScrollDistance: CGFloat,
        stationaryItemRange: (Int, Int)?
    ) {
        if let updateSizeAndInsets {
            applySizeAndInsetsUpdate(updateSizeAndInsets)
        }

        let beforeIntermediateState = AetherListIntermediateState(
            stableIds: items.map(\.stableId),
            heights: itemHeights,
            itemOffsetInsets: AetherListContentMetricsPlanner.effectiveOffsetInsets(
                itemOffsetInsets: _itemOffsetInsets,
                virtualContentInsets: _virtualContentInsets
            )
        )
        let stationaryAnchor = beforeIntermediateState.stationaryAnchor(in: stationaryItemRange)
        let preFrames = Dictionary(uniqueKeysWithValues: itemNodes.map { (ObjectIdentifier($0), $0.frame) })
        let insertedItemIds = Set(insertIndicesAndItems.map { $0.item.stableId })
        let hasForcedInsertionAnimation = insertIndicesAndItems.contains { $0.forceAnimateInsertion }
        let hasParticleDissolveRemoval = deleteIndices.contains {
            if case .particleDissolve = $0.animation { return true }
            return false
        }
        let replayPlan = AetherListNodeReplayPlan.make(
            options: options,
            hasForcedInsertionAnimation: hasForcedInsertionAnimation,
            hasParticleDissolveRemoval: hasParticleDissolveRemoval,
            baseDuration: transactionAnimationDuration,
            particleDissolveDuration: particleDissolveVisualDuration,
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
        var removingNodes: [TransactionRemovingNode] = []

        for deletion in deleteIndices.sorted(by: { $0.index > $1.index }) {
            guard deletion.index >= 0, deletion.index < items.count else { continue }
            if let node = nodeForItem(at: deletion.index) {
                let item = items[deletion.index]
                item.didEndDisplay(node: node, at: deletion.index)
                if let itemNodeIndex = itemNodes.firstIndex(where: { $0 === node }) {
                    itemNodes.remove(at: itemNodeIndex)
                }
                removeSwipeActionsNode(for: node)
                node.layer.zPosition = 1000.0
                removingNodes.append(TransactionRemovingNode(
                    node: node,
                    reuseIdentifier: item.reuseIdentifier,
                    animation: deletion.animation,
                    hint: deletion.directionHint
                ))
            }
            let item = items.remove(at: deletion.index)
            cancelAsyncLayout(forID: item.stableId)
            removeCachedLayout(forID: item.stableId)
            selectedItemIds.remove(ObjectIdentifier(item))
            itemHeights.remove(at: deletion.index)
            if item.stableId == revealedSwipeItemId {
                revealedSwipeItemId = nil
                revealedSwipeOffset = 0.0
            }
        }

        for move in moveIndices {
            guard move.fromIndex >= 0,
                  move.fromIndex < items.count,
                  move.toIndex >= 0,
                  move.toIndex <= items.count,
                  move.fromIndex != move.toIndex else {
                continue
            }
            let item = items.remove(at: move.fromIndex)
            let height = itemHeights.remove(at: move.fromIndex)
            let target = min(move.toIndex, items.count)
            items.insert(item, at: target)
            itemHeights.insert(height, at: target)
        }

        for insertion in insertIndicesAndItems.sorted(by: { $0.index < $1.index }) {
            let target = min(max(0, insertion.index), items.count)
            items.insert(insertion.item, at: target)
            itemHeights.insert(estimatedHeight(for: insertion.item), at: target)
        }

        for update in updateIndicesAndItems {
            guard update.index >= 0, update.index < items.count, update.index < itemHeights.count else { continue }
            let previousItem = items[update.index]
            if previousItem.stableId != update.item.stableId {
                cancelAsyncLayout(forID: previousItem.stableId)
                removeCachedLayout(forID: previousItem.stableId)
                selectedItemIds.remove(ObjectIdentifier(previousItem))
            }
            items[update.index] = update.item
            if let node = nodeForItem(at: update.previousIndex) ?? nodeForItem(at: update.index) {
                let layout = updateNode(node, with: update.item, at: update.index, animation: .none)
                debugInstrumentation.measureLayoutApplication {
                    node.applyLayout(layout)
                }
                syncAccessories(for: node, item: update.item)
                recordLayout(layout, for: update.item)
                node.index = update.index
                node.item = update.item
                itemHeights[update.index] = layout.totalHeight
            } else {
                itemHeights[update.index] = estimatedHeight(for: update.item)
            }
        }

        rebuildStickyHeaderIndexCache()
        reindexLoadedNodes()
        syncSelectionToNodes(animated: false)
        rebuildOffsets()
        let didApplyScrollBeforeMaterializing: Bool
        if let scrollToItem, !scrollToItem.animated {
            updateContentSize(anchorsBottomIfNeeded: false)
            self.scrollToItem(at: scrollToItem.index, position: scrollToItem.position, animated: false)
            if !additionalScrollDistance.isZero {
                setRawContentOffsetY(scrollNode.view.contentOffset.y + additionalScrollDistance, animated: false)
            }
            didApplyScrollBeforeMaterializing = true
        } else if additionalScrollDistance.isZero,
                  let stationaryAnchor,
                  let stationaryDelta = AetherListIntermediateState(
                    stableIds: items.map(\.stableId),
                    heights: itemHeights,
                    itemOffsetInsets: AetherListContentMetricsPlanner.effectiveOffsetInsets(
                        itemOffsetInsets: _itemOffsetInsets,
                        virtualContentInsets: _virtualContentInsets
                    )
                  ).offsetDelta(preserving: stationaryAnchor),
                  !stationaryDelta.isZero {
            updateContentSize(anchorsBottomIfNeeded: false)
            setRawContentOffsetY(scrollNode.view.contentOffset.y + stationaryDelta, animated: false)
            didApplyScrollBeforeMaterializing = true
        } else {
            didApplyScrollBeforeMaterializing = false
        }
        relayoutContent()
        syncRevealedSwipeStateAfterTransaction()
        var insertDirectionHintByItemId: [AnyHashable: AetherListItemOperationDirectionHint] = [:]
        var forceAnimateInsertionItemIds = Set<AnyHashable>()
        for insertion in insertIndicesAndItems {
            if let directionHint = insertion.directionHint {
                insertDirectionHintByItemId[insertion.item.stableId] = directionHint
            }
            if insertion.forceAnimateInsertion {
                forceAnimateInsertionItemIds.insert(insertion.item.stableId)
            }
        }
        replayTransactionAnimations(
            replayPlan: replayPlan,
            preFrames: preFrames,
            insertedItemIds: insertedItemIds,
            removingNodes: removingNodes,
            options: options,
            insertDirectionHintByItemId: insertDirectionHintByItemId,
            forceAnimateInsertionItemIds: forceAnimateInsertionItemIds
        )

        if let scrollToItem, !didApplyScrollBeforeMaterializing {
            self.scrollToItem(at: scrollToItem.index, position: scrollToItem.position, animated: scrollToItem.animated)
            if !additionalScrollDistance.isZero {
                setRawContentOffsetY(scrollNode.view.contentOffset.y + additionalScrollDistance, animated: scrollToItem.animated)
            }
        }
    }

    private func replayTransactionAnimations(
        replayPlan: AetherListNodeReplayPlan,
        preFrames: [ObjectIdentifier: CGRect],
        insertedItemIds: Set<AnyHashable>,
        removingNodes: [TransactionRemovingNode],
        options: AetherListTransactionOptions,
        insertDirectionHintByItemId: [AnyHashable: AetherListItemOperationDirectionHint],
        forceAnimateInsertionItemIds: Set<AnyHashable>
    ) {
        let insertedNodes = itemNodes.filter { node in
            guard let item = node.item else { return false }
            return insertedItemIds.contains(item.stableId)
        }
        let insertedNodeIds = Set(insertedNodes.map { ObjectIdentifier($0) })

        if case let .animated(duration, curve) = replayPlan.survivingFrameAnimation {
            for node in itemNodes {
                let nodeId = ObjectIdentifier(node)
                guard !insertedNodeIds.contains(nodeId),
                      let previousFrame = preFrames[nodeId] else {
                    continue
                }
                let targetFrame = node.frame
                guard previousFrame != targetFrame else { continue }
                setFrame(previousFrame, for: node)
                UIView.animate(
                    withDuration: duration,
                    delay: 0.0,
                    options: frameAnimationOptions(for: curve),
                    animations: {
                        self.setFrame(targetFrame, for: node)
                    },
                    completion: nil
                )
            }
        }

        for node in insertedNodes {
            guard let item = node.item else { continue }
            let animation = replayPlan.insertionAnimation(
                isNewNode: true,
                forceItemAnimation: forceAnimateInsertionItemIds.contains(item.stableId),
                directionHint: insertDirectionHintByItemId[item.stableId],
                invertOffsetDirection: options.contains(.invertOffsetDirection)
            )
            switch animation {
            case .none:
                break
            case let .alphaFade(duration):
                node.alpha = 0.0
                UIView.animate(
                    withDuration: duration,
                    delay: 0.0,
                    options: [.beginFromCurrentState, .allowUserInteraction],
                    animations: { node.alpha = 1.0 },
                    completion: nil
                )
            case let .item(duration, directionHint, invertOffsetDirection):
                node.animateInsertion(
                    duration: duration,
                    directionHint: directionHint,
                    invertOffsetDirection: invertOffsetDirection
                )
            }
        }

        for removingNode in removingNodes {
            guard let animation = replayPlan.deletionAnimation(for: removingNode.animation) else {
                recycleDetachedNode(removingNode.node, reuseIdentifier: removingNode.reuseIdentifier)
                continue
            }
            runDeleteAnimation(animation, on: removingNode.node, hint: removingNode.hint) { [weak self, weak node = removingNode.node] in
                guard let self, let node else { return }
                self.recycleDetachedNode(node, reuseIdentifier: removingNode.reuseIdentifier)
            }
        }
    }

    private func frameAnimationOptions(for curve: AetherListNodeFrameReplayCurve) -> UIView.AnimationOptions {
        switch curve {
        case .standard:
            return [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        case .easeOut:
            return [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        }
    }

    private func runDeleteAnimation(
        _ animation: AetherListItemDeleteAnimation,
        on node: AetherListItemNode,
        hint: AetherListItemOperationDirectionHint?,
        completion: @escaping () -> Void
    ) {
        switch animation {
        case .fade:
            UIView.animate(
                withDuration: transactionAnimationDuration,
                delay: 0.0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: { node.alpha = 0.0 },
                completion: { _ in completion() }
            )
        case .slide(let direction):
            let dx: CGFloat = direction == .up ? -bounds.width : bounds.width
            UIView.animate(
                withDuration: transactionAnimationDuration,
                delay: 0.0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                animations: {
                    node.view.transform = CGAffineTransform(translationX: dx, y: 0.0)
                    node.alpha = 0.0
                },
                completion: { _ in completion() }
            )
        case .scale:
            let resolvedHint = hint ?? .down
            let translateY: CGFloat = resolvedHint == .up ? -node.frame.height * 0.3 : node.frame.height * 0.3
            UIView.animate(
                withDuration: transactionAnimationDuration,
                delay: 0.0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0.2,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    node.view.transform = CGAffineTransform(translationX: 0.0, y: translateY).scaledBy(x: 0.6, y: 0.6)
                    node.alpha = 0.0
                },
                completion: { _ in completion() }
            )
        case .particleDissolve(let tileSize):
            runParticleDissolve(on: node, tileSize: tileSize, completion: completion)
        }
    }

    private func runParticleDissolve(
        on node: AetherListItemNode,
        tileSize: CGFloat,
        completion: @escaping () -> Void
    ) {
        let target = node.particleDissolveTargetView
        let targetBounds = target.bounds
        guard targetBounds.width > 1.0, targetBounds.height > 1.0 else {
            UIView.animate(withDuration: transactionAnimationDuration, animations: {
                node.alpha = 0.0
            }, completion: { _ in completion() })
            return
        }

        let dustView = ensureDustEffectView()
        guard dustView.isReady else {
            UIView.animate(withDuration: transactionAnimationDuration, animations: {
                node.alpha = 0.0
            }, completion: { _ in completion() })
            return
        }

        let savedAlpha = target.alpha
        target.alpha = 1.0
        let snapshot = AetherDustEffectView.snapshot(of: target)
        target.alpha = savedAlpha

        guard let snapshot else {
            UIView.animate(withDuration: transactionAnimationDuration, animations: {
                node.alpha = 0.0
            }, completion: { _ in completion() })
            return
        }

        let frameInOverlay = target.convert(target.bounds, to: dustView)
        dustView.animationSpeed = particleDissolveDustAnimationSpeed
        dustView.addItem(frame: frameInOverlay, image: snapshot, tileSize: tileSize)
        UIView.animate(
            withDuration: particleDissolveVisualDuration,
            delay: 0.0,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: { node.alpha = 0.0 },
            completion: nil
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + particleDissolveVisualDuration) {
            completion()
        }
    }

    private func ensureDustEffectView() -> AetherDustEffectView {
        let dustView: AetherDustEffectView
        if let existing = self.dustEffectView {
            dustView = existing
        } else {
            let created = AetherDustEffectView(frame: .zero)
            created.isUserInteractionEnabled = false
            created.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.dustEffectView = created
            dustView = created
        }

        let host = _particleDissolveOverlayHostView ?? _particleDissolveOverlayHostNode?.view ?? view
        if dustView.superview !== host {
            dustView.removeFromSuperview()
            host.addSubview(dustView)
        }
        dustView.frame = host.bounds
        host.bringSubviewToFront(dustView)
        let scale = dustView.metalLayer.contentsScale
        let pixelSize = CGSize(
            width: max(1.0, host.bounds.width * scale),
            height: max(1.0, host.bounds.height * scale)
        )
        if dustView.metalLayer.drawableSize != pixelSize {
            dustView.metalLayer.drawableSize = pixelSize
        }
        return dustView
    }

    private func recycleDetachedNode(_ node: AetherListItemNode, reuseIdentifier: String?) {
        removeSwipeActionsNode(for: node)
        node.prepareForReuse()
        node.removeFromSupernode()
        node.index = nil
        node.item = nil
        node.pendingSelectionAnimated = false
        node.isSelected = false
        node.alpha = 1.0
        node.view.transform = .identity
        node.updateStickyHeaderState(.none, animated: false)
        node.layer.removeAllAnimations()
        node.layer.zPosition = 0.0
        node.isHidden = false

        guard let reuseIdentifier else { return }
        var bucket = reusePool[reuseIdentifier] ?? []
        if bucket.count < maxReusableNodesPerIdentifier {
            bucket.append(node)
            reusePool[reuseIdentifier] = bucket
            debugInstrumentation.recordRecycledView()
        }
    }

    private func createNode(for item: AetherListItem, at index: Int, params: AetherListItemLayoutParams) -> (node: AetherListItemNode, layout: AetherListItemNodeLayout) {
        let previous = index > 0 && index - 1 < items.count ? items[index - 1] : nil
        let next = index + 1 < items.count ? items[index + 1] : nil
        let created = debugInstrumentation.measureNodeCreate {
            item.createNode(params: params, previousItem: previous, nextItem: next)
        }
        return (created.0, created.1)
    }

    private func updateNode(
        _ node: AetherListItemNode,
        with item: AetherListItem,
        at index: Int,
        animation: AetherListItemUpdateAnimation
    ) -> AetherListItemNodeLayout {
        let params = layoutParams()
        let previous = index > 0 && index - 1 < items.count ? items[index - 1] : nil
        let next = index + 1 < items.count ? items[index + 1] : nil
        let layout = debugInstrumentation.measureNodeUpdate {
            item.updateNode(node, params: params, previousItem: previous, nextItem: next, animation: animation)
        }
        return layout
    }

    private func syncAccessories(for node: AetherListItemNode, item: AetherListItem) {
        node.setAccessoryItem(item.accessoryItem as? AetherListAccessoryItem, placement: .accessory)
        node.setAccessoryItem(item.headerAccessoryItem as? AetherListAccessoryItem, placement: .headerAccessory)
    }

    private func applySizeAndInsetsUpdate(_ update: AetherListUpdateSizeAndInsets) {
        let sanitizedSize = AetherListFrameMetrics.sanitizedSize(update.size)
        if bounds.size != sanitizedSize {
            frame = CGRect(
                origin: AetherListFrameMetrics.sanitizedPoint(frame.origin),
                size: sanitizedSize
            )
            scrollNode.frame = AetherListFrameMetrics.sanitizedRect(bounds)
        }
        _insets = AetherListFrameMetrics.sanitizedInsets(update.insets)
        _headerInsets = update.headerInsets.map(AetherListFrameMetrics.sanitizedInsets)
        scrollIndicatorInsets = update.scrollIndicatorInsets
        _itemOffsetInsets = update.itemOffsetInsets.map(AetherListFrameMetrics.sanitizedInsets)
        if let virtualContentInsets = update.virtualContentInsets {
            _virtualContentInsets = virtualContentInsets
        }
        _ = applyScrollInsets()
    }

    private func reindexLoadedNodes() {
        var nodesToRecycle: [AetherListItemNode] = []
        for node in itemNodes {
            guard let item = node.item,
                  let index = items.firstIndex(where: { $0.stableId == item.stableId }) else {
                nodesToRecycle.append(node)
                continue
            }
            node.index = index
            node.item = items[index]
        }
        for node in nodesToRecycle {
            recycleNode(node)
        }
        itemNodes.sort { ($0.index ?? 0) < ($1.index ?? 0) }
    }

    private func rebuildOffsets() {
        let metrics = AetherListContentMetricsPlanner.metrics(
            itemHeights: itemHeights,
            itemOffsetInsets: _itemOffsetInsets,
            virtualContentInsets: _virtualContentInsets
        )
        itemOffsets = metrics.itemOffsets
        totalContentHeight = metrics.totalContentHeight
    }

    private func relayoutContent() {
        let shouldAnchorBottom = shouldPreserveBottomAnchor()
        rebuildOffsets()
        _ = applyScrollInsets(adjustsContentOffsetForTopInsetChange: !stackFromBottom)
        updateContentSize(anchorsBottomIfNeeded: shouldAnchorBottom)
        updateVisibleNodes()
        positionLoadedNodes()
        applyStickyHeaderLayout()
        applyVisibilityLifecycle()
        debugInstrumentation.recordVisibleViews(itemNodes.count)
    }

    private func updateVisibleNodes() {
        guard !items.isEmpty else {
            recycleAllLoadedNodes()
            return
        }
        guard bounds.width > 0.0, bounds.height > 0.0 else {
            debugInstrumentation.recordVisibleViews(itemNodes.count)
            return
        }

        var visibleRange = computeLoadedRange()
        while true {
            var didChangeHeights = false
            var didMutateNodes = false
            var pinnedIndices = currentStickyHeaderIndices()
            let commands = makeVirtualizationCommands(
                visibleRange: visibleRange,
                pinnedIndices: pinnedIndices
            )
            for command in commands {
                switch command {
                case let .recycle(nodeId, _):
                    guard let node = node(with: nodeId) else { continue }
                    recycleNode(node)
                    didMutateNodes = true
                case let .mount(index):
                    if let result = mountNode(at: index, params: layoutParams()) {
                        didChangeHeights = didChangeHeights || result.didChangeHeight
                        didMutateNodes = true
                    }
                case .setFrame:
                    break
                }
            }

            if didMutateNodes {
                itemNodes.sort { ($0.index ?? 0) < ($1.index ?? 0) }
            }

            if didChangeHeights {
                rebuildOffsets()
                updateContentSize()
                let correctedVisibleRange = computeLoadedRange()
                if correctedVisibleRange != visibleRange {
                    visibleRange = correctedVisibleRange
                    continue
                }
                pinnedIndices = currentStickyHeaderIndices()
            }

            for command in makeVirtualizationCommands(
                visibleRange: visibleRange,
                pinnedIndices: pinnedIndices
            ) {
                if case let .setFrame(nodeId, _, frame) = command,
                   let node = node(with: nodeId) {
                    if let reorderState, reorderState.draggingNode === node {
                        continue
                    }
                    setFrame(frame, for: node)
                }
            }
            break
        }

        applyStickyHeaderLayout()
        prefetchAsyncLayouts(in: computeLoadedRange(), params: layoutParams())
        debugInstrumentation.recordVisibleViews(itemNodes.count)
    }

    private func makeVirtualizationCommands(
        visibleRange: Range<Int>,
        pinnedIndices: Set<Int>
    ) -> [AetherListVirtualizationCommand<ObjectIdentifier>] {
        AetherListVirtualizationCommandPlanner.commands(
            visibleRange: visibleRange,
            pinnedIndices: pinnedIndices,
            loadedNodes: itemNodes.map {
                AetherListVirtualizationLoadedNode(
                    nodeId: ObjectIdentifier($0),
                    index: $0.index,
                    isProtected: reorderState?.draggingNode === $0
                )
            },
            itemOffsets: itemOffsets,
            itemHeights: itemHeights,
            boundsWidth: bounds.width,
            displayScale: UIScreen.main.scale
        )
    }

    private func stickyHeaderAffinity(for item: AetherListItem) -> AetherListHeaderAffinity {
        let affinity = item.headerAffinity
        if affinity != .none {
            return affinity
        }
        return item.isFloatingHeader ? .top : .none
    }

    private func rebuildStickyHeaderIndexCache() {
        stickyHeaderItemIndices = items.indices.filter {
            stickyHeaderAffinity(for: items[$0]) != .none
        }
    }

    private func stickyHeaderViewportEdges() -> (top: CGFloat, bottom: CGFloat) {
        let edgeInsets = _headerInsets ?? _insets
        return (
            top: scrollNode.view.contentOffset.y + edgeInsets.top,
            bottom: scrollNode.view.contentOffset.y + bounds.height - edgeInsets.bottom
        )
    }

    private func makeStickyHeaderDescriptors() -> [AetherListStickyHeaderDescriptor<ObjectIdentifier>] {
        guard !items.isEmpty, !itemOffsets.isEmpty else { return [] }

        var nodeIdByIndex: [Int: ObjectIdentifier] = [:]
        for node in itemNodes {
            if let index = node.index {
                nodeIdByIndex[index] = ObjectIdentifier(node)
            }
        }

        return stickyHeaderItemIndices.compactMap { index in
            guard index < items.count,
                  index < itemOffsets.count,
                  index < itemHeights.count else {
                return nil
            }
            let item = items[index]
            let affinity = stickyHeaderAffinity(for: item)
            guard affinity != .none else { return nil }
            return AetherListStickyHeaderDescriptor(
                index: index,
                affinity: affinity,
                naturalY: itemOffsets[index],
                height: itemHeights[index],
                nodeId: nodeIdByIndex[index]
            )
        }
    }

    private func currentStickyHeaderIndices() -> Set<Int> {
        let viewport = stickyHeaderViewportEdges()
        return AetherListStickyHeaderCommandPlanner.pinnedIndices(
            descriptors: makeStickyHeaderDescriptors(),
            viewportTop: viewport.top,
            viewportBottom: viewport.bottom
        )
    }

    private func makeStickyHeaderCommands() -> [AetherListStickyHeaderCommand<ObjectIdentifier>] {
        let viewport = stickyHeaderViewportEdges()
        return AetherListStickyHeaderCommandPlanner.commands(
            descriptors: makeStickyHeaderDescriptors(),
            viewportTop: viewport.top,
            viewportBottom: viewport.bottom,
            boundsWidth: bounds.width,
            displayScale: UIScreen.main.scale
        )
    }

    private func applyStickyHeaderLayout() {
        guard !items.isEmpty, !itemOffsets.isEmpty else { return }

        var didMountNodes = false
        var didChangeHeights = false
        var commands = makeStickyHeaderCommands()
        for command in commands {
            guard case let .ensureNode(index) = command else { continue }
            if let result = mountNode(at: index, params: layoutParams()) {
                didMountNodes = true
                didChangeHeights = didChangeHeights || result.didChangeHeight
            }
        }

        if didMountNodes {
            itemNodes.sort { ($0.index ?? 0) < ($1.index ?? 0) }
        }
        if didChangeHeights {
            rebuildOffsets()
            updateContentSize()
        }

        if didMountNodes || didChangeHeights {
            commands = makeStickyHeaderCommands()
        }
        for command in commands {
            guard case let .applyLayout(nodeId, _, frame, state, zPosition, bringToFront) = command,
                  let node = node(with: nodeId) else {
                continue
            }
            setFrame(frame, for: node)
            node.updateStickyHeaderState(state, animated: false)
            node.layer.zPosition = zPosition
            if bringToFront {
                node.view.superview?.bringSubviewToFront(node.view)
            }
        }
    }

    private func computeLoadedRange() -> Range<Int> {
        guard !items.isEmpty else { return 0..<0 }
        return AetherListFrameMetrics.visibleRange(
            offsets: itemOffsets,
            heights: itemHeights,
            viewportTop: AetherListFrameMetrics.sanitizedCoordinate(scrollNode.view.contentOffset.y),
            viewportHeight: AetherListFrameMetrics.sanitizedLength(bounds.height),
            preloadPages: AetherListFrameMetrics.sanitizedLength(nodePreloadPages ?? preloadPages)
        )
    }

    private func updateContentSize(anchorsBottomIfNeeded: Bool? = nil) {
        let shouldAnchorBottom = anchorsBottomIfNeeded ?? shouldPreserveBottomAnchor()
        _ = applyScrollInsets(adjustsContentOffsetForTopInsetChange: !stackFromBottom)
        let contentHeight = AetherListFrameMetrics.sanitizedLength(resolvedContentHeight())
        let width = AetherListFrameMetrics.sanitizedLength(bounds.width)
        contentNode.frame = CGRect(x: 0.0, y: 0.0, width: width, height: contentHeight)
        scrollNode.view.contentSize = CGSize(width: width, height: contentHeight)
        let visibleContentHeight = max(
            0.0,
            bounds.height - scrollNode.view.contentInset.top - scrollNode.view.contentInset.bottom
        )
        let shouldStackShortContentFromBottom = stackFromBottom
            && contentHeight <= visibleContentHeight + 0.5
        if shouldAnchorBottom || shouldStackShortContentFromBottom {
            scrollToBottom(animated: false)
        }
    }

    private struct NodeMountResult {
        let node: AetherListItemNode
        let didChangeHeight: Bool
    }

    @discardableResult
    private func mountNode(at index: Int, params: AetherListItemLayoutParams) -> NodeMountResult? {
        guard index >= 0, index < items.count, index < itemHeights.count else {
            return nil
        }

        let item = items[index]
        let node: AetherListItemNode
        let layout: AetherListItemNodeLayout
        if let reused = dequeueReusableNode(for: item) {
            node = reused
            let fallbackLayout = updateNode(reused, with: item, at: index, animation: .none)
            layout = resolvedLayout(for: item, node: reused, fallback: fallbackLayout)
        } else {
            let created = createNode(for: item, at: index, params: params)
            node = created.node
            layout = resolvedLayout(for: item, node: created.node, fallback: created.layout)
        }

        debugInstrumentation.measureLayoutApplication {
            node.applyLayout(layout)
        }
        syncAccessories(for: node, item: item)
        recordLayout(layout, for: item)
        applySelection(to: node, item: item, animated: false)

        let didChangeHeight = abs(itemHeights[index] - layout.totalHeight) > 0.5
        itemHeights[index] = layout.totalHeight
        node.index = index
        node.item = item

        if !itemNodes.contains(where: { $0 === node }) {
            itemNodes.append(node)
        }
        if node.supernode !== contentNode {
            contentNode.addSubnode(node)
        }
        if item.stableId == revealedSwipeItemId, !revealedSwipeOffset.isZero {
            node.view.transform = CGAffineTransform(translationX: revealedSwipeOffset, y: 0.0)
            node.setSwipeRevealBackgroundActive(true, transition: .immediate)
            ensureSwipeActionsNode(for: node, item: item).updateRevealOffset(revealedSwipeOffset, transition: .immediate)
        }
        item.willDisplay(node: node, at: index)

        return NodeMountResult(node: node, didChangeHeight: didChangeHeight)
    }

    private func dequeueReusableNode(for item: AetherListItem) -> AetherListItemNode? {
        let key = item.reuseIdentifier
        guard var bucket = reusePool[key], !bucket.isEmpty else { return nil }
        let node = bucket.removeLast()
        reusePool[key] = bucket
        node.alpha = 1.0
        node.view.transform = .identity
        node.updateStickyHeaderState(.none, animated: false)
        node.layer.removeAllAnimations()
        node.layer.zPosition = 0.0
        node.isHidden = false
        debugInstrumentation.recordReusedView()
        return node
    }

    private func recycleLoadedNode(at index: Int) {
        guard let node = nodeForItem(at: index) else { return }
        recycleNode(node)
    }

    private func recycleAllLoadedNodes() {
        for node in itemNodes {
            recycleNode(node)
        }
    }

    private func recycleNode(_ node: AetherListItemNode) {
        guard let itemIndex = itemNodes.firstIndex(where: { $0 === node }) else { return }
        itemNodes.remove(at: itemIndex)
        if let item = node.item, let index = node.index {
            item.didEndDisplay(node: node, at: index)
            if item.stableId == revealedSwipeItemId {
                revealedSwipeItemId = nil
                revealedSwipeOffset = 0.0
            }
        }
        let reuseIdentifier = node.item?.reuseIdentifier
        node.prepareForReuse()
        node.removeFromSupernode()
        node.index = nil
        node.item = nil
        node.pendingSelectionAnimated = false
        node.isSelected = false
        node.alpha = 1.0
        node.view.transform = .identity
        node.updateStickyHeaderState(.none, animated: false)
        node.layer.removeAllAnimations()
        node.layer.zPosition = 0.0
        node.isHidden = false
        removeSwipeActionsNode(for: node)

        guard let reuseIdentifier else { return }
        var bucket = reusePool[reuseIdentifier] ?? []
        if bucket.count < maxReusableNodesPerIdentifier {
            bucket.append(node)
            reusePool[reuseIdentifier] = bucket
            debugInstrumentation.recordRecycledView()
        }
    }

    private func node(with id: ObjectIdentifier) -> AetherListItemNode? {
        itemNodes.first { ObjectIdentifier($0) == id }
    }

    private func positionLoadedNodes() {
        for node in itemNodes {
            if let reorderState, reorderState.draggingNode === node {
                continue
            }
            guard let index = node.index,
                  index >= 0,
                  index < itemOffsets.count,
                  index < itemHeights.count else {
                continue
            }
            setFrame(
                CGRect(x: 0.0, y: itemOffsets[index], width: bounds.width, height: itemHeights[index]),
                for: node
            )
            syncSwipeActionsNodeFrame(for: node)
        }
    }

    private func relayoutLoadedNodes(params: AetherListItemLayoutParams) {
        guard !itemNodes.isEmpty else { return }
        for node in itemNodes {
            guard let index = node.index,
                  index >= 0,
                  index < items.count,
                  index < itemHeights.count else {
                continue
            }
            let item = items[index]
            let fallbackLayout = updateNode(node, with: item, at: index, animation: .none)
            let layout = resolvedLayout(for: item, node: node, fallback: fallbackLayout)
            debugInstrumentation.measureLayoutApplication {
                node.applyLayout(layout)
            }
            syncAccessories(for: node, item: item)
            recordLayout(layout, for: item)
            itemHeights[index] = layout.totalHeight
        }
        rebuildOffsets()
    }

    private func setFrame(_ frame: CGRect, for node: AetherListItemNode) {
        let sanitizedFrame = AetherListFrameMetrics.sanitizedRect(frame)
        node.frame = sanitizedFrame
        node.updateAbsoluteRect(sanitizedFrame, within: AetherListFrameMetrics.sanitizedSize(bounds.size))
        syncSwipeActionsNodeFrame(for: node)
    }

    func itemNodeForListGesture(
        at point: CGPoint,
        gesture: AetherListItemGesture,
        consultExternalGate: Bool = true
    ) -> AetherListItemNode? {
        for node in itemNodesForListGestureHitTesting() {
            guard node.view.superview != nil,
                  !node.isHidden,
                  node.alpha > 0.01,
                  let index = node.index,
                  index >= 0,
                  index < items.count else {
                continue
            }

            let hitFrame = node.frame.inset(by: node.listGestureHitTestInsets(for: gesture))
            guard hitFrame.contains(point) else {
                continue
            }

            let pointInNode = node.view.convert(point, from: contentNode.view)
            guard node.allowsListGesture(gesture, at: pointInNode) else {
                continue
            }

            if gesture == .reorder {
                guard allowsReorder, items[index].canReorder else {
                    continue
                }
            }

            if gesture == .swipe {
                guard !items[index].swipeActions.isEmpty else {
                    continue
                }
            }

            if consultExternalGate,
               let itemGestureShouldBegin,
               !itemGestureShouldBegin(gesture, index, node, pointInNode) {
                continue
            }

            return node
        }
        return nil
    }

    private func itemNodesForListGestureHitTesting() -> [AetherListItemNode] {
        itemNodes.sorted { lhs, rhs in
            let lhsZ = lhs.layer.zPosition
            let rhsZ = rhs.layer.zPosition
            if abs(lhsZ - rhsZ) > CGFloat.ulpOfOne {
                return lhsZ > rhsZ
            }
            return (lhs.index ?? Int.min) > (rhs.index ?? Int.min)
        }
    }

    private func setupSwipeRecognizer() {
        guard swipeRecognizer == nil else { return }
        let panGesture = AetherListSwipeGestureRecognizer(target: self, action: #selector(handleSwipeGesture(_:)))
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = delegateProxy
        contentNode.view.addGestureRecognizer(panGesture)
        swipeRecognizer = panGesture
    }

    private func setupReorderRecognizer() {
        guard reorderRecognizer == nil else { return }
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleReorderGesture(_:)))
        longPressGesture.minimumPressDuration = 0.4
        longPressGesture.cancelsTouchesInView = false
        longPressGesture.isEnabled = allowsReorder
        longPressGesture.delegate = delegateProxy
        contentNode.view.addGestureRecognizer(longPressGesture)
        reorderRecognizer = longPressGesture
    }

    private func setupTapRecognizer() {
        guard tapRecognizer == nil else { return }
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = delegateProxy
        if let swipeRecognizer {
            tapGesture.require(toFail: swipeRecognizer)
        }
        if let reorderRecognizer {
            tapGesture.require(toFail: reorderRecognizer)
        }
        contentNode.view.addGestureRecognizer(tapGesture)
        tapRecognizer = tapGesture
    }

    @objc private func handleSwipeGesture(_ recognizer: AetherListSwipeGestureRecognizer) {
        let location = recognizer.location(in: contentNode.view)
        switch recognizer.state {
        case .began:
            swipeBegan(at: location, recognizer: recognizer)
        case .changed:
            swipeChanged(recognizer: recognizer)
        case .ended:
            swipeEnded(recognizer: recognizer)
        case .cancelled, .failed:
            swipeCancelled()
        default:
            break
        }
    }

    private func swipeBegan(at location: CGPoint, recognizer: AetherListSwipeGestureRecognizer) {
        guard reorderState == nil,
              let node = itemNodeForListGesture(at: location, gesture: .swipe),
              let index = node.index,
              index >= 0,
              index < items.count,
              !items[index].swipeActions.isEmpty else {
            recognizer.becomeCancelled()
            return
        }

        let item = items[index]
        if revealedSwipeItemId != nil, revealedSwipeItemId != item.stableId {
            closeSwipeActions(animated: true)
        }
        swipeState = SwipeState(
            itemId: item.stableId,
            node: node,
            initialRevealOffset: swipeRevealOffset(at: index),
            didNotifyOpen: !swipeRevealOffset(at: index).isZero
        )
    }

    private func swipeChanged(recognizer: AetherListSwipeGestureRecognizer) {
        guard var state = swipeState,
              let node = state.node,
              let index = node.index,
              index >= 0,
              index < items.count,
              items[index].stableId == state.itemId else {
            return
        }

        let actions = items[index].swipeActions
        var offset = recognizer.translation(in: contentNode.view).x + state.initialRevealOffset
        if actions.left.isEmpty {
            offset = min(0.0, offset)
        }
        if actions.right.isEmpty {
            offset = max(0.0, offset)
        }
        if offset > 0.0 {
            offset = aetherListBoundedSwipeOffset(
                offset,
                revealWidth: swipeRevealWidth(for: actions.left, at: index),
                viewportWidth: node.bounds.width
            )
        } else if offset < 0.0 {
            offset = aetherListBoundedSwipeOffset(
                offset,
                revealWidth: swipeRevealWidth(for: actions.right, at: index),
                viewportWidth: node.bounds.width
            )
        }

        updateSwipeRevealOffset(offset, for: node, animated: false)
        if !offset.isZero, !state.didNotifyOpen {
            state.didNotifyOpen = true
            swipeActionsInteractivelyOpened?(index)
        }
        swipeState = state
    }

    private func swipeEnded(recognizer: AetherListSwipeGestureRecognizer) {
        guard let state = swipeState,
              let node = state.node,
              let index = node.index,
              index >= 0,
              index < items.count,
              items[index].stableId == state.itemId else {
            swipeState = nil
            return
        }

        let offset = swipeRevealOffset(at: index)
        let velocityX = recognizer.velocity(in: contentNode.view).x
        let side: AetherListSwipeActionsSide = offset >= 0.0 ? .left : .right
        finishSwipe(side: side, offset: offset, velocityX: velocityX, state: state, node: node)
        swipeState = nil
    }

    private func finishSwipe(
        side: AetherListSwipeActionsSide,
        offset: CGFloat,
        velocityX: CGFloat,
        state: SwipeState,
        node: AetherListItemNode
    ) {
        guard let index = node.index,
              index >= 0,
              index < items.count else {
            return
        }
        let actions = items[index].swipeActions.actions(for: side)
        let revealWidth = swipeRevealWidth(for: actions, at: index)
        guard revealWidth > 0.0 else {
            updateSwipeRevealOffset(0.0, for: node, animated: true)
            swipeActionsInteractivelyClosed?(index)
            return
        }

        let shouldReveal: Bool
        if abs(velocityX) < 100.0 {
            switch side {
            case .left:
                shouldReveal = state.initialRevealOffset.isZero ? offset > revealWidth * 0.5 : offset > revealWidth
            case .right:
                shouldReveal = state.initialRevealOffset.isZero ? offset < -revealWidth * 0.5 : offset < -revealWidth
            }
        } else {
            switch side {
            case .left:
                shouldReveal = velocityX > 0.0
            case .right:
                shouldReveal = velocityX < 0.0
            }
        }

        let fullSwipeDistance = revealWidth + min(max(48.0, revealWidth * 0.35), node.bounds.width * 0.32)
        if shouldReveal,
           abs(offset) >= fullSwipeDistance,
           let expandedAction = expandedSwipeAction(for: side, actions: actions) {
            performSwipeActionHaptic()
            updateSwipeRevealOffset(0.0, for: node, animated: true)
            performSwipeAction(expandedAction, at: index, isFullSwipe: true)
            return
        }

        let targetOffset: CGFloat = shouldReveal ? (side == .left ? revealWidth : -revealWidth) : 0.0
        updateSwipeRevealOffset(targetOffset, for: node, animated: true)
        if !shouldReveal {
            swipeActionsInteractivelyClosed?(index)
        }
    }

    private func swipeCancelled() {
        guard let state = swipeState,
              let node = state.node else {
            swipeState = nil
            return
        }
        updateSwipeRevealOffset(state.initialRevealOffset, for: node, animated: true)
        swipeState = nil
    }

    @objc private func handleReorderGesture(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: contentNode.view)
        switch recognizer.state {
        case .began:
            reorderBegan(at: location)
        case .changed:
            reorderChanged(to: location)
        case .ended, .cancelled, .failed:
            reorderEnded()
        default:
            break
        }
    }

    private func reorderBegan(at location: CGPoint) {
        guard allowsReorder,
              reorderState == nil else {
            return
        }
        if revealedSwipeItemId != nil {
            closeSwipeActions(animated: true)
            return
        }
        guard let node = itemNodeForListGesture(at: location, gesture: .reorder),
              let index = node.index,
              index >= 0,
              index < items.count,
              items[index].canReorder else {
            return
        }

        willBeginReorder?(index)
        let touchOffsetY = location.y - node.frame.minY
        let originalAlpha = node.alpha
        node.layer.zPosition = 2000
        node.alpha = 0.96
        node.view.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
        reorderState = ReorderState(
            originalIndex: index,
            currentIndex: index,
            touchOffsetY: touchOffsetY,
            draggingNode: node,
            originalAlpha: originalAlpha,
            dragHeight: node.frame.height
        )
        reorderHapticFeedback?()
        reorderDidBegin?(index)
    }

    private func reorderChanged(to location: CGPoint) {
        guard var state = reorderState else { return }

        let dragHeight = state.dragHeight
        let maxY = max(0.0, scrollNode.view.contentSize.height - dragHeight)
        let targetY = max(0.0, min(maxY, location.y - state.touchOffsetY))
        setFrame(
            CGRect(x: 0.0, y: targetY, width: bounds.width, height: dragHeight),
            for: state.draggingNode
        )
        autoScrollForReorderIfNeeded(visibleY: location.y - scrollNode.view.contentOffset.y)

        let centerY = targetY + dragHeight / 2.0
        guard let proposedIndex = indexForReorderInsertion(centerY: centerY),
              proposedIndex != state.currentIndex else {
            reorderState = state
            return
        }

        let allowed = (canMoveItem?(state.currentIndex, proposedIndex) ?? true)
            && items[proposedIndex].canReorder
        guard allowed else {
            reorderState = state
            return
        }

        moveReorderItem(from: state.currentIndex, to: proposedIndex)
        animateLoadedNodesToCurrentLayout(excluding: state.draggingNode)
        reorderItem?(state.currentIndex, proposedIndex)
        reorderHapticFeedback?()
        state.currentIndex = proposedIndex
        reorderState = state
    }

    private func reorderEnded() {
        guard let state = reorderState else { return }
        if state.originalIndex != state.currentIndex, let validateReorder {
            validateReorder(state.originalIndex, state.currentIndex) { [weak self] accepted in
                DispatchQueue.main.async {
                    self?.finishReorder(state: state, accepted: accepted)
                }
            }
        } else {
            if state.originalIndex != state.currentIndex {
                didMoveItem?(state.originalIndex, state.currentIndex)
            }
            reorderCompleted?(state.originalIndex, state.currentIndex, true)
            finishReorderVisuals(state)
        }
    }

    private func finishReorder(state: ReorderState, accepted: Bool) {
        if accepted {
            didMoveItem?(state.originalIndex, state.currentIndex)
            reorderCompleted?(state.originalIndex, state.currentIndex, true)
        } else {
            rollbackReorder(state)
            reorderCompleted?(state.originalIndex, state.currentIndex, false)
        }
        finishReorderVisuals(state)
    }

    private func finishReorderVisuals(_ state: ReorderState) {
        reorderState = nil
        state.draggingNode.alpha = state.originalAlpha
        state.draggingNode.view.transform = .identity
        state.draggingNode.layer.zPosition = 0.0
        reindexLoadedNodesByItemIdentity()
        positionLoadedNodes()
        applyStickyHeaderLayout()
        applyVisibilityLifecycle()
    }

    private func rollbackReorder(_ state: ReorderState) {
        guard let item = state.draggingNode.item,
              let currentIndex = items.firstIndex(where: { $0 === item }),
              currentIndex < itemHeights.count else {
            return
        }
        let movedItem = items.remove(at: currentIndex)
        let movedHeight = itemHeights.remove(at: currentIndex)
        let targetIndex = min(state.originalIndex, items.count)
        items.insert(movedItem, at: targetIndex)
        itemHeights.insert(movedHeight, at: targetIndex)
        rebuildStickyHeaderIndexCache()
        rebuildOffsets()
        reindexLoadedNodesByItemIdentity()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        performTap(at: gesture.location(in: contentNode.view))
    }

    func performTap(at point: CGPoint) {
        if revealedSwipeItemId != nil {
            let closedIndex = revealedSwipeItemIndex
            closeSwipeActions(animated: true)
            swipeActionsInteractivelyClosed?(closedIndex)
            return
        }
        guard !isTapSelectionSuppressedByScrollMomentum() else {
            return
        }
        guard let node = itemNodeForListGesture(at: point, gesture: .tap),
              let index = node.index,
              index >= 0,
              index < items.count else {
            return
        }

        node.tapped()
        guard items[index].selectable else { return }

        switch selectionMode {
        case .none:
            break
        case .single:
            let id = ObjectIdentifier(items[index])
            if selectedItemIds != [id] {
                selectedItemIds = [id]
                syncSelectionToNodes(animated: true)
                notifySelectionChanged()
            }
        case .multiple:
            let id = ObjectIdentifier(items[index])
            if selectedItemIds.contains(id) {
                selectedItemIds.remove(id)
            } else {
                selectedItemIds.insert(id)
            }
            syncSelectionToNodes(animated: true)
            notifySelectionChanged()
        }

        items[index].selected(listNode: self)
        itemTapped?(index)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: contentNode.view)
        if swipeActionsNodeContainsPoint(point) {
            return false
        }
        if gestureRecognizer === swipeRecognizer {
            configureSwipeRecognizerForGestureStart(at: point)
            if reorderState != nil {
                return false
            }
            return itemNodeForListGesture(at: point, gesture: .swipe) != nil
        }
        if gestureRecognizer === reorderRecognizer {
            if revealedSwipeItemId != nil {
                closeSwipeActions(animated: true)
                return false
            }
            return itemNodeForListGesture(at: point, gesture: .reorder) != nil
        }
        guard gestureRecognizer === tapRecognizer else { return true }
        guard !isTapSelectionSuppressedByScrollMomentum() else { return false }
        if itemNodeForListGesture(at: point, gesture: .tap) != nil {
            return true
        }
        if revealedSwipeItemId != nil {
            return true
        }
        return !limitsListGestureHitTestingToVisibleItemNodes
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let tapRecognizer else { return false }
        return gestureRecognizer === tapRecognizer || otherGestureRecognizer === tapRecognizer
    }

    open override var accessibilityElements: [Any]? {
        get {
            let order = accessibilityNodeOrder.isEmpty && !itemNodes.isEmpty
                ? makeVisibilitySnapshot().accessibilityNodeIds
                : accessibilityNodeOrder
            let nodesById = Dictionary(uniqueKeysWithValues: itemNodes.map { (ObjectIdentifier($0), $0) })
            return order.compactMap { nodeId in
                guard let node = nodesById[nodeId],
                      node.view.superview != nil,
                      !node.isHidden,
                      node.alpha > 0.01 else {
                    return nil
                }
                return node
            }
        }
        set {
            // AetherListNode owns traversal order so recycled rows stay hidden.
        }
    }

    open override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let page = max(1.0, bounds.height - scrollNode.view.contentInset.top - scrollNode.view.contentInset.bottom)
        var target = scrollNode.view.contentOffset.y
        switch direction {
        case .up:
            target -= page
        case .down:
            target += page
        case .left, .right, .next, .previous:
            return false
        @unknown default:
            return false
        }

        let minOffset = -scrollNode.view.contentInset.top
        let maxOffset = max(
            minOffset,
            scrollNode.view.contentSize.height + scrollNode.view.contentInset.bottom - bounds.height
        )
        target = min(maxOffset, max(minOffset, target))
        guard abs(scrollNode.view.contentOffset.y - target) > 0.5 else { return false }
        setRawContentOffsetY(target, animated: true)
        return true
    }

    private func swipeRevealWidth(for actions: [AetherListSwipeAction], at index: Int) -> CGFloat {
        guard !actions.isEmpty else { return 0.0 }
        let itemHeight = index >= 0 && index < itemHeights.count ? itemHeights[index] : 44.0
        let shapeWidth: CGFloat = itemHeight < 72.0 ? 64.0 : 60.0
        let spacing: CGFloat = 10.0
        let edgeInset: CGFloat = 10.0
        return edgeInset * 2.0 + shapeWidth * CGFloat(actions.count) + spacing * CGFloat(actions.count - 1)
    }

    private func configureSwipeRecognizerForGestureStart(at point: CGPoint) {
        guard let swipeRecognizer,
              let node = itemNodeForListGesture(at: point, gesture: .swipe, consultExternalGate: false),
              let index = node.index,
              index >= 0,
              index < items.count else {
            swipeRecognizer?.allowAnyDirection = false
            return
        }
        let actions = items[index].swipeActions
        swipeRecognizer.allowAnyDirection = !actions.left.isEmpty || !swipeRevealOffset(at: index).isZero
    }

    private func ensureSwipeActionsNode(for node: AetherListItemNode, item: AetherListItem) -> AetherListSwipeActionsNode {
        let nodeId = ObjectIdentifier(node)
        let actionsNode: AetherListSwipeActionsNode
        if let existing = swipeActionNodes[nodeId] {
            actionsNode = existing
        } else {
            let created = AetherListSwipeActionsNode(
                actionSelected: { [weak self, weak node] action in
                    guard let self, let node, let index = node.index else { return }
                    self.performSwipeAction(action, at: index, isFullSwipe: false)
                },
                expandedStateChanged: { [weak self] in
                    self?.performSwipeActionHaptic()
                }
            )
            swipeActionNodes[nodeId] = created
            actionsNode = created
        }

        actionsNode.setActions(item.swipeActions)
        syncSwipeActionsNodeFrame(for: node)
        if actionsNode.supernode !== contentNode {
            contentNode.insertSubnode(actionsNode, belowSubnode: node)
        } else {
            actionsNode.removeFromSupernode()
            contentNode.insertSubnode(actionsNode, belowSubnode: node)
        }
        return actionsNode
    }

    private func syncSwipeActionsNodeFrame(for node: AetherListItemNode) {
        guard let actionsNode = swipeActionNodes[ObjectIdentifier(node)] else { return }
        actionsNode.frame = AetherListFrameMetrics.sanitizedRect(node.frame)
        let leftInset = AetherListFrameMetrics.sanitizedCoordinate(_headerInsets?.left ?? _insets.left)
        let rightInset = AetherListFrameMetrics.sanitizedCoordinate(_headerInsets?.right ?? _insets.right)
        actionsNode.updateLayout(
            size: AetherListFrameMetrics.sanitizedSize(node.bounds.size),
            leftInset: leftInset,
            rightInset: rightInset
        )
    }

    private func removeSwipeActionsNode(for node: AetherListItemNode) {
        guard let actionsNode = swipeActionNodes.removeValue(forKey: ObjectIdentifier(node)) else { return }
        actionsNode.removeFromSupernode()
        if node.view.transform != .identity, node.item?.stableId != revealedSwipeItemId {
            node.view.transform = .identity
        }
    }

    private func removeAllSwipeActionsNodes() {
        for actionsNode in swipeActionNodes.values {
            actionsNode.removeFromSupernode()
        }
        swipeActionNodes.removeAll()
        for node in itemNodes where node.view.transform != .identity {
            node.view.transform = .identity
        }
        for node in itemNodes {
            node.setSwipeRevealBackgroundActive(false, transition: .immediate)
        }
        revealedSwipeItemId = nil
        revealedSwipeOffset = 0.0
    }

    private func swipeActionsNodeContainsPoint(_ point: CGPoint) -> Bool {
        for actionsNode in swipeActionNodes.values {
            guard !actionsNode.revealOffset.isZero,
                  actionsNode.frame.contains(point) else {
                continue
            }
            let localPoint = CGPoint(x: point.x - actionsNode.frame.minX, y: point.y - actionsNode.frame.minY)
            if actionsNode.containsInteractiveAction(at: localPoint) {
                return true
            }
        }
        return false
    }

    private func expandedSwipeAction(
        for side: AetherListSwipeActionsSide,
        actions: [AetherListSwipeAction]
    ) -> AetherListSwipeAction? {
        switch side {
        case .left:
            return actions.first
        case .right:
            return actions.last
        }
    }

    private func updateSwipeRevealOffset(_ offset: CGFloat, for node: AetherListItemNode, animated: Bool) {
        guard let item = node.item else { return }
        let transition: ContainedViewLayoutTransition = animated
            ? .animated(duration: 0.3, curve: .spring)
            : .immediate
        debugInstrumentation.measureSwipeRevealUpdate {
            let actionsNode = ensureSwipeActionsNode(for: node, item: item)
            if offset.isZero {
                if revealedSwipeItemId == item.stableId {
                    revealedSwipeItemId = nil
                    revealedSwipeOffset = 0.0
                }
            } else {
                revealedSwipeItemId = item.stableId
                revealedSwipeOffset = offset
            }
            node.setSwipeRevealBackgroundActive(!offset.isZero, transition: transition)
            transition.updateTransform(view: node.view, transform: CGAffineTransform(translationX: offset, y: 0.0))
            actionsNode.updateRevealOffset(offset, transition: transition) { [weak self, weak node, weak actionsNode] in
                guard let self, let node, let actionsNode, actionsNode.revealOffset.isZero else { return }
                self.removeSwipeActionsNode(for: node)
            }
        }
    }

    private func performSwipeAction(
        _ action: AetherListSwipeAction,
        at index: Int,
        isFullSwipe: Bool
    ) {
        guard index >= 0, index < items.count else { return }
        let item = items[index]
        closeSwipeActions(animated: true)
        item.swipeActionSelected(action, listNode: self, isFullSwipe: isFullSwipe)
        swipeActionSelected?(index, action, isFullSwipe)
    }

    private func performSwipeActionHaptic() {
        if let swipeActionHapticFeedback {
            swipeActionHapticFeedback()
            return
        }
        if swipeHapticFeedbackGenerator == nil {
            swipeHapticFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        }
        swipeHapticFeedbackGenerator?.impactOccurred()
    }

    private func syncRevealedSwipeStateAfterTransaction() {
        guard let revealedSwipeItemId else { return }
        guard let index = items.firstIndex(where: { $0.stableId == revealedSwipeItemId }) else {
            closeSwipeActions(animated: false)
            return
        }
        let actions = items[index].swipeActions
        if actions.isEmpty
            || (revealedSwipeOffset > 0.0 && actions.left.isEmpty)
            || (revealedSwipeOffset < 0.0 && actions.right.isEmpty) {
            closeSwipeActions(animated: false)
            return
        }
        guard let node = nodeForItem(at: index) else { return }
        updateSwipeRevealOffset(revealedSwipeOffset, for: node, animated: false)
    }

    private func syncRefreshControl() {
        guard isNodeLoaded else { return }
        if refreshHandler != nil {
            if refreshControl == nil {
                let control = UIRefreshControl()
                control.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
                scrollNode.view.refreshControl = control
                refreshControl = control
            }
        } else {
            scrollNode.view.refreshControl = nil
            refreshControl = nil
        }
    }

    @objc private func handleRefresh() {
        triggerRefresh()
    }

    private func triggerRefresh() {
        guard let handler = refreshHandler else {
            refreshControl?.endRefreshing()
            return
        }
        handler { [weak self] in
            DispatchQueue.main.async {
                self?.refreshControl?.endRefreshing()
            }
        }
    }

    @objc private func handleContentSizeCategoryDidChange() {
        dynamicTypeInvalidated?()
        contentSizeCategoryRelayoutGeneration &+= 1
        let generation = contentSizeCategoryRelayoutGeneration

        // UIKit posts the notification while it is still propagating the new
        // trait environment. Texture nodes can briefly report zero bounds in
        // that window; applying a layout then permanently collapses every row
        // to width 0 because the outer list frame itself did not change.
        // Reflow on the next main-loop turn, once the hierarchy is coherent.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.contentSizeCategoryRelayoutGeneration == generation else {
                return
            }
            self.relayoutAfterContentSizeCategoryChange(generation: generation)
            // UIKit may apply a second geometry pass after the notification
            // (notably when moving from an accessibility category back to a
            // standard one). Revalidate once more after that pass.
            DispatchQueue.main.async { [weak self] in
                self?.relayoutAfterContentSizeCategoryChange(generation: generation)
            }
        }
    }

    private func relayoutAfterContentSizeCategoryChange(generation: UInt) {
        guard contentSizeCategoryRelayoutGeneration == generation else { return }
        clearLayoutCaches(cancelPending: true)
        guard bounds.width > 0.0, bounds.height > 0.0 else {
            setNeedsLayout()
            return
        }
        relayoutLoadedNodes(params: layoutParams())
        relayoutContent()
        setNeedsLayout()
    }

    private func syncDebugOverlay() {
        guard isNodeLoaded else { return }
        let shouldShow = debugInfo || showsDebugOverlay
        if shouldShow {
            if debugOverlayLabel == nil {
                let label = AetherTextNodeOverlayView()
                label.backgroundColor = UIColor.black.withAlphaComponent(0.72)
                label.textColor = .white
                label.font = .monospacedSystemFont(ofSize: 11.0, weight: .medium)
                label.maximumNumberOfLines = 0
                label.layer.cornerRadius = 6.0
                label.layer.masksToBounds = true
                label.textInsets = UIEdgeInsets(top: 6.0, left: 8.0, bottom: 6.0, right: 8.0)
                view.addSubview(label)
                debugOverlayLabel = label
            }
            updateDebugOverlay()
            layoutDebugOverlay()
        } else {
            debugOverlayLabel?.removeFromSuperview()
            debugOverlayLabel = nil
        }
    }

    private func layoutDebugOverlay() {
        guard let label = debugOverlayLabel else { return }
        let width = min(max(0.0, bounds.width - 16.0), 280.0)
        label.frame = CGRect(x: 8.0, y: max(8.0, view.safeAreaInsets.top + 8.0), width: width, height: 116.0)
        view.bringSubviewToFront(label)
    }

    private func updateDebugOverlay() {
        guard let label = debugOverlayLabel else { return }
        let displayed = computeDisplayedRange()
        let counters = debugInstrumentation.counters
        let loaded = displayed.loadedRange.map { "\($0.lowerBound)..<\($0.upperBound)" } ?? "nil"
        let visible = displayed.visibleRange.map { "\($0.lowerBound)..<\($0.upperBound)" } ?? "nil"
        let text = """
        visible \(visible) loaded \(loaded)
        views \(itemNodes.count) created \(counters.createdViews) reused \(counters.reusedViews)
        update \(counters.updatedNodes) apply \(counters.layoutApplications) prepared \(counters.preparedLayoutApplications)
        swipe \(counters.swipeRevealUpdates) last \(String(format: "%.2f", counters.lastSwipeRevealUpdateDuration * 1000))ms
        cache \(layoutCache.count) hits \(counters.layoutCacheHits) misses \(counters.layoutCacheMisses)
        tx \(counters.transactionCount) last \(String(format: "%.2f", counters.lastTransactionDuration * 1000))ms
        """
        label.text = text
    }

    private func syncCustomScrollIndicator() {
        guard isNodeLoaded else { return }
        if usesCustomScrollIndicator {
            scrollNode.view.showsVerticalScrollIndicator = false
            if customScrollIndicatorView == nil {
                let view = UIView()
                view.backgroundColor = UIColor.label.withAlphaComponent(0.42)
                view.layer.cornerRadius = 1.5
                view.alpha = 0.0
                view.isUserInteractionEnabled = false
                self.view.addSubview(view)
                customScrollIndicatorView = view
            }
            updateCustomScrollIndicator()
        } else {
            scrollNode.view.showsVerticalScrollIndicator = true
            customScrollIndicatorFadeWorkItem?.cancel()
            customScrollIndicatorFadeWorkItem = nil
            customScrollIndicatorView?.removeFromSuperview()
            customScrollIndicatorView = nil
        }
    }

    private func updateCustomScrollIndicator() {
        guard usesCustomScrollIndicator, let indicator = customScrollIndicatorView else { return }
        guard let frame = AetherListFrameMetrics.verticalScrollIndicatorFrame(
            boundsWidth: bounds.width,
            viewportHeight: bounds.height,
            contentSizeHeight: scrollNode.view.contentSize.height,
            contentInset: scrollNode.view.contentInset,
            scrollIndicatorInsets: scrollIndicatorInsets,
            contentOffsetY: scrollNode.view.contentOffset.y,
            followsOverscroll: customScrollIndicatorFollowsOverscroll
        ) else {
            indicator.isHidden = true
            return
        }
        indicator.isHidden = false
        indicator.frame = frame
        view.bringSubviewToFront(indicator)
    }

    private func flashCustomScrollIndicator() {
        guard usesCustomScrollIndicator, let indicator = customScrollIndicatorView, !indicator.isHidden else { return }
        updateCustomScrollIndicator()
        customScrollIndicatorFadeWorkItem?.cancel()
        indicator.alpha = 1.0
        let workItem = DispatchWorkItem { [weak indicator] in
            UIView.animate(withDuration: 0.25) {
                indicator?.alpha = 0.0
            }
        }
        customScrollIndicatorFadeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func updateOverscrollState() {
        let overscroll = AetherListFrameMetrics.overscrollDistances(
            contentOffsetY: scrollNode.view.contentOffset.y,
            contentSizeHeight: scrollNode.view.contentSize.height,
            viewportHeight: bounds.height,
            contentInset: scrollNode.view.contentInset
        )
        topOverscrollChanged?(overscroll.top)
        bottomOverscrollChanged?(overscroll.bottom)

        _topOverscrollBackgroundNode?.frame = CGRect(x: 0.0, y: 0.0, width: bounds.width, height: overscroll.top)
        _bottomOverscrollBackgroundNode?.frame = CGRect(
            x: 0.0,
            y: bounds.height - overscroll.bottom,
            width: bounds.width,
            height: overscroll.bottom
        )
    }

    private func autoScrollForReorderIfNeeded(visibleY: CGFloat) {
        let edge: CGFloat = 56.0
        let step: CGFloat = 10.0
        var targetY = scrollNode.view.contentOffset.y
        if visibleY < edge {
            targetY -= step
        } else if visibleY > bounds.height - edge {
            targetY += step
        } else {
            return
        }
        let minY = -scrollNode.view.contentInset.top
        let maxY = max(minY, scrollNode.view.contentSize.height + scrollNode.view.contentInset.bottom - bounds.height)
        targetY = min(maxY, max(minY, targetY))
        guard abs(targetY - scrollNode.view.contentOffset.y) > 0.5 else { return }
        setRawContentOffsetY(targetY, animated: false)
    }

    private func indexForReorderInsertion(centerY: CGFloat) -> Int? {
        guard !items.isEmpty else { return nil }
        let upperBound = min(items.count, itemOffsets.count, itemHeights.count)
        guard upperBound > 0 else { return nil }

        var low = 0
        var high = upperBound
        while low < high {
            let mid = low + (high - low) / 2
            let itemCenterY = itemOffsets[mid] + itemHeights[mid] / 2.0
            if centerY < itemCenterY {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return min(items.count - 1, max(0, low))
    }

    @discardableResult
    private func moveReorderItem(from fromIndex: Int, to toIndex: Int) -> Bool {
        guard fromIndex >= 0,
              fromIndex < items.count,
              fromIndex < itemHeights.count,
              toIndex >= 0,
              toIndex < items.count,
              fromIndex != toIndex else {
            return false
        }
        let item = items.remove(at: fromIndex)
        let height = itemHeights.remove(at: fromIndex)
        let target = min(toIndex, items.count)
        items.insert(item, at: target)
        itemHeights.insert(height, at: target)
        rebuildStickyHeaderIndexCache()
        rebuildOffsets()
        reindexLoadedNodesByItemIdentity()
        return true
    }

    func performReorderMoveForTesting(from fromIndex: Int, to toIndex: Int) -> Bool {
        guard allowsReorder,
              fromIndex >= 0,
              fromIndex < items.count,
              toIndex >= 0,
              toIndex < items.count,
              items[fromIndex].canReorder,
              items[toIndex].canReorder,
              canMoveItem?(fromIndex, toIndex) ?? true else {
            return false
        }
        let moved = moveReorderItem(from: fromIndex, to: toIndex)
        if moved {
            positionLoadedNodes()
            applyStickyHeaderLayout()
            applyVisibilityLifecycle()
            reorderItem?(fromIndex, toIndex)
            didMoveItem?(fromIndex, toIndex)
            reorderCompleted?(fromIndex, toIndex, true)
        }
        return moved
    }

    private func animateLoadedNodesToCurrentLayout(excluding excludedNode: AetherListItemNode) {
        UIView.animate(withDuration: 0.22, delay: 0.0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            for node in self.itemNodes where node !== excludedNode {
                guard let index = node.index,
                      index >= 0,
                      index < self.itemOffsets.count,
                      index < self.itemHeights.count else {
                    continue
                }
                self.setFrame(
                    CGRect(x: 0.0, y: self.itemOffsets[index], width: self.bounds.width, height: self.itemHeights[index]),
                    for: node
                )
            }
        }
    }

    private func reindexLoadedNodesByItemIdentity() {
        let loadedItemIds = Set(itemNodes.compactMap { node -> ObjectIdentifier? in
            guard let item = node.item else { return nil }
            return ObjectIdentifier(item)
        })
        var indexByItemId: [ObjectIdentifier: Int] = [:]
        indexByItemId.reserveCapacity(loadedItemIds.count)
        for (index, item) in items.enumerated() {
            let itemId = ObjectIdentifier(item)
            guard loadedItemIds.contains(itemId) else { continue }
            indexByItemId[itemId] = index
            if indexByItemId.count == loadedItemIds.count {
                break
            }
        }
        for node in itemNodes {
            guard let item = node.item else { continue }
            node.index = indexByItemId[ObjectIdentifier(item)]
        }
        itemNodes.sort { ($0.index ?? 0) < ($1.index ?? 0) }
    }

    private func applySelection(to node: AetherListItemNode, item: AetherListItem, animated: Bool) {
        let shouldSelect = selectedItemIds.contains(ObjectIdentifier(item))
        guard node.isSelected != shouldSelect else { return }
        node.pendingSelectionAnimated = animated
        node.isSelected = shouldSelect
        node.pendingSelectionAnimated = false
    }

    private func syncSelectionToNodes(animated: Bool) {
        for node in itemNodes {
            guard let item = node.item else { continue }
            applySelection(to: node, item: item, animated: animated)
        }
    }

    private func notifySelectionChanged() {
        selectionChanged?(selectedIndices)
    }

    private func layoutParams() -> AetherListItemLayoutParams {
        AetherListItemLayoutParams(
            width: AetherListFrameMetrics.sanitizedLength(bounds.width),
            availableHeight: AetherListFrameMetrics.sanitizedLength(bounds.height)
        )
    }

    private func estimatedHeight(for item: AetherListItem) -> CGFloat {
        if let prepared = preparedLayoutCache[item.stableId] {
            debugInstrumentation.recordLayoutCacheHit()
            return AetherListFrameMetrics.sanitizedLength(prepared.layout.totalHeight)
        }
        if let cached = layoutCache[item.stableId] {
            debugInstrumentation.recordLayoutCacheHit()
            return AetherListFrameMetrics.sanitizedLength(cached.totalHeight)
        }
        debugInstrumentation.recordLayoutCacheMiss()
        return AetherListFrameMetrics.sanitizedLength(item.estimatedHeight)
    }

    private func recordLayout(_ layout: AetherListItemNodeLayout, for item: AetherListItem) {
        let id = item.stableId
        if layoutCache[id] == nil {
            layoutCacheOrder.append(id)
        }
        layoutCache[id] = layout
        while layoutCacheOrder.count > maxLayoutCacheEntries {
            let removed = layoutCacheOrder.removeFirst()
            layoutCache.removeValue(forKey: removed)
            preparedLayoutCache.removeValue(forKey: removed)
        }
    }

    private func resolvedLayout(
        for item: AetherListItem,
        node: AetherListItemNode,
        fallback: AetherListItemNodeLayout
    ) -> AetherListItemNodeLayout {
        guard let prepared = preparedLayoutCache[item.stableId] else {
            return fallback
        }
        debugInstrumentation.measurePreparedLayoutApplication {
            prepared.apply(node)
        }
        return prepared.layout
    }

    private final class AsyncLayoutTaskBox {
        var task: AetherListLayoutTask?
    }

    private func makeAsyncLayoutCommands(prefetchRange: Range<Int>) -> [AetherListAsyncLayoutCommand<AnyHashable>] {
        var itemDescriptors: [AetherListAsyncLayoutItemDescriptor<AnyHashable>] = []
        var describedItemIds = Set<AnyHashable>()
        let lowerBound = max(0, prefetchRange.lowerBound)
        let upperBound = min(items.count, prefetchRange.upperBound)

        if lowerBound < upperBound {
            itemDescriptors.reserveCapacity((upperBound - lowerBound) + pendingLayoutTasks.count)
            for index in lowerBound..<upperBound {
                let item = items[index]
                let id = item.stableId
                describedItemIds.insert(id)
                itemDescriptors.append(AetherListAsyncLayoutItemDescriptor(
                    index: index,
                    itemId: id,
                    reuseIdentifier: item.reuseIdentifier,
                    hasPreparedLayout: preparedLayoutCache[id] != nil,
                    hasPendingLayoutTask: pendingLayoutTasks[id] != nil,
                    isKnownSynchronous: synchronousLayoutIdentifiers.contains(item.reuseIdentifier)
                ))
            }
        }

        for itemId in pendingLayoutTasks.keys where !describedItemIds.contains(itemId) {
            itemDescriptors.append(AetherListAsyncLayoutItemDescriptor(
                index: -1,
                itemId: itemId,
                reuseIdentifier: "",
                hasPreparedLayout: preparedLayoutCache[itemId] != nil,
                hasPendingLayoutTask: true,
                isKnownSynchronous: false
            ))
        }

        return AetherListAsyncLayoutCommandPlanner.commands(
            prefetchRange: prefetchRange,
            itemDescriptors: itemDescriptors
        )
    }

    private func prefetchAsyncLayouts(in range: Range<Int>, params: AetherListItemLayoutParams) {
        for command in makeAsyncLayoutCommands(prefetchRange: range) {
            switch command {
            case let .cancel(itemId):
                cancelAsyncLayout(forID: itemId)
            case let .prepare(index, itemId):
                startAsyncLayoutPreparation(at: index, itemId: itemId, params: params)
            }
        }
    }

    private func startAsyncLayoutPreparation(
        at index: Int,
        itemId: AnyHashable,
        params: AetherListItemLayoutParams
    ) {
        guard index >= 0, index < items.count else { return }
        let item = items[index]
        let id = item.stableId
        guard id == itemId,
              preparedLayoutCache[id] == nil,
              pendingLayoutTasks[id] == nil,
              !synchronousLayoutIdentifiers.contains(item.reuseIdentifier) else {
            return
        }

        let previous = index > 0 ? items[index - 1] : nil
        let next = index + 1 < items.count ? items[index + 1] : nil
        let requestedWidth = params.width
        let taskBox = AsyncLayoutTaskBox()
        let task = item.asyncLayout(params: params, previousItem: previous, nextItem: next) { [weak self, weak item] prepared in
            DispatchQueue.main.async {
                guard let self, let item else { return }
                if let expectedTask = taskBox.task {
                    guard self.pendingLayoutTasks[item.stableId] === expectedTask else {
                        return
                    }
                    self.pendingLayoutTasks.removeValue(forKey: item.stableId)
                } else {
                    self.pendingLayoutTasks.removeValue(forKey: item.stableId)
                }

                guard abs(self.layoutParams().width - requestedWidth) < 0.5,
                      self.items.contains(where: { $0.stableId == item.stableId }) else {
                    return
                }
                self.preparedLayoutCache[item.stableId] = prepared
                self.recordLayout(prepared.layout, for: item)
                self.applyPreparedLayoutIfVisible(prepared, for: item)
            }
        }
        taskBox.task = task
        if let task {
            pendingLayoutTasks[id] = task
        } else {
            synchronousLayoutIdentifiers.insert(item.reuseIdentifier)
        }
    }

    private func applyPreparedLayoutIfVisible(_ prepared: AetherListPreparedItemLayout, for item: AetherListItem) {
        guard let currentIndex = items.firstIndex(where: { $0.stableId == item.stableId }),
              currentIndex < itemHeights.count else {
            return
        }

        itemHeights[currentIndex] = prepared.layout.totalHeight
        if let node = nodeForItem(at: currentIndex) {
            debugInstrumentation.measurePreparedLayoutApplication {
                prepared.apply(node)
            }
            debugInstrumentation.measureLayoutApplication {
                node.applyLayout(prepared.layout)
            }
            syncAccessories(for: node, item: item)
        }
        rebuildOffsets()
        updateContentSize()
        positionLoadedNodes()
        applyStickyHeaderLayout()
        applyVisibilityLifecycle()
    }

    private func cancelAsyncLayout(forID id: AnyHashable) {
        if let task = pendingLayoutTasks.removeValue(forKey: id) {
            task.cancel()
        }
    }

    private func removeCachedLayout(forID id: AnyHashable) {
        layoutCache.removeValue(forKey: id)
        preparedLayoutCache.removeValue(forKey: id)
        layoutCacheOrder.removeAll { $0 == id }
    }

    private func clearLayoutCaches(cancelPending: Bool) {
        layoutCache.removeAll()
        layoutCacheOrder.removeAll()
        preparedLayoutCache.removeAll()
        guard cancelPending else { return }
        for task in pendingLayoutTasks.values {
            task.cancel()
        }
        pendingLayoutTasks.removeAll()
    }

    @discardableResult
    private func applyScrollInsets(
        transition: ContainedViewLayoutTransition = .immediate,
        adjustsContentOffsetForTopInsetChange: Bool = true,
        additionalContentOffsetDeltaY: CGFloat? = nil
    ) -> Bool {
        guard isNodeLoaded else { return false }
        let effectiveInsets = effectiveScrollInsets()
        let scrollView = scrollNode.view
        let previousTopInset = scrollView.contentInset.top
        let previousOffsetY = scrollView.contentOffset.y
        let wasPinnedToTop = previousOffsetY <= -previousTopInset + 0.5
        let shouldAdjustTopOffset = adjustsContentOffsetForTopInsetChange
            && abs(effectiveInsets.top - previousTopInset) > 0.5
            && wasPinnedToTop
        let targetOffset: CGPoint?
        if shouldAdjustTopOffset {
            targetOffset = AetherListFrameMetrics.sanitizedPoint(
                CGPoint(x: scrollView.contentOffset.x, y: -effectiveInsets.top)
            )
        } else if let additionalContentOffsetDeltaY, !additionalContentOffsetDeltaY.isZero {
            targetOffset = AetherListFrameMetrics.sanitizedPoint(
                CGPoint(x: scrollView.contentOffset.x, y: scrollView.contentOffset.y + additionalContentOffsetDeltaY)
            )
        } else {
            targetOffset = nil
        }
        transition.updateScrollViewInsetsAndOffset(
            scrollView: scrollView,
            contentInset: effectiveInsets,
            scrollIndicatorInsets: scrollIndicatorInsets ?? effectiveInsets,
            contentOffset: targetOffset
        )
        return shouldAdjustTopOffset
    }

    private func effectiveScrollInsets() -> UIEdgeInsets {
        var insets = _insets
        if automaticInsetEdges.contains(.top) {
            insets.top += automaticSafeAreaInsets.top
        }
        if automaticInsetEdges.contains(.left) {
            insets.left += automaticSafeAreaInsets.left
        }
        if automaticInsetEdges.contains(.bottom) {
            insets.bottom += automaticSafeAreaInsets.bottom
        }
        if automaticInsetEdges.contains(.right) {
            insets.right += automaticSafeAreaInsets.right
        }
        insets.bottom += keyboardBottomInset
        if stackFromBottom {
            let availableHeight = max(0.0, AetherListFrameMetrics.sanitizedLength(bounds.height) - insets.top - insets.bottom)
            insets.top += max(0.0, availableHeight - AetherListFrameMetrics.sanitizedLength(totalContentHeight))
        }
        return AetherListFrameMetrics.sanitizedInsets(insets)
    }

    private func resolvedContentHeight() -> CGFloat {
        if stackFromBottom {
            return max(0.0, totalContentHeight)
        }
        let insets = effectiveScrollInsets()
        let visibleHeight = max(
            0.0,
            AetherListFrameMetrics.sanitizedLength(bounds.height) - insets.top - insets.bottom
        )
        return max(AetherListFrameMetrics.sanitizedLength(totalContentHeight), visibleHeight)
    }

    private func shouldPreserveBottomAnchor() -> Bool {
        guard stackFromBottom else { return false }
        guard isNodeLoaded else { return true }
        if items.isEmpty {
            return true
        }
        return visibleBottomContentOffset() <= stackFromBottomAutoAnchorTolerance
    }

    private func setRawContentOffsetY(_ y: CGFloat, animated: Bool) {
        scrollNode.view.setContentOffset(
            AetherListFrameMetrics.sanitizedPoint(CGPoint(x: scrollNode.view.contentOffset.x, y: y)),
            animated: animated
        )
    }

    private func computeDisplayedRange() -> AetherListDisplayedItemRange {
        makeVisibilitySnapshot().displayedRange
    }

    private func makeVisibilitySnapshot() -> AetherListVisibilitySnapshot<ObjectIdentifier> {
        guard !items.isEmpty else {
            return AetherListVisibilitySnapshot(
                displayedRange: AetherListDisplayedItemRange(loadedRange: nil, visibleRange: nil),
                accessibilityNodeIds: [],
                loadedViewCount: 0
            )
        }
        return AetherListVisibilityLifecycleCommandPlanner.snapshot(
            nodeDescriptors: makeVisibilityNodeDescriptors(),
            viewportTop: scrollNode.view.contentOffset.y,
            viewportHeight: bounds.height
        )
    }

    private func makeVisibilityNodeDescriptors() -> [AetherListVisibilityNodeDescriptor<ObjectIdentifier>] {
        itemNodes.map { node in
            AetherListVisibilityNodeDescriptor(
                nodeId: ObjectIdentifier(node),
                index: node.index,
                frame: node.frame,
                isAccessibilityVisible: node.view.superview != nil && !node.isHidden && node.alpha > 0.01
            )
        }
    }

    @discardableResult
    private func applyVisibilityLifecycle(
        notifyDisplayedRangeChanged: Bool = true,
        isUserInitiated: Bool = false
    ) -> AetherListDisplayedItemRange {
        let snapshot = makeVisibilitySnapshot()
        for command in AetherListVisibilityLifecycleCommandPlanner.commands(
            snapshot: snapshot,
            notifyDisplayedRange: notifyDisplayedRangeChanged
        ) {
            switch command {
            case let .recordVisibleViews(count):
                debugInstrumentation.recordVisibleViews(count)

            case let .setAccessibilityOrder(nodeIds):
                accessibilityNodeOrder = nodeIds

            case let .notifyDisplayedRange(displayedRange):
                displayedItemRangeChanged?(displayedRange)
            }
        }
        evaluateBoundaryTriggers(displayedRange: snapshot.displayedRange, isUserInitiated: isUserInitiated)
        updateDebugOverlay()
        return snapshot.displayedRange
    }

    private func evaluateBoundaryTriggers(
        displayedRange: AetherListDisplayedItemRange,
        isUserInitiated: Bool
    ) {
        guard let configuration = boundaryTriggerConfiguration,
              let boundaryReached else {
            return
        }

        let snapshot = AetherListBoundaryTriggerSnapshot(
            itemCount: items.count,
            displayedRange: displayedRange,
            visibleContentOffset: visibleContentOffset(),
            visibleBottomContentOffset: visibleBottomContentOffset(),
            isUserInitiated: isUserInitiated
        )
        let triggers = AetherListBoundaryTriggerPlanner.triggers(
            snapshot: snapshot,
            configuration: configuration
        )
        let activeEdges = Set(triggers.map(\.edge))
        for edge in [AetherListBoundaryEdge.top, .bottom] where !activeEdges.contains(edge) {
            boundaryTriggerSignatures.removeValue(forKey: edge)
        }

        for trigger in triggers {
            let signature = BoundaryTriggerSignature(
                itemCount: items.count,
                loadedLowerBound: displayedRange.loadedRange?.lowerBound,
                loadedUpperBound: displayedRange.loadedRange?.upperBound,
                visibleLowerBound: displayedRange.visibleRange?.lowerBound,
                visibleUpperBound: displayedRange.visibleRange?.upperBound
            )
            guard boundaryTriggerSignatures[trigger.edge] != signature else {
                continue
            }
            boundaryTriggerSignatures[trigger.edge] = signature
            boundaryReached(AetherListBoundaryTriggerContext(
                edge: trigger.edge,
                reasons: trigger.reasons,
                displayedRange: displayedRange,
                visibleContentOffset: snapshot.visibleContentOffset,
                visibleBottomContentOffset: snapshot.visibleBottomContentOffset,
                contentSize: scrollNode.view.contentSize,
                visibleSize: visibleSize,
                isUserInitiated: isUserInitiated
            ))
        }
    }
}
