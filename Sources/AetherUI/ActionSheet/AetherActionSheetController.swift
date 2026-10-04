import UIKit
import AsyncDisplayKit

/// A floating glass menu of pill actions. Pass a source view to make the
/// surface expand from the trigger and return to it on dismissal.
open class AetherActionSheetController: ASDKViewController<ASDisplayNode>, UIViewControllerTransitioningDelegate {
    public var theme: AetherActionSheetTheme {
        didSet { rootView?.theme = theme }
    }

    /// The trigger whose visible surface becomes the menu during transition.
    /// Set this before presenting; it must belong to the presenting window.
    public weak var sourceView: UIView? {
        didSet { rootView?.sourceView = sourceView }
    }

    /// Fires once after the closing animation. The argument is true for an
    /// outside tap or Escape, and false for a programmatic dismissal.
    public var dismissed: ((Bool) -> Void)?

    private var groups: [AetherActionSheetItemGroup] = []
    private var groupOverlayViews: [Int: UIView] = [:]
    private var groupOverlayNodes: [Int: ASDisplayNode] = [:]
    private var isDismissed = false
    private var isDismissing = false
    private var pendingDismissCompletion: (() -> Void)?

    private var rootView: AetherActionSheetControllerView? {
        isViewLoaded ? (view as? AetherActionSheetControllerView) : nil
    }

    public init(theme: AetherActionSheetTheme = .light, sourceView: UIView? = nil) {
        self.theme = theme
        self.sourceView = sourceView
        let initialTheme = theme
        super.init(node: ASDisplayNode(viewBlock: {
            AetherActionSheetControllerView(theme: initialTheme)
        }))
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .coverVertical
        transitioningDelegate = self
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        super.loadView()
        guard let root = rootView else { return }
        root.sourceView = sourceView
        root.dismiss = { [weak self] cancelled in
            guard let self, !self.isDismissed else { return }
            self.isDismissed = true
            self.dismissed?(cancelled)
            let completion = self.pendingDismissCompletion
            self.pendingDismissCompletion = nil
            self.presentingViewController?.dismiss(animated: false, completion: completion)
        }
        root.setGroups(groups)
        root.setGroupOverlayViews(groupOverlayViews)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !isDismissing else { return }
        rootView?.animateIn()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            rootView?.restoreSourcePresentation()
        }
    }

    public func setItemGroups(_ groups: [AetherActionSheetItemGroup]) {
        self.groups = groups
        rootView?.setGroups(groups)
    }

    public func updateItem(
        groupIndex: Int,
        itemIndex: Int,
        _ transform: (AetherActionSheetItem) -> AetherActionSheetItem
    ) {
        guard groups.indices.contains(groupIndex),
              groups[groupIndex].items.indices.contains(itemIndex) else { return }
        var items = groups[groupIndex].items
        items[itemIndex] = transform(items[itemIndex])
        groups[groupIndex] = AetherActionSheetItemGroup(items: items)
        rootView?.updateItem(groupIndex: groupIndex, itemIndex: itemIndex, with: items[itemIndex])
    }

    public func setItemGroupOverlayView(groupIndex: Int, view: UIView?) {
        groupOverlayViews[groupIndex] = view
        rootView?.setItemGroupOverlayView(groupIndex: groupIndex, view: view)
    }

    public func setItemGroupOverlayNode(groupIndex: Int, node: ASDisplayNode?) {
        groupOverlayNodes[groupIndex] = node
        setItemGroupOverlayView(groupIndex: groupIndex, view: node?.view)
    }

    public func dismissAnimated() {
        guard !isDismissing, !isDismissed else { return }
        isDismissing = true
        loadViewIfNeeded()
        rootView?.animateOut(cancelled: false)
    }

    open override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        guard flag, presentingViewController != nil, !isDismissed else {
            super.dismiss(animated: flag, completion: completion)
            return
        }
        if let completion {
            let previous = pendingDismissCompletion
            pendingDismissCompletion = {
                previous?()
                completion()
            }
        }
        dismissAnimated()
    }

    open override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(action: #selector(escapePressed), input: UIKeyCommand.inputEscape),
            UIKeyCommand(action: #selector(escapePressed), input: "W", modifierFlags: .command)
        ]
    }

    @objc private func escapePressed() {
        rootView?.animateOut(cancelled: true)
    }

    public func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        AetherActionSheetAttachmentAnimator()
    }
}

private final class AetherActionSheetAttachmentAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.001
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let targetController = transitionContext.viewController(forKey: .to),
              let target = transitionContext.view(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }
        target.frame = transitionContext.finalFrame(for: targetController)
        transitionContext.containerView.addSubview(target)
        target.layoutIfNeeded()
        transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
    }
}

// MARK: - Root view

final class AetherActionSheetControllerView: UIView, AetherAppearanceConsumer {
    var theme: AetherActionSheetTheme {
        didSet {
            dimView.backgroundColor = theme.dimColor
            card.legacySurfaceColorOverride = theme.cardBackgroundColor
            setGroups(groups)
            updateTintOverlay(for: AetherAppearance.runtimeCurrent.style)
        }
    }

    weak var sourceView: UIView?
    var dismiss: (Bool) -> Void = { _ in }

    private let dimView = UIView()
    private let card = GlassBackgroundView(style: .regular)
    private let tintOverlay = UIView()
    private let scrollView = UIScrollView()
    private let containerView = UIView()
    private var groups: [AetherActionSheetItemGroup] = []
    private var groupViews: [AetherActionSheetItemGroupView] = []
    private var groupOverlayViews: [Int: UIView] = [:]
    private var sourceLease: SourcePresentationLease?
    private var bloomHost: ContextMenuGlassmorphicTransitionView?
    private var sourceFrame: CGRect?
    private var targetCardFrame: CGRect = .zero
    private var isAnimatingGeometry = false
    private var hasStartedPresentation = false
    private var isClosing = false
    private var isUserInteractionReady = false
    private var transitionProgress: CGFloat = 0
    private var transitionLink: CADisplayLink?
    private var transitionStartTime: CFTimeInterval = 0
    private var transitionDuration: TimeInterval = 0
    private var transitionFrom: CGFloat = 0
    private var transitionTo: CGFloat = 1
    private var transitionCompletion: (() -> Void)?

    private static let cardCornerRadius: CGFloat = 38.0
    private static let horizontalPadding: CGFloat = 16.0
    private static let topPadding: CGFloat = 8.0
    private static let bottomPadding: CGFloat = 16.0
    private static let groupSpacing: CGFloat = 8.0
    private static let horizontalMargin: CGFloat = 24.0
    private static let verticalMargin: CGFloat = 12.0
    private static let maxCardWidth: CGFloat = 420.0

    init(theme: AetherActionSheetTheme) {
        self.theme = theme
        super.init(frame: .zero)

        dimView.backgroundColor = theme.dimColor
        dimView.alpha = 0
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimTapped)))
        addSubview(dimView)

        card.surfaceRole = .card
        card.glassIsInteractive = true
        card.glassCornerRadius = Self.cardCornerRadius
        card.legacySurfaceColorOverride = theme.cardBackgroundColor
        card.alpha = 0
        addSubview(card)

        updateTintOverlay(for: AetherAppearance.runtimeCurrent.style)
        card.contentView.addSubview(tintOverlay)
        scrollView.alwaysBounceVertical = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.showsVerticalScrollIndicator = true
        scrollView.isUserInteractionEnabled = false
        card.contentView.addSubview(scrollView)
        scrollView.addSubview(containerView)
        AetherAppearanceConsumerRegistry.register(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        transitionLink?.invalidate()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else {
            return
        }
        setGroups(groups)
    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated _: Bool) {
        updateTintOverlay(for: appearance.style)
    }

    private func updateTintOverlay(for style: AetherAppearanceStyle) {
        // Match the Alert's material treatment: the legacy renderer already
        // applies its tint, so an extra opaque layer would cover its blur.
        tintOverlay.backgroundColor = style == .legacy || GlassCompatibility.isLiquidDesignAvailable
            ? .clear
            : theme.cardBackgroundColor
    }

    func setGroups(_ groups: [AetherActionSheetItemGroup]) {
        self.groups = groups
        groupViews.forEach { $0.removeFromSuperview() }
        groupViews = groups.map { group in
            let view = AetherActionSheetItemGroupView(theme: theme)
            view.setItems(group.items)
            containerView.addSubview(view)
            return view
        }
        applyGroupOverlayViews()
        setNeedsLayout()
    }

    func updateItem(groupIndex: Int, itemIndex: Int, with item: AetherActionSheetItem) {
        guard groupViews.indices.contains(groupIndex),
              groups[groupIndex].items.indices.contains(itemIndex) else { return }
        var items = groups[groupIndex].items
        items[itemIndex] = item
        groups[groupIndex] = AetherActionSheetItemGroup(items: items)
        groupViews[groupIndex].updateItem(at: itemIndex, with: item)
        setNeedsLayout()
    }

    func setItemGroupOverlayView(groupIndex: Int, view: UIView?) {
        groupOverlayViews[groupIndex] = view
        applyGroupOverlayViews()
    }

    func setGroupOverlayViews(_ views: [Int: UIView]) {
        groupOverlayViews = views
        applyGroupOverlayViews()
    }

    private func applyGroupOverlayViews() {
        for (index, groupView) in groupViews.enumerated() {
            groupView.setOverlayView(groupOverlayViews[index])
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimView.frame = bounds
        let safeInsets = safeAreaInsets
        let maximumCardWidth = min(
            Self.maxCardWidth,
            max(0, bounds.width - safeInsets.left - safeInsets.right - Self.horizontalMargin * 2)
        )
        let cardWidth = preferredCardWidth(maximum: maximumCardWidth)
        let innerWidth = max(0, cardWidth - Self.horizontalPadding * 2)
        var y = Self.topPadding
        for (index, view) in groupViews.enumerated() {
            let height = view.preferredHeight(constrainedWidth: innerWidth)
            view.frame = CGRect(x: Self.horizontalPadding, y: y, width: innerWidth, height: height)
            y += height
            if index < groupViews.count - 1 { y += Self.groupSpacing }
        }
        let contentHeight = y + Self.bottomPadding
        let safeTop = safeInsets.top + Self.verticalMargin
        let safeBottom = bounds.height - safeInsets.bottom - Self.verticalMargin
        let availableHeight = max(0, safeBottom - safeTop)
        let cardHeight = min(contentHeight, availableHeight)
        let source = currentSourceFrame()
        let cardX: CGFloat
        let cardY: CGFloat
        if let source {
            // Preserve the same source edge and opening direction as
            // ContextMenuController's source-menu placement.
            let left = max(safeInsets.left, 12)
            let right = bounds.width - max(safeInsets.right, 12)
            let centeredX = source.midX - cardWidth / 2
            let leadingX = source.minX
            let trailingX = source.maxX - cardWidth
            let fitsCentered = centeredX >= left && centeredX + cardWidth <= right
            let fitsLeading = leadingX >= left && leadingX + cardWidth <= right
            let fitsTrailing = trailingX >= left && trailingX + cardWidth <= right
            let preferredX: CGFloat
            if fitsCentered {
                preferredX = centeredX
            } else if source.midX > bounds.midX && fitsTrailing {
                preferredX = trailingX
            } else if source.midX <= bounds.midX && fitsLeading {
                preferredX = leadingX
            } else {
                preferredX = fitsTrailing ? trailingX : leadingX
            }
            cardX = min(max(left, preferredX), right - cardWidth)

            let downward = source.minY
            let upward = source.maxY - cardHeight
            if downward + cardHeight <= safeBottom {
                cardY = max(safeTop, downward)
            } else if upward >= safeTop {
                cardY = upward
            } else {
                cardY = min(max(safeTop, downward), safeBottom - cardHeight)
            }
        } else {
            cardX = floor((bounds.width - cardWidth) / 2)
            cardY = safeTop + floor((availableHeight - cardHeight) / 2)
        }
        targetCardFrame = CGRect(x: floor(cardX), y: floor(cardY), width: cardWidth, height: cardHeight)

        if !isAnimatingGeometry && bloomHost == nil {
            card.frame = targetCardFrame
            card.glassCornerRadius = Self.cardCornerRadius
            card.update(size: card.bounds.size, cornerRadius: Self.cardCornerRadius, transition: .immediate)
        }
        tintOverlay.frame = card.bounds
        if let bloomHost {
            bloomHost.frame = bounds
            scrollView.frame = bloomHost.liveMenuContentView.bounds
        } else if !isAnimatingGeometry {
            scrollView.frame = card.bounds
        }
        containerView.frame = CGRect(x: 0, y: 0, width: cardWidth, height: contentHeight)
        scrollView.contentSize = containerView.bounds.size
        scrollView.alwaysBounceVertical = contentHeight > cardHeight + 0.5
    }

    private func preferredCardWidth(maximum: CGFloat) -> CGFloat {
        guard maximum > 0 else { return 0 }
        let bodyFont = UIFont.aetherScaledSystemFont(
            ofSize: floor(theme.baseFontSize), weight: .medium, compatibleWith: traitCollection
        )
        let headingFont = UIFont.aetherScaledSystemFont(
            ofSize: floor(theme.baseFontSize * 19.0 / 17.0), compatibleWith: traitCollection
        )
        var widest: CGFloat = 0
        for group in groups {
            for item in group.items {
                let title: String
                let font: UIFont
                let extra: CGFloat
                switch item {
                case let button as AetherActionSheetButtonItem:
                    title = button.title
                    font = bodyFont
                    extra = 64
                case let text as AetherActionSheetTextItem:
                    title = text.title
                    font = headingFont
                    extra = 48
                case let toggle as AetherActionSheetSwitchItem:
                    title = toggle.title
                    font = bodyFont
                    extra = 130
                case let checkbox as AetherActionSheetCheckboxItem:
                    title = checkbox.title + checkbox.label
                    font = bodyFont
                    extra = 100
                default:
                    return maximum
                }
                widest = max(widest, ceil((title as NSString).size(withAttributes: [.font: font]).width) + extra)
            }
        }
        return min(maximum, max(220, widest))
    }

    private func currentSourceFrame() -> CGRect? {
        guard let sourceView,
              sourceView.window != nil,
              sourceView.window === window else { return sourceFrame }
        let frame = sourceView.convert(sourceView.bounds, to: self)
        guard frame.width > 0, frame.height > 0,
              frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite else { return sourceFrame }
        return frame
    }

    func animateIn() {
        guard !hasStartedPresentation, !isClosing else { return }
        hasStartedPresentation = true
        layoutIfNeeded()
        if let sourceView, sourceView.window === window {
            let lease = SourcePresentationLease(
                sourceID: ObjectIdentifier(sourceView),
                originalView: sourceView,
                overlayView: self
            )
            sourceLease = lease
            sourceFrame = lease?.sourceFrameInOverlay
            lease?.acquire()
        }
        if let sourceFrame, let sourceLease {
            let host = ContextMenuGlassmorphicTransitionView(
                sourceFrameInOverlay: sourceFrame,
                targetMenuFrameInOverlay: targetCardFrame,
                finalCornerRadius: Self.cardCornerRadius,
                sourceCornerRadius: sourceView?.layer.cornerRadius ?? 0,
                sourceMode: .leasedGlassSource,
                isDark: theme.backgroundType == .dark,
                surfaceRole: .card,
                legacySurfaceColorOverride: theme.cardBackgroundColor
            )
            host.frame = bounds
            host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            bloomHost = host
            card.isHidden = true
            scrollView.removeFromSuperview()
            scrollView.frame = CGRect(origin: .zero, size: targetCardFrame.size)
            host.liveMenuContentView.addSubview(scrollView)
            addSubview(host)
            sourceLease.attachProxy(to: host.sourceProxyContainer)
            host.prepareSourceContentSnapshots(regions: sourceLease.sourceContentRegions)
            scrollView.layoutIfNeeded()
            host.prepareMenuContentSnapshots(from: scrollView)
            isAnimatingGeometry = true
            dimView.alpha = 0
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.dimView.alpha = 1
            }
            host.animateExpand(
                duration: ContextMenuController.glassmorphicTiming.openDuration,
                damping: AetherMotion.contextMenu.presentation.dampingRatio
            ) { [weak self] in
                guard let self, !self.isClosing else { return }
                self.isAnimatingGeometry = false
                host.liveMenuContentView.isUserInteractionEnabled = true
                self.scrollView.isUserInteractionEnabled = true
                self.isUserInteractionReady = true
            }
            return
        }
        isAnimatingGeometry = true
        card.glassIsInteractive = false
        applyTransition(progress: 0, direction: .opening)
        startTransition(to: 1, direction: .opening) { [weak self] in
            guard let self, !self.isClosing else { return }
            self.isAnimatingGeometry = false
            self.card.frame = self.targetCardFrame
            self.card.update(size: self.card.bounds.size, cornerRadius: Self.cardCornerRadius, transition: .immediate)
            self.scrollView.frame = self.card.bounds
            self.card.glassIsInteractive = true
            self.scrollView.isUserInteractionEnabled = true
            self.isUserInteractionReady = true
        }
    }

    func animateOut(cancelled: Bool) {
        guard !isClosing else { return }
        isClosing = true
        isUserInteractionReady = false
        scrollView.isUserInteractionEnabled = false
        layoutIfNeeded()
        isAnimatingGeometry = true
        if let bloomHost {
            bloomHost.liveMenuContentView.isUserInteractionEnabled = false
            bloomHost.finalMenuGlassSurfaceView.resetGlassInteractionTransform()
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
                self.dimView.alpha = 0
            }
            let duration = bloomHost.supportsSharedSourceReturn && !UIAccessibility.isReduceMotionEnabled
                ? ContextMenuSharedSourceReturn.duration
                : AetherMotion.contextMenu.dismissal.duration
            bloomHost.animateCollapse(
                duration: duration,
                damping: AetherMotion.contextMenu.dismissal.dampingRatio
            ) { [weak self] in
                guard let self else { return }
                self.restoreSourcePresentation()
                self.dismiss(cancelled)
            }
            return
        }
        card.glassIsInteractive = false
        sourceFrame = currentSourceFrame()
        startTransition(to: 0, direction: .closing) { [weak self] in
            guard let self else { return }
            self.restoreSourcePresentation()
            self.dismiss(cancelled)
        }
    }

    private func startTransition(
        to target: CGFloat,
        direction: ContextMenuBloomDirection,
        completion: @escaping () -> Void
    ) {
        transitionLink?.invalidate()
        transitionLink = nil
        transitionCompletion = completion
        transitionFrom = transitionProgress
        transitionTo = target
        let nominalDuration = direction == .opening
            ? AetherMotion.contextMenu.presentation.duration
            : AetherMotion.contextMenu.dismissal.duration
        transitionDuration = (UIAccessibility.isReduceMotionEnabled ? 0.18 : nominalDuration)
            * TimeInterval(abs(target - transitionFrom))
        transitionStartTime = CACurrentMediaTime()
        guard transitionDuration > 0.001 else {
            finishTransition(direction: direction)
            return
        }
        let driver = AetherDisplayLinkTarget { [weak self] link in
            self?.transitionTick(link)
        }
        let link = CADisplayLink(target: driver, selector: #selector(AetherDisplayLinkTarget.tick(_:)))
        let refreshRate = Float(min(120, max(60, UIScreen.main.maximumFramesPerSecond)))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: min(80, refreshRate),
            maximum: refreshRate,
            preferred: refreshRate
        )
        link.add(to: .main, forMode: .common)
        transitionLink = link
    }

    private func transitionTick(_ link: CADisplayLink) {
        let elapsed = max(0, link.timestamp - transitionStartTime)
        let fraction = min(1, CGFloat(elapsed / transitionDuration))
        let direction: ContextMenuBloomDirection = transitionTo > transitionFrom ? .opening : .closing
        let sample = contextMenuLiquidAnimationSample(
            fraction: fraction,
            reduceMotion: UIAccessibility.isReduceMotionEnabled,
            direction: direction
        )
        transitionProgress = transitionFrom + (transitionTo - transitionFrom) * sample.progress
        applyTransition(progress: transitionProgress, direction: direction)
        if fraction >= 1 { finishTransition(direction: direction) }
    }

    private func finishTransition(direction: ContextMenuBloomDirection) {
        transitionLink?.invalidate()
        transitionLink = nil
        transitionProgress = transitionTo
        applyTransition(progress: transitionTo, direction: direction)
        let completion = transitionCompletion
        transitionCompletion = nil
        completion?()
    }

    private func applyTransition(progress rawProgress: CGFloat, direction: ContextMenuBloomDirection) {
        let progress = min(1, max(0, rawProgress))
        let startFrame = sourceFrame ?? targetCardFrame.insetBy(
            dx: targetCardFrame.width * 0.08,
            dy: targetCardFrame.height * 0.08
        )
        let frame = CGRect(
            x: startFrame.minX + (targetCardFrame.minX - startFrame.minX) * progress,
            y: startFrame.minY + (targetCardFrame.minY - startFrame.minY) * progress,
            width: startFrame.width + (targetCardFrame.width - startFrame.width) * progress,
            height: startFrame.height + (targetCardFrame.height - startFrame.height) * progress
        )
        let maxSourceRadius = min(startFrame.width, startFrame.height) / 2
        let visibleSourceRadius = sourceView?.layer.cornerRadius ?? 0
        let sourceRadius = sourceLease == nil
            ? Self.cardCornerRadius
            : min(visibleSourceRadius > 0 ? visibleSourceRadius : maxSourceRadius, maxSourceRadius)
        let radius = sourceRadius + (Self.cardCornerRadius - sourceRadius) * progress
        let contentAlpha = direction == .opening
            ? Self.smoothstep(0.18, 0.58, progress)
            : Self.smoothstep(0.08, 0.72, progress)
        let sourceAlpha = direction == .opening
            ? 1 - Self.smoothstep(0.04, 0.24, progress)
            : 1 - Self.smoothstep(0, 0.46, progress)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.frame = frame
        card.glassCornerRadius = radius
        card.update(size: frame.size, cornerRadius: radius, transition: .immediate)
        tintOverlay.frame = card.bounds
        scrollView.frame = CGRect(
            x: targetCardFrame.minX - frame.minX,
            y: targetCardFrame.minY - frame.minY,
            width: targetCardFrame.width,
            height: targetCardFrame.height
        )
        scrollView.alpha = contentAlpha
        dimView.alpha = Self.smoothstep(0, 0.4, progress)
        card.alpha = sourceLease == nil ? Self.smoothstep(0, 0.3, progress) : 1
        sourceLease?.proxyView.alpha = sourceAlpha
        CATransaction.commit()
    }

    private static func smoothstep(_ start: CGFloat, _ end: CGFloat, _ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, (value - start) / max(0.001, end - start)))
        return t * t * (3 - 2 * t)
    }

    func restoreSourcePresentation() {
        transitionLink?.invalidate()
        transitionLink = nil
        bloomHost?.tearDownGlassEffects()
        sourceLease?.release()
        sourceLease = nil
        bloomHost?.removeFromSuperview()
        bloomHost = nil
    }

    @objc private func dimTapped() {
        guard isUserInteractionReady else { return }
        window?.endEditing(true)
        animateOut(cancelled: true)
    }
}
