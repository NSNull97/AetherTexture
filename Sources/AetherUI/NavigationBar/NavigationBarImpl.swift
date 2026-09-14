import UIKit
import AsyncDisplayKit

final class NavigationSeparatedButtonGlueAnimator: NSObject {
    private weak var container: UIView?
    private var groups: [GlassControlGroup]
    private let fromContainerFrame: CGRect
    private let toContainerFrame: CGRect
    private let fromFrames: [CGRect]
    private let toFrames: [CGRect]
    private let appearing: Bool
    private let duration: CFTimeInterval
    private var updateContainerEffects: ((CGSize) -> Void)?
    private var completion: (() -> Void)?
    private var displayLink: CADisplayLink?
    private var startTimestamp: CFTimeInterval?
    private var didComplete = false

    init(
        container: UIView,
        groups: [GlassControlGroup],
        fromContainerFrame: CGRect,
        toContainerFrame: CGRect,
        fromFrames: [CGRect],
        toFrames: [CGRect],
        appearing: Bool,
        duration: Double,
        updateContainerEffects: @escaping (CGSize) -> Void,
        completion: @escaping () -> Void
    ) {
        self.container = container
        self.groups = groups
        self.fromContainerFrame = fromContainerFrame
        self.toContainerFrame = toContainerFrame
        self.fromFrames = fromFrames
        self.toFrames = toFrames
        self.appearing = appearing
        self.duration = max(0.001, duration)
        self.updateContainerEffects = updateContainerEffects
        self.completion = completion
        super.init()
    }

    deinit {
        invalidate()
    }

    var hasActiveDisplayLinkForTesting: Bool {
        displayLink != nil
    }

    var retainedGroupCountForTesting: Int {
        groups.count
    }

    func start() {
        guard !didComplete else { return }
        apply(progress: 0.0)
        let target = AetherDisplayLinkTarget { [weak self] displayLink in
            self?.tick(displayLink)
        }
        let displayLink = CADisplayLink(
            target: target,
            selector: #selector(AetherDisplayLinkTarget.tick(_:))
        )
        if #available(iOS 15.0, *) {
            let maximumFramesPerSecond = UIScreen.main.maximumFramesPerSecond
            let preferred = Float(min(120, max(60, maximumFramesPerSecond > 0 ? maximumFramesPerSecond : 120)))
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60.0,
                maximum: preferred,
                preferred: preferred
            )
        }
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    func invalidate() {
        didComplete = true
        stopDisplayLink()
        releaseRetainedResources()
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        if startTimestamp == nil {
            startTimestamp = displayLink.timestamp
        }
        let elapsed = displayLink.timestamp - (startTimestamp ?? displayLink.timestamp)
        let progress = min(1.0, max(0.0, elapsed / duration))
        apply(progress: CGFloat(progress))
        if progress >= 1.0 {
            finish()
        }
    }

    private func finish() {
        guard !didComplete else {
            return
        }
        didComplete = true
        stopDisplayLink()
        applyEndpoint()
        let completion = self.completion
        releaseRetainedResources()
        completion?()
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func releaseRetainedResources() {
        groups.removeAll(keepingCapacity: false)
        updateContainerEffects = nil
        completion = nil
    }

    private func applyEndpoint() {
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let container {
                removeCompetingGeometryAnimations(from: container.layer)
                container.frame = toContainerFrame
                updateContainerEffects?(toContainerFrame.size)
            }
            for index in 0 ..< min(groups.count, toFrames.count) {
                removeCompetingGeometryAnimations(from: groups[index].layer)
                groups[index].frame = toFrames[index]
            }
            CATransaction.commit()
        }
    }

    private func removeCompetingGeometryAnimations(from layer: CALayer) {
        for key in layer.animationKeys() ?? [] {
            if key == "position" || key == "bounds" || key.hasPrefix("bounds.") {
                layer.removeAnimation(forKey: key)
            }
        }
    }

    private func apply(progress: CGFloat) {
        // Use one C2-continuous path in both directions. Reversing the same
        // smootherstep keeps split/merge motion perfectly reciprocal and
        // removes the high-velocity endpoint of the old cubic ease-in.
        let eased = appearing
            ? smootherStep(progress)
            : 1.0 - smootherStep(1.0 - progress)
        if let container {
            let frame = interpolate(from: fromContainerFrame, to: toContainerFrame, progress: eased)
            container.frame = frame
            updateContainerEffects?(frame.size)
        }
        for index in 0 ..< min(groups.count, fromFrames.count, toFrames.count) {
            groups[index].frame = interpolate(from: fromFrames[index], to: toFrames[index], progress: eased)
        }
    }

    private func interpolate(from: CGRect, to: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: from.minX + (to.minX - from.minX) * progress,
            y: from.minY + (to.minY - from.minY) * progress,
            width: from.width + (to.width - from.width) * progress,
            height: from.height + (to.height - from.height) * progress
        )
    }

    private func smootherStep(_ value: CGFloat) -> CGFloat {
        let value = max(0.0, min(1.0, value))
        return value * value * value * (value * (value * 6.0 - 15.0) + 10.0)
    }
}

private final class AetherNavigationBarLegacyButtonView: UIControl {
    private let imageNode = ASImageNode()
    private let titleNode = ASTextNode()
    private var image: UIImage?
    private var title: String?
    private var titleFont = UIFont.aetherScaledSystemFont(ofSize: 17.0)

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
        imageNode.contentMode = .center
        imageNode.view.isUserInteractionEnabled = false
        addSubview(imageNode.view)

        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        titleNode.view.isUserInteractionEnabled = false
        addSubview(titleNode.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        imageNode.view.removeFromSuperview()
        titleNode.view.removeFromSuperview()
    }

    func configure(image: UIImage?, title: String?, font: UIFont) {
        self.image = image
        self.title = title
        self.titleFont = font
        isAccessibilityElement = true
        accessibilityLabel = title
        updateContent()
        setNeedsLayout()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateContent()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let imageSize = image?.size ?? .zero
        let titleSize = Self.titleSize(title, font: titleFont)
        let spacing: CGFloat = imageSize.width > 0.0 && titleSize.width > 0.0 ? 6.0 : 0.0
        let width = ceil(imageSize.width + spacing + titleSize.width)
        let height = ceil(max(22.0, imageSize.height, titleSize.height))
        return CGSize(width: max(30.0, width), height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let imageSize = image?.size ?? .zero
        let titleSize = Self.titleSize(title, font: titleFont)
        let spacing: CGFloat = imageSize.width > 0.0 && titleSize.width > 0.0 ? 6.0 : 0.0
        let totalWidth = imageSize.width + spacing + titleSize.width
        var x = floor((bounds.width - totalWidth) / 2.0)

        if imageSize.width > 0.0 {
            imageNode.frame = CGRect(
                x: x,
                y: floor((bounds.height - imageSize.height) / 2.0),
                width: imageSize.width,
                height: imageSize.height
            )
            x += imageSize.width + spacing
        } else {
            imageNode.frame = .zero
        }

        if titleSize.width > 0.0 {
            titleNode.frame = CGRect(
                x: x,
                y: floor((bounds.height - titleSize.height) / 2.0),
                width: titleSize.width,
                height: titleSize.height
            )
        } else {
            titleNode.frame = .zero
        }
    }

    private func updateContent() {
        imageNode.image = image?.withRenderingMode(.alwaysTemplate)
        imageNode.tintColor = tintColor
        titleNode.attributedText = Self.attributedTitle(title, font: titleFont, color: tintColor)
    }

    private static func attributedTitle(_ title: String?, font: UIFont, color: UIColor) -> NSAttributedString? {
        guard let title, !title.isEmpty else { return nil }
        return NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
    }

    private static func titleSize(_ title: String?, font: UIFont) -> CGSize {
        guard let title, !title.isEmpty else { return .zero }
        let size = (title as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }
}

/// Full UIKit implementation of NavigationBarView.
/// Pure UIKit implementation.
public final class NavigationBarImpl: UIView, NavigationBarView {
    // MARK: - Subviews

    public let backgroundView: NavigationBackgroundView
    public let stripeNode: ASDisplayNode
    private let clippingView: SparseView
    private let buttonsContainerView: UIView
    private let buttonLayer: AetherNavigationBarButtonLayer

    private let backButtonView: NavigationBackButtonView
    private let backArrowNode: ASImageNode
    private var backArrowView: UIView { backArrowNode.view }
    private let titleNode: ASTextNode
    private let subtitleNode: ASTextNode
    private let leftButtonContainer: UIView
    private let rightButtonContainer: UIView
    private let leftButtonGlassContainer: GlassBackgroundContainerView
    private let rightButtonGlassContainer: GlassBackgroundContainerView
    /// Persistent glass group used for the left bar button items in glass mode
    /// (direct port equivalent of `leftButtonsBackgroundView`).
    private var leftButtonsGroup: GlassControlGroup?
    private var leftAdditionalButtonsGroups: [GlassControlGroup] = []
    /// Persistent glass group used for the right bar button items in glass mode.
    private var rightButtonsGroup: GlassControlGroup?
    private var rightAdditionalButtonsGroups: [GlassControlGroup] = []
    public let badgeView: NavigationBarBadgeView
    private var titleContentView: UIView?
    private var automaticBackBadgeContentView: NavigationAutomaticBackBadgeContentView?

    private var _contentView: NavigationBarContentView?
    public var contentView: NavigationBarContentView? { _contentView }
    private weak var pendingAppearingContentView: NavigationBarContentView?
    private var contentViewTransitionGeneration: Int = 0
    private var contentViewTransitionLocksButtonChrome = false

    private var glassBackgroundView: GlassBackgroundView?
    /// Scroll-edge fade effect. Hosts can move it outside the bar so the
    /// floating controls stay above content without the frost covering it.
    private var edgeEffectView: EdgeEffectView?
    public weak var edgeEffectHostView: UIView? {
        didSet {
            guard edgeEffectHostView !== oldValue else {
                return
            }
            rehostEdgeEffectView()
            setNeedsLayout()
        }
    }

    // MARK: - State

    public private(set) var presentationData: NavigationBarPresentationData
    private var validLayout: (size: CGSize, defaultHeight: CGFloat, leftInset: CGFloat, rightInset: CGFloat)?
    private var isSearchModeActive = false
    private var contentHeightOverride: CGFloat?
    private var scrollEdgeAlpha: CGFloat = 0.0
    internal private(set) var lastScrollEdgeTransitionForTesting: ContainedViewLayoutTransition?

    /// Natural height of `titleContentView`, measured during `updateLayout` for
    /// the available width. The title row in `contentHeight(defaultHeight:)`
    /// is grown to `max(defaultHeight, measuredTitleHeight)` so a tall custom
    /// titleView (avatar + multi-line subtitle, etc.) is never clipped to the
    /// standard ~44pt button-row height.
    ///
    /// Buttons (left/right/back) keep their original `defaultHeight` slot at
    /// `y=0` of `buttonsContainerView` and never re-center when the title
    /// grows — only the title centers within the expanded container.
    private var measuredTitleHeight: CGFloat = 0

    public var backPressed: () -> Void = {}
    public var userInfo: Any?

    private static let contentBlurCrossfadeDuration: TimeInterval = AetherMotion.navigationChrome.contentAppearanceDuration
    private static let contentBlurCrossfadeRadius: CGFloat = 10.0
    #if !APPSTORE_SAFE
    private static let transitionBlurAnimationKey = ObfuscatedSymbols.keypath(
        ObfuscatedSymbols.filters,
        ObfuscatedSymbols.gaussianBlur,
        ObfuscatedSymbols.filterRadiusKey
    )
    #endif

    /// Legacy chrome keeps the same alpha / scale / geometry choreography as
    /// Liquid Glass, but its system material must never be supplemented by a
    /// private layer blur. Keep the policy here, at the owner of navigation
    /// transition effects, so callers cannot accidentally opt Legacy back in
    /// by passing a non-zero blur radius.
    private var usesLiquidGlassTransitionBlur: Bool {
        presentationData.theme.appearanceStyle.usesLiquidGlass
    }

    private static func clearOwnedTransitionBlur(from layer: CALayer) {
        #if APPSTORE_SAFE
        // Safe builds cannot install the private Gaussian layer filter, so
        // there is no owned filter or filter-keypath animation to dismantle.
        return
        #else
        for key in layer.animationKeys() ?? [] {
            let animationKeyPath = (layer.animation(forKey: key) as? CAPropertyAnimation)?.keyPath
            if key == transitionBlurAnimationKey
                || animationKeyPath?.contains(ObfuscatedSymbols.gaussianBlur) == true {
                layer.removeAnimation(forKey: key)
            }
        }
        guard let filters = layer.filters else {
            return
        }
        let retainedFilters = filters.filter { candidate in
            guard let object = candidate as? NSObject else {
                return true
            }
            return !object.description.contains(ObfuscatedSymbols.gaussianBlur)
        }
        layer.filters = retainedFilters.isEmpty ? nil : retainedFilters
        #endif
    }

    private static func clearOwnedTransitionBlur(in view: UIView) {
        // UIKit owns the effect view's material filters. We intentionally skip
        // that layer while still walking through its contentView to reach
        // Aether-owned glyph / controls layers beneath it.
        if !(view is UIVisualEffectView) {
            clearOwnedTransitionBlur(from: view.layer)
        }
        for subview in view.subviews {
            clearOwnedTransitionBlur(in: subview)
        }
    }

    private func clearLegacyTransitionBlurState() {
        Self.clearOwnedTransitionBlur(in: clippingView)
        Self.clearOwnedTransitionBlur(in: buttonLayer)
        Self.clearOwnedTransitionBlur(in: leftButtonContainer)
        Self.clearOwnedTransitionBlur(in: rightButtonContainer)
        Self.clearOwnedTransitionBlur(in: backButtonView)
        Self.clearOwnedTransitionBlur(in: backArrowView)
        Self.clearOwnedTransitionBlur(in: badgeView)
    }
    // Navigation chrome has a fixed-height interaction row. It still follows
    // Dynamic Type, but is capped so accessibility categories cannot push the
    // title underneath the buttons or turn a one-line bar into a full-screen
    // header. These are computed from the current traits rather than cached:
    // the content-size category may change while the app is running.
    private var titleFont: UIFont {
        UIFont.aetherScaledSystemFont(
            ofSize: 17.0,
            weight: .semibold,
            maximumPointSize: 28.0,
            compatibleWith: traitCollection
        )
    }

    private var subtitleFont: UIFont {
        UIFont.aetherScaledSystemFont(
            ofSize: 12.0,
            weight: .medium,
            maximumPointSize: 18.0,
            compatibleWith: traitCollection
        )
    }

    public var item: NavigationBarItem? {
        didSet {
            updateItemContent()
        }
    }

    public var previousItem: NavigationPreviousAction? {
        didSet {
            updateBackButton()
        }
    }

    public var enableAutomaticBackButton: Bool = true {
        didSet { updateBackButton() }
    }

    public var secondaryContentHeight: CGFloat = 0.0

    public var isBackgroundVisible: Bool {
        return backgroundView.alpha > 0.01
    }

    public var intrinsicCanTransitionInline: Bool = true
    public var canTransitionInline: Bool {
        return intrinsicCanTransitionInline && !isHidden
    }

    public var passthroughTouches: Bool = false
    public var layoutSuspended: Bool = false
    public var requestContainerLayout: ((ContainedViewLayoutTransition) -> Void)?
    private var titleTransitionMode: Bool = false
    private var titleContentHiddenForTransition: Bool = false
    private var buttonsOnlyTransitionMode: Bool = false
    private var buttonContentHiddenForTransition: Bool = false
    private var buttonMorphTransitionOverride: ContainedViewLayoutTransition?
    private var leftSeparatedButtonGlueAnimator: NavigationSeparatedButtonGlueAnimator?
    private var rightSeparatedButtonGlueAnimator: NavigationSeparatedButtonGlueAnimator?
    private var legacyLeftButtonViewsByID: [BarButtonID: UIView] = [:]
    private var legacyRightButtonViewsByID: [BarButtonID: UIView] = [:]
    private var leftSemanticButtonIDsByObject: [ObjectIdentifier: BarButtonID] = [:]
    private var rightSemanticButtonIDsByObject: [ObjectIdentifier: BarButtonID] = [:]
    private var appearingTitleContentViewIDs = Set<ObjectIdentifier>()
    private var appearingVisualViewIDs = Set<ObjectIdentifier>()
    private var disappearingVisualViewIDs = Set<ObjectIdentifier>()
    private var disappearingVisualInteractionByID: [ObjectIdentifier: Bool] = [:]
    private var disappearingVisualTransformByID: [ObjectIdentifier: CGAffineTransform] = [:]
    private var barButtonContextMenuProviderObserver: NSObjectProtocol?
    private var buttonsRowAlpha: CGFloat = 1.0
    private var currentButtonsRowFrame: CGRect = .zero
    private var outgoingButtonLayerFrame: CGRect?
    private var outgoingButtonLayerCleanup: DispatchWorkItem?

    /// The page's bar can move offscreen before its fixed-duration button
    /// exit finishes (notably an interactive pop to a hidden root bar).
    /// Keep only the external chrome at its source position during that exit.
    internal func prepareButtonLayerVisibility(visible: Bool, transition: ContainedViewLayoutTransition?) {
        if visible {
            outgoingButtonLayerCleanup?.cancel()
            outgoingButtonLayerCleanup = nil
            outgoingButtonLayerFrame = nil
        } else if outgoingButtonLayerFrame == nil,
                  isButtonLayerExternallyHosted, buttonLayer.alpha > 0.01,
                  let transition, transition.isAnimated,
                  !UIAccessibility.isReduceMotionEnabled {
            outgoingButtonLayerFrame = buttonLayer.frame
            let cleanup = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.outgoingButtonLayerFrame = nil
                self.outgoingButtonLayerCleanup = nil
                self.updateButtonLayerFrame(self.currentButtonsRowFrame, transition: .immediate)
                self.updateButtonLayerEffectiveVisibility()
            }
            outgoingButtonLayerCleanup = cleanup
            DispatchQueue.main.asyncAfter(deadline: .now() + transition.duration, execute: cleanup)
        }
    }
    internal var hostsNavigationItemTitleView: Bool = true {
        didSet {
            guard oldValue != hostsNavigationItemTitleView else {
                return
            }
            updateItemContent()
        }
    }

    internal static var defaultButtonHostingMode: AetherNavigationBarButtonHostingMode = .separatedLayer
    internal var buttonHostingMode: AetherNavigationBarButtonHostingMode {
        didSet {
            guard oldValue != buttonHostingMode else {
                return
            }
            installButtonChromeViewsForCurrentHostingMode(preservePresentationLayer: true)
            installTitleContentViewForCurrentHostingMode(preservePresentationLayer: true)
        }
    }

    internal weak var buttonLayerHostView: UIView? {
        didSet {
            guard buttonLayerHostView !== oldValue else {
                return
            }
            installButtonLayerForCurrentHost(preservePresentationLayer: true)
            updateButtonLayerFrame(currentButtonsRowFrame, transition: .immediate)
            updateButtonLayerEffectiveVisibility()
        }
    }

    internal var debugButtonLayer: AetherNavigationBarButtonLayer {
        buttonLayer
    }

    internal var debugButtonsContainerView: UIView {
        buttonsContainerView
    }

    internal var debugEdgeEffectView: EdgeEffectView? {
        edgeEffectView
    }

    internal var debugLegacyBackArrowFrame: CGRect {
        backArrowView.frame
    }

    internal var debugLegacyLeftButtonContainerFrame: CGRect {
        leftButtonContainer.frame
    }

    internal var debugLegacyRightButtonContainerFrame: CGRect {
        rightButtonContainer.frame
    }

    internal var debugLeftSeparatedButtonGlueAnimator: NavigationSeparatedButtonGlueAnimator? {
        leftSeparatedButtonGlueAnimator
    }

    internal var debugRightSeparatedButtonGlueAnimator: NavigationSeparatedButtonGlueAnimator? {
        rightSeparatedButtonGlueAnimator
    }

    override public var alpha: CGFloat {
        didSet {
            updateButtonLayerEffectiveVisibility()
        }
    }

    override public var isHidden: Bool {
        didSet {
            updateButtonLayerEffectiveVisibility()
        }
    }

    public struct ButtonChromeLayout {
        public var leftFrame: CGRect?
        public var rightFrame: CGRect?

        public init(leftFrame: CGRect?, rightFrame: CGRect?) {
            self.leftFrame = leftFrame
            self.rightFrame = rightFrame
        }

        internal func interactivePopPreviewLayout(towards target: ButtonChromeLayout, progress: CGFloat) -> ButtonChromeLayout {
            let interpolationProgress = Self.clampedProgress(progress)
            return ButtonChromeLayout(
                leftFrame: Self.previewFrame(from: leftFrame, to: target.leftFrame, progress: interpolationProgress, anchorsTrailingEdge: false),
                rightFrame: Self.previewFrame(from: rightFrame, to: target.rightFrame, progress: interpolationProgress, anchorsTrailingEdge: true)
            )
        }

        internal func interactivePopMissingTargetScales(towards target: ButtonChromeLayout, progress: CGFloat) -> (left: CGFloat, right: CGFloat) {
            let scale = 1.0 - 0.3 * Self.clampedProgress(progress)
            return (
                left: leftFrame != nil && target.leftFrame == nil ? scale : 1.0,
                right: rightFrame != nil && target.rightFrame == nil ? scale : 1.0
            )
        }

        private static func previewFrame(from source: CGRect?, to target: CGRect?, progress: CGFloat, anchorsTrailingEdge: Bool) -> CGRect? {
            guard let source else {
                return nil
            }
            guard let target else {
                return source
            }
            let resolvedWidth = source.width + (target.width - source.width) * progress
            if anchorsTrailingEdge {
                return CGRect(x: source.maxX - resolvedWidth, y: source.minY, width: resolvedWidth, height: source.height)
            } else {
                return CGRect(x: source.minX, y: source.minY, width: resolvedWidth, height: source.height)
            }
        }

        private static func clampedProgress(_ progress: CGFloat) -> CGFloat {
            return max(0.0, min(1.0, progress))
        }
    }

    /// Amount (in points) by which the scroll-edge frost is extended
    /// upward past the navbar's own top. Set by hosts that sit the bar
    /// below a visual chrome element (e.g. AetherModalController's
    /// grabber) so the frost covers that chrome too.
    public var edgeEffectTopExtension: CGFloat = 0.0 {
        didSet {
            if edgeEffectTopExtension != oldValue {
                setNeedsLayout()
            }
        }
    }

    // MARK: - Init

    public init(presentationData: NavigationBarPresentationData) {
        self.presentationData = presentationData
        let theme = presentationData.theme

        self.backgroundView = NavigationBackgroundView(
            color: theme.backgroundColor,
            enableBlur: theme.enableBackgroundBlur,
            blurStyle: theme.appearanceStyle == .legacy ? .systemChromeMaterial : .systemMaterial
        )
        self.stripeNode = ASDisplayNode()
        self.clippingView = SparseView()
        self.buttonsContainerView = UIView()
        self.buttonLayer = AetherNavigationBarButtonLayer()

        self.backButtonView = NavigationBackButtonView(
            appearanceStyle: theme.appearanceStyle
        )
        self.backArrowNode = ASImageNode()
        self.titleNode = ASTextNode()
        self.subtitleNode = ASTextNode()
        self.leftButtonContainer = UIView()
        self.rightButtonContainer = UIView()
        self.leftButtonGlassContainer = GlassBackgroundContainerView(
            spacing: 7.0,
            appearanceStyle: theme.appearanceStyle
        )
        self.rightButtonGlassContainer = GlassBackgroundContainerView(
            spacing: 7.0,
            appearanceStyle: theme.appearanceStyle
        )
        self.badgeView = NavigationBarBadgeView()
        self.buttonHostingMode = Self.defaultButtonHostingMode

        super.init(frame: .zero)

        let rendererStyle = theme.appearanceStyle
        leftButtonGlassContainer.appearanceStyleOverride = rendererStyle
        rightButtonGlassContainer.appearanceStyleOverride = rendererStyle
        for group in glassButtonGroups(for: .left) + glassButtonGroups(for: .right) {
            group.appearanceStyleOverride = rendererStyle
        }
        backButtonView.appearanceStyleOverride = rendererStyle
        glassBackgroundView?.appearanceStyleOverride = rendererStyle
        edgeEffectView?.appearanceStyleOverride = rendererStyle

        barButtonContextMenuProviderObserver = NotificationCenter.default.addObserver(
            forName: AetherBarButtonItemContextMenuInvalidation.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.barButtonContextMenuProviderDidChange(notification)
        }

        backButtonView.isHidden = true
        backArrowView.isHidden = true

        // Background
        addSubview(backgroundView)

        // Stripe (separator)
        stripeNode.backgroundColor = theme.separatorColor
        addSubview(stripeNode.view)

        // Clipping
        clippingView.clipsToBounds = theme.style != .glass
        addSubview(clippingView)

        // Buttons container
        clippingView.addSubview(buttonsContainerView)

        // Back arrow
        backArrowNode.image = NavigationBarTheme.generateBackArrowImage(color: theme.buttonColor)
        backArrowNode.contentMode = .center

        // Back button
        backButtonView.color = theme.buttonColor
        backButtonView.contentTintColor = theme.buttonColor
        // isDark is applied effectively in updateLayout / traitCollectionDidChange
        // so the glass pill responds to the system dark-mode switch, not just
        // the static theme flag. Kept static here for the very first frame.
        backButtonView.isDark = theme.overallDarkAppearance
        backButtonView.usesGlassStyle = theme.style == .glass
        backButtonView.icon = NavigationBarTheme.generateBackArrowImage(color: theme.buttonColor)
        backButtonView.action = { [weak self] in self?.backButtonPressed() }

        // Title
        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        titleNode.view.isUserInteractionEnabled = false
        buttonsContainerView.addSubview(titleNode.view)

        subtitleNode.maximumNumberOfLines = 1
        subtitleNode.truncationMode = .byTruncatingTail
        subtitleNode.isHidden = true
        subtitleNode.view.isUserInteractionEnabled = false
        buttonsContainerView.addSubview(subtitleNode.view)

        // Left/Right button containers
        leftButtonContainer.clipsToBounds = false
        rightButtonContainer.clipsToBounds = false
        leftButtonContainer.addSubview(leftButtonGlassContainer)
        rightButtonContainer.addSubview(rightButtonGlassContainer)

        installButtonChromeViewsForCurrentHostingMode(preservePresentationLayer: false)

        // Glass style
        if theme.style == .glass {
            setupGlassBackground(theme: theme)
        }

        updateBackButton()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Trait collection

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let contentSizeChanged = previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory
        if contentSizeChanged {
            updateTitleNodes()
            updateBackButton()
        }
        // Interface style change (dark ↔ light) must propagate to glass
        // children that bake `isDark` as a parameter (see updateLayout). A
        // full re-layout is the cheapest way to get every glass subview to
        // re-apply its dark override.
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            // Dismiss any context menu currently anchored to a bar button
            // BEFORE we tear down + rebuild the GlassControlGroup item
            // buttons. Otherwise the menu's `source.view` weak reference
            // ends up dangling, the morph-back-to-source step on dismiss
            // sees a nil/detached source, and the navbar's own group
            // layout gets stuck mid-rebuild.
            dismissPresentedBarButtonContextMenu()
            let isEffectivelyDark = isEffectivelyDarkGlassChrome
            backButtonView.isDark = isEffectivelyDark
            if let layout = validLayout {
                updateLayout(
                    size: layout.size,
                    defaultHeight: layout.defaultHeight,
                    additionalTopHeight: 0,
                    additionalContentHeight: 0,
                    additionalBackgroundHeight: 0,
                    leftInset: layout.leftInset,
                    rightInset: layout.rightInset,
                    appearsHidden: false,
                    isLandscape: false,
                    transition: .immediate
                )
            }
        } else if contentSizeChanged, let layout = validLayout {
            updateLayout(
                size: layout.size,
                defaultHeight: layout.defaultHeight,
                additionalTopHeight: 0,
                additionalContentHeight: 0,
                additionalBackgroundHeight: 0,
                leftInset: layout.leftInset,
                rightInset: layout.rightInset,
                appearsHidden: false,
                isLandscape: false,
                transition: .immediate
            )
        }
    }

    // MARK: - Hit Testing

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if passthroughTouches {
            // Only respond to touches on interactive elements
            let result = super.hitTest(point, with: event)
            if result === self || result === clippingView || result === buttonsContainerView || result === buttonLayer {
                return nil
            }
            return result
        }
        return super.hitTest(point, with: event)
    }

    private var usesSeparatedButtonHosting: Bool {
        buttonHostingMode == .separatedLayer
    }

    private var isButtonLayerExternallyHosted: Bool {
        usesSeparatedButtonHosting && buttonLayerHostView != nil && buttonLayer.superview !== self
    }

    private var buttonChromeViews: [UIView] {
        [backArrowView, backButtonView, leftButtonContainer, rightButtonContainer, badgeView]
    }

    private func resolvedButtonLayerHostView() -> UIView {
        buttonLayerHostView ?? self
    }

    private func buttonLayerFrame(for rowFrame: CGRect) -> CGRect {
        if let outgoingButtonLayerFrame { return outgoingButtonLayerFrame }
        guard let buttonLayerHostView else {
            return rowFrame
        }
        if superview != nil {
            return convert(rowFrame, to: buttonLayerHostView)
        }
        return CGRect(
            x: frame.minX + rowFrame.minX,
            y: frame.minY + rowFrame.minY,
            width: rowFrame.width,
            height: rowFrame.height
        )
    }

    private func installButtonLayerForCurrentHost(preservePresentationLayer: Bool) {
        guard usesSeparatedButtonHosting else {
            buttonLayer.isHidden = true
            return
        }

        let hostView = resolvedButtonLayerHostView()
        if buttonLayer.superview !== hostView {
            AetherNavigationBarButtonLayer.reparentPreservingPresentation(
                view: buttonLayer,
                from: buttonLayer.superview,
                to: hostView,
                targetFrame: buttonLayerFrame(for: currentButtonsRowFrame),
                preservePresentationLayer: preservePresentationLayer
            )
        }
        updateButtonLayerEffectiveVisibility()
    }

    private func installButtonChromeViewsForCurrentHostingMode(preservePresentationLayer: Bool) {
        installButtonLayerForCurrentHost(preservePresentationLayer: preservePresentationLayer)

        let hostView: UIView = usesSeparatedButtonHosting ? buttonLayer : buttonsContainerView

        for view in buttonChromeViews where view.superview !== hostView {
            AetherNavigationBarButtonLayer.reparentPreservingPresentation(
                view: view,
                from: view.superview,
                to: hostView,
                targetFrame: view.frame,
                preservePresentationLayer: preservePresentationLayer
            )
        }

        if !usesSeparatedButtonHosting {
            buttonLayer.removeAllButtonPlacements(detachViews: false)
        }
    }

    private func installTitleContentViewForCurrentHostingMode(preservePresentationLayer: Bool) {
        guard let titleContentView else {
            buttonLayer.removeButtonPlacement(id: ButtonChromePlacementID.titleContentView, detachView: false)
            return
        }

        installButtonLayerForCurrentHost(preservePresentationLayer: preservePresentationLayer)
        let hostView: UIView = usesSeparatedButtonHosting ? buttonLayer : buttonsContainerView
        if titleContentView.superview !== hostView {
            AetherNavigationBarButtonLayer.reparentPreservingPresentation(
                view: titleContentView,
                from: titleContentView.superview,
                to: hostView,
                targetFrame: titleContentView.frame,
                preservePresentationLayer: preservePresentationLayer
            )
        }
        if !usesSeparatedButtonHosting {
            buttonLayer.removeButtonPlacement(id: ButtonChromePlacementID.titleContentView, detachView: false)
        }
    }

    private func updateButtonsRowFrame(_ frame: CGRect, transition: ContainedViewLayoutTransition) {
        currentButtonsRowFrame = frame
        let geometryTransition: ContainedViewLayoutTransition = buttonMorphTransitionOverride == nil ? transition : .immediate
        performMorphGeometryWithoutAnimation {
            geometryTransition.updateFrame(view: buttonsContainerView, frame: frame)
            if usesSeparatedButtonHosting {
                updateButtonLayerFrame(frame, transition: geometryTransition)
            }
        }
    }

    private func updateButtonLayerFrame(_ rowFrame: CGRect, transition: ContainedViewLayoutTransition) {
        guard usesSeparatedButtonHosting else {
            return
        }
        installButtonLayerForCurrentHost(preservePresentationLayer: transition.isAnimated)
        transition.updateFrame(view: buttonLayer, frame: buttonLayerFrame(for: rowFrame))
    }

    private func setButtonsRowAlpha(_ alpha: CGFloat) {
        buttonsRowAlpha = alpha
        buttonsContainerView.alpha = alpha
        updateButtonLayerEffectiveVisibility()
    }

    private func updateButtonLayerEffectiveVisibility() {
        guard usesSeparatedButtonHosting else {
            buttonLayer.isHidden = true
            buttonLayer.alpha = 1.0
            return
        }

        let retainsOutgoingChrome = outgoingButtonLayerFrame != nil && isButtonLayerExternallyHosted
        buttonLayer.isHidden = isButtonLayerExternallyHosted && !retainsOutgoingChrome ? isHidden : false
        buttonLayer.alpha = buttonsRowAlpha * (isButtonLayerExternallyHosted && !retainsOutgoingChrome ? alpha : 1.0)
    }

    internal func bringButtonLayerToFrontIfNeeded() {
        guard usesSeparatedButtonHosting, let superview = buttonLayer.superview, superview.subviews.last !== buttonLayer else {
            return
        }
        superview.bringSubviewToFront(buttonLayer)
    }

    internal func detachButtonLayerFromHost() {
        buttonLayer.removeFromSuperview()
    }

    private var isEffectivelyDarkGlassChrome: Bool {
        presentationData.theme.overallDarkAppearance || traitCollection.userInterfaceStyle == .dark
    }

    private enum ButtonChromePlacementID: Hashable {
        case leftContainer
        case rightContainer
        case backButton
        case backArrow
        case badge
        case titleContentView
        case outgoingTitleContentView(ObjectIdentifier)
    }

    private func buttonChromePlacementID(for view: UIView) -> ButtonChromePlacementID? {
        if let titleContentView, view === titleContentView {
            return .titleContentView
        }
        if view === leftButtonContainer {
            return .leftContainer
        }
        if view === rightButtonContainer {
            return .rightContainer
        }
        if view === backButtonView {
            return .backButton
        }
        if view === backArrowView {
            return .backArrow
        }
        if view === badgeView {
            return .badge
        }
        return nil
    }

    private func buttonChromeAccessibilityOrder(for id: ButtonChromePlacementID) -> Int {
        switch id {
        case .backArrow:
            return 0
        case .backButton:
            return 1
        case .leftContainer:
            return 2
        case .titleContentView:
            return 3
        case .outgoingTitleContentView:
            return 3
        case .rightContainer:
            return 4
        case .badge:
            return 5
        }
    }

    private func buttonChromeZIndex(for id: ButtonChromePlacementID) -> CGFloat {
        switch id {
        case .backArrow:
            return 0
        case .backButton:
            return 1
        case .leftContainer:
            return 2
        case .rightContainer:
            return 2
        case .titleContentView:
            return 2.5
        case .outgoingTitleContentView:
            return 2.5
        case .badge:
            return 3
        }
    }

    private func activeButtonMorphTransition() -> ContainedViewLayoutTransition? {
        guard let transition = buttonMorphTransitionOverride, transition.isAnimated else {
            return nil
        }
        return transition
    }

    private func performMorphGeometryWithoutAnimation(_ body: () -> Void) {
        guard buttonMorphTransitionOverride != nil else {
            body()
            return
        }
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            body()
            CATransaction.commit()
        }
    }

    private func buttonEffectTransition(appearing: Bool, from transition: ContainedViewLayoutTransition) -> ContainedViewLayoutTransition {
        guard transition.isAnimated else {
            return .immediate
        }
        let requestedDuration = appearing
            ? AetherMotion.navigationChrome.contentAppearanceDuration
            : AetherMotion.navigationChrome.contentDisappearanceDuration
        return .animated(
            duration: min(transition.duration, requestedDuration),
            curve: .easeInOut
        )
    }

    private func prepareAppearingVisualView(_ view: UIView, targetTransform: CGAffineTransform = .identity) {
        reclaimDisappearingVisualView(view)
        AetherContentMaterialization.cancel(view: view)
        performMorphGeometryWithoutAnimation {
            view.alpha = 0.0
            let scale = AetherMotion.navigationChrome.contentScale
            view.transform = targetTransform.scaledBy(x: scale, y: scale)
            if usesLiquidGlassTransitionBlur && !(view is GlassControlGroup) {
                ContainedViewLayoutTransition.immediate.setBlur(
                    layer: view.layer,
                    radius: AetherMotion.navigationChrome.contentBlurRadius
                )
            } else {
                Self.clearOwnedTransitionBlur(from: view.layer)
            }
        }
    }

    private func animateAppearingVisualView(
        _ view: UIView,
        transition: ContainedViewLayoutTransition,
        targetTransform: CGAffineTransform = .identity
    ) {
        let id = ObjectIdentifier(view)
        appearingVisualViewIDs.insert(id)
        let effectTransition = buttonEffectTransition(appearing: true, from: transition)
        let usesContentBlur = usesLiquidGlassTransitionBlur && !(view is GlassControlGroup)
        if usesContentBlur && effectTransition.isAnimated && CALayer.blur() == nil {
            Self.clearOwnedTransitionBlur(from: view.layer)
            effectTransition.updateTransform(view: view, transform: targetTransform)
            AetherContentMaterialization.animate(
                view: view,
                samples: AetherMotion.navigationChromeMaterializationSamples(appearing: true),
                duration: effectTransition.duration,
                targetAlpha: 1.0
            ) { [weak self] in
                self?.appearingVisualViewIDs.remove(id)
            }
            applyButtonOverspringPulseIfNeeded(to: view, amplitude: buttonPulseAmplitude(appearing: true), transition: effectTransition)
            return
        }
        effectTransition.updateAlpha(view: view, alpha: 1.0) { [weak self] _ in
            self?.appearingVisualViewIDs.remove(id)
        }
        effectTransition.updateTransform(view: view, transform: targetTransform)
        if usesContentBlur {
            effectTransition.setBlur(layer: view.layer, radius: 0.0)
        } else {
            Self.clearOwnedTransitionBlur(from: view.layer)
        }
        applyButtonOverspringPulseIfNeeded(to: view, amplitude: buttonPulseAmplitude(appearing: true), transition: effectTransition)
    }

    private func animateDisappearingVisualView(
        _ view: UIView,
        transition: ContainedViewLayoutTransition?,
        completion: (() -> Void)? = nil
    ) {
        guard !AetherContentMaterialization.isSnapshotView(view) else { return }
        let id = ObjectIdentifier(view)
        guard !disappearingVisualViewIDs.contains(id) else {
            return
        }
        AetherContentMaterialization.cancel(view: view)
        appearingVisualViewIDs.remove(id)
        let originalTransform = view.transform

        guard let transition, transition.isAnimated else {
            view.removeFromSuperview()
            view.alpha = 1.0
            view.transform = originalTransform
            Self.clearOwnedTransitionBlur(from: view.layer)
            completion?()
            return
        }

        disappearingVisualViewIDs.insert(id)
        disappearingVisualTransformByID[id] = originalTransform
        let wasUserInteractionEnabled = view.isUserInteractionEnabled
        disappearingVisualInteractionByID[id] = wasUserInteractionEnabled
        view.isUserInteractionEnabled = false
        let effectTransition = buttonEffectTransition(appearing: false, from: transition)
        let finish: () -> Void = { [weak self, weak view] in
            guard let self else { return }
            guard self.disappearingVisualViewIDs.remove(id) != nil else {
                return
            }
            self.disappearingVisualTransformByID.removeValue(forKey: id)
            let restoredUserInteraction = self.disappearingVisualInteractionByID.removeValue(forKey: id) ?? wasUserInteractionEnabled
            guard let view else {
                completion?()
                return
            }
            view.removeFromSuperview()
            view.alpha = 1.0
            view.transform = originalTransform
            view.isUserInteractionEnabled = restoredUserInteraction
            Self.clearOwnedTransitionBlur(from: view.layer)
            completion?()
        }
        let usesContentBlur = usesLiquidGlassTransitionBlur && !(view is GlassControlGroup)
        let usesPublicMaterialization = usesContentBlur && CALayer.blur() == nil
        if usesPublicMaterialization {
            Self.clearOwnedTransitionBlur(from: view.layer)
            AetherContentMaterialization.animate(
                view: view,
                samples: AetherMotion.navigationChromeMaterializationSamples(appearing: false),
                duration: effectTransition.duration,
                targetAlpha: 0.0,
                completion: finish
            )
            // A zero-size view can complete synchronously without a proxy.
            guard disappearingVisualViewIDs.contains(id) else { return }
        } else {
            effectTransition.updateAlpha(view: view, alpha: 0.0) { _ in finish() }
        }
        let scale = AetherMotion.navigationChrome.contentScale
        effectTransition.updateTransform(
            view: view,
            transform: originalTransform.scaledBy(x: scale, y: scale)
        )
        if usesContentBlur && !usesPublicMaterialization {
            effectTransition.setBlur(
                layer: view.layer,
                radius: AetherMotion.navigationChrome.contentBlurRadius
            )
        } else {
            Self.clearOwnedTransitionBlur(from: view.layer)
        }
        applyButtonOverspringPulseIfNeeded(to: view, amplitude: buttonPulseAmplitude(appearing: false), transition: effectTransition)
    }

    /// A caller-owned view may return before its previous disappearance ends.
    /// Invalidate that completion before restoring the view for its new owner.
    private func reclaimDisappearingVisualView(_ view: UIView) {
        let id = ObjectIdentifier(view)
        guard disappearingVisualViewIDs.remove(id) != nil else { return }
        appearingVisualViewIDs.remove(id)
        AetherContentMaterialization.cancel(view: view)
        view.layer.removeAllAnimations()
        view.alpha = 1.0
        if let transform = disappearingVisualTransformByID.removeValue(forKey: id) {
            view.transform = transform
        }
        if let interaction = disappearingVisualInteractionByID.removeValue(forKey: id) {
            view.isUserInteractionEnabled = interaction
        }
        Self.clearOwnedTransitionBlur(from: view.layer)
        buttonLayer.removeButtonPlacement(
            id: ButtonChromePlacementID.outgoingTitleContentView(id),
            detachView: false
        )
    }

    private func buttonPulseAmplitude(appearing: Bool) -> CGFloat {
        appearing
            ? AetherMotion.navigationChrome.appearancePulseAmplitude
            : AetherMotion.navigationChrome.disappearancePulseAmplitude
    }

    private func legacyButtonViews(for alignment: ButtonAlignment) -> [BarButtonID: UIView] {
        switch alignment {
        case .left:
            return legacyLeftButtonViewsByID
        case .right:
            return legacyRightButtonViewsByID
        }
    }

    private func legacyButtonView(for id: BarButtonID, alignment: ButtonAlignment) -> UIView? {
        switch alignment {
        case .left:
            return legacyLeftButtonViewsByID[id]
        case .right:
            return legacyRightButtonViewsByID[id]
        }
    }

    private func setLegacyButtonView(_ view: UIView?, for id: BarButtonID, alignment: ButtonAlignment) {
        switch alignment {
        case .left:
            legacyLeftButtonViewsByID[id] = view
        case .right:
            legacyRightButtonViewsByID[id] = view
        }
    }

    private func clearLegacyButtonViews(alignment: ButtonAlignment) {
        switch alignment {
        case .left:
            legacyLeftButtonViewsByID.removeAll()
        case .right:
            legacyRightButtonViewsByID.removeAll()
        }
    }

    private func applyButtonLayerPlacement(
        id: ButtonChromePlacementID,
        view: UIView,
        frame: CGRect,
        alpha: CGFloat,
        transform: CGAffineTransform,
        isHidden: Bool,
        isUserInteractionEnabled: Bool,
        transition: ContainedViewLayoutTransition
    ) {
        let preservePresentationLayer = transition.isAnimated && buttonMorphTransitionOverride == nil
        installButtonLayerForCurrentHost(preservePresentationLayer: preservePresentationLayer)
        buttonLayer.applyButtonPlacements(
            [
                AetherNavigationBarButtonPlacement(
                    id: id,
                    view: view,
                    frame: frame,
                    alpha: alpha,
                    transform: transform,
                    isHidden: isHidden,
                    zIndex: buttonChromeZIndex(for: id),
                    accessibilityOrder: buttonChromeAccessibilityOrder(for: id),
                    isUserInteractionEnabled: isUserInteractionEnabled,
                    preservePresentationLayer: preservePresentationLayer
                )
            ],
            transition: .existing(transition),
            removesMissing: false
        )
    }

    private func updateButtonLayerHostedView(
        view: UIView,
        frame: CGRect? = nil,
        alpha: CGFloat? = nil,
        transform: CGAffineTransform? = nil,
        transition: ContainedViewLayoutTransition
    ) {
        guard usesSeparatedButtonHosting, let id = buttonChromePlacementID(for: view) else {
            if let frame {
                transition.updateFrame(view: view, frame: frame)
            }
            if let alpha {
                transition.updateAlpha(view: view, alpha: alpha)
            }
            if let transform {
                transition.updateTransform(view: view, transform: transform)
            }
            return
        }

        let preservePresentationLayer = transition.isAnimated && buttonMorphTransitionOverride == nil
        if id == .titleContentView {
            installTitleContentViewForCurrentHostingMode(preservePresentationLayer: preservePresentationLayer)
        } else {
            installButtonChromeViewsForCurrentHostingMode(preservePresentationLayer: preservePresentationLayer)
        }
        applyButtonLayerPlacement(
            id: id,
            view: view,
            frame: frame ?? view.frame,
            alpha: alpha ?? view.alpha,
            transform: transform ?? view.transform,
            isHidden: view.isHidden,
            isUserInteractionEnabled: view.isUserInteractionEnabled,
            transition: transition
        )
    }

    private func updateButtonChromeFrame(
        view: UIView,
        frame: CGRect,
        transition: ContainedViewLayoutTransition
    ) {
        updateButtonLayerHostedView(view: view, frame: frame, transition: transition)
    }

    private func animateOutgoingTitleContentView(_ view: UIView, transition: ContainedViewLayoutTransition?) {
        let id = ButtonChromePlacementID.outgoingTitleContentView(ObjectIdentifier(view))
        if usesSeparatedButtonHosting {
            applyButtonLayerPlacement(
                id: id,
                view: view,
                frame: view.frame,
                alpha: view.alpha,
                transform: view.transform,
                isHidden: view.isHidden,
                isUserInteractionEnabled: view.isUserInteractionEnabled,
                transition: .immediate
            )
        }
        animateDisappearingVisualView(view, transition: transition) { [weak self] in
            self?.buttonLayer.removeButtonPlacement(id: id, detachView: false)
        }
    }

    // MARK: - NavigationBarView Protocol

    private var ownedContentView: NavigationBarContentView? {
        guard let contentView = _contentView, contentView.superview === clippingView else {
            return nil
        }
        return contentView
    }

    public func setContentHeightOverride(_ height: CGFloat?) {
        contentHeightOverride = height
    }

    private func resolvedDefaultContentHeight(_ proposedHeight: CGFloat) -> CGFloat {
        presentationData.theme.appearanceStyle == .legacy ? 44.0 : proposedHeight
    }

    public func contentHeight(defaultHeight: CGFloat) -> CGFloat {
        if let contentHeightOverride {
            return contentHeightOverride
        }
        if isSearchModeActive, let contentView = ownedContentView {
            // Search mode: only the search pill height, no title row or filters
            if let stacked = contentView as? AetherStackedBarContent {
                // Use only the first child's height (search pill)
                return stacked.views.first?.nominalHeight ?? contentView.height
            }
            return contentView.height
        }
        let titleAreaHeight = max(resolvedDefaultContentHeight(defaultHeight), measuredTitleHeight)
        if let contentView = ownedContentView {
            switch contentView.mode {
            case .replacement:
                return contentView.height
            case .expansion:
                return titleAreaHeight + contentView.height
            }
        }
        return titleAreaHeight
    }

    private func geometryTransition(for contentView: NavigationBarContentView, transition: ContainedViewLayoutTransition) -> ContainedViewLayoutTransition {
        return pendingAppearingContentView === contentView ? .immediate : transition
    }

    private func buttonChromeTransition(_ transition: ContainedViewLayoutTransition) -> ContainedViewLayoutTransition {
        return contentViewTransitionLocksButtonChrome ? .immediate : transition
    }

    private func contentViewKeepsButtonChromeStable(_ contentView: NavigationBarContentView?) -> Bool {
        guard let contentView else {
            return true
        }
        return contentView.mode == .expansion
    }

    private func rectsAreEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        return abs(lhs.minX - rhs.minX) < 0.5
            && abs(lhs.minY - rhs.minY) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }

    private func shouldUpdateButtonChrome(targetFrame: CGRect) -> Bool {
        if contentViewTransitionLocksButtonChrome, rectsAreEqual(currentButtonsRowFrame, targetFrame) {
            return false
        }
        return true
    }

    private func unlockButtonChromeIfCurrentContentTransition(generation: Int) {
        if contentViewTransitionGeneration == generation {
            contentViewTransitionLocksButtonChrome = false
        }
    }

    private func animateDisappearingContentView(_ contentView: NavigationBarContentView, generation: Int) {
        if pendingAppearingContentView === contentView {
            pendingAppearingContentView = nil
        }
        contentView.transform = .identity
        let transition: ContainedViewLayoutTransition = .animated(
            duration: Self.contentBlurCrossfadeDuration,
            curve: .easeInOut
        )
        if usesLiquidGlassTransitionBlur {
            transition.setBlur(layer: contentView.layer, radius: Self.contentBlurCrossfadeRadius)
        } else {
            Self.clearOwnedTransitionBlur(from: contentView.layer)
        }
        UIView.animate(
            withDuration: Self.contentBlurCrossfadeDuration,
            delay: 0.0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
            animations: {
                contentView.alpha = 0.0
            },
            completion: { [weak self, weak contentView] _ in
                guard let contentView else { return }
                // Race guard: a later setContentView call may have
                // re-attached `contentView` as the active view. Only
                // remove it if the bar is no longer using it.
                if self?._contentView === contentView {
                    contentView.alpha = 1.0
                    contentView.transform = .identity
                    if self?.contentViewTransitionGeneration == generation {
                        Self.clearOwnedTransitionBlur(from: contentView.layer)
                    }
                } else if contentView.superview === self?.clippingView {
                    contentView.removeFromSuperview()
                    contentView.alpha = 1.0
                    contentView.transform = .identity
                    Self.clearOwnedTransitionBlur(from: contentView.layer)
                } else {
                    contentView.alpha = 1.0
                    contentView.transform = .identity
                    Self.clearOwnedTransitionBlur(from: contentView.layer)
                }
                self?.unlockButtonChromeIfCurrentContentTransition(generation: generation)
            }
        )
    }

    private func animatePendingAppearingContentViewIfNeeded(_ contentView: NavigationBarContentView) {
        guard pendingAppearingContentView === contentView else {
            return
        }
        pendingAppearingContentView = nil
        let generation = contentViewTransitionGeneration
        let transition: ContainedViewLayoutTransition = .animated(
            duration: Self.contentBlurCrossfadeDuration,
            curve: .easeInOut
        )
        if usesLiquidGlassTransitionBlur {
            transition.setBlur(layer: contentView.layer, radius: 0.0) { [weak self, weak contentView] _ in
                guard let self, let contentView else { return }
                if self._contentView === contentView, self.contentViewTransitionGeneration == generation {
                    Self.clearOwnedTransitionBlur(from: contentView.layer)
                }
            }
        } else {
            Self.clearOwnedTransitionBlur(from: contentView.layer)
        }
        UIView.animate(
            withDuration: Self.contentBlurCrossfadeDuration,
            delay: 0.0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
            animations: {
                contentView.alpha = 1.0
            },
            completion: { [weak self, weak contentView] _ in
                guard let self, let contentView else { return }
                if self._contentView === contentView, self.contentViewTransitionGeneration == generation {
                    contentView.alpha = 1.0
                    contentView.transform = .identity
                }
                self.unlockButtonChromeIfCurrentContentTransition(generation: generation)
            }
        )
    }

    public func setContentView(_ contentView: NavigationBarContentView?, animated: Bool) {
        let oldContentView = _contentView
        let contentIsChanging = oldContentView !== contentView
        if !contentIsChanging {
            if let contentView {
                contentView.requestContainerLayout = { [weak self] transition in
                    self?.requestContainerLayout?(transition)
                }
                if contentView.superview !== clippingView {
                    clippingView.addSubview(contentView)
                }
                if !animated {
                    contentView.alpha = 1.0
                    contentView.transform = .identity
                    Self.clearOwnedTransitionBlur(from: contentView.layer)
                    if pendingAppearingContentView === contentView {
                        pendingAppearingContentView = nil
                    }
                }
            }
            requestContainerLayout?(animated ? .animated(duration: Self.contentBlurCrossfadeDuration, curve: .easeInOut) : .immediate)
            return
        }

        contentViewTransitionGeneration += 1
        let generation = contentViewTransitionGeneration
        contentViewTransitionLocksButtonChrome = animated
            && contentIsChanging
            && !isSearchModeActive
            && contentViewKeepsButtonChromeStable(oldContentView)
            && contentViewKeepsButtonChromeStable(contentView)
        if let old = oldContentView, old !== contentView {
            let ownsOldContent = old.superview === clippingView
            if animated {
                if ownsOldContent {
                    animateDisappearingContentView(old, generation: generation)
                }
            } else {
                if ownsOldContent {
                    old.removeFromSuperview()
                    old.alpha = 1.0
                    old.transform = .identity
                    Self.clearOwnedTransitionBlur(from: old.layer)
                }
            }
        }

        _contentView = contentView

        if let contentView = contentView {
            contentView.requestContainerLayout = { [weak self] transition in
                self?.requestContainerLayout?(transition)
            }
            if contentView.superview !== clippingView {
                clippingView.addSubview(contentView)
            }

            if animated {
                contentView.alpha = 0.0
                contentView.transform = .identity
                if usesLiquidGlassTransitionBlur {
                    ContainedViewLayoutTransition.immediate.setBlur(
                        layer: contentView.layer,
                        radius: Self.contentBlurCrossfadeRadius
                    )
                } else {
                    Self.clearOwnedTransitionBlur(from: contentView.layer)
                }
                pendingAppearingContentView = contentView
            } else {
                // Always land at visible + identity when the swap is
                // non-animated — `contentView` may have been left at
                // alpha 0 / scaled by a prior fade-out that was
                // interrupted.
                contentView.alpha = 1.0
                contentView.transform = .identity
                Self.clearOwnedTransitionBlur(from: contentView.layer)
                if pendingAppearingContentView === contentView {
                    pendingAppearingContentView = nil
                }
            }
        }

        // Honour the caller's `animated` flag for the outer layout too.
        // Previously this always fired an animated spring layout even on
        // tab switches (which pass animated: false expecting an instant
        // state swap). That made the bar re-lay-out with a 0.3s spring,
        // which the user sees as an "extra" animation.
        requestContainerLayout?(animated ? .animated(duration: Self.contentBlurCrossfadeDuration, curve: .easeInOut) : .immediate)
    }

    public func executeBack() -> Bool {
        backPressed()
        return true
    }

    public func setHidden(_ hidden: Bool, animated: Bool) {
        if animated {
            UIView.animate(withDuration: AetherMotion.navigationChrome.geometry.duration) {
                self.alpha = hidden ? 0.0 : 1.0
            }
        } else {
            self.alpha = hidden ? 0.0 : 1.0
        }
    }

    public func setTitleTransitionMode(_ enabled: Bool) {
        titleTransitionMode = enabled
        isUserInteractionEnabled = !enabled
        if enabled {
            applyTransitionVisibilityState()
        } else {
            updateBackButton()
        }
    }

    public func setTitleContentHiddenForTransition(_ hidden: Bool) {
        titleContentHiddenForTransition = hidden
        applyTransitionVisibilityState()
    }

    public func setButtonsOnlyTransitionMode(_ enabled: Bool) {
        buttonsOnlyTransitionMode = enabled
        isUserInteractionEnabled = !enabled
        applyTransitionVisibilityState()
    }

    public func setButtonContentHiddenForTransition(_ hidden: Bool) {
        buttonContentHiddenForTransition = hidden
        applyTransitionVisibilityState()
    }

    public func setButtonChromeScale(_ scale: CGFloat, transition: ContainedViewLayoutTransition) {
        setButtonChromeScale(left: scale, right: scale, transition: transition)
    }

    public func setButtonChromeScale(left: CGFloat, right: CGFloat, transition: ContainedViewLayoutTransition) {
        let leftTransform = CGAffineTransform(scaleX: left, y: left)
        let rightTransform = CGAffineTransform(scaleX: right, y: right)
        updateButtonLayerHostedView(view: leftButtonContainer, transform: leftTransform, transition: transition)
        updateButtonLayerHostedView(view: rightButtonContainer, transform: rightTransform, transition: transition)
        updateButtonLayerHostedView(view: backButtonView, transform: leftTransform, transition: transition)
        updateButtonLayerHostedView(view: backArrowView, transform: leftTransform, transition: transition)
        updateButtonLayerHostedView(view: badgeView, transform: leftTransform, transition: transition)
    }

    public func buttonChromeLayout() -> ButtonChromeLayout {
        return ButtonChromeLayout(
            leftFrame: buttonChromeFrame(container: leftButtonContainer, groups: glassButtonGroups(for: .left)),
            rightFrame: buttonChromeFrame(container: rightButtonContainer, groups: glassButtonGroups(for: .right))
        )
    }

    internal func transitionMeasuredButtonChromeLayout() -> ButtonChromeLayout {
        return ButtonChromeLayout(
            leftFrame: buttonChromeFrame(container: leftButtonContainer, groups: glassButtonGroups(for: .left), ignoresContainerHidden: true),
            rightFrame: buttonChromeFrame(container: rightButtonContainer, groups: glassButtonGroups(for: .right), ignoresContainerHidden: true)
        )
    }

    var hasPureAutomaticBackButtonGroup: Bool {
        return glassButtonGroups(for: .left).contains { group in
            isPureAutomaticBackButtonGroup(group, in: leftButtonContainer)
        }
    }

    public func setButtonChromeLayout(_ layout: ButtonChromeLayout, transition: ContainedViewLayoutTransition, appearing: Bool? = nil) {
        applyButtonChromeFrame(layout.leftFrame, container: leftButtonContainer, groups: glassButtonGroups(for: .left), alignment: .leading, transition: transition, appearing: appearing)
        applyButtonChromeFrame(layout.rightFrame, container: rightButtonContainer, groups: glassButtonGroups(for: .right), alignment: .trailing, transition: transition, appearing: appearing)
    }

    public func setButtonChromeAlpha(left: CGFloat, right: CGFloat, keepsPureBackButtonStable: Bool = false, transition: ContainedViewLayoutTransition) {
        applyButtonChromeAlpha(left, container: leftButtonContainer, groups: glassButtonGroups(for: .left), keepsPureBackButtonStable: keepsPureBackButtonStable, transition: transition)
        applyButtonChromeAlpha(right, container: rightButtonContainer, groups: glassButtonGroups(for: .right), keepsPureBackButtonStable: false, transition: transition)
    }

    public func setButtonTransitionEffects(alpha: CGFloat, blurRadius: CGFloat, scale: CGFloat, horizontalScale: CGFloat = 1.0, pulseAmplitude: CGFloat = 0.0, keepsPureBackButtonStable: Bool = false, transition: ContainedViewLayoutTransition) {
        leftButtonContainer.alpha = 1.0
        rightButtonContainer.alpha = 1.0
        Self.clearOwnedTransitionBlur(from: leftButtonContainer.layer)
        Self.clearOwnedTransitionBlur(from: rightButtonContainer.layer)

        let resolvedBlurRadius = usesLiquidGlassTransitionBlur ? blurRadius : 0.0

        applyButtonContentTransitionEffects(
            container: leftButtonContainer,
            groups: glassButtonGroups(for: .left),
            alpha: alpha,
            blurRadius: resolvedBlurRadius,
            scale: scale,
            horizontalScale: horizontalScale,
            pulseAmplitude: pulseAmplitude,
            keepsPureBackButtonStable: keepsPureBackButtonStable,
            transition: transition
        )
        applyButtonContentTransitionEffects(
            container: rightButtonContainer,
            groups: glassButtonGroups(for: .right),
            alpha: alpha,
            blurRadius: resolvedBlurRadius,
            scale: scale,
            horizontalScale: horizontalScale,
            pulseAmplitude: pulseAmplitude,
            keepsPureBackButtonStable: false,
            transition: transition
        )
        let transform = CGAffineTransform(scaleX: scale * horizontalScale, y: scale)
        updateButtonLayerHostedView(view: backButtonView, alpha: alpha, transform: transform, transition: transition)
        updateButtonLayerHostedView(view: backArrowView, alpha: alpha, transform: transform, transition: transition)
        updateButtonLayerHostedView(view: badgeView, alpha: alpha, transform: transform, transition: transition)
        if usesLiquidGlassTransitionBlur {
            transition.setBlur(layer: backButtonView.layer, radius: resolvedBlurRadius)
            transition.setBlur(layer: backArrowView.layer, radius: resolvedBlurRadius)
            transition.setBlur(layer: badgeView.layer, radius: resolvedBlurRadius)
        } else {
            Self.clearOwnedTransitionBlur(from: backButtonView.layer)
            Self.clearOwnedTransitionBlur(from: backArrowView.layer)
            Self.clearOwnedTransitionBlur(from: badgeView.layer)
        }
        applyButtonOverspringPulseIfNeeded(to: backButtonView, amplitude: pulseAmplitude, transition: transition)
        applyButtonOverspringPulseIfNeeded(to: backArrowView, amplitude: pulseAmplitude, transition: transition)
        applyButtonOverspringPulseIfNeeded(to: badgeView, amplitude: pulseAmplitude, transition: transition)
    }

    public func setButtonContentTransform(scale: CGFloat, horizontalScale: CGFloat = 1.0, transition: ContainedViewLayoutTransition) {
        applyButtonContentTransform(container: leftButtonContainer, groups: glassButtonGroups(for: .left), scale: scale, horizontalScale: horizontalScale, transition: transition)
        applyButtonContentTransform(container: rightButtonContainer, groups: glassButtonGroups(for: .right), scale: scale, horizontalScale: horizontalScale, transition: transition)
        let transform = CGAffineTransform(scaleX: scale * horizontalScale, y: scale)
        updateButtonLayerHostedView(view: backButtonView, transform: transform, transition: transition)
        updateButtonLayerHostedView(view: backArrowView, transform: transform, transition: transition)
        updateButtonLayerHostedView(view: badgeView, transform: transform, transition: transition)
    }

    private func buttonChromeFrame(container: UIView, groups: [GlassControlGroup], ignoresContainerHidden: Bool = false) -> CGRect? {
        guard (ignoresContainerHidden || !container.isHidden), container.bounds.width > 0.0, container.bounds.height > 0.0 else {
            return nil
        }
        if groups.contains(where: { isGlassButtonGroup($0, hostedIn: container) && !$0.items.isEmpty }) {
            return container.frame
        }
        let hasVisibleSubview = container.subviews.contains { subview in
            !isButtonGlassContainer(subview, for: container) &&
            !subview.isHidden && subview.alpha > 0.01 && subview.bounds.width > 0.0 && subview.bounds.height > 0.0
        }
        return hasVisibleSubview ? container.frame : nil
    }

    private func applyButtonChromeFrame(
        _ frame: CGRect?,
        container: UIView,
        groups: [GlassControlGroup],
        alignment: GlassControlGroup.TransitionChromeContentAlignment,
        transition: ContainedViewLayoutTransition,
        appearing: Bool?
    ) {
        guard let frame else {
            return
        }
        container.clipsToBounds = false
        if groups.count > 1 {
            let visibleGroups = groups.filter { isGlassButtonGroup($0, hostedIn: container) }
            guard !visibleGroups.isEmpty else {
                updateButtonChromeFrame(view: container, frame: frame, transition: transition)
                updateButtonGlassContainer(in: container, size: frame.size, transition: transition)
                return
            }
            let spacing: CGFloat = 8.0
            let naturalTotalWidth = visibleGroups.enumerated().reduce(CGFloat(0.0)) { partial, entry in
                partial + entry.element.bounds.width + (entry.offset < visibleGroups.count - 1 ? spacing : 0.0)
            }
            let targetFrame = frame

            var finalGroupFrames: [(group: GlassControlGroup, frame: CGRect)] = []
            finalGroupFrames.reserveCapacity(visibleGroups.count)
            var finalGroupX: CGFloat = 0.0
            for group in visibleGroups {
                let size = group.bounds.size
                finalGroupFrames.append((group, CGRect(x: finalGroupX, y: 0.0, width: size.width, height: size.height)))
                finalGroupX += size.width + spacing
            }

            if transition.isAnimated, let appearing {
                animateSeparatedButtonGlue(
                    entries: finalGroupFrames,
                    naturalTotalWidth: naturalTotalWidth,
                    targetContainerFrame: targetFrame,
                    alignment: alignment,
                    appearing: appearing,
                    transition: transition,
                    container: container
                )
            } else {
                setSeparatedButtonGlueAnimator(nil, for: container)
                updateButtonChromeFrame(view: container, frame: targetFrame, transition: transition)
                updateButtonGlassContainer(in: container, size: targetFrame.size, transition: transition)
                let measuredProgress = separatedButtonLayoutProgress(
                    finalFrames: finalGroupFrames.map(\.frame),
                    naturalTotalWidth: naturalTotalWidth,
                    containerWidth: targetFrame.width,
                    alignment: alignment
                )
                let progress: CGFloat = appearing == true && targetFrame.width < naturalTotalWidth - 0.5 ? 0.0 : measuredProgress
                let frames = separatedButtonFrames(
                    finalFrames: finalGroupFrames.map(\.frame),
                    naturalTotalWidth: naturalTotalWidth,
                    containerWidth: targetFrame.width,
                    alignment: alignment,
                    progress: progress
                )
                for index in 0 ..< min(finalGroupFrames.count, frames.count) {
                    transition.updateFrame(view: finalGroupFrames[index].group, frame: frames[index])
                }
            }
        } else {
            updateButtonChromeFrame(view: container, frame: frame, transition: transition)
            updateButtonGlassContainer(in: container, size: frame.size, transition: transition)
        }

        if groups.count == 1, let group = groups.first, isGlassButtonGroup(group, hostedIn: container) {
            let finalFrame = CGRect(origin: .zero, size: frame.size)
            group.setTransitionChromeFrame(finalFrame, contentAlignment: alignment, transition: transition)
        }
    }

    private func separatedButtonFrames(
        finalFrames: [CGRect],
        naturalTotalWidth: CGFloat,
        containerWidth: CGFloat,
        alignment: GlassControlGroup.TransitionChromeContentAlignment,
        progress: CGFloat
    ) -> [CGRect] {
        guard finalFrames.count > 1 else {
            return finalFrames
        }
        let clampedProgress = max(0.0, min(1.0, progress))
        return finalFrames.map { frame in
            let collapsedX: CGFloat
            let finalX: CGFloat
            switch alignment {
            case .leading:
                collapsedX = 0.0
                finalX = frame.minX
            case .trailing:
                collapsedX = containerWidth - frame.width
                finalX = containerWidth - naturalTotalWidth + frame.minX
            }
            return CGRect(
                x: collapsedX + (finalX - collapsedX) * clampedProgress,
                y: frame.minY,
                width: frame.width,
                height: frame.height
            )
        }
    }

    private func animateSeparatedButtonGlue(
        entries: [(group: GlassControlGroup, frame: CGRect)],
        naturalTotalWidth: CGFloat,
        targetContainerFrame: CGRect,
        alignment: GlassControlGroup.TransitionChromeContentAlignment,
        appearing: Bool,
        transition: ContainedViewLayoutTransition,
        container: UIView
    ) {
        let groups = entries.map(\.group)
        let finalFrames = entries.map(\.frame)
        guard !groups.isEmpty else {
            return
        }
        guard transition.isAnimated else {
            for entry in entries {
                entry.group.frame = entry.frame
            }
            return
        }

        let currentContainerFrame = container.layer.presentation()?.frame ?? container.frame
        let targetFrame = targetContainerFrame
        let collapsedWidth = separatedButtonCollapsedWidth(
            finalFrames: finalFrames,
            fallback: min(targetFrame.width, targetFrame.height),
            alignment: alignment
        )
        let shouldUseCurrentFrame = currentContainerFrame.width > 0.0 && abs(currentContainerFrame.width - targetFrame.width) > 0.5
        let startContainerFrame: CGRect
        if appearing {
            if shouldUseCurrentFrame {
                startContainerFrame = currentContainerFrame
            } else {
                startContainerFrame = collapsedButtonContainerFrame(
                    from: targetFrame,
                    collapsedWidth: collapsedWidth,
                    alignment: alignment
                )
            }
        } else {
            startContainerFrame = shouldUseCurrentFrame ? currentContainerFrame : targetFrame
        }
        let endContainerFrame: CGRect
        if appearing {
            endContainerFrame = targetFrame
        } else {
            endContainerFrame = collapsedButtonContainerFrame(
                from: targetFrame,
                collapsedWidth: min(max(targetFrame.width, collapsedWidth), max(naturalTotalWidth, collapsedWidth)),
                alignment: alignment
            )
        }

        let collapsedStartFrames = separatedButtonFrames(
            finalFrames: finalFrames,
            naturalTotalWidth: naturalTotalWidth,
            containerWidth: startContainerFrame.width,
            alignment: alignment,
            progress: 0.0
        )
        let collapsedEndFrames = separatedButtonFrames(
            finalFrames: finalFrames,
            naturalTotalWidth: naturalTotalWidth,
            containerWidth: endContainerFrame.width,
            alignment: alignment,
            progress: 0.0
        )
        let targetFrames = separatedButtonFrames(
            finalFrames: finalFrames,
            naturalTotalWidth: naturalTotalWidth,
            containerWidth: endContainerFrame.width,
            alignment: alignment,
            progress: 1.0
        )
        let currentFrames = groups.map { group in
            group.layer.presentation()?.frame ?? group.frame
        }
        let fromFrames: [CGRect]
        let toFrames: [CGRect]
        if appearing {
            fromFrames = shouldUseCurrentFrame ? currentFrames : collapsedStartFrames
            toFrames = targetFrames
        } else {
            fromFrames = shouldUseCurrentFrame ? currentFrames : separatedButtonFrames(
                finalFrames: finalFrames,
                naturalTotalWidth: naturalTotalWidth,
                containerWidth: startContainerFrame.width,
                alignment: alignment,
                progress: 1.0
            )
            toFrames = collapsedEndFrames
        }
        let animator = NavigationSeparatedButtonGlueAnimator(
            container: container,
            groups: groups,
            fromContainerFrame: startContainerFrame,
            toContainerFrame: endContainerFrame,
            fromFrames: fromFrames,
            toFrames: toFrames,
            appearing: appearing,
            duration: AetherMotion.navigationChrome.separatedGeometryDuration,
            updateContainerEffects: { [weak self, weak container] size in
                guard let self, let container else {
                    return
                }
                self.updateButtonGlassContainer(in: container, size: size, transition: .immediate)
            },
            completion: { [weak self, weak container] in
                guard let self, let container else {
                    return
                }
                self.setSeparatedButtonGlueAnimator(nil, for: container, invalidating: false)
            }
        )
        setSeparatedButtonGlueAnimator(animator, for: container)
        animator.start()
    }

    private func separatedButtonLayoutProgress(
        finalFrames: [CGRect],
        naturalTotalWidth: CGFloat,
        containerWidth: CGFloat,
        alignment: GlassControlGroup.TransitionChromeContentAlignment
    ) -> CGFloat {
        guard finalFrames.count > 1, naturalTotalWidth > 0.0 else {
            return 1.0
        }
        let collapsedWidth = separatedButtonCollapsedWidth(
            finalFrames: finalFrames,
            fallback: min(naturalTotalWidth, containerWidth),
            alignment: alignment
        )
        let denominator = max(1.0, naturalTotalWidth - collapsedWidth)
        return max(0.0, min(1.0, (containerWidth - collapsedWidth) / denominator))
    }

    private func separatedButtonCollapsedWidth(
        finalFrames: [CGRect],
        fallback: CGFloat,
        alignment: GlassControlGroup.TransitionChromeContentAlignment
    ) -> CGFloat {
        guard !finalFrames.isEmpty else {
            return max(1.0, fallback)
        }
        switch alignment {
        case .leading:
            return max(1.0, finalFrames.first?.width ?? fallback)
        case .trailing:
            return max(1.0, finalFrames.last?.width ?? fallback)
        }
    }

    private func collapsedButtonContainerFrame(
        from frame: CGRect,
        collapsedWidth: CGFloat,
        alignment: GlassControlGroup.TransitionChromeContentAlignment
    ) -> CGRect {
        let width = max(1.0, min(max(frame.width, 1.0), collapsedWidth))
        switch alignment {
        case .leading:
            return CGRect(x: frame.minX, y: frame.minY, width: width, height: frame.height)
        case .trailing:
            return CGRect(x: frame.maxX - width, y: frame.minY, width: width, height: frame.height)
        }
    }

    private func setSeparatedButtonGlueAnimator(
        _ animator: NavigationSeparatedButtonGlueAnimator?,
        for container: UIView,
        invalidating: Bool = true
    ) {
        if container === leftButtonContainer {
            if invalidating {
                leftSeparatedButtonGlueAnimator?.invalidate()
            }
            leftSeparatedButtonGlueAnimator = animator
        } else if container === rightButtonContainer {
            if invalidating {
                rightSeparatedButtonGlueAnimator?.invalidate()
            }
            rightSeparatedButtonGlueAnimator = animator
        }
    }

    private func cancelSeparatedButtonGlueAnimators() {
        setSeparatedButtonGlueAnimator(nil, for: leftButtonContainer)
        setSeparatedButtonGlueAnimator(nil, for: rightButtonContainer)
    }

    private func applyButtonChromeAlpha(
        _ alpha: CGFloat,
        container: UIView,
        groups: [GlassControlGroup],
        keepsPureBackButtonStable: Bool,
        transition: ContainedViewLayoutTransition
    ) {
        let groupSet = Set(groups.map { ObjectIdentifier($0) })
        for group in groups where isGlassButtonGroup(group, hostedIn: container) {
            let resolvedAlpha = keepsPureBackButtonStable && isPureAutomaticBackButtonGroup(group, in: container) ? 1.0 : alpha
            group.setTransitionChromeAlpha(resolvedAlpha, transition: transition)
        }
        for subview in container.subviews where !AetherContentMaterialization.isSnapshotView(subview) && !groupSet.contains(ObjectIdentifier(subview)) && !isButtonGlassContainer(subview, for: container) {
            transition.updateAlpha(view: subview, alpha: alpha)
        }
    }

    private func applyButtonContentTransitionEffects(
        container: UIView,
        groups: [GlassControlGroup],
        alpha: CGFloat,
        blurRadius: CGFloat,
        scale: CGFloat,
        horizontalScale: CGFloat,
        pulseAmplitude: CGFloat,
        keepsPureBackButtonStable: Bool,
        transition: ContainedViewLayoutTransition
    ) {
        let groupSet = Set(groups.map { ObjectIdentifier($0) })
        for group in groups where isGlassButtonGroup(group, hostedIn: container) {
            group.alpha = 1.0
            Self.clearOwnedTransitionBlur(in: group)
            if keepsPureBackButtonStable && isPureAutomaticBackButtonGroup(group, in: container) {
                group.setContentTransitionEffects(alpha: 1.0, blurRadius: 0.0, scale: 1.0, horizontalScale: 1.0, pulseAmplitude: 0.0, transition: transition)
            } else {
                group.setContentTransitionEffects(alpha: alpha, blurRadius: blurRadius, scale: scale, horizontalScale: horizontalScale, pulseAmplitude: pulseAmplitude, transition: transition)
            }
        }

        let transform = CGAffineTransform(scaleX: scale * horizontalScale, y: scale)
        for subview in container.subviews where !AetherContentMaterialization.isSnapshotView(subview) && !groupSet.contains(ObjectIdentifier(subview)) && !isButtonGlassContainer(subview, for: container) {
            transition.updateAlpha(view: subview, alpha: alpha)
            if usesLiquidGlassTransitionBlur {
                transition.setBlur(layer: subview.layer, radius: blurRadius)
            } else {
                Self.clearOwnedTransitionBlur(from: subview.layer)
            }
            transition.updateTransform(view: subview, transform: transform)
            applyButtonOverspringPulseIfNeeded(to: subview, amplitude: pulseAmplitude, transition: transition)
        }
    }

    private func applyButtonContentTransform(
        container: UIView,
        groups: [GlassControlGroup],
        scale: CGFloat,
        horizontalScale: CGFloat,
        transition: ContainedViewLayoutTransition
    ) {
        let groupSet = Set(groups.map { ObjectIdentifier($0) })
        for group in groups where isGlassButtonGroup(group, hostedIn: container) {
            group.setContentTransform(scale: scale, horizontalScale: horizontalScale, transition: transition)
        }

        let transform = CGAffineTransform(scaleX: scale * horizontalScale, y: scale)
        for subview in container.subviews where !AetherContentMaterialization.isSnapshotView(subview) && !groupSet.contains(ObjectIdentifier(subview)) && !isButtonGlassContainer(subview, for: container) {
            transition.updateTransform(view: subview, transform: transform)
        }
    }

    private func isPureAutomaticBackButtonGroup(_ group: GlassControlGroup, in container: UIView) -> Bool {
        guard container === leftButtonContainer,
              group.items.count == 1,
              let item = group.items.first else {
            return false
        }
        return item.id == AnyHashable(automaticBackButtonID(alignment: .left))
    }

    private func applyButtonOverspringPulseIfNeeded(to view: UIView, amplitude: CGFloat, transition: ContainedViewLayoutTransition) {
        let resolvedAmplitude = abs(amplitude)
        guard resolvedAmplitude > 0.0, transition.isAnimated, !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        let duration = transition.duration
        guard duration > 0.0 else {
            return
        }
        view.layer.removeAnimation(forKey: "aether.navigationButtonOverspringPulse")

        let baseTransform = view.layer.transform
        let peakTransform = CATransform3DScale(baseTransform, 1.0 + resolvedAmplitude, 1.0 + resolvedAmplitude, 1.0)
        let undershootScale = max(0.968, 1.0 - resolvedAmplitude * 0.30)
        let undershootTransform = CATransform3DScale(baseTransform, undershootScale, undershootScale, 1.0)
        let animation = CAKeyframeAnimation(keyPath: "transform")
        if amplitude >= 0.0 {
            animation.values = [baseTransform, peakTransform, undershootTransform, baseTransform]
        } else {
            animation.values = [baseTransform, undershootTransform, peakTransform, baseTransform]
        }
        animation.keyTimes = [0.0, 0.36, 0.74, 1.0]
        animation.duration = duration
        let timingFunction = amplitude >= 0.0
            ? CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.30, 1.0)
            : CAMediaTimingFunction(controlPoints: 0.70, 0.0, 0.84, 0.0)
        animation.timingFunctions = [timingFunction, timingFunction, timingFunction]
        animation.isRemovedOnCompletion = true
        animation.aetherPreferHighFrameRate()
        view.layer.add(animation, forKey: "aether.navigationButtonOverspringPulse")
    }

    @discardableResult
    internal func updateMeasuredTitleHeight(
        titleView: UIView?,
        size: CGSize,
        defaultHeight: CGFloat,
        leftInset: CGFloat,
        rightInset: CGFloat,
        requestLayoutIfNeeded: Bool
    ) -> Bool {
        let newTitleHeight = Self.measureTitleNaturalHeight(titleView: titleView, for: size, leftInset: leftInset, rightInset: rightInset)
        guard abs(measuredTitleHeight - newTitleHeight) > 0.5 else {
            return false
        }

        let oldEffective = max(defaultHeight, measuredTitleHeight)
        let newEffective = max(defaultHeight, newTitleHeight)
        measuredTitleHeight = newTitleHeight
        if requestLayoutIfNeeded && abs(oldEffective - newEffective) > 0.5 {
            DispatchQueue.main.async { [weak self] in
                self?.requestContainerLayout?(
                    .animated(duration: AetherMotion.navigationChrome.geometry.duration, curve: .spring)
                )
            }
        }
        return true
    }

    public func withButtonMorphTransition(_ transition: ContainedViewLayoutTransition, _ body: () -> Void) {
        buttonMorphTransitionOverride = transition
        defer { buttonMorphTransitionOverride = nil }
        body()
    }

    public func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition) {
        lastScrollEdgeTransitionForTesting = transition
        scrollEdgeAlpha = max(0.0, min(1.0, alpha))
        if presentationData.theme.style == .glass {
            transition.updateAlpha(view: backgroundView, alpha: 0.0)
            if let glassBackgroundView {
                transition.updateAlpha(view: glassBackgroundView, alpha: 0.0)
            }
            transition.updateAlpha(node: stripeNode, alpha: presentationData.theme.glassStyle == .strong ? scrollEdgeAlpha : 0.0)
            updateEdgeEffectVisibility(transition: transition)
            return
        }
        transition.updateAlpha(view: backgroundView, alpha: glassBackgroundView == nil ? alpha : 0.0)
        if let glassBackgroundView {
            transition.updateAlpha(view: glassBackgroundView, alpha: alpha)
        }
        transition.updateAlpha(node: stripeNode, alpha: alpha)
        updateEdgeEffectVisibility(transition: transition)
    }

    public func updatePresentationData(_ presentationData: NavigationBarPresentationData, transition: ContainedViewLayoutTransition) {
        self.presentationData = presentationData
        let theme = presentationData.theme
        let rendererStyle = theme.appearanceStyle
        if rendererStyle == .legacy {
            // A glue animator owns its groups strongly while its display link is
            // active. Stop it before touching the renderer hierarchy so a live
            // Liquid -> Legacy switch cannot leave either the frame driver or
            // detached glass groups alive until the natural animation endpoint.
            cancelSeparatedButtonGlueAnimators()
        }
        leftButtonGlassContainer.appearanceStyleOverride = rendererStyle
        rightButtonGlassContainer.appearanceStyleOverride = rendererStyle
        for group in glassButtonGroups(for: .left) + glassButtonGroups(for: .right) {
            group.appearanceStyleOverride = rendererStyle
        }
        backButtonView.appearanceStyleOverride = rendererStyle
        glassBackgroundView?.appearanceStyleOverride = rendererStyle
        edgeEffectView?.appearanceStyleOverride = rendererStyle

        if rendererStyle == .legacy {
            // A live Liquid -> Legacy switch may land in the middle of a
            // content/button crossfade. Cancel only Aether's blur key paths;
            // UIKit alpha, transform and position animations keep running.
            clearLegacyTransitionBlurState()
        }

        backgroundView.blurStyle = theme.appearanceStyle == .legacy ? .systemChromeMaterial : .systemMaterial
        backgroundView.updateColor(color: theme.backgroundColor, enableBlur: theme.enableBackgroundBlur, transition: transition)
        stripeNode.backgroundColor = theme.separatorColor
        clippingView.clipsToBounds = theme.style != .glass
        updateTitleNodes()
        backButtonView.color = theme.buttonColor
        backButtonView.contentTintColor = theme.buttonColor
        backButtonView.isDark = theme.overallDarkAppearance
        backButtonView.usesGlassStyle = theme.style == .glass
        backButtonView.icon = NavigationBarTheme.generateBackArrowImage(color: theme.buttonColor)
        backArrowNode.image = NavigationBarTheme.generateBackArrowImage(color: theme.buttonColor)

        badgeView.badgeColor = theme.badgeBackgroundColor
        badgeView.textColor = theme.badgeTextColor
        badgeView.strokeColor = theme.badgeStrokeColor

        if theme.style == .glass && glassBackgroundView == nil {
            setupGlassBackground(theme: theme)
        } else if theme.style == .glass {
            glassBackgroundView?.alpha = 0.0
            backgroundView.alpha = 0.0
            stripeNode.alpha = 0.0
        } else if theme.style == .legacy {
            glassBackgroundView?.removeFromSuperview()
            glassBackgroundView = nil
            edgeEffectView?.layer.removeAllAnimations()
            edgeEffectView?.removeFromSuperview()
            edgeEffectView = nil
            backgroundView.alpha = 1.0
            stripeNode.alpha = 1.0
        }
        applyTransitionVisibilityState()
    }

    public func updateLayout(size: CGSize, defaultHeight: CGFloat, additionalTopHeight: CGFloat, additionalContentHeight: CGFloat, additionalBackgroundHeight: CGFloat, additionalCutout: CGSize?, leftInset: CGFloat, rightInset: CGFloat, appearsHidden: Bool, isLandscape: Bool, transition: ContainedViewLayoutTransition) {
        guard !layoutSuspended else { return }

        self.validLayout = (size, defaultHeight, leftInset, rightInset)
        let resolvedDefaultHeight = resolvedDefaultContentHeight(defaultHeight)

        // Re-measure titleContentView for the current width. If the new
        // natural height changes the EFFECTIVE title-row height
        // (`max(defaultHeight, titleHeight)`) — i.e. the title is tall
        // enough to grow the nav bar — schedule a follow-up layout pass so
        // the parent container picks up the new contentHeight. Skip the
        // re-layout when the title fits within `defaultHeight`: the cached
        // value still updates, but contentHeight wouldn't change, and
        // firing `.immediate` here would interrupt any in-flight push /
        // height-change animation for nothing.
        updateMeasuredTitleHeight(
            titleView: titleContentView ?? item?.titleView,
            size: size,
            defaultHeight: resolvedDefaultHeight,
            leftInset: leftInset,
            rightInset: rightInset,
            requestLayoutIfNeeded: true
        )

        let stripeHeight = 1.0 / max(window?.screen.scale ?? traitCollection.displayScale, 1.0)
        let contentHeight = self.contentHeight(defaultHeight: defaultHeight)

        // Background
        let bgHeight = size.height + additionalBackgroundHeight
        transition.updateFrame(view: backgroundView, frame: CGRect(origin: .zero, size: CGSize(width: size.width, height: bgHeight)))
        backgroundView.update(size: CGSize(width: size.width, height: bgHeight), transition: transition)

        // Glass — `isDark` must follow the system interface style, not the
        // static `theme.overallDarkAppearance` (which is often false even on
        // a dark-mode device because `.liquidGlass()` doesn't know the
        // runtime style). Without this, the glass renders with a light
        // lumaMin/lumaMax on dark-mode devices and the bar flashes white
        // during push/pop transitions when the glass re-composites.
        let isEffectivelyDark = isEffectivelyDarkGlassChrome
        if backButtonView.isDark != isEffectivelyDark {
            backButtonView.isDark = isEffectivelyDark
        }
        if let glass = glassBackgroundView {
            transition.updateFrame(view: glass, frame: CGRect(origin: .zero, size: CGSize(width: size.width, height: bgHeight)))
            glass.update(
                size: CGSize(width: size.width, height: bgHeight),
                cornerRadius: 0.0,
                isDark: isEffectivelyDark,
                tintColor: .init(kind: presentationData.theme.glassStyle == .clear ? .clear : .panel),
                isInteractive: false,
                isVisible: true,
                transition: transition
            )
            if presentationData.theme.style == .glass {
                transition.updateAlpha(view: glass, alpha: 0.0)
            }
        }

        // Stripe
        // Stripe is carved out by `additionalCutout` to leave a gap for pinned
        // content (matches Dynamic-Island-style cutout handling).
        let stripeOriginX = additionalCutout?.width ?? 0.0
        transition.updateFrame(node: stripeNode, frame: CGRect(x: stripeOriginX, y: size.height - stripeHeight, width: size.width - stripeOriginX, height: stripeHeight))
        if presentationData.theme.style == .glass {
            transition.updateAlpha(view: backgroundView, alpha: 0.0)
            transition.updateAlpha(node: stripeNode, alpha: presentationData.theme.glassStyle == .strong ? scrollEdgeAlpha : 0.0)
        }

        // Scroll-edge frost anchored to the BOTTOM of the nav bar. The fade
        // zone terminates exactly at the nav bar bottom (transparent there)
        // and ramps up to full frost near the top of the screen. No bleed
        // past the nav bar — the bottom boundary is a clean transparent edge.
        if let edgeEffect = edgeEffectView {
            if presentationData.theme.style != .glass {
                updateEdgeEffectVisibility(transition: transition)
            } else if let edgeEffectColor = presentationData.theme.edgeEffectColor, edgeEffectColor.cgColor.alpha == 0.0 {
                updateEdgeEffectVisibility(transition: transition)
            } else {
                updateEdgeEffectVisibility(transition: transition)
                // 8pt bleed into the safe-area region on top, plus 8pt
                // past the navbar bottom so the fade spills softly into
                // the content area (instead of ending sharply at the
                // navbar edge). When `edgeEffectTopExtension` is set the
                // frost starts even higher — used e.g. by the modal
                // controller to have the frost cover its grabber strip.
                //
                // `bandShift` raises the band's TOP edge further past the
                // status bar AND grows the band's height by the same
                // amount — bottom edge stays put, frost extends upward.
                // Mirror of the tab bar's downward bleed; covers the
                // visible "просвет" between the nav bar's frost and the
                // status bar / dynamic island area.
                let usesRegularEdgeEffect = presentationData.theme.edgeEffectStyle == .regular
                edgeEffect.clipsToBounds = true
                let topInset: CGFloat = usesRegularEdgeEffect ? 8.0 : 0.0
                // Regular glass must not draw any pixels below the navbar
                // boundary. Even a tiny bottom bleed reads as a separator
                // when a topBarAccessory is installed.
                let bottomBleed: CGFloat = 0.0
                let bandShift: CGFloat = usesRegularEdgeEffect ? 12.0 : 0.0
                let topExtension = usesRegularEdgeEffect ? edgeEffectTopExtension : 0.0
                let localEdgeEffectFrame = CGRect(
                    x: 0.0,
                    y: -(topInset + topExtension + bandShift),
                    width: size.width,
                    height: size.height + topInset + topExtension + bottomBleed + bandShift
                )
                // Snap the edge-effect frame and force `.immediate` on the
                // internal frame setters inside `edgeEffect.update(...)`.
                // When the nav-bar resizes via an `.animated` transition
                // (search pill jumping navbar↔bottom, modal detent change),
                // the bar's own frame snaps synchronously (see
                // `ViewController.containerLayoutUpdated`) but the edge
                // effect's frame would otherwise interpolate over 0.3s —
                // its bottom edge would lag behind the bar's bottom for
                // the duration of the animation, showing as a visible
                // gap (or "hard line" along the trailing edge of the
                // ramping fade) between the navbar and the content
                // beneath it. Snapping the edge-effect geometry restores
                // lockstep. Visual-only properties of the effect (color,
                // blur radius) still animate via the caller's transition
                // because we no longer pass the heavy frame-resize work
                // through it.
                let edgeEffectFrame: CGRect
                if let hostView = edgeEffectHostView, edgeEffect.superview === hostView {
                    let convertedOrigin = convert(localEdgeEffectFrame.origin, to: hostView)
                    edgeEffectFrame = CGRect(
                        x: 0.0,
                        y: convertedOrigin.y,
                        width: hostView.bounds.width,
                        height: localEdgeEffectFrame.height
                    )
                } else {
                    edgeEffectFrame = localEdgeEffectFrame
                }
                edgeEffect.frame = edgeEffectFrame
                // A short constant zone followed by a short fade creates a
                // visible horizontal boundary inside tall navigation bars
                // (especially with topBarAccessory). For regular navigation
                // chrome the frost should dissolve across the whole hosted
                // band, with no internal separator-like seam.
                // The regular variable blur endpoint is laid out 1pt below
                // the visible navbar edge, while `edgeEffect` clips to its
                // frame. This keeps the visible bottom row slightly before
                // the mask reaches zero and avoids a raw-backdrop seam.
                let regularBottomOverscan: CGFloat = usesRegularEdgeEffect ? 1.0 : 0.0
                let edgeEffectUpdateSize = CGSize(
                    width: edgeEffectFrame.width,
                    height: edgeEffectFrame.height + regularBottomOverscan
                )
                let fadeZone: CGFloat = usesRegularEdgeEffect ? edgeEffectUpdateSize.height : 0.0
                let fadeCurveExponent: CGFloat = usesRegularEdgeEffect ? 2.0 : 1.0
                let edgeBlurRadius = presentationData.theme.edgeEffectBlurRadiusAtEdge
                let fadeBlurRadius: CGFloat = usesRegularEdgeEffect ? 0.0 : edgeBlurRadius
                let edgeContentColor = presentationData.theme.edgeEffectColor ?? presentationData.theme.opaqueBackgroundColor
                edgeEffect.update(
                    content: edgeContentColor,
                    blur: true,
                    alpha: presentationData.theme.edgeEffectAlpha,
                    rect: CGRect(origin: .zero, size: edgeEffectUpdateSize),
                    edge: .top,
                    edgeSize: usesRegularEdgeEffect ? fadeZone : 0.0,
                    blurRadiusAtEdge: edgeBlurRadius,
                    blurRadiusAtFade: fadeBlurRadius,
                    solidBlur: !usesRegularEdgeEffect,
                    fadeCurveExponent: fadeCurveExponent,
                    minimumFadeAlpha: usesRegularEdgeEffect ? 0.0 : 0.04,
                    prefersStaticVariableBlurMask: usesRegularEdgeEffect,
                    transition: .immediate
                )
            }
        }

        // Clipping
        transition.updateFrame(view: clippingView, frame: CGRect(origin: .zero, size: size))

        // Content area
        let statusBarHeight = size.height - contentHeight
        let buttonsAreaY = statusBarHeight + additionalTopHeight
        let buttonTransition = buttonChromeTransition(transition)

        // Content view
        if let contentView = ownedContentView {
            switch contentView.mode {
            case .replacement:
                // Buttons hidden, content replaces title row
                let buttonsHeight = contentHeight - additionalTopHeight
                let buttonsFrame = CGRect(x: 0, y: buttonsAreaY, width: size.width, height: buttonsHeight)
                if shouldUpdateButtonChrome(targetFrame: buttonsFrame) {
                    updateButtonsRowFrame(buttonsFrame, transition: buttonTransition)
                    layoutButtons(width: size.width, height: buttonsHeight, leftInset: leftInset, rightInset: rightInset, defaultHeight: resolvedDefaultHeight, transition: buttonTransition)
                }

                let contentFrame = CGRect(x: 0, y: buttonsAreaY, width: size.width, height: contentView.height)
                let contentTransition = geometryTransition(for: contentView, transition: transition)
                contentTransition.updateFrame(view: contentView, frame: contentFrame)
                let _ = contentView.updateLayout(size: contentFrame.size, leftInset: leftInset, rightInset: rightInset, transition: contentTransition)
                setButtonsRowAlpha(0.0)
            case .expansion:
                let buttonsHeight = max(resolvedDefaultHeight, measuredTitleHeight)
                let buttonsFrame = CGRect(x: 0, y: buttonsAreaY, width: size.width, height: buttonsHeight)
                if shouldUpdateButtonChrome(targetFrame: buttonsFrame) {
                    updateButtonsRowFrame(buttonsFrame, transition: buttonTransition)
                    layoutButtons(width: size.width, height: buttonsHeight, leftInset: leftInset, rightInset: rightInset, defaultHeight: resolvedDefaultHeight, transition: buttonTransition)
                }

                if isSearchModeActive {
                    // Search mode: content (search pill) at title position, no offset
                    let searchPillHeight = (contentView as? AetherStackedBarContent)?.views.first?.nominalHeight ?? contentView.height
                    let contentFrame = CGRect(x: 0, y: buttonsAreaY, width: size.width, height: searchPillHeight)
                    let contentTransition = geometryTransition(for: contentView, transition: transition)
                    contentTransition.updateFrame(view: contentView, frame: contentFrame)
                    let _ = contentView.updateLayout(size: contentFrame.size, leftInset: leftInset, rightInset: rightInset, transition: contentTransition)
                    // Hide non-search children (filters) in stacked content
                    if let stacked = contentView as? AetherStackedBarContent {
                        for (i, v) in stacked.views.enumerated() {
                            v.alpha = i == 0 ? 1.0 : 0.0
                        }
                    }
                } else {
                    // Normal: content below title row
                    let contentFrame = CGRect(x: 0, y: buttonsAreaY + buttonsHeight, width: size.width, height: contentView.height)
                    let contentTransition = geometryTransition(for: contentView, transition: transition)
                    contentTransition.updateFrame(view: contentView, frame: contentFrame)
                    let _ = contentView.updateLayout(size: contentFrame.size, leftInset: leftInset, rightInset: rightInset, transition: contentTransition)
                    // Restore all children alpha
                    if let stacked = contentView as? AetherStackedBarContent {
                        for v in stacked.views { v.alpha = 1.0 }
                    }
                    setButtonsRowAlpha(1.0)
                }
            }
            animatePendingAppearingContentViewIfNeeded(contentView)
            // Buttons always above content view (glass capsules over filter bar).
            clippingView.bringSubviewToFront(buttonsContainerView)
        } else {
            // No content view — buttons fill the entire content area
            let buttonsHeight: CGFloat
            if contentHeightOverride != nil {
                buttonsHeight = min(contentHeight - additionalTopHeight, max(resolvedDefaultHeight, measuredTitleHeight))
            } else {
                buttonsHeight = contentHeight - additionalTopHeight
            }
            let buttonsFrame = CGRect(x: 0, y: buttonsAreaY, width: size.width, height: buttonsHeight)
            if shouldUpdateButtonChrome(targetFrame: buttonsFrame) {
                updateButtonsRowFrame(buttonsFrame, transition: buttonTransition)
                layoutButtons(width: size.width, height: buttonsHeight, leftInset: leftInset, rightInset: rightInset, defaultHeight: resolvedDefaultHeight, transition: buttonTransition)
            }
            if !isSearchModeActive {
                setButtonsRowAlpha(1.0)
            }
        }

        bringButtonLayerToFrontIfNeeded()
        applyTransitionVisibilityState()
    }

    // MARK: - Search Mode

    public func setSearchMode(_ active: Bool, animated: Bool) {
        guard isSearchModeActive != active else { return }
        isSearchModeActive = active

        // Trigger a full layout cycle through the VC hierarchy.
        // This recalculates contentHeight (smaller in search mode),
        // which causes the VC to recompute additionalSafeAreaInsets,
        // which animates the collection content offset.
        let profile = active ? AetherMotion.search.presentation : AetherMotion.search.dismissal
        let transition: ContainedViewLayoutTransition = animated
            ? .animated(
                duration: profile.duration,
                curve: .customSpring(
                    damping: profile.dampingRatio,
                    initialVelocity: profile.initialVelocity
                )
            )
            : .immediate

        if animated {
            UIView.animate(
                withDuration: profile.duration,
                delay: 0,
                usingSpringWithDamping: profile.dampingRatio,
                initialSpringVelocity: profile.initialVelocity,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.setButtonsRowAlpha(active ? 0.0 : 1.0)
                for group in self.glassButtonGroups(for: .left) {
                    group.alpha = active ? 0.0 : 1.0
                }
                for group in self.glassButtonGroups(for: .right) {
                    group.alpha = active ? 0.0 : 1.0
                }
            }
        } else {
            setButtonsRowAlpha(active ? 0.0 : 1.0)
            for group in glassButtonGroups(for: .left) {
                group.alpha = active ? 0.0 : 1.0
            }
            for group in glassButtonGroups(for: .right) {
                group.alpha = active ? 0.0 : 1.0
            }
        }

        requestContainerLayout?(transition)
    }

    // MARK: - Private

    private func layoutButtons(width: CGFloat, height: CGFloat, leftInset: CGFloat, rightInset: CGFloat, defaultHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let buttonHeight: CGFloat = min(defaultHeight, height)
        let legacyBackSideInset: CGFloat = 8.0
        let legacyBarButtonSideInset: CGFloat = 16.0
        let usesGlassStyle = presentationData.theme.style == .glass
        let geometryTransition: ContainedViewLayoutTransition = buttonMorphTransitionOverride == nil ? transition : .immediate
        let buttonContainerTransition = buttonMorphTransitionOverride ?? geometryTransition
        let glassTransition = buttonMorphTransitionOverride ?? transition

        let titleLeftInset: CGFloat
        let titleRightInset: CGFloat
        if titleTransitionMode && !buttonsOnlyTransitionMode {
            backArrowView.isHidden = true
            backButtonView.isHidden = true
            leftButtonContainer.isHidden = true
            rightButtonContainer.isHidden = true
            badgeView.isHidden = true
            titleLeftInset = leftInset
            titleRightInset = rightInset
        } else if usesGlassStyle {
            // In glass mode the back button lives INSIDE the left
            // GlassControlGroup — no separate capsule. The group handles
            // morphing (fade old items out, new items in) automatically.
            backArrowView.isHidden = true
            backButtonView.isHidden = true
            let glassButtonHeight: CGFloat = 44.0
            // Inset from the bar edges to the button capsule. 20pt
            // (vs the original 16pt) gives a touch more breathing room
            // on the right side without throwing off symmetry — the
            // same value is applied to both sides below so left/right
            // capsules sit at identical distances from the bar edges.
            let glassSideInset: CGFloat = 16.0
            let glassY = floor((buttonHeight - glassButtonHeight) / 2.0) + 2.0
            let hadLeftChrome = buttonChromeFrame(container: leftButtonContainer, groups: glassButtonGroups(for: .left)) != nil
            let hadRightChrome = buttonChromeFrame(container: rightButtonContainer, groups: glassButtonGroups(for: .right)) != nil

            let leftStart = leftInset + glassSideInset
            let leftAvailableWidth = max(1.0, width * 0.5 - leftStart)
            let rightAvailableWidth = max(1.0, width * 0.5 - rightInset - glassSideInset)

            if (buttonMorphTransitionOverride == nil || leftButtonContainer.bounds.height.isZero) && !glassButtonGroups(for: .left).contains(where: { $0.isFinishingContentRemoval }) {
                updateButtonChromeFrame(view: leftButtonContainer, frame: CGRect(x: leftStart, y: glassY, width: leftAvailableWidth, height: glassButtonHeight), transition: geometryTransition)
            }
            if (buttonMorphTransitionOverride == nil || rightButtonContainer.bounds.height.isZero) && !glassButtonGroups(for: .right).contains(where: { $0.isFinishingContentRemoval }) {
                updateButtonChromeFrame(view: rightButtonContainer, frame: CGRect(x: width * 0.5, y: glassY, width: rightAvailableWidth, height: glassButtonHeight), transition: geometryTransition)
            }

            let leftButtonsWidth = layoutBarButtonItems(in: leftButtonContainer, items: item?.leftBarButtonItems, alignment: .left, height: glassButtonHeight, transition: glassTransition)
            let rightButtonsWidth = layoutBarButtonItems(in: rightButtonContainer, items: item?.rightBarButtonItems, alignment: .right, height: glassButtonHeight, transition: glassTransition)

            if leftButtonsWidth > 0.0 {
                updateButtonChromeFrame(view: leftButtonContainer, frame: CGRect(x: leftStart, y: glassY, width: leftButtonsWidth, height: glassButtonHeight), transition: hadLeftChrome ? buttonContainerTransition : .immediate)
            }
            if rightButtonsWidth > 0.0 {
                let rightFrame = CGRect(x: width - rightInset - glassSideInset - rightButtonsWidth, y: glassY, width: rightButtonsWidth, height: glassButtonHeight)
                updateButtonChromeFrame(view: rightButtonContainer, frame: rightFrame, transition: hadRightChrome ? buttonContainerTransition : .immediate)
            }
            titleLeftInset = leftButtonsWidth > 0.0 ? leftInset + glassSideInset + leftButtonsWidth + 10.0 : leftInset
            titleRightInset = rightButtonsWidth > 0.0 ? rightInset + glassSideInset + rightButtonsWidth + 10.0 : rightInset
        } else {
            let chromeGeometryTransition = geometryTransition
            // Back arrow
            let arrowSize = CGSize(width: 13.0, height: 22.0)
            let arrowFrame = CGRect(x: legacyBackSideInset + leftInset, y: (buttonHeight - arrowSize.height) / 2.0, width: arrowSize.width, height: arrowSize.height)
            updateButtonChromeFrame(view: backArrowView, frame: arrowFrame, transition: chromeGeometryTransition)

            // Back button
            let backTextX = arrowFrame.maxX + 6.0
            let backSize = backButtonView.sizeThatFits(CGSize(width: width / 2.0, height: buttonHeight))
            let backFrame = CGRect(x: backTextX, y: (buttonHeight - backSize.height) / 2.0, width: backSize.width, height: backSize.height)
            updateButtonChromeFrame(view: backButtonView, frame: backFrame, transition: chromeGeometryTransition)

            titleLeftInset = max(
                backFrame.maxX + legacyBackSideInset,
                legacyBackSideInset + leftInset + 44.0
            )
            titleRightInset = legacyBackSideInset + rightInset + 88.0

            // Left buttons
            let leftFrame = CGRect(
                x: legacyBarButtonSideInset + leftInset,
                y: 0,
                width: width / 3.0,
                height: buttonHeight
            )
            updateButtonChromeFrame(view: leftButtonContainer, frame: leftFrame, transition: chromeGeometryTransition)

            // Right buttons
            let rightWidth = width / 3.0
            let rightFrame = CGRect(
                x: width - rightWidth - legacyBarButtonSideInset - rightInset,
                y: 0,
                width: rightWidth,
                height: buttonHeight
            )
            updateButtonChromeFrame(view: rightButtonContainer, frame: rightFrame, transition: chromeGeometryTransition)

            layoutBarButtonItems(in: rightButtonContainer, items: item?.rightBarButtonItems, alignment: .right, height: buttonHeight)
            layoutBarButtonItems(in: leftButtonContainer, items: item?.leftBarButtonItems, alignment: .left, height: buttonHeight)
        }

        let balancedTitleInset = max(titleLeftInset, titleRightInset)
        let titleMaxWidth = max(0.0, width - balancedTitleInset * 2.0)
        if let titleContentView {
            // Try, in order: systemLayoutSizeFitting (Auto Layout-aware)
            // → sizeThatFits → current bounds → intrinsicContentSize.
            //
            // Auto Layout-aware fitting is first because it's the only
            // path that correctly resolves wrapper views without their
            // own `intrinsicContentSize` (HypeUI `.padding()` returns a
            // plain UIView; `GlassBackgroundView` is a custom UIView). For
            // those, both `sizeThatFits` (returns `bounds.size` = .zero
            // before first layout) and `intrinsicContentSize` (returns
            // `noIntrinsicMetric`) collapse to 0 and the title renders
            // invisible. `systemLayoutSizeFitting` propagates constraints
            // through the whole subtree and gives the real size.
            //
            // Height budget here is the FULL container height (`height`,
            // grown to fit a tall titleView via `measuredTitleHeight`),
            // not the short `buttonHeight` — otherwise tall titles get
            // clipped to ~44pt.
            let alFitting = titleContentView.systemLayoutSizeFitting(
                CGSize(width: titleMaxWidth, height: 0),
                withHorizontalFittingPriority: .fittingSizeLevel,
                verticalFittingPriority: .fittingSizeLevel
            )
            var resolvedWidth: CGFloat = alFitting.width
            var resolvedHeight: CGFloat = alFitting.height
            if resolvedWidth <= 0.0 || resolvedHeight <= 0.0 {
                let stf = titleContentView.sizeThatFits(CGSize(width: titleMaxWidth, height: .greatestFiniteMagnitude))
                if resolvedWidth <= 0.0 { resolvedWidth = stf.width }
                if resolvedHeight <= 0.0 { resolvedHeight = stf.height }
            }
            if resolvedWidth <= 0.0 { resolvedWidth = titleContentView.bounds.width }
            if resolvedHeight <= 0.0 { resolvedHeight = titleContentView.bounds.height }
            if resolvedWidth <= 0.0 || resolvedHeight <= 0.0 {
                let intrinsic = titleContentView.intrinsicContentSize
                if resolvedWidth <= 0.0 && intrinsic.width > 0.0 { resolvedWidth = intrinsic.width }
                if resolvedHeight <= 0.0 && intrinsic.height > 0.0 { resolvedHeight = intrinsic.height }
            }
            if resolvedHeight <= 0.0 { resolvedHeight = buttonHeight }
            let titleSize = CGSize(
                width: min(titleMaxWidth, max(0.0, resolvedWidth)),
                height: min(height, max(0.0, resolvedHeight))
            )
            // Center within the full container height. For a short title
            // this matches the previous (`buttonHeight`) centering exactly
            // because the container collapses to `defaultHeight`. For a
            // tall title, the container grew to titleHeight, so the title
            // sits at y≈0 and fills it — buttons stay at y=0 with their
            // own `buttonHeight`, never re-centering with the title.
            var titleFrame = CGRect(
                x: floor((width - titleSize.width) / 2.0),
                y: floor((height - titleSize.height) / 2.0) + (usesGlassStyle ? 1.0 : 0.0),
                width: titleSize.width,
                height: titleSize.height
            )
            titleFrame.origin.x = min(max(titleFrame.origin.x, titleLeftInset), max(titleLeftInset, width - titleRightInset - titleFrame.width))
            let titleViewID = ObjectIdentifier(titleContentView)
            if appearingTitleContentViewIDs.contains(titleViewID), let morphTransition = activeButtonMorphTransition() {
                appearingTitleContentViewIDs.remove(titleViewID)
                let targetTransform = titleContentView.transform
                updateButtonLayerHostedView(
                    view: titleContentView,
                    frame: titleFrame,
                    alpha: 0.0,
                    transform: targetTransform,
                    transition: .immediate
                )
                prepareAppearingVisualView(titleContentView, targetTransform: targetTransform)
                animateAppearingVisualView(titleContentView, transition: morphTransition, targetTransform: targetTransform)
            } else {
                updateButtonLayerHostedView(view: titleContentView, frame: titleFrame, transition: geometryTransition)
            }
        } else {
            let hasSubtitle = !(item?.subtitle?.isEmpty ?? true)
            if hasSubtitle {
                let titleMeasure = Self.textSize(item?.title, font: titleFont, constrainedSize: CGSize(width: titleMaxWidth, height: buttonHeight))
                let subtitleMeasure = Self.textSize(item?.subtitle, font: subtitleFont, constrainedSize: CGSize(width: titleMaxWidth, height: buttonHeight))
                let stackSpacing: CGFloat = 1.0
                let titleHeight = min(22.0, max(0.0, titleMeasure.height))
                let subtitleHeight = min(16.0, max(0.0, subtitleMeasure.height))
                let stackHeight = min(buttonHeight, titleHeight + stackSpacing + subtitleHeight)
                let stackWidth = min(titleMaxWidth, max(titleMeasure.width, subtitleMeasure.width))
                var stackFrame = CGRect(
                    x: floor((width - stackWidth) / 2.0),
                    y: floor((buttonHeight - stackHeight) / 2.0) + (usesGlassStyle ? 1.0 : 0.0),
                    width: stackWidth,
                    height: stackHeight
                )
                stackFrame.origin.x = min(max(stackFrame.origin.x, titleLeftInset), max(titleLeftInset, width - titleRightInset - stackFrame.width))
                geometryTransition.updateFrame(
                    node: titleNode,
                    frame: CGRect(
                        x: stackFrame.minX,
                        y: stackFrame.minY,
                        width: stackFrame.width,
                        height: titleHeight
                    )
                )
                geometryTransition.updateFrame(
                    node: subtitleNode,
                    frame: CGRect(
                        x: stackFrame.minX,
                        y: stackFrame.minY + titleHeight + stackSpacing,
                        width: stackFrame.width,
                        height: subtitleHeight
                    )
                )
            } else {
                let measuredTitleSize = Self.textSize(item?.title, font: titleFont, constrainedSize: CGSize(width: titleMaxWidth, height: buttonHeight))
                let titleSize = CGSize(
                    width: min(titleMaxWidth, max(0.0, measuredTitleSize.width)),
                    height: min(buttonHeight, max(0.0, measuredTitleSize.height))
                )
                var titleFrame = CGRect(x: floor((width - titleSize.width) / 2.0), y: floor((buttonHeight - titleSize.height) / 2.0) + (usesGlassStyle ? 1.0 : 0.0), width: titleSize.width, height: titleSize.height)
                titleFrame.origin.x = min(max(titleFrame.origin.x, titleLeftInset), max(titleLeftInset, width - titleRightInset - titleFrame.width))
                geometryTransition.updateFrame(node: titleNode, frame: titleFrame)
            }
        }
    }

    private enum ButtonAlignment {
        case left, right
    }

    private enum BarButtonSemanticIdentity: Hashable {
        case image(AetherImageSemanticIdentity)
        case title(String)
        case customView(ObjectIdentifier)
        case empty

        var stableComponent: String {
            switch self {
            case let .image(identity):
                return "image.\(identity.stableComponent)"
            case let .title(title):
                return "title.\(title)"
            case let .customView(identifier):
                return "custom.\(identifier)"
            case .empty:
                return "empty"
            }
        }
    }

    private struct BuiltGlassButtonGroup {
        var items: [GlassControlGroup.Item] = []
        var sourceItems: [UIBarButtonItem] = []
    }

    private func measuredBarButtonCustomViewSize(
        _ view: UIView,
        availableWidth: CGFloat,
        height: CGFloat,
        minimumWidth: CGFloat = 0.0
    ) -> CGSize {
        let bounds = view.bounds.size
        var measured = CGSize.zero

        if bounds.width > 0.0 && bounds.height > 0.0 {
            measured = bounds
        } else {
            let fitting = view.sizeThatFits(CGSize(width: availableWidth, height: height))
            if fitting.width > 0.0 { measured.width = fitting.width }
            if fitting.height > 0.0 { measured.height = fitting.height }
            if measured.width <= 0.0 && bounds.width > 0.0 { measured.width = bounds.width }
            if measured.height <= 0.0 && bounds.height > 0.0 { measured.height = bounds.height }
        }

        if measured.width <= 0.0 || measured.height <= 0.0 {
            let intrinsic = view.intrinsicContentSize
            if measured.width <= 0.0 && intrinsic.width > 0.0 { measured.width = intrinsic.width }
            if measured.height <= 0.0 && intrinsic.height > 0.0 { measured.height = intrinsic.height }
        }

        if measured.width <= 0.0 { measured.width = height }
        if measured.height <= 0.0 { measured.height = height }
        measured.width = max(minimumWidth, measured.width)
        measured.height = min(height, measured.height)
        return measured
    }

    private func glassButtonGroups(for alignment: ButtonAlignment) -> [GlassControlGroup] {
        switch alignment {
        case .left:
            return [leftButtonsGroup].compactMap { $0 } + leftAdditionalButtonsGroups
        case .right:
            return [rightButtonsGroup].compactMap { $0 } + rightAdditionalButtonsGroups
        }
    }

    private func storeGlassButtonGroups(_ groups: [GlassControlGroup], alignment: ButtonAlignment) {
        switch alignment {
        case .left:
            leftButtonsGroup = groups.first
            leftAdditionalButtonsGroups = groups.count > 1 ? Array(groups.dropFirst()) : []
        case .right:
            rightButtonsGroup = groups.first
            rightAdditionalButtonsGroups = groups.count > 1 ? Array(groups.dropFirst()) : []
        }
    }

    /// Match persistent glass surfaces by the semantic IDs they contain.
    /// Exact/overlap matches run before positional fallback so a stable back or
    /// menu button can move between shared/separated layouts without becoming
    /// a different view. Completely new groups may still reuse an otherwise
    /// unmatched surface at the same position to preserve material continuity.
    private func matchedGlassButtonGroups(
        existing: [GlassControlGroup],
        target: [BuiltGlassButtonGroup]
    ) -> (groups: [GlassControlGroup], stale: [GlassControlGroup]) {
        guard !target.isEmpty else {
            return ([], existing)
        }

        let existingIDs = existing.map { Set($0.items.map(\.id)) }
        let targetIDs = target.map { Set($0.items.map(\.id)) }
        var assignments = Array<GlassControlGroup?>(repeating: nil, count: target.count)
        var remainingExisting = Set(existing.indices)
        var remainingTargets = Set(target.indices)

        while true {
            var best: (target: Int, existing: Int, keepsBack: Bool, overlap: Int, distance: Int)?
            for targetIndex in remainingTargets {
                for existingIndex in remainingExisting {
                    let matchingIDs = targetIDs[targetIndex].intersection(existingIDs[existingIndex])
                    let overlap = matchingIDs.count
                    guard overlap > 0 else { continue }
                    let keepsBack = matchingIDs.contains { id in
                        (id.base as? BarButtonID)?.rawValue.hasSuffix(".nav.back") == true
                    }
                    let candidate = (
                        target: targetIndex,
                        existing: existingIndex,
                        keepsBack: keepsBack,
                        overlap: overlap,
                        distance: abs(targetIndex - existingIndex)
                    )
                    if let current = best {
                        if (candidate.keepsBack && !current.keepsBack)
                            || (candidate.keepsBack == current.keepsBack && candidate.overlap > current.overlap)
                            || (candidate.keepsBack == current.keepsBack
                                && candidate.overlap == current.overlap
                                && candidate.distance < current.distance) {
                            best = candidate
                        }
                    } else {
                        best = candidate
                    }
                }
            }
            guard let best else { break }
            assignments[best.target] = existing[best.existing]
            remainingTargets.remove(best.target)
            remainingExisting.remove(best.existing)
        }

        for targetIndex in remainingTargets.sorted() {
            if let existingIndex = remainingExisting.min(by: {
                abs($0 - targetIndex) < abs($1 - targetIndex)
            }) {
                assignments[targetIndex] = existing[existingIndex]
                remainingExisting.remove(existingIndex)
            } else {
                assignments[targetIndex] = GlassControlGroup(
                    appearanceStyle: presentationData.theme.appearanceStyle
                )
            }
        }

        return (
            assignments.map {
                $0 ?? GlassControlGroup(
                    appearanceStyle: presentationData.theme.appearanceStyle
                )
            },
            remainingExisting.sorted().map { existing[$0] }
        )
    }

    private func buttonGlassContainer(for container: UIView) -> GlassBackgroundContainerView? {
        if container === leftButtonContainer {
            return leftButtonGlassContainer
        }
        if container === rightButtonContainer {
            return rightButtonGlassContainer
        }
        return nil
    }

    private func buttonGroupHostView(for container: UIView) -> UIView {
        return buttonGlassContainer(for: container)?.contentView ?? container
    }

    private func isButtonGlassContainer(_ view: UIView, for container: UIView) -> Bool {
        guard let glassContainer = buttonGlassContainer(for: container) else {
            return false
        }
        return view === glassContainer
    }

    private func isGlassButtonGroup(_ group: GlassControlGroup, hostedIn container: UIView) -> Bool {
        let hostView = buttonGroupHostView(for: container)
        return group.superview === hostView || group.superview === container
    }

    private func updateButtonGlassContainer(
        in container: UIView,
        size: CGSize,
        transition: ContainedViewLayoutTransition
    ) {
        guard let glassContainer = buttonGlassContainer(for: container) else {
            return
        }
        if size.width <= 0, glassContainer.contentView.subviews.contains(where: {
            ($0 as? GlassControlGroup)?.isFinishingContentRemoval == true
        }) { return }
        let resolvedSize = CGSize(width: max(0.0, size.width), height: max(0.0, size.height))
        transition.updateFrame(view: glassContainer, frame: CGRect(origin: .zero, size: resolvedSize))
        glassContainer.update(
            size: resolvedSize,
            isDark: presentationData.theme.overallDarkAppearance || traitCollection.userInterfaceStyle == .dark,
            transition: transition
        )
    }

    private func removeGlassButtonGroups(
        alignment: ButtonAlignment,
        transition: ContainedViewLayoutTransition = .immediate,
        preservingCustomViews customViews: [UIView] = []
    ) {
        switch alignment {
        case .left:
            setSeparatedButtonGlueAnimator(nil, for: leftButtonContainer)
        case .right:
            setSeparatedButtonGlueAnimator(nil, for: rightButtonContainer)
        }
        for group in glassButtonGroups(for: alignment) {
            retireButtonVisual(group, transition: transition, preservingCustomViews: customViews)
        }
        storeGlassButtonGroups([], alignment: alignment)
    }

    /// Retire visuals outside the resizing button containers, so a switch
    /// between caller-owned controls and generated glass cannot clip, move or
    /// immediately delete the outgoing state. A reused caller view is never
    /// retained by the outgoing animation: only its old visual is retained.
    private func retireButtonVisual(
        _ view: UIView,
        transition: ContainedViewLayoutTransition,
        preservingCustomViews customViews: [UIView] = []
    ) {
        guard !AetherContentMaterialization.isSnapshotView(view),
              !disappearingVisualViewIDs.contains(ObjectIdentifier(view)) else { return }
        guard transition.isAnimated, let parent = view.superview else {
            AetherContentMaterialization.cancel(view: view)
            appearingVisualViewIDs.remove(ObjectIdentifier(view))
            view.removeFromSuperview()
            return
        }

        var outgoingView = view
        for customView in customViews where customView === view || customView.isDescendant(of: view) {
            AetherContentMaterialization.cancel(view: customView)
            guard let snapshot = buttonVisualSnapshot(customView) else {
                // A zero-sized caller view has no visible outgoing state.
                // It must still remain available to the incoming layout.
                customView.removeFromSuperview()
                if customView === view { return }
                continue
            }
            snapshot.frame = customView.frame
            snapshot.isUserInteractionEnabled = false
            if customView === view {
                parent.insertSubview(snapshot, belowSubview: view)
                outgoingView = snapshot
            } else if let customParent = customView.superview {
                customParent.insertSubview(snapshot, belowSubview: customView)
            }
            // The incoming group/control will take ownership synchronously.
            customView.removeFromSuperview()
        }

        let host: UIView = usesSeparatedButtonHosting ? buttonLayer : buttonsContainerView
        let outgoingParent = outgoingView.superview ?? parent
        let visibleFrame = outgoingView.layer.presentation()?.frame ?? outgoingView.frame
        let frame = outgoingParent.convert(visibleFrame, to: host)
        AetherNavigationBarButtonLayer.reparentPreservingPresentation(
            view: outgoingView,
            from: outgoingParent,
            to: host,
            targetFrame: frame,
            preservePresentationLayer: true
        )
        outgoingView.frame = frame
        animateDisappearingVisualView(outgoingView, transition: transition)
    }

    private func buttonVisualSnapshot(_ view: UIView) -> UIView? {
        guard view.bounds.width > 0.0, view.bounds.height > 0.0 else { return nil }
        if let snapshot = view.snapshotView(afterScreenUpdates: false) {
            return snapshot
        }
        // Off-window/custom drawing views may not supply a UIKit snapshot.
        let image = UIGraphicsImageRenderer(size: view.bounds.size).image { context in
            view.layer.render(in: context.cgContext)
        }
        return UIImageView(image: image)
    }

    private func semanticIdentity(for item: UIBarButtonItem) -> BarButtonSemanticIdentity {
        if let customView = item.customView {
            return .customView(ObjectIdentifier(customView))
        }
        if let image = item.image {
            return .image(AetherImageSemanticIdentity(image))
        }
        if let title = item.title {
            return .title(title)
        }
        return .empty
    }

    private func updateSemanticButtonIDs(_ items: [UIBarButtonItem], alignment: ButtonAlignment) {
        let side: String
        switch alignment {
        case .left: side = "left"
        case .right: side = "right"
        }
        var occurrences: [BarButtonSemanticIdentity: Int] = [:]
        var idsByObject: [ObjectIdentifier: BarButtonID] = [:]
        idsByObject.reserveCapacity(items.count)
        for item in items {
            let identity = semanticIdentity(for: item)
            let occurrence = occurrences[identity, default: 0]
            occurrences[identity] = occurrence + 1
            idsByObject[ObjectIdentifier(item)] = BarButtonID(
                "\(side).semantic.\(identity.stableComponent).\(occurrence)"
            )
        }
        switch alignment {
        case .left:
            leftSemanticButtonIDsByObject = idsByObject
        case .right:
            rightSemanticButtonIDsByObject = idsByObject
        }
    }

    private func barButtonID(for item: UIBarButtonItem, alignment: ButtonAlignment) -> BarButtonID {
        let objectID = ObjectIdentifier(item)
        switch alignment {
        case .left:
            if let id = leftSemanticButtonIDsByObject[objectID] {
                return id
            }
        case .right:
            if let id = rightSemanticButtonIDsByObject[objectID] {
                return id
            }
        }

        // Context-menu lookup can race a layout request by one run-loop turn.
        // Preserve semantic lookup even in that narrow window.
        let side = alignment == .left ? "left" : "right"
        return BarButtonID("\(side).semantic.\(semanticIdentity(for: item).stableComponent).0")
    }

    private func automaticBackButtonID(alignment: ButtonAlignment) -> BarButtonID {
        let side: String
        switch alignment {
        case .left: side = "left"
        case .right: side = "right"
        }
        return BarButtonID("\(side).nav.back")
    }

    @discardableResult
    private func layoutBarButtonItems(in container: UIView, items: [UIBarButtonItem]?, alignment: ButtonAlignment, height: CGFloat, transition glassTransition: ContainedViewLayoutTransition = .immediate) -> CGFloat {
        let theme = presentationData.theme
        let buttonForegroundColor = theme.buttonColor
        let itemGeometryTransition: ContainedViewLayoutTransition = buttonMorphTransitionOverride == nil ? glassTransition : .immediate
        let rawItems = items ?? []
        updateSemanticButtonIDs(rawItems, alignment: alignment)

        if theme.style == .glass {
            clearLegacyButtonViews(alignment: alignment)
            // When every bar-button item has its own customView and no
            // auto back-button is needed, skip the shared GlassControlGroup
            // capsule entirely. Reason: wrapping caller-provided views
            // (especially glass-bearing ones like GlassButton) inside the
            // group's glass capsule creates a double-glass stack — the
            // inner iconView's iOS 26 monochromatic treatment then inverts
            // against the outer capsule and renders with the wrong tint,
            // and custom layout views lose their size when the group
            // constrains them to its own flow. Laying out customViews
            // directly in the container lets them render exactly as-is.
            let needsBackButton = alignment == .left && previousItem != nil && enableAutomaticBackButton
            let allCustomView = !rawItems.isEmpty && rawItems.allSatisfy {
                $0.customView != nil && !$0.aetherHostsCustomViewInGlassControlGroup
            }

            if allCustomView && !needsBackButton {
                let expected = rawItems.compactMap { $0.customView }
                removeGlassButtonGroups(alignment: alignment, transition: glassTransition, preservingCustomViews: expected)

                for sub in container.subviews where !AetherContentMaterialization.isSnapshotView(sub) && !isButtonGlassContainer(sub, for: container) && !expected.contains(where: { $0 === sub }) {
                    retireButtonVisual(sub, transition: glassTransition)
                }

                let spacing: CGFloat = 6.0
                var offsetX: CGFloat = 0.0
                for (idx, view) in expected.enumerated() {
                    let item = rawItems[idx]
                    reclaimDisappearingVisualView(view)
                    let isNewView = view.superview !== container
                    let targetTransform = view.transform
                    if view.superview !== container {
                        if glassTransition.isAnimated {
                            prepareAppearingVisualView(view, targetTransform: targetTransform)
                        }
                        container.addSubview(view)
                    }
                    let measured = measuredBarButtonCustomViewSize(
                        view,
                        availableWidth: .greatestFiniteMagnitude,
                        height: height
                    )

                    let y = floor((height - measured.height) / 2.0)
                    let frame = CGRect(x: offsetX, y: y, width: measured.width, height: measured.height)
                    itemGeometryTransition.updateFrame(view: view, frame: frame)
                    if isNewView {
                        animateAppearingVisualView(
                            view,
                            transition: glassTransition,
                            targetTransform: targetTransform
                        )
                    } else if disappearingVisualViewIDs.contains(ObjectIdentifier(view)) {
                        reclaimDisappearingVisualView(view)
                        view.transform = targetTransform
                    } else if appearingVisualViewIDs.contains(ObjectIdentifier(view)) {
                        // Preserve the in-flight blur/fade when layout is
                        // requested again before the handoff has settled.
                    } else {
                        view.alpha = 1.0
                        view.transform = targetTransform
                        Self.clearOwnedTransitionBlur(from: view.layer)
                    }
                    if #available(iOS 14.0, *), let control = view as? UIControl {
                        syncBarButtonMenuTrigger(button: control, item: item, alignment: alignment)
                    }
                    offsetX += measured.width
                    if idx < expected.count - 1 { offsetX += spacing }
                }
                let glassContainerTransition = buttonMorphTransitionOverride ?? itemGeometryTransition
                updateButtonGlassContainer(in: container, size: CGSize(width: offsetX, height: height), transition: glassContainerTransition)
                return offsetX
            }

            var builtGroups: [BuiltGlassButtonGroup] = []
            var currentGroup = BuiltGlassButtonGroup()

            func flushCurrentGroup() {
                guard !currentGroup.items.isEmpty else {
                    return
                }
                builtGroups.append(currentGroup)
                currentGroup = BuiltGlassButtonGroup()
            }

            // Left group: prepend back button (icon-only circle) if applicable.
            if alignment == .left, let _ = self.previousItem, enableAutomaticBackButton {
                let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
                let backArrow = UIImage(systemName: "chevron.left", withConfiguration: config)!
                let backContent: GlassControlGroup.Item.Content
                if let badgeText = item?.backButtonBadgeText, !badgeText.isEmpty {
                    let badgeContent: NavigationAutomaticBackBadgeContentView
                    if let existing = automaticBackBadgeContentView, existing.badgeText == badgeText {
                        badgeContent = existing
                    } else {
                        badgeContent = NavigationAutomaticBackBadgeContentView(text: badgeText, chevron: backArrow)
                        automaticBackBadgeContentView = badgeContent
                    }
                    badgeContent.updateTheme(theme)
                    backContent = .customView(badgeContent)
                } else {
                    automaticBackBadgeContentView = nil
                    backContent = .icon(backArrow)
                }
                currentGroup.items.append(GlassControlGroup.Item(
                    id: automaticBackButtonID(alignment: alignment),
                    content: backContent,
                    action: { [weak self] in self?.backPressed() }
                ))
            }

            // Regular bar button items.
            if let items, !items.isEmpty {
                for item in items {
                    let content: GlassControlGroup.Item.Content
                    let insets: UIEdgeInsets
                    if let customView = item.customView {
                        content = .customView(customView)
                        insets = .zero
                    } else if let image = item.image {
                        content = .icon(image)
                        insets = .zero
                    } else if let title = item.title {
                        content = .text(title)
                        insets = UIEdgeInsets(top: 0.0, left: 10.0, bottom: 0.0, right: 10.0)
                    } else {
                        content = .text("")
                        insets = UIEdgeInsets(top: 0.0, left: 10.0, bottom: 0.0, right: 10.0)
                    }

                    let primaryAction: (() -> Void)?
                    if let selector = item.action, let target = item.target as AnyObject? {
                        primaryAction = { [weak target] in
                            UIApplication.shared.sendAction(selector, to: target, from: item, for: nil)
                        }
                    } else if item.aetherHostsCustomViewInGlassControlGroup, item.customView?.isUserInteractionEnabled == true {
                        primaryAction = {}
                    } else {
                        primaryAction = nil
                    }

                    // If the bar item carries a AetherUI menu provider
                    // (set by `UIBarButtonItem(title:image:primaryAction:contextMenuItemsProvider:)`
                    // or directly via `contextMenuItemsProvider`),
                    // tapping pops the AetherUI context menu anchored
                    // to the capsule cell.
                    //
                    //   * iOS 14+ — pass a NO-OP action here (so the
                    //     `GlassControlGroup` keeps `isUserInteractionEnabled = true`
                    //     and the button rendered at full alpha; passing
                    //     `nil` greys the cell out and silences taps).
                    //     The real menu trigger is wired further down via
                    //     `wireBarButtonMenuTrigger` on `.touchDown`,
                    //     BEFORE the button's highlight + onTap chain.
                    //   * iOS 13 — `UIAction` is unavailable, so route
                    //     through the action callback (touchUpInside).
                    let action: (() -> Void)?
                    if let menuProvider = item.contextMenuItemsProvider {
                        if #available(iOS 14.0, *) {
                            action = { /* no-op — menu fires on .touchDown */ }
                        } else {
                            action = { [weak self, weak item] in
                                guard let self, let item else { return }
                                self.presentBarButtonContextMenu(for: item, alignment: alignment, provider: menuProvider)
                            }
                        }
                    } else {
                        action = primaryAction
                    }

                    let groupItem = GlassControlGroup.Item(id: barButtonID(for: item, alignment: alignment), content: content, contentInsets: insets, action: action)
                    if item.separatesSharedBackground {
                        flushCurrentGroup()
                        builtGroups.append(BuiltGlassButtonGroup(items: [groupItem], sourceItems: [item]))
                    } else {
                        currentGroup.items.append(groupItem)
                        currentGroup.sourceItems.append(item)
                    }
                }
            }
            flushCurrentGroup()

            guard !builtGroups.isEmpty else {
                var existingGroups = glassButtonGroups(for: alignment)
                for (index, group) in existingGroups.enumerated() {
                    group.animatesInsertedItemsAlpha = glassTransition.isAnimated
                    group.suppressesAutomaticSizeMorphPulse = false
                    group.transitionContentAlignment = alignment == .right ? .trailing : .leading
                    _ = group.update(
                        items: [],
                        background: .panel,
                        preferClearGlass: theme.glassStyle == .clear,
                        foregroundColor: buttonForegroundColor,
                        isDark: isEffectivelyDarkGlassChrome,
                        availableHeight: height,
                        minWidth: height,
                        transition: glassTransition
                    )
                    if index > 0 {
                        if glassTransition.isAnimated {
                            glassTransition.updateAlpha(view: group, alpha: 0.0) { [weak group] _ in
                                group?.removeFromSuperview()
                                group?.alpha = 1.0
                            }
                        } else {
                            group.removeFromSuperview()
                            group.alpha = 1.0
                        }
                    }
                }
                if existingGroups.count > 1 {
                    existingGroups = Array(existingGroups.prefix(1))
                }
                storeGlassButtonGroups(existingGroups, alignment: alignment)
                if !glassTransition.isAnimated {
                    updateButtonGlassContainer(in: container, size: CGSize(width: 0.0, height: height), transition: .immediate)
                }
                return 0.0
            }

            let groupMatch = matchedGlassButtonGroups(
                existing: glassButtonGroups(for: alignment),
                target: builtGroups
            )
            let groups = groupMatch.groups
            groups.forEach {
                $0.appearanceStyleOverride = theme.appearanceStyle
                $0.motionProfile = AetherMotion.navigationButtonPress
                $0.suppressesAutomaticSizeMorphPulse = false
            }
            for staleGroup in groupMatch.stale {
                staleGroup.suppressesAutomaticSizeMorphPulse = false
                staleGroup.animatesInsertedItemsAlpha = glassTransition.isAnimated
                staleGroup.transitionContentAlignment = alignment == .right ? .trailing : .leading
                _ = staleGroup.update(
                    items: [],
                    background: .panel,
                    preferClearGlass: theme.glassStyle == .clear,
                    foregroundColor: buttonForegroundColor,
                    isDark: isEffectivelyDarkGlassChrome,
                    availableHeight: height,
                    minWidth: height,
                    transition: glassTransition
                )
                if glassTransition.isAnimated {
                    staleGroup.isAwaitingAnimatedRemoval = true
                    glassTransition.updateAlpha(view: staleGroup, alpha: 0.0) { [weak staleGroup] _ in
                        staleGroup?.isAwaitingAnimatedRemoval = false
                        staleGroup?.removeFromSuperview()
                        staleGroup?.alpha = 1.0
                    }
                } else {
                    staleGroup.removeFromSuperview()
                    staleGroup.alpha = 1.0
                }
            }

            let groupHostView = buttonGroupHostView(for: container)
            for group in groups where group.superview !== groupHostView {
                groupHostView.addSubview(group)
            }
            storeGlassButtonGroups(groups, alignment: alignment)
            let animatesGroupGeometry = glassTransition.isAnimated && buttonMorphTransitionOverride != nil
            let previouslyPopulatedGroups = Set(groups.filter { !$0.items.isEmpty }.map(ObjectIdentifier.init))
            var previousGroupFrames: [ObjectIdentifier: CGRect] = [:]
            if animatesGroupGeometry {
                for group in groups where group.bounds.width > 0.0 && group.bounds.height > 0.0 {
                    previousGroupFrames[ObjectIdentifier(group)] = group.layer.presentation()?.frame ?? group.frame
                }
            }

            // Clean up stale non-group subviews from legacy/custom paths.
            let groupSet = Set(groups.map { ObjectIdentifier($0) })
            for sub in container.subviews where !AetherContentMaterialization.isSnapshotView(sub) && !isButtonGlassContainer(sub, for: container) {
                retireButtonVisual(sub, transition: glassTransition, preservingCustomViews: rawItems.compactMap(\.customView))
            }
            for sub in groupHostView.subviews where !AetherContentMaterialization.isSnapshotView(sub) && !groupSet.contains(ObjectIdentifier(sub))
                && !((sub as? GlassControlGroup)?.isAwaitingAnimatedRemoval ?? false) {
                sub.removeFromSuperview()
            }

            let spacing: CGFloat = 8.0
            var groupSizes: [CGSize] = []
            groupSizes.reserveCapacity(builtGroups.count)
            var totalWidth: CGFloat = 0.0
            for (index, builtGroup) in builtGroups.enumerated() {
                let group = groups[index]
                group.animatesInsertedItemsAlpha = glassTransition.isAnimated
                group.transitionContentAlignment = alignment == .right ? .trailing : .leading
                let size = group.update(
                    items: builtGroup.items,
                    background: .panel,
                    preferClearGlass: theme.glassStyle == .clear,
                    foregroundColor: buttonForegroundColor,
                    isDark: isEffectivelyDarkGlassChrome,
                    availableHeight: height,
                    minWidth: height,
                    transition: glassTransition
                )
                groupSizes.append(size)
                totalWidth += size.width
                if index < builtGroups.count - 1 {
                    totalWidth += spacing
                }
            }

            var offsetX: CGFloat = 0.0
            let groupGeometryTransition = animatesGroupGeometry ? glassTransition : itemGeometryTransition
            for (index, group) in groups.enumerated() {
                let size = groupSizes[index]
                if let previousFrame = previousGroupFrames[ObjectIdentifier(group)] {
                    UIView.performWithoutAnimation {
                        group.frame = previousFrame
                    }
                }
                let geometryTransition: ContainedViewLayoutTransition = previouslyPopulatedGroups.contains(ObjectIdentifier(group)) ? groupGeometryTransition : .immediate
                geometryTransition.updateFrame(view: group, frame: CGRect(x: offsetX, y: 0.0, width: size.width, height: size.height))
                offsetX += size.width
                if index < groups.count - 1 {
                    offsetX += spacing
                }
            }
            let glassContainerTransition = buttonMorphTransitionOverride ?? itemGeometryTransition
            let targetGlassContainerSize = CGSize(width: totalWidth, height: height)
            updateButtonGlassContainer(in: container, size: targetGlassContainerSize, transition: previouslyPopulatedGroups.isEmpty ? .immediate : glassContainerTransition)

            // After `group.update` rebuilds the cell buttons, wire the
            // menu trigger DIRECTLY onto each button that carries a
            // provider. We use `.touchDown` on iOS 14+ so the menu fires
            // the moment the finger lands — same response curve as
            // `UIButton.menu` with `showsMenuAsPrimaryAction = true` —
            // and the menu source is still in a clean (non-press) state.
            // iOS 13 falls back to the old action-callback path
            // already wired through GlassControlGroup.
            if #available(iOS 14.0, *) {
                for (groupIndex, builtGroup) in builtGroups.enumerated() {
                    let group = groups[groupIndex]
                    for item in builtGroup.sourceItems {
                        guard let buttonView = group.itemButton(id: barButtonID(for: item, alignment: alignment)) as? UIControl
                        else { continue }
                        syncBarButtonMenuTrigger(button: buttonView, item: item, alignment: alignment)
                    }
                }
            }
            return totalWidth
        }

        // Legacy (non-glass) layout — unchanged from prior behaviour.
        if container === leftButtonContainer {
            removeGlassButtonGroups(alignment: .left)
        }
        if container === rightButtonContainer {
            removeGlassButtonGroups(alignment: .right)
        }

        let expectedIDs = Set(rawItems.map { barButtonID(for: $0, alignment: alignment) })
        let morphTransition = activeButtonMorphTransition()
        for (id, view) in legacyButtonViews(for: alignment) where !expectedIDs.contains(id) {
            setLegacyButtonView(nil, for: id, alignment: alignment)
            animateDisappearingVisualView(view, transition: morphTransition)
        }

        guard !rawItems.isEmpty else {
            clearLegacyButtonViews(alignment: alignment)
            for subview in container.subviews where !AetherContentMaterialization.isSnapshotView(subview) && !isButtonGlassContainer(subview, for: container) {
                animateDisappearingVisualView(subview, transition: morphTransition)
            }
            return 0.0
        }

        var offsetX: CGFloat = 0
        var expectedViews: [UIView] = []

        for item in rawItems {
            let id = barButtonID(for: item, alignment: alignment)
            let view: UIView
            let size: CGSize
            let isNewView: Bool
            let targetTransform: CGAffineTransform

            if let customView = item.customView {
                if let generatedView = legacyButtonView(for: id, alignment: alignment), generatedView !== customView {
                    setLegacyButtonView(nil, for: id, alignment: alignment)
                    animateDisappearingVisualView(generatedView, transition: morphTransition)
                }
                view = customView
                reclaimDisappearingVisualView(customView)
                isNewView = customView.superview !== container
                targetTransform = customView.transform
                size = measuredBarButtonCustomViewSize(
                    customView,
                    availableWidth: container.bounds.width,
                    height: height,
                    minimumWidth: 30.0
                )
            } else if theme.style == .glass {
                let button = GlassBarButtonView(
                    icon: item.image,
                    title: item.title,
                    state: .glass,
                    appearanceStyle: theme.appearanceStyle
                )
                button.contentTintColor = buttonForegroundColor
                button.isDarkAppearance = isEffectivelyDarkGlassChrome
                if let action = item.action, let target = item.target {
                    button.action = { _ in
                        UIApplication.shared.sendAction(action, to: target, from: item, for: nil)
                    }
                }
                view = button
                isNewView = true
                targetTransform = .identity
                size = button.intrinsicContentSize
            } else {
                let button: AetherNavigationBarLegacyButtonView
                if let existingButton = legacyButtonView(for: id, alignment: alignment) as? AetherNavigationBarLegacyButtonView {
                    button = existingButton
                    isNewView = button.superview !== container
                } else {
                    button = AetherNavigationBarLegacyButtonView()
                    setLegacyButtonView(button, for: id, alignment: alignment)
                    isNewView = true
                }
                button.tintColor = theme.buttonColor
                button.configure(
                    image: item.image,
                    title: item.title,
                    font: UIFont.aetherScaledSystemFont(
                        ofSize: 17.0,
                        maximumPointSize: 22.0,
                        compatibleWith: traitCollection
                    )
                )

                button.removeTarget(nil, action: nil, for: .touchUpInside)
                if item.contextMenuItemsProvider == nil, let action = item.action, let target = item.target {
                    button.addTarget(target, action: action, for: .touchUpInside)
                }

                button.sizeToFit()
                view = button
                targetTransform = .identity
                size = CGSize(width: max(button.bounds.width, 30.0), height: button.bounds.height)
            }

            let x: CGFloat
            switch alignment {
            case .left:
                x = offsetX
            case .right:
                x = container.bounds.width - offsetX - size.width
            }

            let frame = CGRect(x: x, y: floor((height - size.height) / 2.0), width: size.width, height: size.height)
            performMorphGeometryWithoutAnimation {
                view.frame = frame
            }
            if view.superview !== container {
                if isNewView, morphTransition != nil {
                    prepareAppearingVisualView(view, targetTransform: targetTransform)
                }
                container.addSubview(view)
                if isNewView, let morphTransition {
                    animateAppearingVisualView(view, transition: morphTransition, targetTransform: targetTransform)
                }
            } else if disappearingVisualViewIDs.contains(ObjectIdentifier(view)) {
                reclaimDisappearingVisualView(view)
                view.transform = targetTransform
            } else if appearingVisualViewIDs.contains(ObjectIdentifier(view)) {
                // Keep the in-flight blur/alpha/scale animation intact.
            } else {
                view.alpha = 1.0
                view.transform = targetTransform
                Self.clearOwnedTransitionBlur(from: view.layer)
            }
            expectedViews.append(view)
            if #available(iOS 14.0, *), let control = view as? UIControl {
                syncBarButtonMenuTrigger(button: control, item: item, alignment: alignment)
            }
            offsetX += size.width + 8.0
        }
        let expectedViewIDs = Set(expectedViews.map { ObjectIdentifier($0) })
        for subview in container.subviews where !AetherContentMaterialization.isSnapshotView(subview) && !isButtonGlassContainer(subview, for: container) && !expectedViewIDs.contains(ObjectIdentifier(subview)) {
            animateDisappearingVisualView(subview, transition: morphTransition)
        }
        return max(0.0, offsetX - 8.0)
    }

    private static let centeredTextParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    private static func attributedText(_ text: String?, font: UIFont, color: UIColor) -> NSAttributedString? {
        guard let text, !text.isEmpty else { return nil }
        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: centeredTextParagraphStyle
            ]
        )
    }

    private static func textSize(_ text: String?, font: UIFont, constrainedSize: CGSize) -> CGSize {
        guard let text, !text.isEmpty else { return .zero }
        let rect = (text as NSString).boundingRect(
            with: constrainedSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    private func updateTitleNodes() {
        titleNode.view.accessibilityLabel = item?.title
        titleNode.attributedText = Self.attributedText(
            item?.title,
            font: titleFont,
            color: presentationData.theme.primaryTextColor.resolvedColor(with: traitCollection)
        )
        subtitleNode.view.accessibilityLabel = item?.subtitle
        subtitleNode.attributedText = Self.attributedText(
            item?.subtitle,
            font: subtitleFont,
            color: UIColor.secondaryLabel.resolvedColor(with: traitCollection)
        )
    }

    private func updateItemContent() {
        updateTitleNodes()
        let itemTitleView = hostsNavigationItemTitleView ? item?.titleView : nil
        if let existingTitleContentView = titleContentView, existingTitleContentView !== itemTitleView {
            let morphTransition = activeButtonMorphTransition()
            buttonLayer.removeButtonPlacement(id: ButtonChromePlacementID.titleContentView, detachView: false)
            let isHostedByThisBar = existingTitleContentView.isDescendant(of: buttonLayer)
                || existingTitleContentView.isDescendant(of: buttonsContainerView)
                || existingTitleContentView.isDescendant(of: self)
            if morphTransition?.isAnimated == true && isHostedByThisBar {
                animateOutgoingTitleContentView(existingTitleContentView, transition: morphTransition)
            } else if isHostedByThisBar {
                AetherContentMaterialization.cancel(view: existingTitleContentView)
                appearingVisualViewIDs.remove(ObjectIdentifier(existingTitleContentView))
                existingTitleContentView.removeFromSuperview()
            }
            titleContentView = nil
            // Drop any cached height from the previous titleView so the next
            // layout pass re-measures (or collapses back to defaultHeight).
            measuredTitleHeight = 0
        }
        if let titleView = itemTitleView, titleView !== titleContentView {
            reclaimDisappearingVisualView(titleView)
            buttonLayer.removeButtonPlacement(id: ButtonChromePlacementID.titleContentView, detachView: false)
            titleContentView?.removeFromSuperview()
            titleContentView = titleView
            if activeButtonMorphTransition()?.isAnimated == true {
                appearingTitleContentViewIDs.insert(ObjectIdentifier(titleView))
            }
            installTitleContentViewForCurrentHostingMode(preservePresentationLayer: false)
            measuredTitleHeight = 0
        }
        titleNode.isHidden = titleContentView != nil
        subtitleNode.isHidden = titleContentView != nil || (item?.subtitle?.isEmpty ?? true)
        updateBackButton()
        // Do NOT schedule any layout here. The caller — syncNavigationItem
        // in TabBarController, wireControllers in NavigationController, etc.
        // — is responsible for driving the layout pass with the correct
        // transition. Requesting an animated spring here meant every
        // `item = ...` set kicked off a 0.3s layout, which showed up as
        // an unwanted animation on tab switches (syncNavigationItem passes
        // animated: false, but this implicit request was overriding it).
    }

    /// Probe the current `titleContentView`'s natural height for the given
    /// container width. Used by `updateLayout` to decide whether the nav
    /// bar should grow to fit a tall custom titleView. Width budget mirrors
    /// the conservative side reserve used by `layoutButtons` (back/right
    /// buttons + insets) so the same height we measure here is what the
    /// title will actually render at later in the pass.
    ///
    /// Auto Layout (`systemLayoutSizeFitting`) is the primary path because
    /// it correctly resolves wrapper views (HypeUI's `.padding()`, etc.)
    /// that have no `intrinsicContentSize` of their own — `sizeThatFits`
    /// on those returns bounds.size = (0, 0) before first layout, and the
    /// intrinsic chain breaks when any child reports `noIntrinsicMetric`.
    internal static func measureTitleNaturalHeight(titleView: UIView?, for size: CGSize, leftInset: CGFloat, rightInset: CGFloat) -> CGFloat {
        guard let titleContentView = titleView else { return 0 }
        let sideButtonsBudget: CGFloat = 100
        let titleMaxWidth = max(0, size.width - leftInset - rightInset - sideButtonsBudget * 2)
        let alFitting = titleContentView.systemLayoutSizeFitting(
            CGSize(width: titleMaxWidth, height: 0),
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
        if alFitting.height > 0 { return alFitting.height }
        let stf = titleContentView.sizeThatFits(CGSize(width: titleMaxWidth, height: .greatestFiniteMagnitude))
        if stf.height > 0 { return stf.height }
        return max(0, titleContentView.intrinsicContentSize.height)
    }

    /// Call after mutating the wrapped titleView in a way that changes its
    /// natural height (text replaced, child added/removed). Drops the cached
    /// measurement and asks the parent container to re-run layout — the
    /// nav bar will then re-measure and grow/shrink to fit.
    public func invalidateTitleViewLayout(
        transition: ContainedViewLayoutTransition = .animated(
            duration: AetherMotion.navigationChrome.geometry.duration,
            curve: .spring
        )
    ) {
        measuredTitleHeight = 0
        requestContainerLayout?(transition)
    }

    private func updateBackButton() {
        let hasBack: Bool
        let backText: String

        if let previousItem = self.previousItem {
            switch previousItem {
            case let .item(navItem):
                hasBack = true
                backText = navItem.title ?? presentationData.strings.back
            case .close:
                hasBack = true
                backText = presentationData.strings.close
            }
        } else {
            hasBack = false
            backText = ""
        }

        backButtonView.isHidden = !hasBack || !enableAutomaticBackButton
        backArrowView.isHidden = backButtonView.isHidden || presentationData.theme.style == .glass
        backButtonView.text = backText
        applyTransitionVisibilityState()
    }

    @objc private func backButtonPressed() {
        backPressed()
    }

    private func setupGlassBackground(theme: NavigationBarTheme) {
        edgeEffectView?.layer.removeAllAnimations()
        edgeEffectView?.removeFromSuperview()
        edgeEffectView = nil
        let glassStyle: GlassBackgroundView.Style
        switch theme.glassStyle {
        case .default:
            glassStyle = .regular
        case .strong:
            glassStyle = .prominent
        case .clear:
            glassStyle = .clear
        }
        let glass = GlassBackgroundView(style: glassStyle)
        glass.surfaceRole = .attachedBar
        glass.appearanceStyleOverride = theme.appearanceStyle
        insertSubview(glass, aboveSubview: backgroundView)
        self.glassBackgroundView = glass
        backgroundView.alpha = 0.0
        glass.alpha = 0.0
        stripeNode.alpha = 0.0

        // Scroll-edge fade (`NavigationBarImpl` creates this unconditionally
        // in glass mode — scrolling content dissolves as it meets the nav bar).
        let edgeEffect = EdgeEffectView()
        edgeEffect.appearanceStyleOverride = theme.appearanceStyle
        edgeEffect.isUserInteractionEnabled = false
        edgeEffect.alpha = scrollEdgeAlpha
        self.edgeEffectView = edgeEffect
        rehostEdgeEffectView()
        applyTransitionVisibilityState()
    }

    private func rehostEdgeEffectView() {
        guard let edgeEffectView else {
            return
        }
        edgeEffectView.removeFromSuperview()
        if let edgeEffectHostView {
            edgeEffectHostView.addSubview(edgeEffectView)
        } else {
            insertSubview(edgeEffectView, at: 0)
        }
    }

    deinit {
        if let barButtonContextMenuProviderObserver {
            NotificationCenter.default.removeObserver(barButtonContextMenuProviderObserver)
        }
        edgeEffectView?.removeFromSuperview()
        buttonLayer.removeFromSuperview()
    }

    private func applyTransitionVisibilityState() {
        if titleTransitionMode {
            backgroundView.isHidden = true
            stripeNode.isHidden = true
            glassBackgroundView?.isHidden = true
            leftButtonContainer.isHidden = true
            rightButtonContainer.isHidden = true
            badgeView.isHidden = true
        } else if buttonsOnlyTransitionMode {
            backgroundView.isHidden = true
            stripeNode.isHidden = true
            glassBackgroundView?.isHidden = true
            leftButtonContainer.isHidden = false
            rightButtonContainer.isHidden = false
            badgeView.isHidden = true
        } else {
            let chromeOnlyTransition = titleContentHiddenForTransition
            backgroundView.isHidden = chromeOnlyTransition
            stripeNode.isHidden = chromeOnlyTransition
            glassBackgroundView?.isHidden = chromeOnlyTransition
            leftButtonContainer.isHidden = buttonContentHiddenForTransition
            rightButtonContainer.isHidden = buttonContentHiddenForTransition
            badgeView.isHidden = buttonContentHiddenForTransition || badgeView.text.isEmpty
        }
        updateEdgeEffectVisibility(transition: .immediate)
        if titleTransitionMode || buttonContentHiddenForTransition {
            backButtonView.isHidden = true
            backArrowView.isHidden = true
        } else if !buttonsOnlyTransitionMode {
            let hasBack = previousItem != nil && enableAutomaticBackButton
            backButtonView.isHidden = !hasBack
            backArrowView.isHidden = !hasBack || presentationData.theme.style == .glass
        }

        let titleAlpha: CGFloat = titleContentHiddenForTransition || buttonsOnlyTransitionMode ? 0.0 : 1.0
        let customTitleAlpha: CGFloat = titleTransitionMode || buttonContentHiddenForTransition ? 0.0 : 1.0
        let contentAlpha: CGFloat = titleContentHiddenForTransition || buttonsOnlyTransitionMode ? 0.0 : 1.0
        titleNode.alpha = titleAlpha
        subtitleNode.alpha = titleAlpha
        if let titleContentView {
            updateButtonLayerHostedView(view: titleContentView, alpha: customTitleAlpha, transition: .immediate)
        }
        ownedContentView?.alpha = contentAlpha
    }

    /// Keeps the scroll-edge frost in lockstep with the scroll-activated
    /// separator. Structural navigation transitions still decide whether the
    /// effect can be displayed at all; `scrollEdgeAlpha` controls its visual
    /// reveal while the bar is otherwise eligible.
    private func updateEdgeEffectVisibility(transition: ContainedViewLayoutTransition) {
        guard let edgeEffectView else {
            return
        }

        let hasVisibleColor = !(presentationData.theme.edgeEffectColor?.cgColor.alpha ?? 1.0).isZero
        let isEligible: Bool
        if presentationData.theme.style != .glass || !hasVisibleColor {
            isEligible = false
        } else if titleTransitionMode {
            isEligible = true
        } else if buttonsOnlyTransitionMode {
            isEligible = false
        } else {
            isEligible = !titleContentHiddenForTransition
        }

        edgeEffectView.isHidden = !isEligible
        transition.updateAlpha(view: edgeEffectView, alpha: isEligible ? scrollEdgeAlpha : 0.0)
    }

    /// Reference to the menu currently anchored to one of our bar
    /// buttons. Tracked so `traitCollectionDidChange` can dismiss it
    /// before the navbar tears down + rebuilds its `GlassControlGroup`
    /// cell buttons (which would otherwise leave the menu pointing at
    /// a detached source view and corrupt the navbar's own re-layout).
    private weak var presentedBarButtonMenu: ContextMenuController?

    private func dismissPresentedBarButtonContextMenu() {
        guard let menu = presentedBarButtonMenu else {
            return
        }
        presentedBarButtonMenu = nil
        menu.dismiss(animated: false)
    }

    /// Wires the menu trigger directly onto the `GlassControlGroup`
    /// cell button via `UIAction` on `.touchDown`. This intentionally
    /// bypasses the group's own `onTap` action — the menu fires the
    /// moment the user's finger lands instead of after touch-up,
    /// matching `UIButton.menu`-with-`showsMenuAsPrimaryAction`'s
    /// timing and avoiding the brief icon shift the action-callback path
    /// produced when the cell was already mid-press.
    @available(iOS 14.0, *)
    private func syncBarButtonMenuTrigger(
        button: UIControl,
        item: UIBarButtonItem,
        alignment: ButtonAlignment
    ) {
        let identifier = UIAction.Identifier("AetherUI.NavigationBar.BarButtonContextMenu")
        button.removeAction(identifiedBy: identifier, for: .touchDown)
        guard item.contextMenuItemsProvider != nil else {
            return
        }
        let action = UIAction(identifier: identifier) { [weak self, weak item, weak button] _ in
            guard let self,
                  let item,
                  let sourceView = button,
                  let provider = item.contextMenuItemsProvider
            else { return }
            let sourceID = self.barButtonID(for: item, alignment: alignment)
            let visualSourceView = self.glassButtonGroups(for: alignment).compactMap { group -> UIView? in
                guard group.itemButton(id: sourceID) === sourceView else {
                    return nil
                }
                return group.itemVisualSourceView(id: sourceID)
            }.first ?? sourceView
            self.presentBarButtonContextMenu(
                sourceView: sourceView,
                visualSourceView: visualSourceView,
                provider: provider
            )
        }
        button.addAction(action, for: .touchDown)
    }

    private func barButtonContextMenuProviderDidChange(_ notification: Notification) {
        guard let changedItem = notification.object as? UIBarButtonItem,
              let item else {
            return
        }

        if item.leftBarButtonItems?.contains(where: { $0 === changedItem }) == true {
            refreshBarButtonMenuConfiguration(alignment: .left)
        }
        if item.rightBarButtonItems?.contains(where: { $0 === changedItem }) == true {
            refreshBarButtonMenuConfiguration(alignment: .right)
        }
    }

    /// Rebuild only the already-rendered button group for the affected side.
    /// Provider changes do not alter geometry, so this updates the cell's
    /// enabled state/action and the `.touchDown` UIAction without asking the
    /// owning controller to perform a full navigation-bar layout pass.
    private func refreshBarButtonMenuConfiguration(alignment: ButtonAlignment) {
        let container: UIView
        let items: [UIBarButtonItem]?
        switch alignment {
        case .left:
            container = leftButtonContainer
            items = item?.leftBarButtonItems
        case .right:
            container = rightButtonContainer
            items = item?.rightBarButtonItems
        }

        let height = container.bounds.height
        guard height > 0.0 else {
            // The provider was assigned before this bar's first layout. The
            // normal layout path will consume the current provider value.
            return
        }
        _ = layoutBarButtonItems(
            in: container,
            items: items,
            alignment: alignment,
            height: height,
            transition: .immediate
        )
    }

    /// Show a AetherUI context menu anchored to the bar item's glass
    /// capsule cell. Routes through `GlassControlGroup.itemButton(id:)`
    /// to find the visible source view — the cell rounds with the
    /// capsule's height/2, so we mirror that for the menu's morph-out
    /// corner radius.
    private func presentBarButtonContextMenu(
        for item: UIBarButtonItem,
        alignment: ButtonAlignment,
        provider: () -> [ContextMenuItem]
    ) {
        // Don't open a duplicate menu if one is already up.
        if presentedBarButtonMenu != nil { return }

        let sourceID = barButtonID(for: item, alignment: alignment)
        let sourceViews = glassButtonGroups(for: alignment).compactMap { group -> (hit: UIView, visual: UIView)? in
            guard let hit = group.itemButton(id: sourceID) else {
                return nil
            }
            return (hit, group.itemVisualSourceView(id: sourceID) ?? hit)
        }.first
        guard let sourceViews else {
            return
        }
        presentBarButtonContextMenu(
            sourceView: sourceViews.hit,
            visualSourceView: sourceViews.visual,
            provider: provider
        )
    }

    private func presentBarButtonContextMenu(
        sourceView: UIView,
        visualSourceView: UIView,
        provider: () -> [ContextMenuItem]
    ) {
        // Don't open a duplicate menu if one is already up.
        if presentedBarButtonMenu != nil { return }

        let items = provider()
        guard !items.isEmpty else { return }
        guard sourceView.window != nil else { return }

        let menu = ContextMenuController(
            source: .init(
                view: visualSourceView,
                cornerRadius: visualSourceView.bounds.height / 2.0,
                hidesDuringPresentation: true
            ),
            items: items,
            appearanceStyle: presentationData.theme.appearanceStyle,
            onDismiss: { [weak self] in
                guard let self else { return }
                self.presentedBarButtonMenu = nil
            }
        )
        presentedBarButtonMenu = menu
        menu.present()
    }

}

// MARK: - Back Button View

/// A single semantic back item: the badge never becomes a second touch target
/// or a separate glass surface, and its width participates in group layout.
final class NavigationAutomaticBackBadgeContentView: UIView {
    let badgeText: String
    private let chevronNode = ASImageNode()
    private let badge = NavigationBarBadgeView()

    init(text: String, chevron: UIImage) {
        badgeText = text
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        chevronNode.image = chevron.withRenderingMode(.alwaysTemplate)
        chevronNode.contentMode = .scaleAspectFit
        chevronNode.view.isUserInteractionEnabled = false
        badge.text = text
        addSubview(chevronNode.view)
        addSubview(badge)
        accessibilityLabel = text
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        chevronNode.view.removeFromSuperview()
    }

    func updateTheme(_ theme: NavigationBarTheme) {
        chevronNode.tintColor = theme.buttonColor
        badge.badgeColor = theme.badgeBackgroundColor
        badge.textColor = theme.badgeTextColor
        badge.strokeColor = theme.badgeStrokeColor
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let badgeSize = badge.sizeThatFits(size)
        return CGSize(width: 12.0 + 13.0 + 5.0 + badgeSize.width + 12.0, height: 44.0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let badgeSize = badge.sizeThatFits(bounds.size)
        chevronNode.frame = CGRect(x: 12.0, y: (bounds.height - 22.0) * 0.5, width: 13.0, height: 22.0)
        chevronNode.recursivelyEnsureDisplaySynchronously(true)
        badge.frame = CGRect(x: 30.0, y: (bounds.height - badgeSize.height) * 0.5, width: badgeSize.width, height: badgeSize.height)
        // UIKit layout alone leaves Texture's nested text/background nodes
        // pending. They must join the chevron in the first materialization
        // frame, including when the public renderer captures this subtree.
        badge.layoutIfNeeded()
        badge.contentNode.layoutIfNeeded()
        badge.contentNode.recursivelyEnsureDisplaySynchronously(true)
    }
}

final class NavigationBackButtonView: UIView, AetherAppearanceConsumer {
    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    private var font: UIFont {
        UIFont.aetherScaledSystemFont(
            ofSize: 17.0,
            maximumPointSize: 22.0,
            compatibleWith: traitCollection
        )
    }

    /// Stable content plane shared by both renderers. Only Liquid mode moves it
    /// under a lazily-created glass surface; Legacy keeps it directly hosted by
    /// the back-button view and therefore owns no hidden effect hierarchy.
    private let contentContainer: UIView
    private var glassBackground: GlassBackgroundView?
    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode()
    private var elasticRecognizer: GlassHighlightGestureRecognizer?
    private var classicPressRecognizer: AetherClassicPressGestureRecognizer?
    private var appliedAppearanceStyle: AetherAppearanceStyle

    var appearanceStyleOverride: AetherAppearanceStyle? {
        didSet {
            guard appearanceStyleOverride != oldValue else { return }
            aetherApplyAppearance(.runtimeCurrent, animated: true)
        }
    }

    var glassBackgroundForTesting: GlassBackgroundView? {
        glassBackground
    }

    var contentContainerForTesting: UIView {
        contentContainer
    }

    var action: (() -> Void)?

    var text: String = "" {
        didSet {
            updateTitleNode()
            invalidateIntrinsicContentSize()
        }
    }

    var color: UIColor = .systemBlue {
        didSet {
            updateTitleNode()
        }
    }

    var contentTintColor: UIColor = .systemBlue {
        didSet {
            updateIconAppearance()
            updateTitleNode()
        }
    }

    var isDark: Bool = false {
        didSet {
            setNeedsLayout()
        }
    }

    var usesGlassStyle: Bool = false {
        didSet {
            guard usesGlassStyle != oldValue else { return }
            applyResolvedRendererMode(animated: false)
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    var icon: UIImage? {
        didSet {
            iconNode.image = icon?.withRenderingMode(.alwaysTemplate)
            iconNode.isHidden = !isUsingLiquidGlassStyle || icon == nil
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    init(appearanceStyle: AetherAppearanceStyle? = nil) {
        let resolvedAppearanceStyle = appearanceStyle ?? AetherAppearance.runtimeCurrent.style
        self.contentContainer = UIView()
        self.glassBackground = nil
        self.appearanceStyleOverride = appearanceStyle
        self.appliedAppearanceStyle = resolvedAppearanceStyle

        super.init(frame: .zero)

        contentContainer.isUserInteractionEnabled = false
        addSubview(contentContainer)

        // Icon + label stay under one persistent host while that host moves
        // between the plain hierarchy and a Liquid glass content plane.
        iconNode.contentMode = .center
        iconNode.isHidden = true
        iconNode.view.isUserInteractionEnabled = false
        contentContainer.addSubview(iconNode.view)
        updateIconAppearance()

        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        titleNode.view.isUserInteractionEnabled = false
        contentContainer.addSubview(titleNode.view)
        updateTitleNode()

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        let classicPress = AetherClassicPressGestureRecognizer(
            target: self,
            action: #selector(handleClassicPress(_:))
        )
        addGestureRecognizer(classicPress)
        classicPressRecognizer = classicPress

        AetherAppearanceConsumerRegistry.register(self)
        applyResolvedRendererMode(animated: false)
    }

    @objc private func handleTap() {
        action?()
    }

    private var isUsingLiquidGlassStyle: Bool {
        usesGlassStyle && appliedAppearanceStyle.usesLiquidGlass
    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        appliedAppearanceStyle = appearanceStyleOverride ?? appearance.style
        applyResolvedRendererMode(animated: animated)
    }

    private func applyResolvedRendererMode(animated: Bool) {
        let usesLiquidRenderer = isUsingLiquidGlassStyle
        if !usesLiquidRenderer {
            updateElasticPressRenderer(enabled: false)
        }
        reconcileGlassRenderer(shouldInstall: usesLiquidRenderer)
        if usesLiquidRenderer {
            updateElasticPressRenderer(enabled: true)
            applyClassicPressed(false, animated: animated)
        }
        classicPressRecognizer?.isEnabled = !usesLiquidRenderer
        iconNode.isHidden = !usesLiquidRenderer || icon == nil
    }

    private func reconcileGlassRenderer(shouldInstall: Bool) {
        if shouldInstall {
            if let glassBackground {
                glassBackground.appearanceStyleOverride = appliedAppearanceStyle
                return
            }

            let glassBackground = GlassBackgroundView(
                style: .regular,
                appearanceStyle: appliedAppearanceStyle
            )
            glassBackground.surfaceRole = .button
            // Native UIGlassEffect must receive the touch stream to drive its
            // interactive deformation; the stable recognizers remain on self.
            glassBackground.isUserInteractionEnabled = true
            insertSubview(glassBackground, at: 0)
            contentContainer.removeFromSuperview()
            glassBackground.contentView.addSubview(contentContainer)
            self.glassBackground = glassBackground
        } else if let glassBackground {
            contentContainer.removeFromSuperview()
            glassBackground.tearDownLiquidRenderer()
            glassBackground.removeFromSuperview()
            self.glassBackground = nil
            addSubview(contentContainer)
        } else if contentContainer.superview !== self {
            contentContainer.removeFromSuperview()
            addSubview(contentContainer)
        }
    }

    private func updateElasticPressRenderer(enabled: Bool) {
        if !enabled {
            if let elasticRecognizer {
                elasticRecognizer.resetVisualState()
                removeGestureRecognizer(elasticRecognizer)
                self.elasticRecognizer = nil
            }
            return
        }
        guard #unavailable(iOS 26.0), let glassBackground else { return }
        guard elasticRecognizer == nil else { return }
        let elastic = GlassHighlightGestureRecognizer(target: nil, action: nil)
        elastic.motionProfile = AetherMotion.navigationButtonPress
        elastic.touchEffectView = self
        elastic.highlightContainerView = glassBackground.contentView
        addGestureRecognizer(elastic)
        elasticRecognizer = elastic
    }

    @objc private func handleClassicPress(_ recognizer: AetherClassicPressGestureRecognizer) {
        let pressed: Bool
        switch recognizer.state {
        case .began, .changed:
            pressed = bounds.contains(recognizer.location(in: self))
        case .ended, .cancelled, .failed:
            pressed = false
        default:
            return
        }
        applyClassicPressed(pressed, animated: true)
    }

    private func applyClassicPressed(_ pressed: Bool, animated: Bool) {
        let tokens = AetherLegacySurfaceTokens.resolve(role: .button, traitCollection: traitCollection)
        let changes = {
            self.contentContainer.alpha = pressed ? tokens.pressedAlpha : 1
            let scale = pressed ? tokens.pressedScale : 1
            self.contentContainer.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        if animated, tokens.animationDuration > 0 {
            UIView.animate(
                withDuration: tokens.animationDuration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
                animations: changes
            )
        } else {
            changes()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        iconNode.view.removeFromSuperview()
        titleNode.view.removeFromSuperview()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let colorAppearanceChanged = previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true
        guard colorAppearanceChanged
            || previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else {
            return
        }
        if colorAppearanceChanged {
            updateIconAppearance()
        }
        updateTitleNode()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let titleSize = textSize(text, constrainedSize: size)
        if isUsingLiquidGlassStyle {
            let iconWidth: CGFloat = icon == nil ? 0.0 : 20.0
            let spacing: CGFloat = icon == nil || text.isEmpty ? 0.0 : 3.0
            return CGSize(width: max(44.0, titleSize.width + iconWidth + spacing + 20.0), height: 44.0)
        }
        return titleSize
    }

    private func updateIconAppearance() {
        let resolvedColor = contentTintColor.resolvedColor(with: traitCollection)
        iconNode.tintColor = resolvedColor
        iconNode.view.setMonochromaticEffect(
            tintColor: resolvedColor
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        contentContainer.frame = bounds

        if isUsingLiquidGlassStyle, let glassBackground {
            glassBackground.frame = bounds
            let cornerRadius = bounds.height * 0.5
            if #available(iOS 26.0, *) {
                glassBackground.setNativeUniformCornerRadius(cornerRadius)
            }
            glassBackground.update(
                size: bounds.size,
                cornerRadius: cornerRadius,
                isDark: isDark,
                tintColor: .init(kind: .panel),
                isInteractive: true,
                isVisible: true,
                transition: .immediate
            )

            let iconWidth: CGFloat = icon == nil ? 0.0 : 20.0
            let spacing: CGFloat = icon == nil || text.isEmpty ? 0.0 : 3.0
            let titleSize = textSize(text, constrainedSize: CGSize(width: max(0.0, bounds.width - iconWidth - spacing - 20.0), height: bounds.height))
            let contentWidth = iconWidth + spacing + titleSize.width
            var x = floor((bounds.width - contentWidth) / 2.0)
            if icon != nil {
                iconNode.frame = CGRect(x: x, y: 0.0, width: iconWidth, height: bounds.height)
                x += iconWidth + spacing
            }
            titleNode.frame = CGRect(x: x, y: 0.0, width: titleSize.width, height: bounds.height)
        } else {
            iconNode.frame = .zero
            titleNode.frame = bounds
        }
    }

    private func updateTitleNode() {
        titleNode.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: contentTintColor.resolvedColor(with: traitCollection),
                .paragraphStyle: Self.paragraphStyle
            ]
        )
    }

    private func textSize(_ text: String, constrainedSize: CGSize) -> CGSize {
        guard !text.isEmpty else { return .zero }
        let rect = (text as NSString).boundingRect(
            with: constrainedSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }
}
