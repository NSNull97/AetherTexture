import UIKit
import AsyncDisplayKit

/// Glass segmented control built on `LiquidLensView` — same lens
/// machinery the tab bar uses for its selection pill. Track and selection
/// are baked into a single lens; selected/unselected item visuals live
/// on two stacked layers (`lensView.contentView` for un-selected,
/// `lensView.selectedContentView` for selected). The lens applies the
/// selection-shaped mask, so the selected style only shows inside the
/// thumb area and crossfades into the unselected style outside it.
///
/// On iOS 26+ this delivers Apple's native liquid-glass selection
/// (refraction, lift on press, elastic deformation under drag); on
/// legacy systems `LiquidLensView` uses public UIKit chrome materials for
/// the track and selection, without a Liquid mask/deformation pipeline.
///
/// Sizing is host-driven: set frame / use Auto Layout. `cornerRadius ==
/// nil` (default) makes the track a capsule (`bounds.height / 2`); pass
/// a fixed value for a rounded rectangle.
public final class AetherSegmentedControl: UIView, AetherAppearanceConsumer {

    // MARK: - Public types

    public final class Theme: Equatable {
        /// Title colour for un-selected items.
        public let textColor: UIColor
        /// Title colour for the selected item (the one on top of the
        /// lens). Default uses the same colour as `textColor`; the
        /// visual distinction comes from the bolder font.
        public let selectedTextColor: UIColor

        public init(
            textColor: UIColor = .label,
            selectedTextColor: UIColor = .label
        ) {
            self.textColor = textColor
            self.selectedTextColor = selectedTextColor
        }

        public static func == (lhs: Theme, rhs: Theme) -> Bool {
            lhs.textColor == rhs.textColor && lhs.selectedTextColor == rhs.selectedTextColor
        }

        public static let system: Theme = Theme()
    }

    public struct Item: Equatable {
        public let title: String
        public let badgeValue: String?

        public init(title: String, badgeValue: String? = nil) {
            self.title = title
            self.badgeValue = badgeValue
        }
    }

    // MARK: - Public configuration

    /// Track corner radius. `nil` (default) → capsule.
    public var cornerRadius: CGFloat? {
        didSet { setNeedsLayout() }
    }

    /// Inset of the lens selection from the track on both axes. Default
    /// 2pt — same as the tab bar's selection pill.
    public var thumbInset: CGFloat = 2.0 {
        didSet { setNeedsLayout() }
    }

    /// Preferred fixed height when the host doesn't set one explicitly
    /// (used by `intrinsicContentSize`).
    public var preferredHeight: CGFloat = 36.0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    public var items: [Item] {
        get { _items }
        set {
            guard _items != newValue else { return }
            _items = newValue
            _selectedIndex = max(0, min(newValue.count - 1, _selectedIndex))
            if let selectionProgress {
                self.selectionProgress = clampedSelectionProgress(selectionProgress)
            }
            rebuildItemContent()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    public var selectedIndex: Int {
        get { _selectedIndex }
        set {
            setSelectedIndex(newValue, animated: false, updatesSelectionProgress: true)
        }
    }

    public func setSelectedIndex(_ index: Int, animated: Bool) {
        setSelectedIndex(index, animated: animated, updatesSelectionProgress: true)
    }

    internal func setSelectedIndex(_ index: Int, animated: Bool, updatesSelectionProgress: Bool) {
        let clampedIndex = clampedIndex(index)
        guard clampedIndex != _selectedIndex || (updatesSelectionProgress && selectionProgress != nil) else { return }
        let preservedSelectionProgress = displayedSelectionProgress
        _selectedIndex = clampedIndex
        if updatesSelectionProgress {
            selectionProgress = nil
        } else if selectionProgress == nil {
            selectionProgress = preservedSelectionProgress
        }
        updateItemControlStates()
        updateLayoutInternal(transition: animated ? .animated(duration: 0.35, curve: .spring) : .immediate)
    }

    internal func setSelectionProgress(_ progress: CGFloat, animated: Bool) {
        let clampedProgress = clampedSelectionProgress(progress)
        if let selectionProgress, abs(selectionProgress - clampedProgress) < 0.001 {
            return
        }
        selectionProgress = clampedProgress
        updateLayoutInternal(transition: animated ? .animated(duration: 0.35, curve: .spring) : .immediate)
    }

    public var selectedIndexChanged: (Int) -> Void = { _ in }

    /// `nil` follows the application runtime. An explicit style is seeded
    /// into the lens during initialization, before it installs a renderer.
    public var appearanceStyleOverride: AetherAppearanceStyle? {
        didSet {
            guard appearanceStyleOverride != oldValue else { return }
            liquidLensView.appearanceStyleOverride = appearanceStyleOverride
            aetherApplyAppearance(.runtimeCurrent, animated: true)
        }
    }

    public var isEnabled: Bool = true {
        didSet {
            guard isEnabled != oldValue else { return }
            panGestureRecognizer?.isEnabled = isEnabled
            scrollView.isUserInteractionEnabled = isEnabled
            updateItemControlStates()
            aetherApplyAppearance(.runtimeCurrent, animated: true)
        }
    }

    /// Pins the control's glass to a view-local light/dark appearance.
    /// `nil` follows the inherited trait collection.
    public var isDarkAppearance: Bool? {
        didSet {
            guard isDarkAppearance != oldValue else { return }
            liquidLensView.isDarkAppearance = isDarkAppearance
            setNeedsLayout()
        }
    }

    public var selectedIndexShouldChange: (Int, @escaping (Bool) -> Void) -> Void = { _, commit in
        commit(true)
    }

    // MARK: - Internal state

    private var theme: Theme
    private var _items: [Item]
    private var _selectedIndex: Int
    private var selectionProgress: CGFloat?
    private var appliedAppearanceStyle: AetherAppearanceStyle

    private let scrollNode = ASScrollNode()
    private let contentHostNode = ASDisplayNode()
    private let normalContentNode = ASDisplayNode()
    private let selectedContentHostNode = ASDisplayNode()
    private let liquidLensView: LiquidLensView

    /// One label per item on the un-selected layer (lens.contentView).
    /// These read in the regular weight; the lens masks them out where
    /// the selection sits.
    private var normalTitleNodes: [ASTextNode] = []

    /// One label per item on the selected layer (lens.selectedContentView).
    /// Bolder weight; only visible inside the lens window.
    private var selectedTitleNodes: [ASTextNode] = []

    private var normalBadgeViews: [NavigationBarBadgeView] = []
    private var selectedBadgeViews: [NavigationBarBadgeView] = []

    /// Hit-test buttons sized + positioned to match each item slot. Sit
    /// ABOVE the lens so taps on text register, not on the lens glass.
    private var itemButtons: [SegmentedItemControlNode] = []

    private var panGestureRecognizer: UIPanGestureRecognizer?
    /// Drag-to-scrub state — `currentX` is the finger's x in lens coords;
    /// the layout pass clamps it and feeds it as the lens selection
    /// origin so the pill follows the finger.
    private struct DragState { var currentX: CGFloat }
    private var dragState: DragState?
    private var pressActive: Bool = false
    private var currentItemFrames: [CGRect] = []

    private enum Metrics {
        static let minimumSegmentHorizontalPadding: CGFloat = 16.0
        static let badgeSpacing: CGFloat = 4.0
    }

    internal var debugSelectionFrame: CGRect? {
        guard let origin = liquidLensView.selectionOrigin,
              let size = liquidLensView.selectionSize
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    internal var debugScrollView: UIScrollView {
        scrollView
    }

    private var scrollView: UIScrollView {
        scrollNode.view
    }

    private var contentHostView: UIView {
        contentHostNode.view
    }

    internal func debugItemFrame(at index: Int) -> CGRect? {
        guard currentItemFrames.indices.contains(index) else {
            return nil
        }
        return currentItemFrames[index]
    }

    internal func debugAccessibilityTraits(at index: Int) -> UIAccessibilityTraits? {
        guard itemButtons.indices.contains(index) else { return nil }
        return itemButtons[index].accessibilityTraits
    }

    internal var appliedAppearanceStyleForTesting: AetherAppearanceStyle {
        appliedAppearanceStyle
    }

    #if DEBUG
    internal var backingUsesClassicRendererForTesting: Bool {
        liquidLensView.usesClassicRendererForTesting
    }

    internal var backingClassicBlurStylesForTesting: [UIBlurEffect.Style] {
        [
            liquidLensView.classicTrackBlurStyleForTesting,
            liquidLensView.classicSelectionBlurStyleForTesting
        ].compactMap { $0 }
    }

    internal var backingHasLiquidMaskForTesting: Bool {
        liquidLensView.hasLiquidMaskForTesting
    }
    #endif

    // MARK: - Init

    public init(
        theme: Theme = .system,
        items: [Item],
        selectedIndex: Int = 0,
        cornerRadius: CGFloat? = nil,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        self.theme = theme
        self._items = items
        self._selectedIndex = max(0, min(items.count - 1, selectedIndex))
        self.appearanceStyleOverride = appearanceStyle
        self.appliedAppearanceStyle = appearanceStyle ?? AetherAppearance.runtimeCurrent.style
        self.cornerRadius = cornerRadius
        // `.builtinContainer` makes the lens self-sufficient — it owns its
        // own glass background container (no external glass plumbing).
        self.liquidLensView = LiquidLensView(
            kind: .builtinContainer,
            appearanceStyle: appearanceStyle
        )

        super.init(frame: .zero)

        clipsToBounds = false  // lens shadow / lift overflow needs to bleed
        liquidLensView.allowsContentInteraction = true

        scrollNode.scrollableDirections = ASScrollDirectionHorizontalDirections
        scrollNode.automaticallyManagesContentSize = false

        normalContentNode.clipsToBounds = true
        normalContentNode.view.layer.cornerCurve = .continuous
        selectedContentHostNode.clipsToBounds = true
        selectedContentHostNode.view.layer.cornerCurve = .continuous

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.bounces = true
        scrollView.clipsToBounds = true
        scrollView.backgroundColor = .clear
        if #available(iOS 11.0, *) {
            scrollView.contentInsetAdjustmentBehavior = .never
        }
        addSubview(liquidLensView)
        liquidLensView.contentView.addSubview(normalContentNode.view)
        liquidLensView.contentView.addSubview(scrollNode.view)
        liquidLensView.selectedContentView.addSubview(selectedContentHostNode.view)
        scrollView.addSubview(contentHostNode.view)

        rebuildItemContent()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        scrollView.panGestureRecognizer.require(toFail: pan)
        scrollView.delegate = self
        panGestureRecognizer = pan
        AetherAppearanceConsumerRegistry.register(self)
        aetherApplyAppearance(.runtimeCurrent, animated: false)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else {
            return
        }
        for (titleNode, item) in zip(normalTitleNodes, _items) {
            titleNode.attributedText = makeNormalAttributed(item.title)
        }
        for (titleNode, item) in zip(selectedTitleNodes, _items) {
            titleNode.attributedText = makeSelectedAttributed(item.title)
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    // MARK: - Gesture gating

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isEnabled else { return false }
        guard gestureRecognizer === panGestureRecognizer else {
            return true
        }
        // Only own the pan when the finger lands inside the current
        // selection rect — taps anywhere else fall through to the
        // per-item buttons.
        let location = gestureRecognizer.location(in: contentHostView)
        return currentSelectionRect().contains(location)
    }

    // MARK: - Theme

    public func updateTheme(_ newTheme: Theme) {
        guard newTheme != theme else { return }
        theme = newTheme
        for (titleNode, item) in zip(normalTitleNodes, _items) {
            titleNode.attributedText = makeNormalAttributed(item.title)
            _ = item
        }
        for (titleNode, item) in zip(selectedTitleNodes, _items) {
            titleNode.attributedText = makeSelectedAttributed(item.title)
            _ = item
        }
    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        appliedAppearanceStyle = appearanceStyleOverride ?? appearance.style
        let tokens = AetherLegacySurfaceTokens.resolve(
            role: .selectionIndicator,
            traitCollection: traitCollection
        )
        let targetAlpha: CGFloat
        if isEnabled {
            targetAlpha = 1.0
        } else {
            targetAlpha = appliedAppearanceStyle.usesLiquidGlass ? 0.45 : tokens.disabledAlpha
        }
        let changes = { self.alpha = targetAlpha }
        if animated {
            UIView.animate(withDuration: tokens.animationDuration, animations: changes)
        } else {
            changes()
        }
        updateItemControlStates()
        setNeedsLayout()
    }

    // MARK: - Layout

    public override var intrinsicContentSize: CGSize {
        guard !_items.isEmpty else {
            return CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
        }
        let intrinsicWidth = naturalContentWidth(for: naturalItemWidths()) + thumbInset * 2
        return CGSize(width: intrinsicWidth, height: preferredHeight)
    }

    private func clampedIndex(_ index: Int) -> Int {
        guard !_items.isEmpty else {
            return 0
        }
        return max(0, min(_items.count - 1, index))
    }

    private func clampedSelectionProgress(_ progress: CGFloat) -> CGFloat {
        guard !_items.isEmpty else {
            return 0.0
        }
        return max(0.0, min(CGFloat(_items.count - 1), progress))
    }

    private var displayedSelectionProgress: CGFloat {
        if let selectionProgress {
            return clampedSelectionProgress(selectionProgress)
        }
        return CGFloat(_selectedIndex)
    }

    private func naturalItemWidths() -> [CGFloat] {
        guard !_items.isEmpty else {
            return []
        }
        return selectedTitleNodes.indices.map { index in
            let size = itemContentSize(
                titleNode: selectedTitleNodes[index],
                badgeView: selectedBadgeViews[index]
            )
            return ceil(size.width + Metrics.minimumSegmentHorizontalPadding * 2.0)
        }
    }

    private func naturalContentWidth(for itemWidths: [CGFloat]) -> CGFloat {
        itemWidths.reduce(0.0, +)
    }

    private func itemContentSize(titleNode: ASTextNode, badgeView: NavigationBarBadgeView) -> CGSize {
        let labelSize = titleSize(for: titleNode)
        guard !badgeView.isHidden else {
            return labelSize
        }
        let badgeSize = badgeView.sizeThatFits(CGSize(width: 80.0, height: 18.0))
        return CGSize(
            width: labelSize.width + Metrics.badgeSpacing + badgeSize.width,
            height: max(labelSize.height, badgeSize.height)
        )
    }

    private func layoutItemContent(
        titleNode: ASTextNode,
        badgeView: NavigationBarBadgeView,
        in frame: CGRect,
        transition: ContainedViewLayoutTransition
    ) {
        let labelSize = titleSize(for: titleNode)
        let horizontalPadding = Metrics.minimumSegmentHorizontalPadding
        let contentFrame = frame.insetBy(dx: min(horizontalPadding, frame.width * 0.5), dy: 0.0)
        let labelY = frame.minY + floor((frame.height - labelSize.height) / 2.0)
        if badgeView.isHidden {
            transition.updateFrame(
                node: titleNode,
                frame: CGRect(
                    x: contentFrame.minX,
                    y: labelY,
                    width: contentFrame.width,
                    height: labelSize.height
                )
            )
            transition.updateFrame(view: badgeView, frame: CGRect(x: frame.midX, y: frame.midY, width: 0.0, height: 0.0))
            return
        }

        let badgeSize = badgeView.sizeThatFits(CGSize(width: 80.0, height: 18.0))
        let totalWidth = min(contentFrame.width, labelSize.width + Metrics.badgeSpacing + badgeSize.width)
        let labelWidth = max(0.0, min(labelSize.width, totalWidth - Metrics.badgeSpacing - badgeSize.width))
        let startX = contentFrame.minX + floor((contentFrame.width - totalWidth) / 2.0)
        let labelFrame = CGRect(
            x: startX,
            y: labelY,
            width: labelWidth,
            height: labelSize.height
        )
        let badgeFrame = CGRect(
            x: labelFrame.maxX + Metrics.badgeSpacing,
            y: frame.minY + floor((frame.height - badgeSize.height) / 2.0),
            width: badgeSize.width,
            height: badgeSize.height
        )
        transition.updateFrame(node: titleNode, frame: labelFrame)
        transition.updateFrame(view: badgeView, frame: badgeFrame)
    }

    private func selectionFrame(for progress: CGFloat, itemFrames: [CGRect]) -> CGRect {
        guard !itemFrames.isEmpty else {
            return .zero
        }
        let clampedProgress = clampedSelectionProgress(progress)
        let lowerIndex = max(0, min(itemFrames.count - 1, Int(floor(clampedProgress))))
        let upperIndex = max(0, min(itemFrames.count - 1, Int(ceil(clampedProgress))))
        guard lowerIndex != upperIndex else {
            return itemFrames[lowerIndex]
        }
        let fraction = clampedProgress - CGFloat(lowerIndex)
        let lowerFrame = itemFrames[lowerIndex]
        let upperFrame = itemFrames[upperIndex]
        return CGRect(
            x: lowerFrame.minX + (upperFrame.minX - lowerFrame.minX) * fraction,
            y: lowerFrame.minY + (upperFrame.minY - lowerFrame.minY) * fraction,
            width: lowerFrame.width + (upperFrame.width - lowerFrame.width) * fraction,
            height: lowerFrame.height + (upperFrame.height - lowerFrame.height) * fraction
        )
    }

    private func ensureSelectionVisible(_ selectionFrame: CGRect, animated: Bool) {
        guard selectionFrame.width > 0.0,
              scrollView.contentSize.width > scrollView.bounds.width + 0.5,
              !scrollView.isTracking,
              !scrollView.isDragging,
              !scrollView.isDecelerating
        else { return }

        let visibleMinX = scrollView.contentOffset.x
        let visibleMaxX = visibleMinX + scrollView.bounds.width
        let targetFrame = selectionFrame.insetBy(dx: -Metrics.minimumSegmentHorizontalPadding, dy: 0.0)
        var targetOffsetX = visibleMinX
        if targetFrame.minX < visibleMinX {
            targetOffsetX = targetFrame.minX
        } else if targetFrame.maxX > visibleMaxX {
            targetOffsetX = targetFrame.maxX - scrollView.bounds.width
        } else {
            return
        }

        let maxOffsetX = max(0.0, scrollView.contentSize.width - scrollView.bounds.width)
        targetOffsetX = max(0.0, min(maxOffsetX, targetOffsetX))
        guard abs(targetOffsetX - scrollView.contentOffset.x) > 0.5 else {
            return
        }
        scrollView.setContentOffset(CGPoint(x: targetOffsetX, y: 0.0), animated: animated)
    }

    private func nearestItemIndex(to x: CGFloat) -> Int {
        guard !currentItemFrames.isEmpty else {
            return _selectedIndex
        }
        var nearestIndex = _selectedIndex
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for (index, frame) in currentItemFrames.enumerated() {
            let distance = abs(frame.midX - x)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }
        return nearestIndex
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateLayoutInternal(transition: .immediate)
    }

    private func updateLayoutInternal(transition: ContainedViewLayoutTransition) {
        let size = bounds.size
        guard size.width > 0, size.height > 0, !_items.isEmpty else { return }

        let resolvedTrackCorner = cornerRadius ?? (size.height / 2.0)

        transition.updateFrame(node: scrollNode, frame: CGRect(origin: .zero, size: size))

        let naturalWidths = naturalItemWidths()
        let naturalWidth = naturalContentWidth(for: naturalWidths)
        let availableInnerWidth = max(0.0, size.width - thumbInset * 2.0)
        let contentInnerWidth = max(availableInnerWidth, naturalWidth)
        let contentSize = CGSize(width: contentInnerWidth + thumbInset * 2.0, height: size.height)
        let extraWidthPerItem = _items.isEmpty ? 0.0 : max(0.0, availableInnerWidth - naturalWidth) / CGFloat(_items.count)

        scrollView.contentSize = contentSize
        scrollView.alwaysBounceHorizontal = contentSize.width > size.width + 0.5
        transition.updateFrame(node: contentHostNode, frame: CGRect(origin: .zero, size: contentSize))
        transition.updateFrame(node: normalContentNode, frame: CGRect(origin: .zero, size: size))
        transition.updateFrame(node: selectedContentHostNode, frame: CGRect(origin: .zero, size: size))
        transition.updateCornerRadius(layer: normalContentNode.view.layer, cornerRadius: resolvedTrackCorner)
        transition.updateCornerRadius(layer: selectedContentHostNode.view.layer, cornerRadius: resolvedTrackCorner)

        let maxOffsetX = max(0.0, contentSize.width - size.width)
        let clampedOffsetX = max(0.0, min(maxOffsetX, scrollView.contentOffset.x))
        if abs(scrollView.contentOffset.x - clampedOffsetX) > 0.5 || abs(scrollView.contentOffset.y) > 0.5 {
            scrollView.contentOffset = CGPoint(x: clampedOffsetX, y: 0.0)
        }
        let contentOffsetX = scrollView.contentOffset.x

        let itemHeight = size.height
        var itemFrames: [CGRect] = []
        itemFrames.reserveCapacity(_items.count)
        var itemX = thumbInset
        for i in 0..<_items.count {
            let itemWidth = naturalWidths[i] + extraWidthPerItem
            itemFrames.append(CGRect(
                x: itemX,
                y: 0,
                width: itemWidth,
                height: itemHeight
            ))
            itemX += itemWidth
        }
        currentItemFrames = itemFrames

        // Layout the per-item content on both lens layers + the hit-test
        // buttons that sit above. Same x/y for all three so they line
        // up pixel-for-pixel.
        for i in 0..<_items.count {
            let frame = itemFrames[i]
            let visualFrame = frame.offsetBy(dx: -contentOffsetX, dy: 0.0)
            layoutItemContent(
                titleNode: normalTitleNodes[i],
                badgeView: normalBadgeViews[i],
                in: visualFrame,
                transition: transition
            )
            layoutItemContent(
                titleNode: selectedTitleNodes[i],
                badgeView: selectedBadgeViews[i],
                in: visualFrame,
                transition: transition
            )
            transition.updateFrame(node: itemButtons[i], frame: frame)
        }

        // Selection rectangle: the slot of the currently selected item,
        // unless a drag is in flight (then follow the finger).
        var selectionFrame = selectionFrame(for: displayedSelectionProgress, itemFrames: itemFrames)
        if let drag = dragState {
            // Centre the selection rect on the finger, clamp inside the
            // track. The lens itself adds its `inset` margin around this
            // rect, so we work in the same coords as the resting layout.
            let halfWidth = selectionFrame.width / 2.0
            let clampedX = max(thumbInset + halfWidth, min(contentSize.width - thumbInset - halfWidth, drag.currentX))
            selectionFrame.origin.x = clampedX - halfWidth
        }

        let isDark = isDarkAppearance ?? (traitCollection.userInterfaceStyle == .dark)

        liquidLensView.update(
            size: size,
            cornerRadius: resolvedTrackCorner,
            selectionOrigin: selectionFrame.offsetBy(dx: -contentOffsetX, dy: 0.0).origin,
            selectionSize: selectionFrame.size,
            inset: thumbInset,
            isDark: isDark,
            isLifted: pressActive || dragState != nil,
            transition: transition
        )
        ensureSelectionVisible(selectionFrame, animated: transition.isAnimated)
    }

    /// Selection rect in the scroll content coords — used by
    /// `gestureRecognizerShouldBegin` to decide whether the pan should
    /// take ownership.
    private func currentSelectionRect() -> CGRect {
        selectionFrame(for: displayedSelectionProgress, itemFrames: currentItemFrames)
    }

    // MARK: - Subview construction

    private func rebuildItemContent() {
        normalTitleNodes.forEach { $0.removeFromSupernode() }
        selectedTitleNodes.forEach { $0.removeFromSupernode() }
        normalBadgeViews.forEach { $0.removeFromSuperview() }
        selectedBadgeViews.forEach { $0.removeFromSuperview() }
        itemButtons.forEach { $0.removeFromSupernode() }
        normalTitleNodes = []
        selectedTitleNodes = []
        normalBadgeViews = []
        selectedBadgeViews = []
        itemButtons = []

        for item in _items {
            let normal = makeTitleNode(attributedText: makeNormalAttributed(item.title), accessibilityLabel: item.title)
            normalContentNode.addSubnode(normal)
            normalTitleNodes.append(normal)

            let normalBadge = makeBadgeView(value: item.badgeValue)
            normalContentNode.view.addSubview(normalBadge)
            normalBadgeViews.append(normalBadge)

            let selected = makeTitleNode(attributedText: makeSelectedAttributed(item.title), accessibilityLabel: item.title)
            selectedContentHostNode.addSubnode(selected)
            selectedTitleNodes.append(selected)

            let selectedBadge = makeBadgeView(value: item.badgeValue)
            selectedContentHostNode.view.addSubview(selectedBadge)
            selectedBadgeViews.append(selectedBadge)

            let button = SegmentedItemControlNode()
            if let badgeValue = item.badgeValue, !badgeValue.isEmpty {
                button.accessibilityLabel = "\(item.title), \(badgeValue)"
            } else {
                button.accessibilityLabel = item.title
            }
            button.isAccessibilityElement = true
            button.accessibilityTraits = [.button]
            button.addTarget(self, action: #selector(itemButtonPressed(_:)), forControlEvents: .touchUpInside)
            button.onHighlightChanged = { [weak self, weak button] highlighted in
                guard let self, let button else { return }
                self.handleItemHighlightChange(highlighted: highlighted, on: button)
            }
            contentHostNode.addSubnode(button)
            itemButtons.append(button)
        }
        updateItemControlStates()
    }

    private func updateItemControlStates() {
        for (index, button) in itemButtons.enumerated() {
            button.isEnabled = isEnabled
            var traits: UIAccessibilityTraits = [.button]
            if index == _selectedIndex {
                traits.insert(.selected)
            }
            if !isEnabled {
                traits.insert(.notEnabled)
            }
            button.accessibilityTraits = traits
        }
    }

    private func makeBadgeView(value: String?) -> NavigationBarBadgeView {
        let badgeView = NavigationBarBadgeView()
        badgeView.text = value ?? ""
        badgeView.isUserInteractionEnabled = false
        return badgeView
    }

    private func makeTitleNode(attributedText: NSAttributedString, accessibilityLabel: String) -> ASTextNode {
        let node = ASTextNode()
        node.attributedText = attributedText
        node.maximumNumberOfLines = 1
        node.truncationMode = .byTruncatingTail
        node.view.isUserInteractionEnabled = false
        node.view.accessibilityLabel = accessibilityLabel
        return node
    }

    private func titleSize(for node: ASTextNode) -> CGSize {
        guard let attributedText = node.attributedText, attributedText.length > 0 else {
            return .zero
        }
        let rect = attributedText.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    private func makeNormalAttributed(_ title: String) -> NSAttributedString {
        return NSAttributedString(string: title, attributes: [
            .font: UIFont.aetherScaledSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: theme.textColor,
            .paragraphStyle: Self.centeredParagraphStyle
        ])
    }

    private func makeSelectedAttributed(_ title: String) -> NSAttributedString {
        return NSAttributedString(string: title, attributes: [
            .font: UIFont.aetherScaledSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: theme.selectedTextColor,
            .paragraphStyle: Self.centeredParagraphStyle
        ])
    }

    private static let centeredParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    // MARK: - Press feedback

    private func handleItemHighlightChange(highlighted: Bool, on button: SegmentedItemControlNode) {
        guard let index = itemButtons.firstIndex(of: button) else { return }
        if _selectedIndex == index {
            // Pressing the already-selected item triggers the lens lift —
            // on iOS 26+ that's the native elastic deformation; on legacy
            // the lens scales+blurs its mask blob to mimic it.
            if pressActive != highlighted {
                pressActive = highlighted
                updateLayoutInternal(transition: .animated(duration: 0.25, curve: .spring))
            }
        } else if highlighted {
            UIView.animate(withDuration: 0.2) {
                button.view.alpha = 0.5
            }
        } else {
            UIView.animate(withDuration: 0.2) {
                button.view.alpha = 1.0
            }
        }
    }

    // MARK: - Tap

    @objc private func itemButtonPressed(_ button: SegmentedItemControlNode) {
        guard isEnabled else { return }
        guard let index = itemButtons.firstIndex(of: button) else { return }
        guard index != _selectedIndex else { return }
        selectedIndexShouldChange(index) { [weak self] commit in
            guard let self, commit else { return }
            self._selectedIndex = index
            self.selectionProgress = nil
            self.updateItemControlStates()
            self.selectedIndexChanged(index)
            self.updateLayoutInternal(transition: .animated(duration: 0.4, curve: .spring))
        }
    }

    // MARK: - Drag-to-scrub

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard isEnabled else { return }
        let location = recognizer.location(in: contentHostView)
        switch recognizer.state {
        case .began:
            selectionProgress = nil
            dragState = DragState(currentX: location.x)
            updateLayoutInternal(transition: .immediate)
        case .changed:
            dragState?.currentX = location.x
            updateLayoutInternal(transition: .immediate)
        case .ended:
            // Snap to the nearest item slot.
            let endingState = dragState
            dragState = nil
            if let endingState {
                let snappedIndex = nearestItemIndex(to: endingState.currentX)
                if snappedIndex != _selectedIndex {
                    selectedIndexShouldChange(snappedIndex) { [weak self] commit in
                        guard let self else { return }
                        if commit {
                            self._selectedIndex = snappedIndex
                            self.selectionProgress = nil
                            self.updateItemControlStates()
                            self.selectedIndexChanged(snappedIndex)
                            self.updateLayoutInternal(transition: .animated(duration: 0.4, curve: .spring))
                        } else {
                            self.updateLayoutInternal(transition: .immediate)
                        }
                    }
                } else {
                    updateLayoutInternal(transition: .animated(duration: 0.4, curve: .spring))
                }
            } else {
                updateLayoutInternal(transition: .immediate)
            }
        case .cancelled, .failed:
            dragState = nil
            updateLayoutInternal(transition: .immediate)
        default:
            break
        }
    }
}

// MARK: - Pan gesture delegate

extension AetherSegmentedControl: UIGestureRecognizerDelegate {
    // Conformance present so `pan.delegate = self` works; the actual
    // `gestureRecognizerShouldBegin` lives on the class so it can also
    // serve as an override of UIView's same-named method.
}

// MARK: - Scroll view delegate

extension AetherSegmentedControl: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateLayoutInternal(transition: .immediate)
    }
}

// MARK: - Highlight-tracking item control

private final class SegmentedItemControlNode: AetherControlNode {
    var onHighlightChanged: ((Bool) -> Void)?

    override var isHighlighted: Bool {
        didSet {
            if oldValue != isHighlighted {
                onHighlightChanged?(isHighlighted)
            }
        }
    }
}
