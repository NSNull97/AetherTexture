import UIKit
import AsyncDisplayKit

internal enum AetherLegacySearchFieldMetrics {
    static let fieldHeight: CGFloat = 36.0
    static let wrapperTopInset: CGFloat = 1.0
    static let wrapperBottomInset: CGFloat = 15.0
    static let horizontalInset: CGFloat = 8.0
    static let cornerRadius: CGFloat = 10.0
    static let contentHeight: CGFloat = 22.0

    static var wrapperHeight: CGFloat {
        wrapperTopInset + fieldHeight + wrapperBottomInset
    }
}

/// Glass-styled search bar matching the Liquid Glass v1 aesthetic.
/// Renders a translucent pill with a magnifying glass icon and placeholder text.
///
/// Can be used standalone or as a `NavigationBarContentView` (`.expansion` mode)
/// to sit below the nav bar title row.
///
/// ```swift
/// let searchBar = AetherSearchBarContent()
/// searchBar.placeholder = "Search"
/// searchBar.onTap = { print("Search activated") }
/// controller.topBarAccessory = searchBar
/// ```
public final class AetherSearchBarContent: NavigationBarContentView {

    // MARK: - Public API

    /// Placeholder text displayed in the search pill.
    public var placeholder: String = "Search" {
        didSet { updatePlaceholderNode() }
    }

    /// Called when the user taps the search bar.
    public var onTap: (() -> Void)?

    /// Explicitly force dark glass. Leave `false` for automatic light/dark
    /// tracking through the current trait collection.
    public var isDark: Bool = false {
        didSet {
            guard isDark != oldValue else { return }
            pillView.isDarkOverride = isDark ? true : nil
            setNeedsLayout()
        }
    }

    private var explicitPillHeight: CGFloat?

    /// Search-field height. With no explicit override, Legacy follows the
    /// iOS 18 metric (36 pt) while Liquid Glass keeps its 44-pt capsule.
    public var pillHeight: CGFloat {
        get {
            explicitPillHeight
                ?? (resolvedAppearanceStyle == .legacy
                    ? AetherLegacySearchFieldMetrics.fieldHeight
                    : 44.0)
        }
        set {
            let clampedValue = max(0.0, newValue)
            guard explicitPillHeight != clampedValue else { return }
            explicitPillHeight = clampedValue
            invalidateLayout(transition: .immediate)
            setNeedsLayout()
        }
    }

    /// Horizontal inset from content edges to pill.
    public var horizontalInset: CGFloat = 16.0

    /// Extra right inset to make room for close button when search is active.
    public var rightExtraInset: CGFloat = 0.0

    /// Optional per-screen style selected by the appearance resolver.
    public var appearanceStyleOverride: AetherAppearanceStyle? {
        didSet {
            guard appearanceStyleOverride != oldValue else { return }
            let resolvedStyle = appearanceStyleOverride ?? AetherAppearance.runtimeCurrent.style
            let metricsChanged = resolvedStyle != appliedAppearanceStyle
            appliedAppearanceStyle = resolvedStyle
            pillView.appearanceStyleOverride = appearanceStyleOverride
            updatePressRenderer(for: resolvedAppearanceStyle)
            if metricsChanged {
                invalidateLayout(transition: .immediate)
            } else {
                setNeedsLayout()
            }
        }
    }

    // MARK: - Subviews

    /// The glass pill background. Public for positioning text field overlays.
    public let pillView: GlassBackgroundView
    private let iconNode = ASImageNode()
    private let placeholderNode = ASTextNode()
    private var iconTintColor: UIColor = .secondaryLabel
    private var elasticPressRecognizer: GlassHighlightGestureRecognizer?
    private var classicPressRecognizer: AetherClassicPressGestureRecognizer?
    private var appliedAppearanceStyle: AetherAppearanceStyle

    private var resolvedAppearanceStyle: AetherAppearanceStyle {
        appliedAppearanceStyle
    }

    // MARK: - Init

    public init(appearanceStyle: AetherAppearanceStyle? = nil) {
        let resolvedAppearanceStyle = appearanceStyle ?? AetherAppearance.runtimeCurrent.style
        self.appearanceStyleOverride = appearanceStyle
        self.appliedAppearanceStyle = resolvedAppearanceStyle
        self.pillView = GlassBackgroundView(
            style: .regular,
            appearanceStyle: appearanceStyle
        )
        super.init(frame: .zero)

        pillView.surfaceRole = .input
        // The classic iOS search field is a semantic tertiary fill, not a
        // translucent attached-bar material.
        pillView.legacyUsesBlurMaterial = false

        // `isUserInteractionEnabled = true` is required for iOS 26's
        // `UIGlassEffect.isInteractive` deformation to track the
        // finger — the effect needs to receive hit-tests on the glass
        // surface itself, not on a transparent ancestor. The parent's
        // tap-to-activate gesture still fires when the user taps the
        // pill (gesture recognizers walk the view hierarchy regardless
        // of which descendant the hit-test landed on).
        pillView.isUserInteractionEnabled = true
        addSubview(pillView)

        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        iconNode.image = UIImage(systemName: "magnifyingglass", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        iconNode.contentMode = .center
        iconNode.view.isUserInteractionEnabled = false
        addSubview(iconNode.view)
        updateIconAppearance()

        placeholderNode.maximumNumberOfLines = 1
        placeholderNode.truncationMode = .byTruncatingTail
        placeholderNode.view.isUserInteractionEnabled = false
        addSubview(placeholderNode.view)
        updatePlaceholderNode()

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)

        AetherAppearanceConsumerRegistry.register(self)
        updatePressRenderer(for: resolvedAppearanceStyle)
    }

    internal var backingUsesLiquidGlassAppearanceForTesting: Bool {
        pillView.usesLiquidGlassAppearance
    }

    internal var backingUsesAnyGlassRendererForTesting: Bool {
        pillView.usesAnyGlassRendererForTesting
    }

    internal var backingLegacyBlurStyleForTesting: UIBlurEffect.Style? {
        pillView.legacyBlurStyleForTesting
    }

    internal var iconFrameForTesting: CGRect {
        iconNode.frame
    }

    internal var placeholderFrameForTesting: CGRect {
        placeholderNode.frame
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        let colorAppearanceChanged = previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? false
        let contentSizeChanged = previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory
        guard colorAppearanceChanged || contentSizeChanged else { return }

        if colorAppearanceChanged {
            updateIconAppearance()
        }
        updatePlaceholderNode()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    // MARK: - NavigationBarContentView

    override public var nominalHeight: CGFloat {
        if resolvedAppearanceStyle == .legacy, explicitPillHeight == nil {
            return AetherLegacySearchFieldMetrics.wrapperHeight
        }
        return pillHeight + (resolvedAppearanceStyle == .legacy ? 16.0 : 12.0)
    }

    override public var mode: NavigationBarContentMode { .expansion }

    override public func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGSize {
        let insetL = horizontalInset + leftInset
        let insetR = horizontalInset + rightInset + rightExtraInset
        let pillWidth = max(0, size.width - insetL - insetR)
        let isLegacy = resolvedAppearanceStyle == .legacy
        let fieldHeight = pillHeight
        let pillY = isLegacy
            ? AetherLegacySearchFieldMetrics.wrapperTopInset
            : floor((size.height - fieldHeight) / 2.0)

        let pillFrame = CGRect(x: insetL, y: pillY, width: pillWidth, height: fieldHeight)
        transition.updateFrame(view: pillView, frame: pillFrame)
        pillView.update(
            size: pillFrame.size,
            cornerRadius: isLegacy
                ? AetherLegacySearchFieldMetrics.cornerRadius
                : fieldHeight / 2.0,
            isDark: isDark || traitCollection.userInterfaceStyle == .dark,
            tintColor: .init(kind: .panel),
            // `true` enables iOS 26's `UIGlassEffect.isInteractive`
            // deformation — see comment on the `pillView.isUserInteractionEnabled`
            // wiring above. The pre-iOS-26 elastic press feedback below
            // covers the legacy path.
            isInteractive: resolvedAppearanceStyle.usesLiquidGlass,
            isVisible: true,
            transition: transition
        )

        let iconSize: CGFloat = isLegacy ? AetherLegacySearchFieldMetrics.contentHeight : 20.0
        let innerHorizontalInset = isLegacy ? AetherLegacySearchFieldMetrics.horizontalInset : 10.0
        let iconX = insetL + innerHorizontalInset
        let iconY = pillY + floor((fieldHeight - iconSize) / 2.0)
        transition.updateFrame(node: iconNode, frame: CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize))

        // The iOS 18 component lays its direct icon/text children next to one
        // another inside 8-pt field padding. Liquid Glass keeps the existing
        // roomier icon-to-label spacing.
        let iconToLabelSpacing: CGFloat = isLegacy ? 0.0 : 10.0
        let labelX = iconX + iconSize + iconToLabelSpacing
        let labelRightInset = isLegacy ? AetherLegacySearchFieldMetrics.horizontalInset : 10.0
        let labelWidth = max(0, pillFrame.maxX - labelX - labelRightInset)
        let labelHeight = AetherLegacySearchFieldMetrics.contentHeight
        let labelY = pillY + floor((fieldHeight - labelHeight) / 2.0)
        transition.updateFrame(
            node: placeholderNode,
            frame: CGRect(x: labelX, y: labelY, width: labelWidth, height: labelHeight)
        )

        return size
    }

    // MARK: - Active/Inactive State

    /// Hides icon and label (keeps glass background) when search is active.
    /// Called by `AetherSearchController` — not for direct use.
    public func setSearchActive(_ active: Bool) {
        iconNode.alpha = active ? 0 : 1
        placeholderNode.alpha = active ? 0 : 1
        // Disable tap gesture when text field is active inside
        gestureRecognizers?.forEach { $0.isEnabled = !active }
    }

    func updateIconTintColor(_ color: UIColor) {
        iconTintColor = color
        updateIconAppearance()
    }

    // MARK: - Private

    @objc private func tapped() {
        onTap?()
    }

    private func updateIconAppearance() {
        let color = iconTintColor.resolvedColor(with: traitCollection)
        iconNode.tintColor = color
        iconNode.view.setMonochromaticEffect(
            tintColor: color
        )
    }

    private func updatePlaceholderNode() {
        placeholderNode.attributedText = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: UIFont.aetherScaledSystemFont(ofSize: 17),
                .foregroundColor: UIColor.secondaryLabel.resolvedColor(with: traitCollection)
            ]
        )
    }

    private func updatePressRenderer(for style: AetherAppearanceStyle) {
        if style.usesLiquidGlass {
            if let classicPressRecognizer {
                removeGestureRecognizer(classicPressRecognizer)
                self.classicPressRecognizer = nil
            }
            pillView.alpha = 1
            pillView.transform = .identity
            if #unavailable(iOS 26.0), elasticPressRecognizer == nil {
                let elastic = GlassHighlightGestureRecognizer(target: nil, action: nil)
                elastic.motionProfile = AetherMotion.navigationButtonPress
                elastic.touchEffectView = self
                elastic.highlightContainerView = pillView.contentView
                addGestureRecognizer(elastic)
                elasticPressRecognizer = elastic
            }
        } else {
            if let elasticPressRecognizer {
                elasticPressRecognizer.resetVisualState()
                removeGestureRecognizer(elasticPressRecognizer)
                self.elasticPressRecognizer = nil
            }
            guard classicPressRecognizer == nil else { return }
            let classic = AetherClassicPressGestureRecognizer(
                target: self,
                action: #selector(classicPressChanged(_:))
            )
            classic.cancelsTouchesInView = false
            addGestureRecognizer(classic)
            classicPressRecognizer = classic
        }
    }

    @objc private func classicPressChanged(_ recognizer: UIGestureRecognizer) {
        let pressed = recognizer.state == .began || recognizer.state == .changed
        let tokens = AetherLegacySurfaceTokens.resolve(
            role: .input,
            traitCollection: traitCollection
        )
        let changes = {
            self.pillView.alpha = pressed ? tokens.pressedAlpha : 1
            let scale = pressed ? tokens.pressedScale : 1
            self.pillView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        if tokens.animationDuration == 0 {
            changes()
        } else {
            UIView.animate(
                withDuration: tokens.animationDuration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: changes
            )
        }
    }
}

extension AetherSearchBarContent: AetherAppearanceConsumer {
    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        let resolvedStyle = appearanceStyleOverride ?? appearance.style
        let metricsChanged = resolvedStyle != appliedAppearanceStyle
        appliedAppearanceStyle = resolvedStyle
        updatePressRenderer(for: resolvedStyle)
        if metricsChanged {
            invalidateLayout(transition: animated
                ? .animated(duration: AetherMotion.search.presentation.duration, curve: .easeInOut)
                : .immediate)
        } else {
            setNeedsLayout()
        }
    }
}
