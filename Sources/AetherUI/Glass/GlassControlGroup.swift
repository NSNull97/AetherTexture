import UIKit
import AsyncDisplayKit

/// Public UIKit does not expose a stable symbol name for every `UIImage`.
/// Navbar morphing still needs to recognise two separately-created images as
/// the same visual item, so use accessibility metadata when present and a
/// deterministic rendered fingerprint as the public fallback.
internal struct AetherImageSemanticIdentity: Hashable {
    let accessibilityIdentifier: String?
    let widthInMilliPoints: Int
    let heightInMilliPoints: Int
    let fingerprint: UInt64
    let preservesOriginalColors: Bool

    init(_ image: UIImage) {
        let identifier = image.accessibilityIdentifier?.isEmpty == false
            ? image.accessibilityIdentifier
            : nil
        self.accessibilityIdentifier = identifier
        self.widthInMilliPoints = Int((image.size.width * 1_000.0).rounded())
        self.heightInMilliPoints = Int((image.size.height * 1_000.0).rounded())
        self.fingerprint = Self.renderedFingerprint(image)
        self.preservesOriginalColors = image.renderingMode == .alwaysOriginal
    }

    var stableComponent: String {
        let identifierHash = accessibilityIdentifier.map(Self.stringFingerprint) ?? 0
        return "\(identifierHash).\(widthInMilliPoints).\(heightInMilliPoints).\(fingerprint).\(preservesOriginalColors)"
    }

    private static func stringFingerprint(_ value: String) -> UInt64 {
        fnv1a(value.utf8)
    }

    private static func renderedFingerprint(_ image: UIImage) -> UInt64 {
        if let data = image.pngData(), !data.isEmpty {
            return fnv1a(data)
        }

        let sourceSize = image.size
        guard sourceSize.width > 0.0, sourceSize.height > 0.0 else {
            return stringFingerprint(image.accessibilityIdentifier ?? "empty-image")
        }

        let maximumDimension: CGFloat = 64.0
        let scale = min(1.0, maximumDimension / max(sourceSize.width, sourceSize.height))
        let renderSize = CGSize(
            width: max(1.0, ceil(sourceSize.width * scale)),
            height: max(1.0, ceil(sourceSize.height * scale))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        let rendered = renderer.image { _ in
            image.withTintColor(.black, renderingMode: .alwaysOriginal).draw(
                in: CGRect(origin: .zero, size: renderSize)
            )
        }
        if let data = rendered.pngData(), !data.isEmpty {
            return fnv1a(data)
        }
        return stringFingerprint(image.accessibilityIdentifier ?? String(describing: image.size))
    }

    private static func fnv1a<S: Sequence>(_ bytes: S) -> UInt64 where S.Element == UInt8 {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return value
    }
}

private final class NavigationChromeMaterializationDelegate: NSObject, CAAnimationDelegate {
    private let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        completion(flag)
    }
}

// MARK: - GlassControlGroup

/// A group of controls rendered on a shared glass capsule.
/// Port of Display framework `GlassControlGroupComponent`, adapted from ComponentFlow to plain UIKit.
public final class GlassControlGroup: UIView, AetherAppearanceConsumer {
    // MARK: - Types

    public struct Item {
        public enum Content {
            case icon(UIImage)
            case text(String)
            /// Caller-provided view; the group takes ownership and lays it out inside the capsule.
            case customView(UIView)
        }

        public let id: AnyHashable
        public let content: Content
        public let action: (() -> Void)?
        public let contentInsets: UIEdgeInsets

        public init(
            id: AnyHashable,
            content: Content,
            contentInsets: UIEdgeInsets = .zero,
            action: (() -> Void)?
        ) {
            self.id = id
            self.content = content
            self.contentInsets = contentInsets
            self.action = action
        }
    }

    public enum Background: Equatable {
        case panel
        case activeTint(foregroundColor: UIColor, fillColor: UIColor)
        case color(UIColor)
    }

    // MARK: - Subviews

    private let backgroundView: GlassBackgroundView
    private let controlsView: UIView
    private var itemViews: [ItemEntry] = []

    public var appearanceStyleOverride: AetherAppearanceStyle? = nil {
        didSet {
            guard appearanceStyleOverride != oldValue else { return }
            backgroundView.appearanceStyleOverride = appearanceStyleOverride
            aetherApplyAppearance(.runtimeCurrent, animated: true)
        }
    }

    private struct ItemEntry {
        let id: AnyHashable
        let contentId: ContentId
        let button: HighlightTrackingButton
        let contentView: UIView
        var contentInsets: UIEdgeInsets
        var isInteractive: Bool
        var itemFrame: CGRect
    }

    private enum ContentId: Hashable {
        case icon(AetherImageSemanticIdentity)
        case text(String)
        case customView(ObjectIdentifier)
    }

    // MARK: - State

    public private(set) var items: [Item] = []
    public private(set) var background: Background = .panel
    public private(set) var preferClearGlass: Bool = false
    private var currentTintColor: GlassBackgroundView.TintColor = .init(kind: .panel)
    private var currentIsInteractive: Bool = false
    public var foregroundColor: UIColor = .label {
        didSet {
            applyForegroundColorToItems()
        }
    }
    /// Theme pin for the underlying glass. When set (including by
    /// `update(isDark:)` internally) the value forwards to
    /// `backgroundView.isDarkOverride`, so the glass re-renders with the
    /// override regardless of the next layout pass or trait-change event.
    /// Default `false`; assign externally before/after `update` to pin the
    /// glass tint to a specific theme (e.g. when hosted on a dark hero
    /// image while the system is in light mode).
    public var isDarkAppearance: Bool = false {
        didSet {
            if isDarkAppearance == oldValue { return }
            backgroundView.isDarkOverride = isDarkAppearance
        }
    }

    public var minWidth: CGFloat = 44.0
    public var animatesInsertedItemsAlpha: Bool = true
    /// Hosts may disable automatic material pulses while they apply a custom
    /// geometry transition. Navbar groups leave this off so unchanged
    /// separated siblings are never transformed with the changed material.
    internal var suppressesAutomaticSizeMorphPulse = false
    /// Keeps an outgoing separated group alive across intervening relayouts
    /// until its long-form disappearance animation completes.
    internal var isAwaitingAnimatedRemoval = false
    public var motionProfile: AetherMotion.Press = AetherMotion.standaloneButtonPress {
        didSet {
            elasticRecognizer?.motionProfile = motionProfile
        }
    }
    var pressedSizeIncrease: CGFloat {
        get { motionProfile.pressedSizeIncrease }
        set {
            var profile = motionProfile
            profile.pressedSizeIncrease = newValue
            motionProfile = profile
        }
    }
    private var naturalSize: CGSize = .zero
    private var updateGeneration: Int = 0

    public enum TransitionChromeContentAlignment {
        case leading
        case trailing
    }

    public var transitionContentAlignment: TransitionChromeContentAlignment = .leading

    // MARK: - Init

    private var elasticRecognizer: GlassHighlightGestureRecognizer?

    public init(
        style: GlassBackgroundView.Style = .regular,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        self.appearanceStyleOverride = appearanceStyle
        self.backgroundView = GlassBackgroundView(
            style: style,
            appearanceStyle: appearanceStyle
        )
        self.controlsView = UIView()

        super.init(frame: .zero)

        backgroundView.surfaceRole = .toolbar

        controlsView.clipsToBounds = true
        addSubview(backgroundView)
        backgroundView.contentView.addSubview(controlsView)

        AetherAppearanceConsumerRegistry.register(self)
        aetherApplyAppearance(.runtimeCurrent, animated: false)
    }

    internal var backingUsesLiquidGlassAppearanceForTesting: Bool {
        backgroundView.usesLiquidGlassAppearance
    }

    internal var backingUsesAnyGlassRendererForTesting: Bool {
        backgroundView.usesAnyGlassRendererForTesting
    }

    internal var backingLegacyBlurStyleForTesting: UIBlurEffect.Style? {
        backgroundView.legacyBlurStyleForTesting
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal private(set) var isFinishingContentRemoval = false

    // MARK: - Update

    public func update(
        items: [Item],
        background: Background = .panel,
        preferClearGlass: Bool = false,
        foregroundColor: UIColor? = nil,
        isDark: Bool = false,
        availableHeight: CGFloat = 44.0,
        minWidth: CGFloat = 44.0,
        transition: ContainedViewLayoutTransition = .immediate
    ) -> CGSize {
        // Navigation can lay out the same empty target several times during
        // a pop. That is not a new removal and must not erase the live exit.
        if items.isEmpty, self.items.isEmpty, isFinishingContentRemoval {
            return .zero
        }
        isFinishingContentRemoval = false
        updateGeneration += 1
        let generation = updateGeneration
        let previousNaturalSize = naturalSize
        let previousItemCount = itemViews.count
        let isCustomBackHandoff = Self.isCustomBackHandoff(
            previousEntries: itemViews,
            nextItems: items
        )
        self.items = items
        self.background = background
        self.preferClearGlass = preferClearGlass
        self.isDarkAppearance = isDark
        self.minWidth = minWidth

        // Derive tint color / foreground color from background.
        let tintColor: GlassBackgroundView.TintColor
        let derivedForeground: UIColor
        switch background {
        case .panel:
            tintColor = .init(kind: preferClearGlass ? .clear : .panel)
            derivedForeground = foregroundColor ?? (isDark ? .white : .label)
        case let .activeTint(fg, fill):
            tintColor = .init(kind: preferClearGlass ? .clear : .panel, innerColor: fill)
            derivedForeground = foregroundColor ?? fg
        case let .color(color):
            tintColor = .init(kind: .custom(style: preferClearGlass ? .clear : .default, color: color))
            derivedForeground = foregroundColor ?? .white
        }
        self.currentTintColor = tintColor
        self.foregroundColor = derivedForeground

        // Diff item views by (id, content-id).
        var newEntries: [ItemEntry] = []
        newEntries.reserveCapacity(items.count)

        var isInteractiveOverall = false
        var contentsWidth: CGFloat = 0.0
        var didChangeVisualItems = false

        for item in items {
            let contentId: ContentId
            switch item.content {
            case let .icon(image):
                contentId = .icon(AetherImageSemanticIdentity(image))
            case let .text(text):
                contentId = .text(text)
            case let .customView(view):
                contentId = .customView(ObjectIdentifier(view))
            }

            // Reuse existing entry with matching id & contentId.
            let existingIndex = itemViews.firstIndex { $0.id == item.id && $0.contentId == contentId }
            var entry: ItemEntry
            let contentView: UIView
            let isNewEntry: Bool
            if let existingIndex {
                entry = itemViews.remove(at: existingIndex)
                entry.contentInsets = item.contentInsets
                entry.isInteractive = item.action != nil
                // Keep existing content view; just update action.
                contentView = entry.contentView
                isNewEntry = false
            } else {
                let freshView: UIView
                switch item.content {
                case let .icon(image):
                    freshView = GlassControlGroupIconContentView(image: image, foregroundColor: derivedForeground)
                case let .text(text):
                    freshView = GlassControlGroupTextContentView(text: text, foregroundColor: derivedForeground)
                case let .customView(view):
                    freshView = view
                }
                let button = HighlightTrackingButton(type: .custom)
                button.isUserInteractionEnabled = item.action != nil
                button.addSubview(freshView)
                controlsView.addSubview(button)
                didChangeVisualItems = true

                entry = ItemEntry(
                    id: item.id,
                    contentId: contentId,
                    button: button,
                    contentView: freshView,
                    contentInsets: item.contentInsets,
                    isInteractive: item.action != nil,
                    itemFrame: .zero
                )
                contentView = freshView
                isNewEntry = true
            }

            // Wire action.
            entry.button.onTap = { item.action?() }
            entry.button.isUserInteractionEnabled = item.action != nil
            if !isNewEntry {
                restoreExistingButton(entry.button, targetAlpha: item.action != nil ? 1.0 : 0.5, transition: transition)
            }

            if item.action != nil {
                isInteractiveOverall = true
            }

            // Measure content.
            let maxContentHeight = availableHeight
            var contentSize = contentView.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: maxContentHeight))
            if case .customView = item.content {
                contentSize = contentView.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: maxContentHeight))
                if contentSize == .zero {
                    contentSize = contentView.bounds.size
                }
            } else if case .text = item.content {
                contentSize.width = ceil(contentSize.width)
                contentSize.height = ceil(contentSize.height)
            } else {
                // Icon buttons use a 36pt icon per Figma spec — visibly larger
                // than the previous 28pt so they're easy to tap on a glass
                // capsule and match the iOS 26 reference size.
                contentSize = CGSize(width: 44.0, height: 44.0)
            }

            // Item frame is at least max(minWidth, availableHeight) wide for single-item groups.
            var itemWidth = contentSize.width + entry.contentInsets.left + entry.contentInsets.right
            itemWidth = max(itemWidth, availableHeight)
            if items.count == 1 {
                itemWidth = max(itemWidth, minWidth)
            }

            let itemFrame = CGRect(x: contentsWidth, y: 0.0, width: itemWidth, height: availableHeight)
            entry.itemFrame = itemFrame
            let itemGeometryTransition: ContainedViewLayoutTransition = isNewEntry ? .immediate : transition
            itemGeometryTransition.updateFrame(view: entry.button, frame: itemFrame)

            // Center the content view inside the button with contentInsets.
            let contentOrigin = CGPoint(
                x: entry.contentInsets.left + floor((itemWidth - entry.contentInsets.left - entry.contentInsets.right - contentSize.width) / 2.0),
                y: floor((availableHeight - contentSize.height) / 2.0)
            )
            itemGeometryTransition.updateFrame(
                view: contentView,
                frame: CGRect(origin: contentOrigin, size: contentSize)
            )
            if isNewEntry {
                contentView.layoutIfNeeded()
                let materializesCustomContent: Bool
                if case .customView = item.content {
                    materializesCustomContent = true
                } else {
                    materializesCustomContent = false
                }
                animateInsertedButton(
                    entry.button,
                    targetAlpha: item.action != nil ? 1.0 : 0.5,
                    transition: transition,
                    materializesCustomContent: materializesCustomContent
                )
            }

            newEntries.append(entry)
            contentsWidth += itemWidth
        }

        // Remove stale views. For trailing bar-button groups, preserve the
        // outgoing button's right edge while the replacement fades in; otherwise
        // a narrower target group makes the old right button look like it moves.
        let nextNaturalWidth = items.isEmpty ? (naturalSize.width > 0.0 ? naturalSize.width : availableHeight) : max(availableHeight, contentsWidth)
        for stale in itemViews {
            didChangeVisualItems = true
            if transitionContentAlignment == .trailing {
                var staleFrame = stale.itemFrame
                staleFrame.origin.x = nextNaturalWidth - staleFrame.width
                ContainedViewLayoutTransition.immediate.updateFrame(view: stale.button, frame: staleFrame)
            }
            let materializesCustomContent: Bool
            if case .customView = stale.contentId { materializesCustomContent = true } else { materializesCustomContent = false }
            animateRemovedButton(stale.button, transition: transition, materializesCustomContent: materializesCustomContent)
        }
        itemViews = newEntries
        currentIsInteractive = false

        // If there are no items, collapse the group entirely — otherwise the
        // glass capsule would still render at its min-width size, producing a
        // visible empty pill next to real content (matches behaviour).
        if items.isEmpty {
            isUserInteractionEnabled = false
            if backgroundView.layer.animation(forKey: Self.surfaceMaterializationOpacityKey) != nil {
                let visibleAlpha = backgroundView.layer.presentation()?.opacity ?? backgroundView.layer.opacity
                backgroundView.layer.removeAnimation(forKey: Self.surfaceMaterializationOpacityKey)
                backgroundView.alpha = CGFloat(visibleAlpha)
            }
            let previousSize = naturalSize == .zero ? backgroundView.bounds.size : naturalSize
            if didChangeVisualItems,
               transition.isAnimated,
               animatesInsertedItemsAlpha,
               previousSize.width > 0.0,
               previousSize.height > 0.0 {
                backgroundView.isHidden = false
                if backgroundView.bounds.size == .zero {
                    backgroundView.frame = CGRect(origin: .zero, size: previousSize)
                }
                if controlsView.bounds.size == .zero {
                    controlsView.frame = CGRect(origin: .zero, size: previousSize)
                }
                isFinishingContentRemoval = true
                let exitTransition = softItemTransition(for: transition, appearing: false)
                animateMaterialPulse(
                    kind: .disappearance,
                    from: previousSize,
                    to: previousSize,
                    transition: exitTransition
                )
                exitTransition.updateAlpha(view: backgroundView, alpha: 0.0) { [weak self] _ in
                    guard let self, self.updateGeneration == generation else {
                        return
                    }
                    self.isFinishingContentRemoval = false
                    self.backgroundView.isHidden = true
                    self.backgroundView.alpha = 1.0
                    self.backgroundView.frame = .zero
                    self.controlsView.frame = .zero
                    self.controlsView.alpha = 1.0
                    self.naturalSize = .zero
                    self.frame.size = .zero
                }
                exitTransition.updateAlpha(view: controlsView, alpha: 0.0)
                return .zero
            }
            transition.updateFrame(view: backgroundView, frame: .zero)
            transition.updateFrame(view: controlsView, frame: .zero)
            backgroundView.isHidden = true
            backgroundView.alpha = 1.0
            controlsView.alpha = 1.0
            naturalSize = .zero
            frame.size = .zero
            return .zero
        }

        backgroundView.isHidden = false
        backgroundView.alpha = 1.0
        controlsView.alpha = 1.0
        isUserInteractionEnabled = isInteractiveOverall
        let size = CGSize(width: max(availableHeight, contentsWidth), height: availableHeight)
        naturalSize = size
        let didMorphSize = previousNaturalSize.width > 0.0
            && previousNaturalSize.height > 0.0
            && (abs(previousNaturalSize.width - size.width) > 0.5
                || abs(previousNaturalSize.height - size.height) > 0.5)

        // A surface that did not exist materializes at its resting size. Only
        // existing surfaces interpolate their bounds; growing a hidden 0x0
        // backdrop makes a new navigation button look like a zoom animation.
        let isInsertingSurface = previousItemCount == 0
        let surfaceGeometryTransition: ContainedViewLayoutTransition = isInsertingSurface ? .immediate : transition
        surfaceGeometryTransition.updateFrame(view: backgroundView, frame: CGRect(origin: .zero, size: size))
        surfaceGeometryTransition.updateFrame(view: controlsView, frame: CGRect(origin: .zero, size: size))
        updateBackgroundChrome(size: size, isDark: isDark, tintColor: tintColor, transition: surfaceGeometryTransition)
        if isInsertingSurface {
            animateInsertedSurface(transition: transition)
        }
        if !suppressesAutomaticSizeMorphPulse {
            if previousItemCount == 0 {
                animateMaterialPulse(kind: .appearance, from: size, to: size, transition: transition)
            } else if previousItemCount != items.count
                || didMorphSize
                || didChangeVisualItems
                || isCustomBackHandoff {
                animateMaterialPulse(
                    kind: .fullMorph,
                    from: previousNaturalSize,
                    to: size,
                    transition: transition
                )
            }
        }

        frame.size = size
        return size
    }

    /// A profile/avatar button is represented by a caller-owned custom view,
    /// while the automatic back affordance is a native icon. Their capsules
    /// commonly have the same 44pt geometry, so a size-only diff would treat
    /// the handoff as content-only and omit the material pulse. Semantically it
    /// is a chrome-state change and therefore uses the full three-phase pulse.
    /// Keep the rule symmetric so push and pop remain exact reverses.
    private static func isCustomBackHandoff(
        previousEntries: [ItemEntry],
        nextItems: [Item]
    ) -> Bool {
        guard previousEntries.count == 1,
              nextItems.count == 1,
              let previous = previousEntries.first,
              let next = nextItems.first else {
            return false
        }

        let previousIsCustom: Bool
        if case .customView = previous.contentId {
            previousIsCustom = true
        } else {
            previousIsCustom = false
        }

        let nextIsCustom: Bool
        if case .customView = next.content {
            nextIsCustom = true
        } else {
            nextIsCustom = false
        }

        let previousIsBack = isAutomaticBackID(previous.id)
        let nextIsBack = isAutomaticBackID(next.id)
        return (previousIsCustom && nextIsBack) || (previousIsBack && nextIsCustom)
    }

    private static func isAutomaticBackID(_ id: AnyHashable) -> Bool {
        (id.base as? BarButtonID)?.rawValue.hasSuffix(".nav.back") == true
    }

    private func softItemTransition(for transition: ContainedViewLayoutTransition, appearing: Bool) -> ContainedViewLayoutTransition {
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

    private func animateInsertedButton(
        _ button: UIView,
        targetAlpha: CGFloat,
        transition: ContainedViewLayoutTransition,
        materializesCustomContent: Bool
    ) {
        guard transition.isAnimated && animatesInsertedItemsAlpha else {
            button.alpha = targetAlpha
            button.transform = .identity
            ContainedViewLayoutTransition.immediate.setBlur(layer: button.layer, radius: 0.0)
            return
        }

        button.transform = .identity
        animateButtonMaterialization(
            button,
            targetAlpha: targetAlpha,
            appearing: true,
            duration: min(transition.duration, AetherMotion.navigationChrome.contentAppearanceDuration),
            generation: updateGeneration,
            materializesCustomContent: materializesCustomContent
        )
    }

    private func animateInsertedSurface(transition: ContainedViewLayoutTransition) {
        let layer = backgroundView.layer
        layer.removeAnimation(forKey: Self.surfaceMaterializationOpacityKey)
        guard transition.isAnimated, animatesInsertedItemsAlpha, !UIAccessibility.isReduceMotionEnabled else {
            backgroundView.alpha = 1.0
            return
        }

        // Keep the material separate from the blurred glyph layer. Applying a
        // filter to a native effect view would also blur its sampled backdrop.
        let samples = AetherMotion.navigationChromeMaterializationSamples(appearing: true)
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = samples.map { NSNumber(value: Float($0.opacity)) }
        animation.keyTimes = samples.indices.map { NSNumber(value: Double($0) / Double(samples.count - 1)) }
        animation.duration = min(transition.duration, AetherMotion.navigationChrome.contentAppearanceDuration)
        animation.calculationMode = .linear
        animation.isRemovedOnCompletion = true
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - (1.0 / 120.0)
        animation.aetherPreferHighFrameRate()
        layer.add(animation, forKey: Self.surfaceMaterializationOpacityKey)
    }

    private func restoreExistingButton(_ button: UIView, targetAlpha: CGFloat, transition: ContainedViewLayoutTransition) {
        if AetherContentMaterialization.isAnimating(view: button) {
            return
        }
        guard transition.isAnimated && animatesInsertedItemsAlpha else {
            button.alpha = targetAlpha
            button.transform = .identity
            ContainedViewLayoutTransition.immediate.setBlur(layer: button.layer, radius: 0.0)
            return
        }

        let softTransition = softItemTransition(for: transition, appearing: true)
        softTransition.updateAlpha(view: button, alpha: targetAlpha)
        softTransition.setBlur(layer: button.layer, radius: 0.0)
    }

    private func animateRemovedButton(_ button: UIView, transition: ContainedViewLayoutTransition, materializesCustomContent: Bool) {
        AetherContentMaterialization.cancel(view: button)
        guard transition.isAnimated else {
            button.removeFromSuperview()
            return
        }

        guard animatesInsertedItemsAlpha else {
            transition.updateAlpha(view: button, alpha: 0.0) { [weak button] _ in
                button?.removeFromSuperview()
            }
            return
        }

        button.isUserInteractionEnabled = false
        animateButtonMaterialization(
            button,
            targetAlpha: button.alpha,
            appearing: false,
            duration: min(transition.duration, AetherMotion.navigationChrome.contentDisappearanceDuration),
            generation: updateGeneration,
            materializesCustomContent: materializesCustomContent
        ) { [weak button] in button?.removeFromSuperview() }
    }

    private func animateButtonMaterialization(
        _ button: UIView,
        targetAlpha: CGFloat,
        appearing: Bool,
        duration: TimeInterval,
        generation: Int,
        materializesCustomContent: Bool,
        completion: (() -> Void)? = nil
    ) {
        AetherContentMaterialization.cancel(view: button)
        guard backgroundView.usesLiquidGlassAppearance else {
            button.layer.removeAnimation(forKey: Self.contentMaterializationOpacityKey)
            button.layer.removeAnimation(forKey: Self.contentMaterializationBlurKey)
            button.layer.filters = nil
            button.alpha = appearing ? 0 : targetAlpha
            UIView.animate(
                withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : min(0.2, duration),
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
                animations: { button.alpha = appearing ? targetAlpha : 0 },
                completion: { _ in completion?() }
            )
            return
        }
        let samples = AetherMotion.navigationChromeMaterializationSamples(appearing: appearing)
        let blurFilter = CALayer.blur()
        // Capture composite content once so every part of a chevron/badge or
        // avatar follows the same optical timeline on both rendering paths.
        if blurFilter == nil || materializesCustomContent {
            button.layer.removeAnimation(forKey: Self.contentMaterializationOpacityKey)
            button.layer.removeAnimation(forKey: Self.contentMaterializationBlurKey)
            button.layer.filters = nil
            AetherContentMaterialization.animate(
                view: button,
                samples: samples,
                duration: duration,
                targetAlpha: appearing ? targetAlpha : 0.0,
                completion: completion
            )
            return
        }
        let keyTimes = (0 ..< samples.count).map {
            NSNumber(value: Double($0) / Double(samples.count - 1))
        }
        let layer = button.layer
        layer.removeAnimation(forKey: Self.contentMaterializationOpacityKey)
        layer.removeAnimation(forKey: Self.contentMaterializationBlurKey)

        button.alpha = appearing ? targetAlpha : 0.0
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = samples.map { NSNumber(value: Float($0.opacity * targetAlpha)) }
        opacity.keyTimes = keyTimes
        opacity.duration = max(0.01, duration)
        opacity.calculationMode = .linear
        opacity.timingFunctions = Array(
            repeating: CAMediaTimingFunction(name: .linear),
            count: samples.count - 1
        )
        opacity.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - (1.0 / 120.0)
        opacity.isRemovedOnCompletion = true
        let delegate = NavigationChromeMaterializationDelegate { [weak self, weak button] _ in
            guard let button else { return }
            // A removed semantic button is no longer present in `itemViews`.
            // It must be detached even if a second navbar update superseded
            // this animation, otherwise a cancelled/restarted push can leave
            // an orphan glyph above the new chrome.
            if !appearing {
                completion?()
                return
            }
            guard let self, self.updateGeneration == generation else { return }
            button.layer.filters = nil
            completion?()
        }
        opacity.delegate = delegate
        opacity.setValue(delegate, forKey: "aether.materialization.delegate")
        opacity.aetherPreferHighFrameRate()
        layer.add(opacity, forKey: Self.contentMaterializationOpacityKey)

        #if !APPSTORE_SAFE
        if let blurFilter {
            let finalBlur = samples.last?.blurRadius ?? 0.0
            blurFilter.setValue(finalBlur as NSNumber, forKey: ObfuscatedSymbols.filterRadiusKey)
            layer.filters = [blurFilter]
            let blur = CAKeyframeAnimation(keyPath: ObfuscatedSymbols.keypath(
                ObfuscatedSymbols.filters,
                ObfuscatedSymbols.gaussianBlur,
                ObfuscatedSymbols.filterRadiusKey
            ))
            blur.values = samples.map { NSNumber(value: Float($0.blurRadius)) }
            blur.keyTimes = keyTimes
            blur.duration = opacity.duration
            blur.calculationMode = .linear
            blur.timingFunctions = opacity.timingFunctions
            blur.beginTime = opacity.beginTime
            blur.isRemovedOnCompletion = true
            blur.aetherPreferHighFrameRate()
            layer.add(blur, forKey: Self.contentMaterializationBlurKey)
        }
        #endif
    }

    private enum MaterialPulseKind {
        case appearance
        case disappearance
        case fullMorph
    }

    /// Compatibility entry point for external geometry changes. The pulse is
    /// intentionally direction-independent: a size/count mutation always uses
    /// the same overshoot -> counter -> settle sequence.
    internal func animateSizeMorphPulse(
        on targetLayer: CALayer? = nil,
        from sourceSize: CGSize,
        to targetSize: CGSize,
        transition: ContainedViewLayoutTransition
    ) {
        animateMaterialPulse(
            kind: .fullMorph,
            from: sourceSize,
            to: targetSize,
            transition: transition,
            targetLayer: targetLayer
        )
    }

    private func animateMaterialPulse(
        kind: MaterialPulseKind,
        from sourceSize: CGSize,
        to targetSize: CGSize,
        transition: ContainedViewLayoutTransition,
        targetLayer: CALayer? = nil
    ) {
        guard transition.isAnimated,
              animatesInsertedItemsAlpha,
              backgroundView.usesLiquidGlassAppearance,
              !UIAccessibility.isReduceMotionEnabled else {
            return
        }

        let profile = AetherMotion.navigationChrome
        // Pulse the whole per-control surface, not only the backdrop's inner
        // effect layer. Native glass containers can resolve the inner effect's
        // vertical transform back into its unscaled layout bounds, which makes
        // an isotropic pulse read as a width-only stretch. The group layer is
        // outside that effect machinery and has no clipping, so X and Y remain
        // equally visible while still isolating the pulse from sibling groups.
        let layer = targetLayer ?? self.layer
        let counterLayer = targetLayer == nil ? controlsView.layer : nil
        let modelTransform = layer.transform
        let startTransform = layer.presentation()?.transform ?? modelTransform
        layer.removeAnimation(forKey: Self.sizeMorphPulseAnimationKey)

        // Sample one continuously damped pulse at the device's maximum useful
        // cadence. The old four-node animation used independent Bézier phases;
        // their slopes did not match at the counter-pulse, which read as a
        // mechanical step. This windowed response has exact resting endpoints
        // (including zero endpoint velocity) while naturally producing the
        // native-like 1 → ~1.23 → ~0.968 → 1 material motion.
        let sampleCount = 49
        let keyTimes = (0 ..< sampleCount).map {
            NSNumber(value: Double($0) / Double(sampleCount - 1))
        }
        let rawPulseSamples = keyTimes.map { keyTime -> CGFloat in
            let t = CGFloat(truncating: keyTime)
            let damping: CGFloat = 3.2
            let window = pow(sin(.pi * t), 2.0)
            return exp(-damping * t)
                * sin((.pi / 0.60) * t)
                * window
        }
        let positivePeak = max(0.000_001, rawPulseSamples.max() ?? 1.0)

        var pulseTransforms: [CATransform3D] = []
        var materialValues: [NSValue] = []
        pulseTransforms.reserveCapacity(sampleCount)
        materialValues.reserveCapacity(sampleCount)

        for index in 0 ..< sampleCount {
            let t = CGFloat(index) / CGFloat(sampleCount - 1)
            let normalizedPulse: CGFloat
            switch kind {
            case .appearance, .fullMorph:
                normalizedPulse = rawPulseSamples[index] / positivePeak
            case .disappearance:
                normalizedPulse = rawPulseSamples[sampleCount - 1 - index] / positivePeak
            }

            let geometryProgress: CGFloat
            switch transition {
            case .immediate:
                geometryProgress = 1.0
            case let .animated(_, curve):
                geometryProgress = curve.value(at: t)
            }
            let sampledSize = CGSize(
                width: sourceSize.width + (targetSize.width - sourceSize.width) * geometryProgress,
                height: sourceSize.height + (targetSize.height - sourceSize.height) * geometryProgress
            )
            // Convert the pulse to physical points before deriving X/Y scale.
            // A wide capsule therefore expands by the same visible amount on
            // every edge instead of reading as a horizontal-only stretch.
            let referenceSpan = max(1.0, min(sampledSize.width, sampledSize.height))
            let scaleX = 1.0
                + profile.sizeMorphPrimaryAmplitude
                * referenceSpan / max(1.0, sampledSize.width)
                * normalizedPulse
            let scaleY = 1.0
                + profile.sizeMorphCrossAmplitude
                * referenceSpan / max(1.0, sampledSize.height)
                * normalizedPulse
            let pulseTransform = sizeMorphPulseTransform(
                base: CATransform3DIdentity,
                scaleX: scaleX,
                scaleY: scaleY,
                size: sampledSize
            )
            pulseTransforms.append(pulseTransform)
            materialValues.append(
                NSValue(caTransform3D: CATransform3DConcat(modelTransform, pulseTransform))
            )
        }

        materialValues[0] = NSValue(caTransform3D: startTransform)
        materialValues[materialValues.count - 1] = NSValue(caTransform3D: modelTransform)

        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = materialValues
        animation.keyTimes = keyTimes
        animation.duration = profile.sizeMorphPulseDuration
        animation.calculationMode = .linear
        animation.timingFunctions = Array(
            repeating: CAMediaTimingFunction(name: .linear),
            count: sampleCount - 1
        )
        animation.isRemovedOnCompletion = true
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - (1.0 / 60.0)
        animation.aetherPreferHighFrameRate()
        layer.add(animation, forKey: Self.sizeMorphPulseAnimationKey)

        // The glass material pulses, while glyphs that semantically survived
        // the diff stay visually fixed. `controlsView` lives inside the glass
        // effect's content view, so an inverse presentation transform cancels
        // the ancestor scale without touching model geometry or hit testing.
        if let counterLayer {
            let counterModel = counterLayer.transform
            let counterStart = counterLayer.presentation()?.transform ?? counterModel
            counterLayer.removeAnimation(forKey: Self.materialPulseCounterAnimationKey)
            var counterValues = pulseTransforms.map { pulseTransform in
                NSValue(
                    caTransform3D: CATransform3DConcat(
                        counterModel,
                        CATransform3DInvert(pulseTransform)
                    )
                )
            }
            counterValues[0] = NSValue(caTransform3D: counterStart)
            counterValues[counterValues.count - 1] = NSValue(caTransform3D: counterModel)
            let counterAnimation = CAKeyframeAnimation(keyPath: "transform")
            counterAnimation.values = counterValues
            counterAnimation.keyTimes = keyTimes
            counterAnimation.duration = animation.duration
            counterAnimation.calculationMode = .linear
            counterAnimation.timingFunctions = animation.timingFunctions
            counterAnimation.isRemovedOnCompletion = true
            counterAnimation.beginTime = counterLayer.convertTime(CACurrentMediaTime(), from: nil) - (1.0 / 60.0)
            counterAnimation.aetherPreferHighFrameRate()
            counterLayer.add(counterAnimation, forKey: Self.materialPulseCounterAnimationKey)
        }
    }

    private static func smootherStep(_ value: CGFloat) -> CGFloat {
        let value = max(0.0, min(1.0, value))
        return value * value * value * (value * (value * 6.0 - 15.0) + 10.0)
    }

    private func sizeMorphPulseTransform(
        base: CATransform3D,
        scaleX: CGFloat,
        scaleY: CGFloat,
        size _: CGSize
    ) -> CATransform3D {
        // Pulse around the material centre. Edge-locking with an X translation
        // made one side stationary and was the reason the effect looked
        // horizontal; navbar geometry itself remains responsible for anchoring.
        var pulse = CATransform3DIdentity
        pulse.m11 = scaleX
        pulse.m22 = scaleY
        return CATransform3DConcat(base, pulse)
    }

    public func setContentTransitionEffects(alpha: CGFloat, blurRadius: CGFloat, scale: CGFloat = 1.0, horizontalScale: CGFloat = 1.0, pulseAmplitude: CGFloat = 0.0, transition: ContainedViewLayoutTransition) {
        let transform = CGAffineTransform(scaleX: scale * horizontalScale, y: scale)
        transition.updateTransform(view: backgroundView, transform: transform)
        transition.updateAlpha(view: controlsView, alpha: alpha)
        transition.updateTransform(view: controlsView, transform: transform)
        let usesLiquidGlass = backgroundView.usesLiquidGlassAppearance
        transition.setBlur(layer: controlsView.layer, radius: usesLiquidGlass ? blurRadius : 0)
        if usesLiquidGlass {
            applyOverspringPulseIfNeeded(to: self, amplitude: pulseAmplitude, transition: transition)
        }
    }

    public func setContentTransform(scale: CGFloat = 1.0, horizontalScale: CGFloat = 1.0, transition: ContainedViewLayoutTransition) {
        let transform = CGAffineTransform(scaleX: scale * horizontalScale, y: scale)
        transition.updateTransform(view: backgroundView, transform: transform)
        transition.updateTransform(view: controlsView, transform: transform)
    }

    private func applyOverspringPulseIfNeeded(to view: UIView, amplitude: CGFloat, transition: ContainedViewLayoutTransition) {
        let resolvedAmplitude = abs(amplitude)
        guard backgroundView.usesLiquidGlassAppearance,
              resolvedAmplitude > 0.0,
              transition.isAnimated,
              !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        let duration = max(
            0.08,
            min(AetherMotion.navigationChrome.geometry.duration, transition.duration)
        )
        let layer = view.layer
        let baseTransform = layer.transform
        let startTransform = layer.presentation()?.transform ?? baseTransform
        layer.removeAnimation(forKey: "aether.glassButtonOverspringPulse")

        let peakTransform = CATransform3DScale(baseTransform, 1.0 + resolvedAmplitude, 1.0 + resolvedAmplitude, 1.0)
        let undershootScale = max(0.968, 1.0 - resolvedAmplitude * 0.30)
        let undershootTransform = CATransform3DScale(baseTransform, undershootScale, undershootScale, 1.0)
        let animation = CAKeyframeAnimation(keyPath: "transform")
        if amplitude >= 0.0 {
            animation.values = [startTransform, peakTransform, undershootTransform, baseTransform]
        } else {
            animation.values = [startTransform, undershootTransform, peakTransform, baseTransform]
        }
        animation.keyTimes = [0.0, 0.36, 0.74, 1.0]
        animation.duration = duration
        let timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.timingFunctions = [timingFunction, timingFunction, timingFunction]
        animation.isRemovedOnCompletion = true
        animation.aetherPreferHighFrameRate()
        layer.add(animation, forKey: "aether.glassButtonOverspringPulse")
    }

    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool) {
        let style = appearanceStyleOverride ?? appearance.style
        updateElasticPressRenderer(for: style)
        guard !style.usesLiquidGlass else { return }
        layer.removeAnimation(forKey: Self.sizeMorphPulseAnimationKey)
        layer.removeAnimation(forKey: "aether.glassButtonOverspringPulse")
        controlsView.layer.removeAnimation(forKey: Self.materialPulseCounterAnimationKey)
        controlsView.layer.filters = nil
        for entry in itemViews {
            entry.button.layer.removeAnimation(forKey: Self.contentMaterializationOpacityKey)
            entry.button.layer.removeAnimation(forKey: Self.contentMaterializationBlurKey)
            entry.button.layer.filters = nil
        }
    }

    private func updateElasticPressRenderer(for style: AetherAppearanceStyle) {
        if style.usesLiquidGlass {
            guard elasticRecognizer == nil else { return }
            // Group items consume the touch stream before native glass can
            // observe enough movement, so Liquid modes use one group-level
            // elastic tracker on every supported OS.
            let elastic = GlassHighlightGestureRecognizer(target: nil, action: nil)
            elastic.motionProfile = motionProfile
            elastic.touchEffectView = self
            elastic.highlightContainerView = controlsView
            elastic.shouldHighlightView = { [weak self] hit in
                var view = hit
                while let current = view, current !== self {
                    if let button = current as? HighlightTrackingButton,
                       button.opensContextMenuOnTouchDown { return false }
                    view = current.superview
                }
                return true
            }
            addGestureRecognizer(elastic)
            elasticRecognizer = elastic
        } else if let elasticRecognizer {
            elasticRecognizer.resetVisualState()
            removeGestureRecognizer(elasticRecognizer)
            self.elasticRecognizer = nil
        }
    }

    internal static let sizeMorphPulseAnimationKey = "aether.glassButtonSizeMorphPulse"
    internal static let surfaceMaterializationOpacityKey = "aether.glassButtonSurfaceMaterializationOpacity"
    internal static let materialPulseCounterAnimationKey = "aether.glassButtonMaterialPulseCounter"
    internal static let contentMaterializationOpacityKey = "aether.navigationChromeMaterialization.opacity"
    internal static let contentMaterializationBlurKey = "aether.navigationChromeMaterialization.blur"

    internal var sizeMorphPulseAnimationForTesting: CAKeyframeAnimation? {
        layer.animation(forKey: Self.sizeMorphPulseAnimationKey) as? CAKeyframeAnimation
    }

    internal var surfaceMaterializationAnimationForTesting: CAKeyframeAnimation? {
        backgroundView.layer.animation(forKey: Self.surfaceMaterializationOpacityKey) as? CAKeyframeAnimation
    }

    internal var surfaceFrameForTesting: CGRect {
        backgroundView.frame
    }

    internal var sizeMorphPulseModelTransformForTesting: CATransform3D {
        layer.transform
    }

    internal var materialPulseCounterAnimationForTesting: CAKeyframeAnimation? {
        controlsView.layer.animation(forKey: Self.materialPulseCounterAnimationKey) as? CAKeyframeAnimation
    }

    public func setTransitionChromeSize(
        _ size: CGSize,
        contentAlignment: TransitionChromeContentAlignment = .leading,
        transition: ContainedViewLayoutTransition
    ) {
        setTransitionChromeFrame(
            CGRect(origin: frame.origin, size: size),
            contentAlignment: contentAlignment,
            transition: transition
        )
    }

    public func setTransitionChromeFrame(
        _ frame: CGRect,
        contentAlignment: TransitionChromeContentAlignment = .leading,
        transition: ContainedViewLayoutTransition
    ) {
        let resolvedSize = CGSize(width: max(0.0, frame.width), height: max(0.0, frame.height))
        let resolvedFrame = CGRect(origin: frame.origin, size: resolvedSize)
        let currentChromeSize = backgroundView.layer.presentation()?.bounds.size ?? backgroundView.bounds.size
        let shouldPulseExternalSizeMorph = transition.isAnimated
            && currentChromeSize.width > 0.0
            && currentChromeSize.height > 0.0
            && (abs(currentChromeSize.width - resolvedSize.width) > 0.5
                || abs(currentChromeSize.height - resolvedSize.height) > 0.5)
        let contentOffsetX: CGFloat
        switch contentAlignment {
        case .leading:
            contentOffsetX = 0.0
        case .trailing:
            contentOffsetX = resolvedSize.width - naturalSize.width
        }
        for entry in itemViews {
            transition.updateFrame(view: entry.button, frame: entry.itemFrame.offsetBy(dx: contentOffsetX, dy: 0.0))
        }
        transition.updateFrame(view: self, frame: resolvedFrame)
        transition.updateFrame(view: backgroundView, frame: CGRect(origin: .zero, size: resolvedSize))
        transition.updateFrame(view: controlsView, frame: CGRect(origin: .zero, size: resolvedSize))
        updateBackgroundChrome(size: resolvedSize, isDark: isDarkAppearance, tintColor: currentTintColor, transition: transition)
        if shouldPulseExternalSizeMorph && !suppressesAutomaticSizeMorphPulse {
            animateSizeMorphPulse(from: currentChromeSize, to: resolvedSize, transition: transition)
        }
    }

    public func setTransitionChromeAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition) {
        transition.updateAlpha(view: backgroundView, alpha: alpha)
    }

    private func updateBackgroundChrome(
        size: CGSize,
        isDark: Bool,
        tintColor: GlassBackgroundView.TintColor,
        transition: ContainedViewLayoutTransition
    ) {
        let cornerRadius = size.height * 0.5
        controlsView.layer.cornerRadius = cornerRadius
        controlsView.layer.cornerCurve = .continuous
        if #available(iOS 26.0, *) {
            backgroundView.setNativeUniformCornerRadius(cornerRadius)
        }
        backgroundView.update(
            size: size,
            cornerRadius: cornerRadius,
            isDark: isDark,
            tintColor: tintColor,
            isInteractive: currentIsInteractive,
            transition: transition
        )
    }

    private func applyForegroundColorToItems() {
        for entry in itemViews {
            if let image = entry.contentView as? GlassControlGroupIconContentView {
                image.foregroundColor = foregroundColor
            } else if let label = entry.contentView as? GlassControlGroupTextContentView {
                label.foregroundColor = foregroundColor
            }
        }
    }

    // MARK: - Public accessors

    public func itemView(id: AnyHashable) -> UIView? {
        return itemViews.first(where: { $0.id == id })?.contentView
    }

    internal func itemResolvedForegroundColorForTesting(id: AnyHashable) -> UIColor? {
        (itemViews.first(where: { $0.id == id })?.contentView as? GlassControlGroupIconContentView)?
            .resolvedForegroundColor
    }

    /// The tappable button slot for the item with the given id, or `nil`
    /// if no such item lives in the group. Used by callers that want to
    /// anchor a popover / context menu to the visible capsule cell —
    /// `itemView(id:)` returns just the inner icon/label, which is too
    /// small a target for that.
    public func itemButton(id: AnyHashable) -> UIView? {
        return itemViews.first(where: { $0.id == id })?.button
    }

    /// Visual source used by menu/presentation leases. A single-item group
    /// reads as one glass button, so the whole group is the visual owner.
    /// Multi-item groups share one background; in that case only the item
    /// button/content can be leased without hiding siblings.
    public func itemVisualSourceView(id: AnyHashable) -> UIView? {
        guard let entry = itemViews.first(where: { $0.id == id }) else {
            return nil
        }
        return itemViews.count == 1 ? self : entry.button
    }

    /// Snapshot source for a presentation lease whose visual owner is this
    /// whole group. A one-item group needs the capsule's full bounds for its
    /// transition geometry, but the transition supplies its own live glass
    /// surface. Snapshotting the transparent button keeps only the item's
    /// glyph/content and avoids stacking the original glass shell underneath
    /// that surface.
    internal var singleItemPresentationProxyContentView: UIView? {
        guard itemViews.count == 1 else {
            return nil
        }
        return itemViews[0].button
    }

    public func visualSourceView(containing view: UIView) -> UIView? {
        for entry in itemViews {
            if entry.button === view || entry.button.isDescendant(of: view) || view.isDescendant(of: entry.button) {
                return itemViews.count == 1 ? self : entry.button
            }
        }
        return nil
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        let count = CGFloat(max(1, items.count))
        let itemSize: CGFloat = 44.0
        return CGSize(width: itemSize * count, height: itemSize)
    }
}

private final class GlassControlGroupIconContentView: UIView {
    private let imageNode = ASImageNode()
    private let preservesOriginalColors: Bool
    private(set) var resolvedForegroundColor: UIColor = .clear

    var foregroundColor: UIColor {
        didSet {
            updateImageAppearance()
        }
    }

    init(image: UIImage, foregroundColor: UIColor) {
        self.foregroundColor = foregroundColor
        preservesOriginalColors = image.renderingMode == .alwaysOriginal
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        imageNode.image = preservesOriginalColors ? image : image.withRenderingMode(.alwaysTemplate)
        imageNode.contentMode = preservesOriginalColors ? .scaleAspectFit : .center
        imageNode.view.isUserInteractionEnabled = false
        addSubview(imageNode.view)
        updateImageAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        imageNode.view.removeFromSuperview()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else {
            return
        }
        updateImageAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageNode.frame = preservesOriginalColors ? bounds.insetBy(dx: 3.0, dy: 3.0) : bounds
        imageNode.recursivelyEnsureDisplaySynchronously(true)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: 44.0, height: 44.0)
    }

    private func updateImageAppearance() {
        let resolvedColor = foregroundColor.resolvedColor(with: traitCollection)
        resolvedForegroundColor = resolvedColor
        imageNode.tintColor = preservesOriginalColors ? nil : resolvedColor
        imageNode.view.setMonochromaticEffect(
            tintColor: preservesOriginalColors ? nil : resolvedColor
        )
    }
}

private final class GlassControlGroupTextContentView: UIView {
    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    private var font: UIFont {
        UIFont.aetherScaledSystemFont(
            ofSize: 17.0,
            weight: .medium,
            maximumPointSize: 22.0,
            compatibleWith: traitCollection
        )
    }

    private let textNode = ASTextNode()
    private let text: String

    var foregroundColor: UIColor {
        didSet {
            updateText()
        }
    }

    init(text: String, foregroundColor: UIColor) {
        self.text = text
        self.foregroundColor = foregroundColor
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        textNode.maximumNumberOfLines = 1
        textNode.truncationMode = .byTruncatingTail
        textNode.view.isUserInteractionEnabled = false
        addSubview(textNode.view)
        updateText()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true
            || previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else {
            return
        }
        updateText()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textNode.frame = bounds
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let rect = (text as NSString).boundingRect(
            with: size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    private func updateText() {
        let resolvedColor = foregroundColor.resolvedColor(with: traitCollection)
        textNode.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: resolvedColor,
                .paragraphStyle: Self.paragraphStyle
            ]
        )
        textNode.view.accessibilityLabel = text
    }
}

// MARK: - HighlightTrackingButton
// Lightweight port of `HighlightTrackingButton` from `submodules/Display/Source/HighlightTrackingButton.swift`.

final class HighlightTrackingButton: UIButton {
    // A menu takes ownership on touch-down; a simultaneous group press
    // would scale both the caption snapshot and the restored source.
    var opensContextMenuOnTouchDown = false
    var highlightedChanged: ((Bool) -> Void)?
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted != oldValue {
                highlightedChanged?(isHighlighted)
            }
        }
    }

    @objc private func tapped() {
        onTap?()
    }
}

// MARK: - GlassControlPanel

/// Panel with left / centre / right groups of glass controls merged into a
/// shared `UIGlassContainerEffect` on iOS 26+.
/// Port of Display framework `GlassControlPanelComponent`.
public final class GlassControlPanel: UIView {
    public struct PanelItem {
        public let items: [GlassControlGroup.Item]
        public let background: GlassControlGroup.Background
        public let keepWide: Bool
        public let foregroundColor: UIColor?

        public init(
            items: [GlassControlGroup.Item],
            background: GlassControlGroup.Background = .panel,
            keepWide: Bool = false,
            foregroundColor: UIColor? = nil
        ) {
            self.items = items
            self.background = background
            self.keepWide = keepWide
            self.foregroundColor = foregroundColor
        }
    }

    private let glassContainerView: GlassBackgroundContainerView
    private var leftGroup: GlassControlGroup?
    private var centerGroup: GlassControlGroup?
    private var rightGroup: GlassControlGroup?

    private var leftItem: PanelItem?
    private var centralItem: PanelItem?
    private var rightItem: PanelItem?
    private var centerAlignmentIfPossible: Bool = false
    private var preferClearGlass: Bool = false
    /// Forwards into the underlying `GlassBackgroundContainerView` on
    /// change so the container's shared glass effect picks up the theme
    /// override without requiring a fresh `update(...)` call.
    private var isDarkAppearance: Bool = false {
        didSet {
            if isDarkAppearance == oldValue { return }
            glassContainerView.isDarkOverride = isDarkAppearance
        }
    }

    public override init(frame: CGRect) {
        self.glassContainerView = GlassBackgroundContainerView(spacing: 7.0)
        super.init(frame: frame)

        addSubview(glassContainerView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(
        leftItem: PanelItem?,
        centralItem: PanelItem?,
        rightItem: PanelItem?,
        centerAlignmentIfPossible: Bool = false,
        preferClearGlass: Bool = false,
        isDark: Bool = false,
        availableSize: CGSize,
        transition: ContainedViewLayoutTransition = .immediate
    ) -> CGSize {
        self.leftItem = leftItem
        self.centralItem = centralItem
        self.rightItem = rightItem
        self.centerAlignmentIfPossible = centerAlignmentIfPossible
        self.preferClearGlass = preferClearGlass
        self.isDarkAppearance = isDark

        let minSpacing: CGFloat = 8.0

        // Left
        var leftFrame: CGRect?
        if let leftItem {
            let group: GlassControlGroup
            if let existing = leftGroup {
                group = existing
            } else {
                group = GlassControlGroup()
                glassContainerView.contentView.addSubview(group)
                leftGroup = group
            }
            let size = group.update(
                items: leftItem.items,
                background: leftItem.background,
                preferClearGlass: preferClearGlass,
                foregroundColor: leftItem.foregroundColor,
                isDark: isDark,
                availableHeight: availableSize.height,
                minWidth: availableSize.height,
                transition: transition
            )
            let frame = CGRect(origin: .zero, size: size)
            leftFrame = frame
            transition.updateFrame(view: group, frame: frame)
        } else if let existing = leftGroup {
            leftGroup = nil
            if transition.isAnimated {
                transition.updateAlpha(view: existing, alpha: 0.0) { [weak existing] _ in existing?.removeFromSuperview() }
            } else {
                existing.removeFromSuperview()
            }
        }

        // Right
        var rightFrame: CGRect?
        if let rightItem {
            let group: GlassControlGroup
            if let existing = rightGroup {
                group = existing
            } else {
                group = GlassControlGroup()
                glassContainerView.contentView.addSubview(group)
                rightGroup = group
            }
            let size = group.update(
                items: rightItem.items,
                background: rightItem.background,
                preferClearGlass: preferClearGlass,
                foregroundColor: rightItem.foregroundColor,
                isDark: isDark,
                availableHeight: availableSize.height,
                minWidth: availableSize.height,
                transition: transition
            )
            let frame = CGRect(origin: CGPoint(x: availableSize.width - size.width, y: 0.0), size: size)
            rightFrame = frame
            transition.updateFrame(view: group, frame: frame)
        } else if let existing = rightGroup {
            rightGroup = nil
            if transition.isAnimated {
                transition.updateAlpha(view: existing, alpha: 0.0) { [weak existing] _ in existing?.removeFromSuperview() }
            } else {
                existing.removeFromSuperview()
            }
        }

        // Central
        if let centralItem {
            let group: GlassControlGroup
            if let existing = centerGroup {
                group = existing
            } else {
                group = GlassControlGroup()
                glassContainerView.contentView.addSubview(group)
                centerGroup = group
            }

            var centerLeftInset: CGFloat = 0.0
            var centerRightInset: CGFloat = 0.0
            if let leftFrame {
                centerLeftInset = leftFrame.maxX + minSpacing
            }
            if let rightFrame {
                centerRightInset = availableSize.width - rightFrame.minX + minSpacing
            }
            if centerLeftInset <= 48.0, centerRightInset <= 48.0 {
                let maxInset = max(centerLeftInset, centerRightInset)
                centerLeftInset = maxInset
                centerRightInset = maxInset
            }

            let size = group.update(
                items: centralItem.items,
                background: centralItem.background,
                preferClearGlass: preferClearGlass,
                foregroundColor: centralItem.foregroundColor,
                isDark: isDark,
                availableHeight: availableSize.height,
                minWidth: centralItem.keepWide ? 165.0 : availableSize.height,
                transition: transition
            )

            var originX = centerLeftInset + floor((availableSize.width - centerLeftInset - centerRightInset - size.width) / 2.0)
            if centerAlignmentIfPossible {
                let maxInset = max(centerLeftInset, centerRightInset)
                if availableSize.width - maxInset * 2.0 > size.width {
                    originX = maxInset + floor((availableSize.width - maxInset * 2.0 - size.width) / 2.0)
                }
            }

            transition.updateFrame(view: group, frame: CGRect(origin: CGPoint(x: originX, y: 0.0), size: size))
        } else if let existing = centerGroup {
            centerGroup = nil
            if transition.isAnimated {
                transition.updateAlpha(view: existing, alpha: 0.0) { [weak existing] _ in existing?.removeFromSuperview() }
            } else {
                existing.removeFromSuperview()
            }
        }

        transition.updateFrame(view: glassContainerView, frame: CGRect(origin: .zero, size: availableSize))
        glassContainerView.update(size: availableSize, isDark: isDark, transition: transition)

        frame.size = availableSize
        return availableSize
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        if result === self {
            return nil
        }
        return result
    }
}
