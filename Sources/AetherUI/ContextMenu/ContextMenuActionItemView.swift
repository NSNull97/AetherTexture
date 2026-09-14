import UIKit
import AsyncDisplayKit

// MARK: - ContextMenuActionItemView

/// Single row inside a context menu actions list. Pure presentation — touch
/// handling and the moving highlight pill live on the parent
/// `ContextMenuActionsView`.
///
/// Layout slots (left → right):
///
///   ┌───────────────────────────────────────────────────────────────┐
///   │ [LEADING]  [TITLE / TITLE+SUBTITLE]                 [TRAILING]│
///   └───────────────────────────────────────────────────────────────┘
///
///   - **Leading slot**: a single 22pt-wide column reserved when at least
///     one item in the menu would fill it (checkmark or leading icon).
///     Fills with the checkmark when `isSelected`, OR the icon when
///     `iconSide == .leading`. Mutually exclusive in render — checkmark
///     wins if both apply (selected + leading icon → checkmark shows).
///
///   - **Trailing slot**: submenu chevron > leading icon (when
///     `iconSide == .trailing`). Submenu chevron always wins (a row with
///     a submenu doesn't render a custom trailing icon).
///
///   - **Text**: title (single line) OR title + subtitle (two lines,
///     vertically centered). Row height grows automatically when subtitle
///     is non-empty (`ContextMenuActionItemView.rowHeight(for:)`).
final class ContextMenuActionItemView: UIView {
    // MARK: - Metrics

    struct Metrics {
        let horizontalInset: CGFloat
        let titleFontSize: CGFloat
        let trailingIconSize: CGFloat
        let separatorHeight: CGFloat

        static func resolve(for appearanceStyle: AetherAppearanceStyle) -> Metrics {
            switch appearanceStyle {
            case .legacy:
                // iOS 18 Context Menu (Figma 754:62668): 16pt row padding,
                // Body/Regular 17pt labels, a 20pt trailing symbol slot and a
                // literal 0.5pt divider between consecutive action rows.
                return Metrics(
                    horizontalInset: 16.0,
                    titleFontSize: 17.0,
                    trailingIconSize: 20.0,
                    separatorHeight: 0.5
                )
            case .liquidGlassV1, .liquidGlassV2:
                return Metrics(
                    horizontalInset: 8.0,
                    titleFontSize: 16.0,
                    trailingIconSize: 22.0,
                    separatorHeight: 1.0 / UIScreen.main.scale
                )
            }
        }
    }

    static let rowHeight: CGFloat = 44.0
    static let rowHeightWithSubtitle: CGFloat = 56.0
    static let leadingSlotWidth: CGFloat = 18.0
    static let leadingSlotSpacing: CGFloat = 12.0
    static let leadingIconSize: CGFloat = 20.0

    /// Height a row of `item` should occupy. Public so the parent actions
    /// view's `heightForItem` can defer to it.
    static func rowHeight(for item: ContextMenuActionItem) -> CGFloat {
        return (item.subtitle ?? "").isEmpty ? rowHeight : rowHeightWithSubtitle
    }

    // MARK: - Subviews

    private let checkmarkNode = ASImageNode()
    /// Icon rendered in the LEADING slot (replaces the checkmark when item
    /// is not selected and `iconSide == .leading`).
    private let leadingIconNode = ASImageNode()
    private let titleNode = ASTextNode()
    private let subtitleNode = ASTextNode()
    /// Icon rendered in the TRAILING slot (when `iconSide == .trailing`).
    private let trailingIconNode = ASImageNode()
    /// Trailing `chevron.right` shown when `item.submenu != nil`. Mutually
    /// exclusive with `trailingIconView` — submenu chevron wins.
    private let submenuIndicatorNode = ASImageNode()
    private let rowSeparatorView = UIView()

    // MARK: - State

    private(set) var item: ContextMenuActionItem
    private let metrics: Metrics
    var showsRowSeparator = false {
        didSet {
            guard showsRowSeparator != oldValue else { return }
            rowSeparatorView.isHidden = !showsRowSeparator
            setNeedsLayout()
        }
    }
    var reservesLeadingSlot = true {
        didSet {
            guard reservesLeadingSlot != oldValue else { return }
            setNeedsLayout()
        }
    }

    // MARK: - Init

    init(
        item: ContextMenuActionItem,
        appearanceStyle: AetherAppearanceStyle = AetherAppearance.runtimeCurrent.style
    ) {
        self.item = item
        self.metrics = Metrics.resolve(for: appearanceStyle)
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .button

        for node in [checkmarkNode, leadingIconNode, trailingIconNode, submenuIndicatorNode] {
            node.contentMode = .scaleAspectFit
            node.tintColor = .label
            node.isUserInteractionEnabled = false
            addSubview(node.view)
        }
        checkmarkNode.image = ContextMenuActionItemView.checkmarkImage()
        submenuIndicatorNode.image = ContextMenuActionItemView.chevronImage()
        submenuIndicatorNode.contentMode = .center
        submenuIndicatorNode.tintColor = item.textColor == .destructive ? .systemRed : .label

        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        titleNode.isUserInteractionEnabled = false
        addSubview(titleNode.view)

        subtitleNode.maximumNumberOfLines = 1
        subtitleNode.truncationMode = .byTruncatingTail
        subtitleNode.isUserInteractionEnabled = false
        addSubview(subtitleNode.view)

        rowSeparatorView.backgroundColor = UIColor(white: 0.5, alpha: 0.55)
        rowSeparatorView.isUserInteractionEnabled = false
        rowSeparatorView.isHidden = true
        addSubview(rowSeparatorView)

        apply(item: item)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Configuration

    func apply(item: ContextMenuActionItem) {
        self.item = item

        let tint: UIColor
        switch item.textColor {
        case .primary: tint = .label
        case .destructive: tint = .systemRed
        }
        titleNode.attributedText = NSAttributedString(
            string: item.title,
            attributes: [
                .font: UIFont.aetherScaledSystemFont(ofSize: metrics.titleFontSize, weight: .regular),
                .foregroundColor: tint
            ]
        )
        subtitleNode.attributedText = NSAttributedString(
            string: item.subtitle ?? "",
            attributes: [
                .font: UIFont.aetherScaledSystemFont(ofSize: 13.0, weight: .regular),
                .foregroundColor: item.textColor == .destructive
                    ? UIColor.systemRed.withAlphaComponent(0.7)
                    : .secondaryLabel
            ]
        )
        subtitleNode.isHidden = (item.subtitle ?? "").isEmpty
        leadingIconNode.tintColor = tint
        trailingIconNode.tintColor = tint
        checkmarkNode.tintColor = tint

        // Leading slot: checkmark > leading icon (mutually exclusive).
        let hasLeadingIcon = (item.icon != nil) && (item.iconSide == .leading)
        checkmarkNode.isHidden = !item.isSelected
        leadingIconNode.isHidden = !(hasLeadingIcon && !item.isSelected)
        if hasLeadingIcon, let icon = item.icon {
            leadingIconNode.image = icon.withRenderingMode(.alwaysTemplate)
        } else {
            leadingIconNode.image = nil
        }

        // Trailing slot: submenu chevron > trailing icon (mutually exclusive).
        let hasTrailingIcon = (item.icon != nil) && (item.iconSide == .trailing)
        submenuIndicatorNode.isHidden = (item.submenu == nil)
        trailingIconNode.isHidden = !(hasTrailingIcon && item.submenu == nil)
        if hasTrailingIcon, item.submenu == nil, let icon = item.icon {
            trailingIconNode.image = icon.withRenderingMode(.alwaysTemplate)
        } else {
            trailingIconNode.image = nil
        }

        alpha = item.isEnabled ? 1.0 : 0.4
        accessibilityLabel = item.title
        if item.isSelected { accessibilityTraits.insert(.selected) }

        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        let insets = UIEdgeInsets(
            top: 0, left: metrics.horizontalInset,
            bottom: 0, right: metrics.horizontalInset
        )
        let layoutRect = bounds.inset(by: insets)

        let slotW = ContextMenuActionItemView.leadingSlotWidth
        let slotSpacing = ContextMenuActionItemView.leadingSlotSpacing
        let leadingContentX = reservesLeadingSlot
            ? layoutRect.minX + slotW + slotSpacing
            : layoutRect.minX

        // Leading slot — checkmark and/or leading icon occupy the same rect.
        let leadingSlotRect = CGRect(
            x: layoutRect.minX,
            y: (bounds.height - slotW) / 2.0,
            width: slotW,
            height: slotW
        )
        checkmarkNode.frame = reservesLeadingSlot ? leadingSlotRect : .zero
        let leadingIconW = ContextMenuActionItemView.leadingIconSize
        leadingIconNode.frame = reservesLeadingSlot
            ? CGRect(
                x: leadingSlotRect.midX - leadingIconW / 2.0,
                y: (bounds.height - leadingIconW) / 2.0,
                width: leadingIconW,
                height: leadingIconW
            )
            : .zero

        // Trailing slot — submenu chevron OR trailing icon. Both occupy the
        // right edge with no overlap (apply(item:) hides one or the other).
        var trailingContentX = layoutRect.maxX
        if !submenuIndicatorNode.isHidden {
            let chevronW: CGFloat = 12.0
            let chevronH: CGFloat = 18.0
            submenuIndicatorNode.frame = CGRect(
                x: trailingContentX - chevronW,
                y: (bounds.height - chevronH) / 2.0,
                width: chevronW,
                height: chevronH
            )
            trailingContentX -= chevronW + 10.0
        } else if !trailingIconNode.isHidden {
            let iconW = metrics.trailingIconSize
            trailingIconNode.frame = CGRect(
                x: trailingContentX - iconW,
                y: (bounds.height - iconW) / 2.0,
                width: iconW,
                height: iconW
            )
            trailingContentX -= iconW + 10.0
        }

        let textRect = CGRect(
            x: leadingContentX,
            y: 0,
            width: max(0, trailingContentX - leadingContentX),
            height: bounds.height
        )

        if subtitleNode.isHidden {
            let titleSize = titleNode.layoutThatFits(
                ASSizeRange(min: .zero, max: CGSize(width: textRect.width, height: textRect.height))
            ).size
            titleNode.frame = CGRect(
                x: textRect.minX,
                y: floor((textRect.height - titleSize.height) / 2.0),
                width: textRect.width,
                height: titleSize.height
            )
            subtitleNode.frame = .zero
        } else {
            // Two-line layout: title on top, subtitle below, vertically
            // centered within the (taller) row.
            let titleH: CGFloat = 22.0
            let subH: CGFloat = 16.0
            let gap: CGFloat = 1.0
            let total = titleH + gap + subH
            let startY = (bounds.height - total) / 2.0
            titleNode.frame = CGRect(x: textRect.minX, y: startY, width: textRect.width, height: titleH)
            subtitleNode.frame = CGRect(x: textRect.minX, y: startY + titleH + gap, width: textRect.width, height: subH)
        }

        rowSeparatorView.frame = showsRowSeparator
            ? CGRect(
                x: 0.0,
                y: max(0.0, bounds.height - metrics.separatorHeight),
                width: bounds.width,
                height: metrics.separatorHeight
            )
            : .zero
    }

    // MARK: - Assets

    private static func checkmarkImage() -> UIImage? {
        if #available(iOS 13.0, *) {
            let config = UIImage.SymbolConfiguration(pointSize: 15.0, weight: .semibold)
            return UIImage(systemName: "checkmark", withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
        }
        return nil
    }

    private static func chevronImage() -> UIImage? {
        if #available(iOS 13.0, *) {
            let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            return UIImage(systemName: "chevron.right", withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
        }
        return nil
    }
}
