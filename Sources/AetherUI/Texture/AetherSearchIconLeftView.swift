import UIKit
import AsyncDisplayKit

final class AetherSearchIconLeftView: UIView {
    private let iconNode = ASImageNode()
    private var semanticTintColor: UIColor

    init(tintColor: UIColor = .secondaryLabel) {
        self.semanticTintColor = tintColor
        super.init(frame: CGRect(x: 0, y: 0, width: 28, height: 20))

        isUserInteractionEnabled = false
        backgroundColor = .clear

        let iconImage = UIImage(
            systemName: "magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        )
        iconNode.image = iconImage?.withRenderingMode(.alwaysTemplate)
        iconNode.contentMode = .center
        iconNode.view.isUserInteractionEnabled = false
        addSubview(iconNode.view)
        applyTintColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTintColor(_ tintColor: UIColor) {
        semanticTintColor = tintColor
        applyTintColor()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyTintColor()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else {
            return
        }
        applyTintColor()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconNode.frame = CGRect(x: 2, y: 0, width: 16, height: bounds.height)
    }

    private func applyTintColor() {
        let color = semanticTintColor.resolvedColor(with: traitCollection)
        iconNode.tintColor = color
        iconNode.view.setMonochromaticEffect(tintColor: color)
    }
}
