import UIKit
import AsyncDisplayKit

public struct AetherTooltipTheme: Equatable {
    public let backgroundColor: UIColor
    public let textColor: UIColor
    public let iconTintColor: UIColor?
    public let cornerRadius: CGFloat
    public let font: UIFont
    public let shadowColor: UIColor
    public let shadowOpacity: Float

    public init(
        backgroundColor: UIColor,
        textColor: UIColor,
        iconTintColor: UIColor? = nil,
        cornerRadius: CGFloat = 12.0,
        font: UIFont = .aetherScaledSystemFont(ofSize: 14.0, weight: .medium),
        shadowColor: UIColor = .black,
        shadowOpacity: Float = 0.22
    ) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.iconTintColor = iconTintColor
        self.cornerRadius = cornerRadius
        self.font = font
        self.shadowColor = shadowColor
        self.shadowOpacity = shadowOpacity
    }

    public static let dark = AetherTooltipTheme(
        backgroundColor: UIColor(white: 0.1, alpha: 0.92),
        textColor: .white,
        iconTintColor: .white
    )

    public static let light = AetherTooltipTheme(
        backgroundColor: UIColor.white.withAlphaComponent(0.95),
        textColor: .black,
        iconTintColor: .black
    )
}

public enum AetherTooltipContent: Equatable {
    case text(String)
    case attributedText(NSAttributedString)
    case iconAndText(UIImage, String)

    var plainText: String {
        switch self {
        case let .text(text), let .iconAndText(_, text): return text
        case let .attributedText(text):                  return text.string
        }
    }

    var image: UIImage? {
        if case let .iconAndText(image, _) = self { return image }
        return nil
    }
}

public enum AetherTooltipArrowDirection {
    /// Arrow points down — tooltip sits ABOVE the source rect.
    case down
    /// Arrow points up — tooltip sits BELOW the source rect.
    case up
}

/// Transient pill pointing at a source view. Mounts into the source view's
/// window as a top-level overlay so it floats above everything including
/// modals; auto-dismisses after `timeout` seconds.
public final class AetherTooltipController {
    public var theme: AetherTooltipTheme
    public let content: AetherTooltipContent
    public var timeout: TimeInterval = 2.0
    public var dismissed: (() -> Void)?

    private weak var hostView: UIView?
    private weak var sourceView: UIView?
    private var sourceRect: CGRect?
    private var rootView: AetherTooltipRootView?
    private var dismissWorkItem: DispatchWorkItem?
    private var trackingDisplayLink: CADisplayLink?
    private var isDismissing = false

    /// Self-pin — callers typically construct and call `present(from:)`
    /// in one line without holding a reference. Without this set the
    /// controller would deallocate before the user sees the tip.
    private static var liveTooltips: [AetherTooltipController] = []

    public init(
        content: AetherTooltipContent,
        theme: AetherTooltipTheme = .dark,
        timeout: TimeInterval = 2.0
    ) {
        self.content = content
        self.theme = theme
        self.timeout = timeout
    }

    /// Show pointing at the given source view. `sourceRect` defaults to the
    /// source view's bounds. Placement: prefers ABOVE the source unless
    /// there's no room, then falls back BELOW.
    public func present(from sourceView: UIView, sourceRect: CGRect? = nil) {
        // Prefer the source view's window so the tip follows that window's
        // coordinate space. If the source isn't yet attached (rare: called
        // before viewDidAppear), fall back to the app's active window.
        let window = sourceView.window ?? AetherToastController.findActiveWindow()
        guard let window else { return }
        dismiss(animated: false)
        isDismissing = false
        hostView = window
        self.sourceView = sourceView
        self.sourceRect = sourceRect ?? sourceView.bounds

        if !Self.liveTooltips.contains(where: { $0 === self }) {
            Self.liveTooltips.append(self)
        }

        let rect = sourceRect ?? sourceView.bounds
        let windowRect = sourceView.convert(rect, to: window)

        let root = AetherTooltipRootView(content: content, theme: theme)
        root.onTapOutside = { [weak self] in self?.dismiss(animated: true) }
        root.onTapInside = { [weak self] in self?.dismiss(animated: true) }
        root.frame = window.bounds
        root.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(root)
        root.setNeedsLayout()
        root.layoutIfNeeded()
        root.place(pointingTo: windowRect)
        root.animateIn()
        rootView = root
        startTrackingSource()

        let work = DispatchWorkItem { [weak self] in
            self?.dismiss(animated: true)
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    public func present(from sourceNode: ASDisplayNode, sourceRect: CGRect? = nil) {
        present(from: sourceNode.view, sourceRect: sourceRect)
    }

    public func dismiss(animated: Bool) {
        guard !isDismissing else { return }
        stopTrackingSource()
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        guard let root = rootView else {
            Self.liveTooltips.removeAll(where: { $0 === self })
            return
        }
        isDismissing = true
        rootView = nil

        let unpin: () -> Void = { [weak self] in
            guard let self else { return }
            Self.liveTooltips.removeAll(where: { $0 === self })
        }

        if animated {
            root.animateOut { [weak self] in
                root.removeFromSuperview()
                unpin()
                self?.isDismissing = false
                self?.dismissed?()
            }
        } else {
            root.removeFromSuperview()
            unpin()
            isDismissing = false
            dismissed?()
        }
    }

    deinit {
        stopTrackingSource()
        dismissWorkItem?.cancel()
        rootView?.removeFromSuperview()
    }

    private func startTrackingSource() {
        stopTrackingSource()
        let target = AetherDisplayLinkTarget { [weak self] _ in
            self?.updateTrackedSourcePosition()
        }
        let link = CADisplayLink(
            target: target,
            selector: #selector(AetherDisplayLinkTarget.tick(_:))
        )
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        trackingDisplayLink = link
    }

    private func stopTrackingSource() {
        trackingDisplayLink?.invalidate()
        trackingDisplayLink = nil
    }

    private func updateTrackedSourcePosition() {
        guard let sourceView else {
            dismiss(animated: false)
            return
        }
        guard let window = hostView, let rootView else { return }
        let rect = sourceRect ?? sourceView.bounds
        rootView.place(pointingTo: sourceView.convert(rect, to: window))
    }
}

// MARK: - Root view

final class AetherTooltipRootView: UIView {
    var onTapOutside: () -> Void = {}
    var onTapInside: () -> Void = {}

    private let content: AetherTooltipContent
    private let theme: AetherTooltipTheme

    private let card = UIView()
    private let surfaceView = GlassBackgroundView(style: .regular)
    private let arrowLayer = CAShapeLayer()
    private let contentNode: AetherTooltipContentNode

    private static let horizontalInset: CGFloat = 12.0
    private static let verticalInset: CGFloat = 8.0
    private static let iconTextSpacing: CGFloat = 8.0
    private static let arrowHeight: CGFloat = 6.0
    private static let arrowHalfWidth: CGFloat = 8.0
    private static let screenMargin: CGFloat = 8.0
    private static let gapToSource: CGFloat = 6.0

    init(content: AetherTooltipContent, theme: AetherTooltipTheme) {
        self.content = content
        self.theme = theme
        self.contentNode = AetherTooltipContentNode(content: content, theme: theme)
        super.init(frame: .zero)

        isUserInteractionEnabled = true

        // Shadow lives on the card itself so it extends below the surface.
        card.layer.cornerRadius = theme.cornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = theme.shadowColor.cgColor
        card.layer.shadowOpacity = theme.shadowOpacity
        card.layer.shadowRadius = 14.0
        card.layer.shadowOffset = CGSize(width: 0, height: 4)
        card.clipsToBounds = false
        addSubview(card)

        let isDark = theme.backgroundColor.isDarkApprox
        card.backgroundColor = .clear
        surfaceView.surfaceRole = .popup
        surfaceView.glassCornerRadius = theme.cornerRadius
        surfaceView.glassIsInteractive = false
        surfaceView.isDarkOverride = isDark
        surfaceView.legacySurfaceColorOverride = theme.backgroundColor
        card.addSubview(surfaceView)
        card.addSubview(contentNode.view)

        arrowLayer.fillColor = theme.backgroundColor.cgColor
        layer.addSublayer(arrowLayer)

        let inside = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        card.addGestureRecognizer(inside)

        let outside = UITapGestureRecognizer(target: self, action: #selector(outsideTapped))
        outside.cancelsTouchesInView = false
        addGestureRecognizer(outside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Lay out card + arrow to point at `sourceGlobalRect`. Prefers ABOVE;
    /// flips below when there's no room above.
    func place(pointingTo sourceGlobalRect: CGRect) {
        let maxCardWidth = max(0.0, min(280.0, bounds.width - safeAreaInsets.left - safeAreaInsets.right - Self.screenMargin * 2))
        let contentSize = contentNode.preferredSize(maxWidth: maxCardWidth)
        let topLimit = safeAreaInsets.top + Self.screenMargin
        let bottomLimit = bounds.height - safeAreaInsets.bottom - Self.screenMargin
        let spaceAbove = max(0.0, sourceGlobalRect.minY - Self.gapToSource - Self.arrowHeight - topLimit)
        let spaceBelow = max(0.0, bottomLimit - sourceGlobalRect.maxY - Self.gapToSource - Self.arrowHeight)
        let useAbove = spaceAbove >= contentSize.height || spaceAbove >= spaceBelow
        let cardHeight = min(contentSize.height, useAbove ? spaceAbove : spaceBelow)
        let cardWidth = contentSize.width

        let anchorX = sourceGlobalRect.midX

        var cardX = anchorX - cardWidth / 2
        let leftLimit = safeAreaInsets.left + Self.screenMargin
        let rightLimit = bounds.width - safeAreaInsets.right - Self.screenMargin
        cardX = max(leftLimit, min(rightLimit - cardWidth, cardX))

        let direction: AetherTooltipArrowDirection = useAbove ? .down : .up

        let cardY: CGFloat
        let arrowY: CGFloat
        switch direction {
        case .down:
            cardY = max(topLimit, sourceGlobalRect.minY - Self.gapToSource - Self.arrowHeight - cardHeight)
            arrowY = cardY + cardHeight
        case .up:
            cardY = min(bottomLimit - cardHeight, sourceGlobalRect.maxY + Self.gapToSource + Self.arrowHeight)
            arrowY = cardY - Self.arrowHeight
        }

        card.frame = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
        surfaceView.frame = card.bounds
        surfaceView.update(
            size: card.bounds.size,
            cornerRadius: theme.cornerRadius,
            transition: .immediate
        )
        contentNode.frame = card.bounds

        // Arrow path — small triangle whose tip lines up with anchorX.
        let path = UIBezierPath()
        let tipX = max(cardX + theme.cornerRadius + Self.arrowHalfWidth,
                       min(cardX + cardWidth - theme.cornerRadius - Self.arrowHalfWidth, anchorX))
        switch direction {
        case .down:
            path.move(to: CGPoint(x: tipX - Self.arrowHalfWidth, y: arrowY))
            path.addLine(to: CGPoint(x: tipX, y: arrowY + Self.arrowHeight))
            path.addLine(to: CGPoint(x: tipX + Self.arrowHalfWidth, y: arrowY))
        case .up:
            path.move(to: CGPoint(x: tipX - Self.arrowHalfWidth, y: arrowY + Self.arrowHeight))
            path.addLine(to: CGPoint(x: tipX, y: arrowY))
            path.addLine(to: CGPoint(x: tipX + Self.arrowHalfWidth, y: arrowY + Self.arrowHeight))
        }
        path.close()
        arrowLayer.path = path.cgPath
    }

    func animateIn() {
        card.alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        arrowLayer.opacity = 0
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.2,
            options: .curveEaseOut
        ) {
            self.card.alpha = 1
            self.card.transform = .identity
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.22
        arrowLayer.opacity = 1
        arrowLayer.add(fade, forKey: "fadeIn")
    }

    func animateOut(completion: @escaping () -> Void) {
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            self.card.alpha = 0
        } completion: { _ in
            completion()
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.18
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        arrowLayer.add(fade, forKey: "fadeOut")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Tap on the card goes to the card so its own recognizer fires;
        // tap anywhere else lands on self so outsideTap runs (and dismisses).
        // Tooltip is a modal-feeling overlay while shown — underlying UI
        // taps are swallowed for the short lifetime of the tip.
        return super.hitTest(point, with: event)
    }

    @objc private func cardTapped() {
        onTapInside()
    }

    @objc private func outsideTapped() {
        onTapOutside()
    }
}

private final class AetherTooltipContentNode: ASDisplayNode {
    private let content: AetherTooltipContent
    private let theme: AetherTooltipTheme
    private let textNode = ASTextNode()
    private let iconNode = ASImageNode()

    private static let horizontalInset: CGFloat = 12.0
    private static let verticalInset: CGFloat = 8.0
    private static let iconSize: CGFloat = 22.0
    private static let iconTextSpacing: CGFloat = 8.0

    init(content: AetherTooltipContent, theme: AetherTooltipTheme) {
        self.content = content
        self.theme = theme
        super.init()

        textNode.maximumNumberOfLines = 0
        textNode.isUserInteractionEnabled = false
        switch content {
        case let .text(text):
            textNode.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: theme.font,
                    .foregroundColor: theme.textColor
                ]
            )
        case let .attributedText(attr):
            textNode.attributedText = attr
        case let .iconAndText(image, text):
            textNode.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: theme.font,
                    .foregroundColor: theme.textColor
                ]
            )
            iconNode.image = theme.iconTintColor != nil ? image.withRenderingMode(.alwaysTemplate) : image
            if let tint = theme.iconTintColor {
                iconNode.tintColor = tint
            }
            iconNode.contentMode = .scaleAspectFit
            iconNode.isUserInteractionEnabled = false
            addSubnode(iconNode)
        }
        addSubnode(textNode)
    }

    func preferredSize(maxWidth: CGFloat) -> CGSize {
        let iconSlot = content.image != nil ? (Self.iconSize + Self.iconTextSpacing) : 0.0
        let textBox = CGSize(
            width: max(1.0, maxWidth - Self.horizontalInset * 2.0 - iconSlot),
            height: .greatestFiniteMagnitude
        )
        let textFits = textNode.layoutThatFits(ASSizeRange(min: .zero, max: textBox)).size
        let contentHeight = max(textFits.height, content.image != nil ? Self.iconSize : 0.0)
        let cardHeight = contentHeight + Self.verticalInset * 2.0
        let cardWidth = min(maxWidth, textFits.width + Self.horizontalInset * 2.0 + iconSlot)
        return CGSize(width: cardWidth, height: cardHeight)
    }

    override func layout() {
        super.layout()
        let hasIcon = content.image != nil
        let iconSlot = hasIcon ? (Self.iconSize + Self.iconTextSpacing) : 0.0
        let textWidth = max(1.0, bounds.width - Self.horizontalInset * 2.0 - iconSlot)
        let textSize = textNode.layoutThatFits(
            ASSizeRange(min: .zero, max: CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        ).size

        if hasIcon {
            iconNode.frame = CGRect(
                x: Self.horizontalInset,
                y: floor((bounds.height - Self.iconSize) / 2.0),
                width: Self.iconSize,
                height: Self.iconSize
            )
            textNode.frame = CGRect(
                x: Self.horizontalInset + Self.iconSize + Self.iconTextSpacing,
                y: floor((bounds.height - textSize.height) / 2.0),
                width: textWidth,
                height: textSize.height
            )
        } else {
            iconNode.frame = .zero
            textNode.frame = CGRect(
                x: Self.horizontalInset,
                y: floor((bounds.height - textSize.height) / 2.0),
                width: textWidth,
                height: textSize.height
            )
        }
    }
}
