import UIKit

/// A transparent stack of independently rounded rows. The controller owns
/// the one shared glass surface, as in `AetherAlertRootView`.
final class AetherActionSheetItemGroupView: UIView {
    var theme: AetherActionSheetTheme

    private(set) var itemViews: [AetherActionSheetItemView] = []
    private var overlayView: UIView?
    private static let itemSpacing: CGFloat = 8.0

    init(theme: AetherActionSheetTheme) {
        self.theme = theme
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setItems(_ items: [AetherActionSheetItem]) {
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = items.map { item in
            let view = item.makeView(theme: theme)
            view.hasSeparator = false
            addSubview(view)
            return view
        }
        if let overlayView { bringSubviewToFront(overlayView) }
        setNeedsLayout()
    }

    func updateItem(at index: Int, with item: AetherActionSheetItem) {
        guard itemViews.indices.contains(index) else { return }
        let existing = itemViews[index]
        let replacement = item.makeView(theme: theme)
        replacement.hasSeparator = false
        insertSubview(replacement, belowSubview: existing)
        existing.removeFromSuperview()
        itemViews[index] = replacement
        setNeedsLayout()
    }

    func setOverlayView(_ view: UIView?) {
        guard overlayView !== view else { return }
        overlayView?.removeFromSuperview()
        overlayView = view
        if let view { addSubview(view) }
        setNeedsLayout()
    }

    func preferredHeight(constrainedWidth: CGFloat) -> CGFloat {
        let rowsHeight = itemViews.reduce(CGFloat.zero) {
            $0 + $1.preferredHeight(constrainedWidth: constrainedWidth)
        }
        return rowsHeight + CGFloat(max(0, itemViews.count - 1)) * Self.itemSpacing
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var y: CGFloat = 0
        for (index, view) in itemViews.enumerated() {
            let height = view.preferredHeight(constrainedWidth: bounds.width)
            view.frame = CGRect(x: 0, y: y, width: bounds.width, height: height)
            y += height
            if index < itemViews.count - 1 { y += Self.itemSpacing }
        }
        overlayView?.frame = bounds
    }
}
