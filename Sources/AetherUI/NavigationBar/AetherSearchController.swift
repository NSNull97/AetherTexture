import UIKit
import AsyncDisplayKit

// MARK: - Delegate Protocol

/// Delegate for `AetherSearchController` lifecycle and text events.
///
/// Implement to react to search activation, text changes, and dismissal.
/// All methods have default empty implementations.
public protocol AetherSearchControllerDelegate: AnyObject {
    /// Called when search is about to activate (pill → text field).
    func searchControllerWillActivate(_ controller: AetherSearchController)

    /// Called after search has activated and the text field is first responder.
    func searchControllerDidActivate(_ controller: AetherSearchController)

    /// Called when the search text changes.
    func searchController(_ controller: AetherSearchController, didChangeText text: String)

    /// Called when the user taps the return key.
    func searchController(_ controller: AetherSearchController, didSubmitText text: String)

    /// Called when search is about to deactivate (text field → pill).
    func searchControllerWillDeactivate(_ controller: AetherSearchController)

    /// Called after search has fully deactivated and the nav bar is restored.
    func searchControllerDidDeactivate(_ controller: AetherSearchController)
}

// Default implementations (all optional)
public extension AetherSearchControllerDelegate {
    func searchControllerWillActivate(_ controller: AetherSearchController) {}
    func searchControllerDidActivate(_ controller: AetherSearchController) {}
    func searchController(_ controller: AetherSearchController, didChangeText text: String) {}
    func searchController(_ controller: AetherSearchController, didSubmitText text: String) {}
    func searchControllerWillDeactivate(_ controller: AetherSearchController) {}
    func searchControllerDidDeactivate(_ controller: AetherSearchController) {}
}

// MARK: - Search Controller

/// Glass-styled search controller that integrates with `ViewController`'s navigation bar.
///
/// ## Integration
///
/// Set on `ViewController.searchController`. The framework automatically
/// shows a glass search pill in the nav bar expansion area (between title and
/// content like filter chips).
///
/// ```swift
/// let search = AetherSearchController()
/// search.placeholder = "Search"
/// search.delegate = self
/// searchController = search
/// ```
///
/// ## Activation Flow
///
/// 1. User taps the search pill in the nav bar
/// 2. Title and buttons fade out (easeInOut 0.3s)
/// 3. Filter chips fade out, nav bar shrinks
/// 4. Search pill slides up to the title position
/// 5. Pill's icon/label hide, real `UITextField` appears inside
/// 6. Glass close button (36pt) appears to the right of the pill
/// 7. Keyboard shows, collection content animates up
///
/// ## Deactivation Flow
///
/// 1. User taps the close button (or `deactivate()` is called)
/// 2. Keyboard dismisses simultaneously with UI restoration
/// 3. Close button scales down and fades
/// 4. Text field removed, pill icon/label restored
/// 5. Nav bar expands back, title/buttons/filters fade in
/// 6. Collection content animates down
///
/// ## Tab Bar Integration
///
/// When the owning `ViewController` is inside a `AetherTabBarController`,
/// the tab bar's search item button can trigger activation:
///
/// ```swift
/// override func tabBarActivateSearch() {
///     searchController?.activate()
/// }
/// ```
///
/// ## Results Controller
///
/// Optionally set `searchResultsController` to display a custom results view
/// when search is active:
///
/// ```swift
/// search.searchResultsController = MySearchResultsController()
/// ```
///
/// The results controller receives text updates via
/// `AetherSearchContentController.searchTextUpdated(text:)`.
public final class AetherSearchController: NSObject, UITextFieldDelegate {

    /// Search bar placement mode, determined automatically.
    public enum Placement {
        /// Search pill in the nav bar (between title and content). Used when
        /// the view controller is inside a `AetherTabBarController`.
        case navBar
        /// Floating search pill at the bottom of the screen with edge effect.
        /// Used when there is no tab bar controller in the hierarchy.
        case bottom
    }

    // MARK: - Public Properties

    /// Placeholder text for the search field.
    public var placeholder: String = "Search" {
        didSet {
            searchBarStorage?.placeholder = placeholder
            bottomPillLabel?.attributedText = bottomPillPlaceholderAttributedText()
        }
    }

    /// Delegate for search lifecycle and text events.
    public weak var delegate: AetherSearchControllerDelegate?

    /// Whether search is currently active.
    public private(set) var isActive: Bool = false

    /// Current search text (empty when inactive).
    public var searchText: String {
        textField?.text ?? ""
    }

    /// Optional controller that displays search results.
    /// Its `searchTextUpdated(text:)` is called on every text change.
    public var searchResultsController: AetherSearchContentController? {
        didSet {
            guard searchResultsController !== oldValue else { return }
            removeSearchResults(animated: false)
            if isActive, let viewController {
                installSearchResults(in: viewController)
            }
        }
    }

    /// Size of the glass close button (default 36pt).
    public var closeButtonSize: CGFloat = 44.0

    /// Force search to bottom mode even when a tab bar controller is present.
    /// Default `false` — placement is determined automatically.
    public var prefersBottomPlacement: Bool = false

    /// Current placement (determined automatically when installed on a ViewController).
    public private(set) var placement: Placement = .navBar

    // MARK: - Internal Views

    /// The search pill is allocated only after placement and local appearance
    /// have been resolved. A bottom-only or locally-Legacy controller must not
    /// briefly construct a global Liquid renderer during its own init.
    private var searchBarStorage: AetherSearchBarContent?
    var searchBar: AetherSearchBarContent {
        if let searchBarStorage {
            return searchBarStorage
        }
        let style = currentResolvedAppearance()?.appearanceStyle
            ?? inheritedAppearance.style
        let searchBar = AetherSearchBarContent(appearanceStyle: style)
        searchBar.placeholder = placeholder
        searchBar.onTap = { [weak self] in
            self?.activate()
        }
        searchBarStorage = searchBar
        return searchBar
    }

    // MARK: - Private State

    private var textField: UITextField?
    private var closeButton: GlassBarButtonView?
    private var searchDisplayController: AetherSearchDisplayController?
    private weak var installedSearchResultsController: AetherSearchContentController?
    weak var viewController: AetherViewController?
    var savedNavigationBarContent: NavigationBarContentView?
    private var inheritedAppearance: AetherAppearance

    // Bottom mode views
    private static let bottomBarHeight: CGFloat = 42.0
    private static let bottomKeyboardSpacing: CGFloat = 8.0
    private var bottomKeyboardHeight: CGFloat = 0.0
    private var bottomPill: GlassBackgroundView?
    private var bottomPillIcon: ASImageNode?
    private var bottomPillLabel: ASTextNode?
    private var bottomEdgeEffect: EdgeEffectView?
    private var bottomEdgeEffectAllocationCount = 0

    // MARK: - Init

    public override init() {
        self.inheritedAppearance = .runtimeCurrent
        super.init()
        AetherAppearanceConsumerRegistry.register(self)
    }

    // MARK: - Installation

    /// Determines placement and installs bottom pill if needed.
    /// Called by `ViewController` when this controller is assigned.
    func install(on vc: AetherViewController) {
        viewController = vc

        // Resolve placement *synchronously* on the responder chain. The
        // previous implementation deferred this to `DispatchQueue.main.async`,
        // which on apps without a tab bar caused the search pill to flash
        // briefly inside the nav bar (default placement = `.navBar`)
        // before snapping down to the bottom — visible jump on every
        // launch.
        let hasTabBarSync = Self.responderChainContainsTabBar(starting: vc)
        placement = (hasTabBarSync && !prefersBottomPlacement) ? .navBar : .bottom
        if placement == .bottom {
            installBottomPill(on: vc)
        }
        applyResolvedAppearance()
        searchBar.updateIconTintColor(resolvedPlaceholderColor(in: vc.view))

        // Edge case — the VC may not be wired into a parent yet at install
        // time (e.g. early init from outside `viewWillAppear`), in which
        // case the sync chain walk finds nothing. Re-check on the next
        // runloop tick so a late-attaching tab bar still routes the pill
        // up into the nav bar.
        if !hasTabBarSync {
            DispatchQueue.main.async { [weak self, weak vc] in
                guard let self, let vc else { return }
                guard self.placement == .bottom, !self.prefersBottomPlacement else { return }
                guard Self.responderChainContainsTabBar(starting: vc) else { return }
                // Promote to nav bar placement: tear down the bottom pill
                // and let the VC rebuild its accessory with the search pill.
                self.removeBottomPill()
                self.placement = .navBar
                vc.rebuildTopBarAccessory()
            }
        }
    }

    private static func responderChainContainsTabBar(starting responder: UIResponder) -> Bool {
        var current: UIResponder? = responder
        while let next = current?.next {
            if next is AetherTabBarController { return true }
            current = next
        }
        return false
    }

    /// Remove bottom pill if present.
    func uninstall() {
        removeSearchResults(animated: false)
        removeBottomPill()
        viewController = nil
    }

    // MARK: - Activation

    /// Activate search mode. Behavior depends on `placement`:
    /// - `.navBar`: pill becomes text field in nav bar, title fades
    /// - `.bottom`: pill shrinks, close button appears, keyboard lifts pill
    public func activate() {
        guard !isActive, let vc = viewController else { return }
        isActive = true
        delegate?.searchControllerWillActivate(self)
        installSearchResults(in: vc)

        switch placement {
        case .navBar:
            activateNavBar(vc: vc)
        case .bottom:
            activateBottom(vc: vc)
        }
    }

    /// Deactivate search. Keyboard and UI restore simultaneously.
    public func deactivate() {
        guard isActive, let vc = viewController else { return }
        isActive = false
        delegate?.searchControllerWillDeactivate(self)
        removeSearchResults(animated: true)

        switch placement {
        case .navBar:
            deactivateNavBar(vc: vc)
        case .bottom:
            deactivateBottom(vc: vc)
        }
    }

    // MARK: - Nav Bar Mode

    private func activateNavBar(vc: AetherViewController) {
        guard let navBar = vc.navigationBarView else { return }

        searchBar.setSearchActive(true)
        searchBar.rightExtraInset = closeButtonSize + 8.0

        let tf = makeTextField()
        searchBar.pillView.contentView.addSubview(tf)
        let fieldHorizontalInset = resolvedAppearance(
            in: vc,
            from: inheritedAppearance
        ).appearanceStyle == .legacy
            ? AetherLegacySearchFieldMetrics.horizontalInset
            : 12.0
        tf.frame = searchBar.pillView.bounds.insetBy(
            dx: fieldHorizontalInset,
            dy: 0
        )
        tf.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textField = tf

        let close = makeCloseButton()
        if let parent = searchBar.superview {
            parent.addSubview(close)
        } else {
            navBar.addSubview(close)
        }
        closeButton = close

        navBar.setSearchMode(true, animated: true)

        DispatchQueue.main.async { [weak self] in
            self?.layoutNavBarCloseButton()
        }

        let profile = AetherMotion.search.presentation
        UIView.animate(
            withDuration: profile.duration,
            delay: 0,
            usingSpringWithDamping: profile.dampingRatio,
            initialSpringVelocity: profile.initialVelocity,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            close.alpha = 1
            close.transform = .identity
        } completion: { [weak self] _ in
            guard let self else { return }
            self.delegate?.searchControllerDidActivate(self)
        }
    }

    private func deactivateNavBar(vc: AetherViewController) {
        textField?.resignFirstResponder()
        textField?.removeFromSuperview()
        textField = nil

        searchBar.setSearchActive(false)
        searchBar.rightExtraInset = 0
        vc.navigationBarView?.setSearchMode(false, animated: true)

        let profile = AetherMotion.search.dismissal
        UIView.animate(
            withDuration: profile.duration,
            delay: 0,
            usingSpringWithDamping: profile.dampingRatio,
            initialSpringVelocity: profile.initialVelocity,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.closeButton?.alpha = 0
            self.closeButton?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        } completion: { [weak self] _ in
            guard let self else { return }
            self.closeButton?.removeFromSuperview()
            self.closeButton = nil
            self.delegate?.searchControllerDidDeactivate(self)
        }
    }

    private func layoutNavBarCloseButton() {
        guard let close = closeButton else { return }
        let s = closeButtonSize
        let pillFrame = searchBar.frame
        let parentBounds = searchBar.superview?.bounds ?? .zero
        let x = parentBounds.width - s - searchBar.horizontalInset
        let y = pillFrame.midY - s / 2
        setFrame(CGRect(x: x, y: y, width: s, height: s), forTransformedView: close)
    }

    // MARK: - Bottom Mode

    private func installBottomPill(on vc: AetherViewController) {
        // Resolve the inherited + controller-local generation before any
        // renderer is allocated. Legacy bottom search must never briefly
        // construct an EdgeEffectView (or a Liquid pill renderer).
        let resolvedStyle = resolvedAppearance(
            in: vc,
            from: inheritedAppearance
        ).appearanceStyle

        let pill = GlassBackgroundView(
            style: .regular,
            appearanceStyle: resolvedStyle
        )
        pill.surfaceRole = .input
        // Legacy search is the iOS tertiary-filled field from the reference,
        // not an attached chrome material.
        pill.legacyUsesBlurMaterial = false
        pill.isUserInteractionEnabled = true
        // We `bringSubviewToFront` again from the VC's `viewDidLayoutSubviews`
        // (see AetherUI ViewController) so the pill stays on top even if
        // the host adds the collection / scroll view AFTER it. Without
        // that, sync `install` called from `viewDidLoad` ends up placing
        // the pill below content the host adds later in viewDidLoad.
        // Attach the tap gesture to `pill.contentView`, NOT to the
        // `pill` itself. `GlassBackgroundView.hitTest` forwards into
        // `contentContainer.hitTest`, which deliberately returns nil
        // when none of its descendants accept the touch AND the
        // container itself has no gesture recognisers — that's the
        // "glass surface should pass touches through" behaviour the
        // class was designed for. Adding the gesture on the bare pill
        // therefore got swallowed by that filter, which is why the
        // bottom pill appeared but couldn't be tapped after the
        // initial layout settled. Putting the gesture on the
        // `contentContainer` makes the filter find a recogniser and
        // capture the touch.
        pill.contentView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(bottomPillTapped))
        )
        pill.contentView.input_setInputAccessoryHeightProvider { [weak self] in
            guard let self, self.isActive else { return 0.0 }
            return Self.bottomBarHeight + Self.bottomKeyboardSpacing
        }
        vc.view.addSubview(pill)
        bottomPill = pill

        let icon = ASImageNode()
        icon.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))?.withRenderingMode(.alwaysTemplate)
        icon.contentMode = .center
        icon.view.isUserInteractionEnabled = false
        pill.contentView.addSubview(icon.view)
        bottomPillIcon = icon
        updateBottomIconAppearance(in: vc.view)

        let label = ASTextNode()
        label.maximumNumberOfLines = 1
        label.truncationMode = .byTruncatingTail
        label.attributedText = bottomPillPlaceholderAttributedText()
        label.view.isUserInteractionEnabled = false
        pill.contentView.addSubview(label.view)
        bottomPillLabel = label

        synchronizeBottomEdgeEffect(
            for: resolvedStyle,
            in: vc.view
        )
        layoutBottomPill(in: vc.view)
    }

    private func synchronizeBottomEdgeEffect(
        for style: AetherAppearanceStyle,
        in hostView: UIView
    ) {
        guard placement == .bottom, bottomPill != nil else {
            removeBottomEdgeEffect()
            return
        }

        guard style.usesLiquidGlass else {
            removeBottomEdgeEffect()
            return
        }

        if let bottomEdgeEffect {
            bottomEdgeEffect.appearanceStyleOverride = style
            return
        }

        let edge = EdgeEffectView()
        bottomEdgeEffectAllocationCount += 1
        edge.appearanceStyleOverride = style
        edge.isUserInteractionEnabled = false
        if let bottomPill, bottomPill.superview === hostView {
            hostView.insertSubview(edge, belowSubview: bottomPill)
        } else {
            hostView.addSubview(edge)
        }
        bottomEdgeEffect = edge
    }

    private func removeBottomEdgeEffect() {
        // Re-resolving the existing renderer as Legacy tears down any blur
        // backend before the view leaves the hierarchy. Nil the owner in the
        // same synchronous update so a subsequent Liquid switch allocates a
        // fresh edge surface.
        bottomEdgeEffect?.appearanceStyleOverride = .legacy
        bottomEdgeEffect?.removeFromSuperview()
        bottomEdgeEffect = nil
    }

    private func removeBottomPill() {
        bottomPill?.removeFromSuperview()
        removeBottomEdgeEffect()
        bottomPill = nil
        bottomPillIcon = nil
        bottomPillLabel = nil
    }

    private func bottomPillY(in view: UIView) -> CGFloat {
        let safeBottom = view.safeAreaInsets.bottom
        return view.bounds.height - max(25.0, safeBottom + 8.0) - Self.bottomBarHeight
    }

    func layoutBottomPill(in view: UIView) {
        guard let pill = bottomPill, !isActive else { return }
        let h = Self.bottomBarHeight
        let side: CGFloat = 16.0
        let y = bottomPillY(in: view)
        let isDark = view.traitCollection.userInterfaceStyle == .dark

        // Keep the pill + frost above content the host adds after the
        // search controller was installed. Sync placement (post-fix)
        // can land the pill in the view hierarchy *before* the host
        // VC adds its scroll/collection view in `viewDidLoad`, so the
        // collection ends up on top by default. Re-asserting z-order
        // on each layout keeps the pill tappable and visible.
        if let edge = bottomEdgeEffect {
            view.bringSubviewToFront(edge)
        }
        view.bringSubviewToFront(pill)

        if let edge = bottomEdgeEffect {
            let edgeH: CGFloat = 48.0
            let edgeFrame = CGRect(x: 0, y: y - edgeH + 72, width: view.bounds.width, height: 72)
            edge.frame = edgeFrame
            let searchAppearance = viewController?.resolvedSearchAppearance(
                surface: .bottomSearch,
                placement: .standaloneBottom
            ) ?? AetherSearchAppearanceResolver.resolve(
                context: AetherAppearanceResolutionContext(
                    appearance: AetherAppearance.runtimeCurrent,
                    surface: .bottomSearch,
                    placement: .standaloneBottom,
                    traitCollection: view.traitCollection
                )
            )
            let edgeAppearance = searchAppearance.edgeEffect
            let hasVisibleEdgeEffect = edgeAppearance.alpha > 0.001
                || edgeAppearance.blurRadiusAtEdge > 0.001
                || edgeAppearance.blurRadiusAtFade > 0.001
            let content: UIColor = edgeAppearance.tintColor ?? .systemBackground
            edge.clipsToBounds = edgeAppearance.style != .regular
            let usesProgressiveBlur = edgeAppearance.style == .regular
            edge.update(
                content: hasVisibleEdgeEffect ? content : .clear,
                blur: hasVisibleEdgeEffect,
                alpha: edgeAppearance.alpha,
                rect: CGRect(origin: .zero, size: edgeFrame.size),
                edge: .bottom,
                edgeSize: usesProgressiveBlur ? edgeH : 0.0,
                blurRadiusAtEdge: edgeAppearance.blurRadiusAtEdge,
                blurRadiusAtFade: usesProgressiveBlur ? 0.0 : edgeAppearance.blurRadiusAtEdge,
                solidBlur: !usesProgressiveBlur,
                minimumFadeAlpha: usesProgressiveBlur ? 0.0 : 0.04,
                transition: .immediate
            )
            edge.isHidden = !hasVisibleEdgeEffect
        }

        let frame = CGRect(x: side, y: y, width: view.bounds.width - side * 2, height: h)
        pill.frame = frame
        pill.update(size: frame.size, cornerRadius: h / 2, isDark: isDark,
                    tintColor: .init(kind: .panel), isInteractive: true, isVisible: true, transition: .immediate)
        bottomPillIcon?.frame = CGRect(x: 14, y: (h - 18) / 2, width: 18, height: 18)
        if let label = bottomPillLabel {
            let labelWidth = max(0.0, frame.width - 48)
            let measuredHeight = label.attributedText?.boundingRect(
                with: CGSize(width: labelWidth, height: h),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height ?? h
            let labelHeight = min(h, max(1.0, ceil(measuredHeight)))
            label.frame = CGRect(
                x: 38,
                y: floor((h - labelHeight) / 2.0),
                width: labelWidth,
                height: labelHeight
            )
        }
    }
    
    public func updateEdgeEffect(color: UIColor) {
        if let edge = bottomEdgeEffect {
            edge.updateColor(color: color, transition: .immediate)
        }
    }

    /// Re-materializes Texture-backed dynamic colors and glass parameters
    /// after the host controller changes light/dark appearance. UIKit views
    /// update dynamic colors automatically, while `ASImageNode` /
    /// `ASTextNode` need their values assigned again to redraw immediately.
    func appearanceDidChange(in view: UIView) {
        let placeholderColor = resolvedPlaceholderColor(in: view)
        searchBarStorage?.updateIconTintColor(placeholderColor)
        updateBottomIconAppearance(in: view, color: placeholderColor)
        bottomPillLabel?.attributedText = bottomPillPlaceholderAttributedText()
        textField?.textColor = .label
        textField?.placeholder = placeholder
        (textField?.leftView as? AetherSearchIconLeftView)?.updateTintColor(placeholderColor)
        closeButton?.contentTintColor = .label
        searchBarStorage?.setNeedsLayout()

        guard placement == .bottom else { return }
        if isActive {
            layoutBottomSearchActive(in: view)
        } else {
            layoutBottomPill(in: view)
        }
    }

    @objc private func bottomPillTapped() {
        activate()
    }

    private func activateBottom(vc: AetherViewController) {
        guard let pill = bottomPill else { return }
        let h = Self.bottomBarHeight

        if let edge = bottomEdgeEffect {
            vc.view.bringSubviewToFront(edge)
        }
        vc.view.bringSubviewToFront(pill)

        bottomPillIcon?.isHidden = true
        bottomPillLabel?.isHidden = true

        let tf = makeTextField()
        pill.contentView.addSubview(tf)
        tf.frame = CGRect(x: 8, y: 0, width: pill.bounds.width - 16, height: h)
        textField = tf
        let close = makeCloseButton()
        vc.view.addSubview(close)
        let pillFrame = pill.frame
        setFrame(
            CGRect(x: pillFrame.maxX, y: pillFrame.minY, width: h, height: h),
            forTransformedView: close
        )
        closeButton = close

        let profile = AetherMotion.search.presentation
        UIView.animate(
            withDuration: profile.duration,
            delay: 0,
            usingSpringWithDamping: profile.dampingRatio,
            initialSpringVelocity: profile.initialVelocity,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.layoutBottomSearchActive(in: vc.view)
            close.alpha = 1
            close.transform = .identity
        } completion: { [weak self] _ in
            guard let self else { return }
            self.delegate?.searchControllerDidActivate(self)
        }

        // Install and lay out both controls before focusing: UIKit can send
        // the keyboard layout synchronously from becomeFirstResponder().
        if !tf.becomeFirstResponder() {
            DispatchQueue.main.async { [weak self, weak tf] in
                guard let self, self.isActive, self.textField === tf else { return }
                tf?.becomeFirstResponder()
            }
        }
    }

    private func deactivateBottom(vc: AetherViewController) {
        textField?.resignFirstResponder()

        let profile = AetherMotion.search.dismissal
        UIView.animate(
            withDuration: profile.duration,
            delay: 0,
            usingSpringWithDamping: profile.dampingRatio,
            initialSpringVelocity: profile.initialVelocity,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.closeButton?.alpha = 0
            self.closeButton?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            self.layoutBottomPill(in: vc.view)
        } completion: { [weak self] _ in
            guard let self else { return }
            self.textField?.removeFromSuperview()
            self.textField = nil
            self.closeButton?.removeFromSuperview()
            self.closeButton = nil
            self.bottomPillIcon?.isHidden = false
            self.bottomPillLabel?.isHidden = false
            self.delegate?.searchControllerDidDeactivate(self)
        }
    }

    func layoutBottomSearchActive(
        in view: UIView,
        keyboardHeight: CGFloat? = nil,
        transition: ContainedViewLayoutTransition = .immediate
    ) {
        guard let pill = bottomPill else { return }
        if let keyboardHeight {
            bottomKeyboardHeight = max(0.0, keyboardHeight)
        }
        let h = Self.bottomBarHeight
        let side: CGFloat = 16.0
        let isDark = view.traitCollection.userInterfaceStyle == .dark
        let kbH = bottomKeyboardHeight
        let baseY = kbH > 0 ? view.bounds.height - kbH - h - Self.bottomKeyboardSpacing : bottomPillY(in: view)
        let closeX = view.bounds.width - side - h
        let pillWidth = closeX - side - 8

        if let closeButton {
            transition.updateBounds(view: closeButton, bounds: CGRect(x: 0, y: 0, width: h, height: h))
            transition.updatePosition(
                view: closeButton,
                position: CGPoint(x: closeX + h / 2, y: baseY + h / 2)
            )
        }
        let pillFrame = CGRect(x: side, y: baseY, width: pillWidth, height: h)
        transition.updateFrame(view: pill, frame: pillFrame)
        pill.update(size: pillFrame.size, cornerRadius: h / 2, isDark: isDark,
                    tintColor: .init(kind: .panel), isInteractive: false, isVisible: true, transition: transition)
        if let textField {
            transition.updateFrame(view: textField, frame: CGRect(x: 8, y: 0, width: pillWidth - 16, height: h))
        }

        if let edge = bottomEdgeEffect {
            let edgeH: CGFloat = 48.0
            let edgeFrame = CGRect(x: 0, y: baseY - edgeH, width: view.bounds.width, height: view.bounds.height - baseY + edgeH)
            transition.updateFrame(view: edge, frame: edgeFrame)
            let searchAppearance = viewController?.resolvedSearchAppearance(
                surface: .bottomSearch,
                placement: .standaloneBottom
            ) ?? AetherSearchAppearanceResolver.resolve(
                context: AetherAppearanceResolutionContext(
                    appearance: AetherAppearance.runtimeCurrent,
                    surface: .bottomSearch,
                    placement: .standaloneBottom,
                    traitCollection: view.traitCollection
                )
            )
            let edgeAppearance = searchAppearance.edgeEffect
            let hasVisibleEdgeEffect = edgeAppearance.alpha > 0.001
                || edgeAppearance.blurRadiusAtEdge > 0.001
                || edgeAppearance.blurRadiusAtFade > 0.001
            let content = edgeAppearance.tintColor ?? .systemBackground
            edge.clipsToBounds = edgeAppearance.style != .regular
            let usesProgressiveBlur = edgeAppearance.style == .regular
            edge.update(
                content: hasVisibleEdgeEffect ? content : .clear,
                blur: hasVisibleEdgeEffect,
                alpha: edgeAppearance.alpha,
                rect: CGRect(origin: .zero, size: edgeFrame.size),
                edge: .bottom,
                edgeSize: usesProgressiveBlur ? edgeH : 0.0,
                blurRadiusAtEdge: edgeAppearance.blurRadiusAtEdge,
                blurRadiusAtFade: usesProgressiveBlur ? 0.0 : edgeAppearance.blurRadiusAtEdge,
                solidBlur: !usesProgressiveBlur,
                minimumFadeAlpha: usesProgressiveBlur ? 0.0 : 0.04,
                transition: transition
            )
            edge.isHidden = !hasVisibleEdgeEffect
        }
    }

    /// `UIView.frame` is undefined while a non-identity transform is active.
    /// Search close buttons start at scale 0.5, so assigning `frame` would
    /// double their bounds and leave an oversized circle after the scale-in.
    private func setFrame(_ frame: CGRect, forTransformedView view: UIView) {
        view.bounds = CGRect(origin: .zero, size: frame.size)
        view.center = CGPoint(x: frame.midX, y: frame.midY)
    }

    // MARK: - UITextFieldDelegate

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = textField.text ?? ""
        delegate?.searchController(self, didSubmitText: text)
        if let searchDisplayController {
            searchDisplayController.updateSearchText(text)
        } else {
            searchResultsController?.searchTextUpdated(text: text)
        }
        return true
    }

    // MARK: - Private

    private func makeTextField() -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.font = .aetherScaledSystemFont(ofSize: 17)
        tf.textColor = .label
        tf.tintColor = .systemBlue
        tf.returnKeyType = .search
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.clearButtonMode = .whileEditing
        tf.delegate = self

        // Wrapper that pins the icon to the LEFT edge so the "after
        // icon" gap controls visible padding between glyph and
        // placeholder. Matches TabBarView search field's leftView.
        let hostView = viewController?.viewIfLoaded ?? viewController?.view
        let iconColor = hostView.map(resolvedPlaceholderColor(in:)) ?? .secondaryLabel
        tf.leftView = AetherSearchIconLeftView()
        (tf.leftView as? AetherSearchIconLeftView)?.updateTintColor(iconColor)
        tf.leftViewMode = .always

        tf.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        return tf
    }

    private func makeCloseButton() -> GlassBarButtonView {
        let icon = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        )
        let btn = GlassBarButtonView(
            icon: icon,
            state: .glass,
            appearanceStyle: currentResolvedAppearance()?.appearanceStyle
        )
        btn.contentTintColor = .label
        btn.alpha = 0
        btn.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        btn.action = { [weak self] _ in self?.closeTapped() }
        return btn
    }

    private func resolvedAppearance(
        in viewController: AetherViewController,
        from appearance: AetherAppearance
    ) -> AetherSearchResolvedAppearance {
        AetherAppearance.withRuntimeCurrent(appearance) {
            viewController.resolvedSearchAppearance(
                surface: placement == .bottom ? .bottomSearch : .search,
                placement: placement == .bottom ? .standaloneBottom : .top
            )
        }
    }

    private func currentResolvedAppearance() -> AetherSearchResolvedAppearance? {
        guard let viewController else { return nil }
        return resolvedAppearance(
            in: viewController,
            from: inheritedAppearance
        )
    }

    private func applyResolvedAppearance() {
        guard let resolved = currentResolvedAppearance() else { return }
        let style = resolved.appearanceStyle
        if placement == .navBar {
            searchBar.appearanceStyleOverride = style
        } else {
            searchBarStorage?.appearanceStyleOverride = style
        }
        bottomPill?.appearanceStyleOverride = style
        if let hostView = viewController?.viewIfLoaded {
            synchronizeBottomEdgeEffect(for: style, in: hostView)
        } else if !style.usesLiquidGlass {
            removeBottomEdgeEffect()
        }
        closeButton?.appearanceStyleOverride = style
        viewController?.viewIfLoaded?.setNeedsLayout()
    }

    internal var bottomEdgeEffectForTesting: EdgeEffectView? {
        bottomEdgeEffect
    }

    internal var bottomPillForTesting: GlassBackgroundView? {
        bottomPill
    }

    internal var hasAllocatedSearchBarForTesting: Bool {
        searchBarStorage != nil
    }

    internal var bottomEdgeEffectAllocationCountForTesting: Int {
        bottomEdgeEffectAllocationCount
    }

    internal var resolvedAppearanceStyleForTesting: AetherAppearanceStyle? {
        currentResolvedAppearance()?.appearanceStyle
    }

    private func bottomPillPlaceholderAttributedText() -> NSAttributedString {
        let hostView = viewController?.viewIfLoaded
        let color = hostView.map(resolvedPlaceholderColor(in:))
            ?? UIColor.secondaryLabel.resolvedColor(with: UITraitCollection.current)
        return NSAttributedString(
            string: placeholder,
            attributes: [
                .font: UIFont.aetherScaledSystemFont(ofSize: 17),
                .foregroundColor: color
            ]
        )
    }

    private func updateBottomIconAppearance(in view: UIView, color: UIColor? = nil) {
        let color = color ?? resolvedPlaceholderColor(in: view)
        bottomPillIcon?.tintColor = color
        bottomPillIcon?.view.setMonochromaticEffect(
            tintColor: color
        )
    }

    private func resolvedPlaceholderColor(in view: UIView) -> UIColor {
        let appearance = viewController?.resolvedSearchAppearance(
            surface: placement == .bottom ? .bottomSearch : .search,
            placement: placement == .bottom ? .standaloneBottom : .top
        ) ?? AetherSearchAppearanceResolver.resolve(
            context: AetherAppearanceResolutionContext(
                appearance: AetherAppearance.runtimeCurrent,
                surface: placement == .bottom ? .bottomSearch : .search,
                placement: placement == .bottom ? .standaloneBottom : .top,
                traitCollection: view.traitCollection
            )
        )
        let traits = UITraitCollection(traitsFrom: [
            view.traitCollection,
            UITraitCollection(
                userInterfaceStyle: appearance.overallDarkAppearance ? .dark : .light
            )
        ])
        return appearance.placeholderColor.resolvedColor(with: traits)
    }

    private func closeTapped() {
        deactivate()
    }

    @objc private func textDidChange() {
        let text = textField?.text ?? ""
        delegate?.searchController(self, didChangeText: text)
        if let searchDisplayController {
            searchDisplayController.updateSearchText(text)
        } else {
            searchResultsController?.searchTextUpdated(text: text)
        }
    }

    func containerLayoutUpdated(
        _ layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition
    ) {
        bottomKeyboardHeight = max(0.0, layout.inputHeight ?? 0.0)
        guard let viewController, let searchDisplayController else { return }
        let navigationBarHeight: CGFloat
        if placement == .navBar, let bar = viewController.navigationBarView {
            navigationBarHeight = max(0.0, bar.convert(bar.bounds, to: viewController.view).maxY)
        } else {
            navigationBarHeight = 0.0
        }
        searchDisplayController.containerLayoutUpdated(
            layout,
            navigationBarHeight: navigationBarHeight,
            transition: transition
        )
    }

    private func installSearchResults(in viewController: AetherViewController) {
        guard searchDisplayController == nil,
              let contentController = searchResultsController else { return }
        guard contentController.parent == nil || contentController.parent === viewController else { return }

        let displayController = AetherSearchDisplayController(
            contentController: contentController,
            cancel: { [weak self] in self?.deactivate() }
        )
        displayController.onDismissInput = { [weak self] in
            self?.textField?.resignFirstResponder()
        }

        let didAttach = contentController.parent == nil
        if didAttach {
            viewController.addChild(contentController)
        }
        displayController.activate(insertIn: viewController.view, above: nil)
        if didAttach {
            contentController.didMove(toParent: viewController)
        }
        searchDisplayController = displayController
        installedSearchResultsController = contentController
        displayController.updateSearchText(searchText)

        let layout = viewController.currentlyAppliedLayout ?? ContainerViewLayout(
            size: viewController.view.bounds.size,
            safeInsets: viewController.view.safeAreaInsets,
            additionalInsets: .zero
        )
        containerLayoutUpdated(layout, transition: .immediate)
    }

    private func removeSearchResults(animated: Bool) {
        searchDisplayController?.deactivate(animated: animated)
        searchDisplayController = nil
        if let contentController = installedSearchResultsController,
           contentController.parent != nil {
            contentController.willMove(toParent: nil)
            contentController.removeFromParent()
        }
        installedSearchResultsController = nil
    }
}

extension AetherSearchController: AetherAppearanceConsumer {
    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        inheritedAppearance = appearance
        applyResolvedAppearance()
    }
}
