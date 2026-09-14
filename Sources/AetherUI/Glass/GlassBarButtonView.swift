import UIKit
import AsyncDisplayKit

/// Glass-styled bar button with multiple display states.
/// Pure UIKit implementation.
///
/// **Why UIView, not UIControl:** iOS 26+ `UIGlassEffect.isInteractive`
/// needs the underlying `UIVisualEffectView` to receive touches so it
/// can observe finger position for the native liquid-surface warp. A
/// UIControl host swallows touches into its own tracking pipeline
/// before the effect view can see them, which kills the press feedback.
/// So we use a plain UIView + `UITapGestureRecognizer` and keep
/// `glassBackground.isUserInteractionEnabled = true` — matches
/// `GlassButton`'s design.
public final class GlassBarButtonView: UIView, AetherAppearanceConsumer {
    // MARK: - Types

    public enum DisplayState {
        case generic
        case glass
        case tintedGlass
    }

    // MARK: - Subviews

    private let glassBackground: GlassBackgroundView
    private let contentContainer: UIView
    /// Lease only the glyph/label; the transition owns the single glass shell.
    internal var contextMenuPresentationContentView: UIView { contentContainer }
    private var iconNode: ASImageNode?
    private var titleNode: ASTextNode?
    private var titleText: String?
    private var chromeMorphIconFrame: CGRect?

    // MARK: - Properties

    private var displayState: DisplayState = .glass
    public var action: ((UIView) -> Void)?
    private var elasticRecognizer: GlassHighlightGestureRecognizer?
    private var classicPressRecognizer: AetherClassicPressGestureRecognizer?

    public var appearanceStyleOverride: AetherAppearanceStyle? = nil {
        didSet {
            guard appearanceStyleOverride != oldValue else { return }
            glassBackground.appearanceStyleOverride = appearanceStyleOverride
            aetherApplyAppearance(.runtimeCurrent, animated: true)
        }
    }

    /// Provider for a long-press context menu. When this returns a non-empty
    /// list, the button attaches a long-press gesture that presents a
    /// `ContextMenuController` anchored at the button.
    public var contextMenuItemsProvider: (() -> [ContextMenuItem])?
    /// Haptic + presentation flavour: `.longPress` uses UILongPressGestureRecognizer,
    /// `.tap` overrides `action` and presents on tap-up.
    public enum ContextMenuTrigger { case longPress, tap }
    public var contextMenuTrigger: ContextMenuTrigger = .longPress
    /// Optional lifted source content shown above the menu.
    public var contextMenuPreview: ContextMenuController.Preview?
    private weak var currentContextController: ContextMenuController?
    private var longPressRecognizer: UILongPressGestureRecognizer?

    public var contentTintColor: UIColor = .white {
        didSet {
            updateIconAppearance()
            updateTitleNode()
        }
    }

    /// Override for the `isDark` flag passed to the glass background.
    /// `nil` (default) → derived from `traitCollection.userInterfaceStyle`
    /// on every layout pass. Forwarded to `GlassBackgroundView.isDarkOverride`
    /// so the glass also picks up the override on its own auto-layout /
    /// trait-change paths. Use when the button sits on a custom dark
    /// background while the system is in light mode (or vice versa).
    public var isDarkAppearance: Bool? {
        didSet {
            glassBackground.isDarkOverride = isDarkAppearance
            setNeedsLayout()
        }
    }

    /// Optional explicit material tint. Keeping this separate from the glyph
    /// `tintColor` lets chrome such as the tab bar and its search button share
    /// one glass tone without tinting their icons.
    public var glassTintColor: GlassBackgroundView.TintColor? {
        didSet { setNeedsLayout() }
    }

    /// Material recipe used by the backing glass. Callers that compose a
    /// control beside another chrome surface can share the exact same style
    /// instead of relying on this button's display-state default.
    public var glassStyle: GlassBackgroundView.Style {
        didSet {
            guard glassStyle != oldValue else { return }
            glassBackground.updateStyle(glassStyle)
            setNeedsLayout()
        }
    }

    /// Separate material/content channels for chrome morphs. Keeping the host
    /// view alive lets a glass surface visibly detach before its glyph handoff
    /// finishes, instead of cross-fading the whole control from transparency.
    internal var chromeMorphMaterialAlpha: CGFloat {
        get { glassBackground.transitionMaterialAlpha }
        set { glassBackground.transitionMaterialAlpha = newValue }
    }

    internal var chromeMorphContentAlpha: CGFloat {
        get { contentContainer.alpha }
        set { contentContainer.alpha = newValue }
    }

    /// Fallback renderers cannot optically union two surfaces. Hosting glyphs
    /// on GlassBackgroundView's transition-content plane lets the material
    /// fade at the expanded overlap without fading the stable Search icon.
    /// Native grouped glass keeps the default content host so UIKit can deform
    /// material and icon together on press.
    internal var chromeMorphKeepsContentIndependentOfMaterial = false {
        didSet {
            guard chromeMorphKeepsContentIndependentOfMaterial != oldValue else { return }
            let host = chromeMorphKeepsContentIndependentOfMaterial
                ? glassBackground.transitionContentView
                : glassBackground.contentView
            host.addSubview(contentContainer)
            setNeedsLayout()
        }
    }

    /// Drives an icon-only control between an expanded tab-slot position and
    /// its compact centered position without swapping glyph owners.
    internal func updateChromeMorphIconFrame(
        _ frame: CGRect,
        transition: ContainedViewLayoutTransition
    ) {
        chromeMorphIconFrame = frame
        if let iconNode, titleNode == nil {
            transition.updateFrame(node: iconNode, frame: frame)
        }
    }
    
    public override var tintColor: UIColor! {
        didSet {
            glassBackground.glassTintColor = .init(kind: .custom(style: .clear, color: tintColor))
        }
    }

    private var tapRecognizer: UITapGestureRecognizer?

    // MARK: - Init

    public init(
        icon: UIImage? = nil,
        title: String? = nil,
        state: DisplayState = .glass,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        let initialGlassStyle: GlassBackgroundView.Style = state == .tintedGlass ? .prominent : .regular
        self.displayState = state
        self.glassStyle = initialGlassStyle
        self.appearanceStyleOverride = appearanceStyle
        self.glassBackground = GlassBackgroundView(
            style: initialGlassStyle,
            appearanceStyle: appearanceStyle
        )
        self.contentContainer = UIView()

        super.init(frame: .zero)

        glassBackground.surfaceRole = .button

        // Keep interaction ON on the glass so iOS 26+
        // UIGlassEffect.isInteractive can observe finger position for
        // the native surface warp. Tap dispatch goes via a
        // UITapGestureRecognizer on self (below).
        glassBackground.isUserInteractionEnabled = true
        addSubview(glassBackground)

        // Content sits inside the glass's own content host so
        // UIGlassEffect's warp deforms both surface and icon in
        // lockstep — otherwise only the glass jelly wobbles while
        // the icon stays pinned (barely visible). Same trick as
        // GlassButton.
        contentContainer.isUserInteractionEnabled = false
        glassBackground.contentView.addSubview(contentContainer)

        if let icon = icon {
            let imageNode = ASImageNode()
            imageNode.image = icon.withRenderingMode(.alwaysTemplate)
            imageNode.contentMode = .center
            imageNode.view.isUserInteractionEnabled = false
            contentContainer.addSubview(imageNode.view)
            self.iconNode = imageNode
            updateIconAppearance()
        }

        if let title = title {
            let node = ASTextNode()
            node.maximumNumberOfLines = 1
            node.truncationMode = .byTruncatingTail
            node.view.isUserInteractionEnabled = false
            self.titleText = title
            self.titleNode = node
            updateTitleNode()
            contentContainer.addSubview(node.view)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        self.tapRecognizer = tap

        let classicPress = AetherClassicPressGestureRecognizer(
            target: self,
            action: #selector(handleClassicPress(_:))
        )
        addGestureRecognizer(classicPress)
        classicPressRecognizer = classicPress

        let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        long.minimumPressDuration = 0.2
        long.cancelsTouchesInView = false
        addGestureRecognizer(long)
        self.longPressRecognizer = long

        AetherAppearanceConsumerRegistry.register(self)
        aetherApplyAppearance(.runtimeCurrent, animated: false)
    }

    internal var backingUsesLiquidGlassAppearanceForTesting: Bool {
        glassBackground.usesLiquidGlassAppearance
    }

    internal var backingUsesAnyGlassRendererForTesting: Bool {
        glassBackground.usesAnyGlassRendererForTesting
    }

    internal var backingLegacyBlurStyleForTesting: UIBlurEffect.Style? {
        glassBackground.legacyBlurStyleForTesting
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        iconNode?.view.removeFromSuperview()
        titleNode?.view.removeFromSuperview()
    }

    // MARK: - Trait changes

    /// `setMonochromaticEffect` writes `overrideUserInterfaceStyle` on
    /// the icon view based on the *resolved* tint color at construction
    /// time — once captured, that override freezes the icon in its
    /// original light/dark mapping and the system trait change can no
    /// longer flow through. Re-applying the tint here recomputes the
    /// override against the current trait collection so dynamic colors
    /// (`.label`, `.secondaryLabel`, etc.) follow the new appearance.
    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            updateIconAppearance()
        }
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle
            || previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            updateTitleNode()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    // MARK: - Layout

    private func updateIconAppearance() {
        let resolvedColor = contentTintColor.resolvedColor(with: traitCollection)
        iconNode?.tintColor = resolvedColor
        iconNode?.view.setMonochromaticEffect(
            tintColor: resolvedColor
        )
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        let resolvedDark = isDarkAppearance ?? (traitCollection.userInterfaceStyle == .dark)
        glassBackground.frame = bounds
        let cornerRadius = bounds.height / 2.0
        if #available(iOS 26.0, *) {
            glassBackground.setNativeUniformCornerRadius(cornerRadius)
        }
        glassBackground.update(
            size: bounds.size,
            cornerRadius: cornerRadius,
            isDark: resolvedDark,
            tintColor: glassTintColor ?? .init(kind: .panel),
            isInteractive: displayState == .glass || displayState == .tintedGlass,
            isVisible: true,
            transition: .immediate
        )
        contentContainer.frame = bounds

        if let iconNode = iconNode, titleNode == nil {
            iconNode.frame = chromeMorphIconFrame ?? bounds
        } else if let titleNode = titleNode, iconNode == nil {
            titleNode.frame = bounds
        } else if let iconNode = iconNode, let titleNode = titleNode {
            let iconSize: CGFloat = 20
            let spacing: CGFloat = 4
            let titleWidth = textSize(titleText, constrainedSize: bounds.size).width
            let totalWidth = iconSize + spacing + titleWidth
            let startX = (bounds.width - totalWidth) / 2
            iconNode.frame = CGRect(x: startX, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
            titleNode.frame = CGRect(x: startX + iconSize + spacing, y: 0, width: titleWidth, height: bounds.height)
        }
    }

    override public var intrinsicContentSize: CGSize {
        if titleNode != nil {
            let textSize = textSize(titleText, constrainedSize: CGSize(width: 200, height: 44))
            let iconWidth: CGFloat = iconNode != nil ? 24 : 0
            return CGSize(width: textSize.width + iconWidth + 24, height: 36)
        }
        return CGSize(width: 36, height: 36)
    }

    // MARK: - State

    public func updateState(_ state: DisplayState) {
        self.displayState = state
        switch state {
        case .generic:
            glassBackground.alpha = 0
        case .glass:
            glassBackground.alpha = 1
            glassBackground.updateStyle(.regular)
        case .tintedGlass:
            glassBackground.alpha = 1
            glassBackground.updateStyle(.prominent)
        }
    }

    @objc private func tapped() {
        // `tap` trigger takes precedence over `action` so callers can easily turn
        // a button into a menu host without replumbing their action pipelines.
        if contextMenuTrigger == .tap, let items = contextMenuItemsProvider?(), !items.isEmpty {
            presentContextMenu(items: items)
            return
        }
        action?(self)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard contextMenuTrigger == .longPress, recognizer.state == .began else { return }
        guard let items = contextMenuItemsProvider?(), !items.isEmpty else { return }
        // Suppress the tap so a single long-press opens only the menu.
        tapRecognizer?.isEnabled = false
        DispatchQueue.main.async { [weak self] in self?.tapRecognizer?.isEnabled = true }
        presentContextMenu(items: items)
    }

    private func presentContextMenu(items: [ContextMenuItem]) {
        let controller = ContextMenuController.present(
            source: self,
            cornerRadius: bounds.height / 2.0,
            items: items,
            preview: contextMenuPreview,
            appearanceStyle: appearanceStyleOverride ?? AetherAppearance.runtimeCurrent.style,
            onDismiss: { [weak self] in
                self?.currentContextController = nil
            }
        )
        currentContextController = controller
    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        let style = appearanceStyleOverride ?? appearance.style
        classicPressRecognizer?.isEnabled = !style.usesLiquidGlass
        updateElasticPressRenderer(for: style)
        if style.usesLiquidGlass {
            applyClassicPressed(false, animated: animated)
        }
    }

    private func updateElasticPressRenderer(for style: AetherAppearanceStyle) {
        guard #unavailable(iOS 26.0) else { return }
        if style.usesLiquidGlass {
            guard elasticRecognizer == nil else { return }
            let elastic = GlassHighlightGestureRecognizer(target: nil, action: nil)
            elastic.motionProfile = AetherMotion.navigationButtonPress
            elastic.touchEffectView = self
            elastic.highlightContainerView = glassBackground.contentView
            addGestureRecognizer(elastic)
            elasticRecognizer = elastic
        } else if let elasticRecognizer {
            elasticRecognizer.resetVisualState()
            removeGestureRecognizer(elasticRecognizer)
            self.elasticRecognizer = nil
        }
    }

    @objc private func handleClassicPress(_ recognizer: AetherClassicPressGestureRecognizer) {
        let inside = bounds.contains(recognizer.location(in: self))
        switch recognizer.state {
        case .began, .changed:
            applyClassicPressed(inside, animated: true)
        case .ended, .cancelled, .failed:
            applyClassicPressed(false, animated: true)
        default:
            break
        }
    }

    private func applyClassicPressed(_ pressed: Bool, animated: Bool) {
        let tokens = AetherLegacySurfaceTokens.resolve(role: .button, traitCollection: traitCollection)
        let changes = {
            self.glassBackground.alpha = pressed ? tokens.pressedAlpha : (self.displayState == .generic ? 0 : 1)
            let scale = pressed ? tokens.pressedScale : 1
            self.glassBackground.transform = CGAffineTransform(scaleX: scale, y: scale)
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

    private func updateTitleNode() {
        guard let titleNode, let titleText else { return }
        titleNode.attributedText = NSAttributedString(
            string: titleText,
            attributes: [
                .font: titleFont,
                .foregroundColor: contentTintColor.resolvedColor(with: traitCollection),
                .paragraphStyle: Self.centeredParagraphStyle
            ]
        )
        titleNode.view.accessibilityLabel = titleText
    }

    private func textSize(_ text: String?, constrainedSize: CGSize) -> CGSize {
        guard let text, !text.isEmpty else { return .zero }
        let rect = (text as NSString).boundingRect(
            with: constrainedSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: titleFont],
            context: nil
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    private var titleFont: UIFont {
        UIFont.aetherScaledSystemFont(
            ofSize: 15,
            weight: .medium,
            maximumPointSize: 20,
            compatibleWith: traitCollection
        )
    }

    private static let centeredParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }()
}
