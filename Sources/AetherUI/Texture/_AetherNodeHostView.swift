import UIKit
import AsyncDisplayKit

internal final class _AetherNodeHostView: UIView {
    let node: ASDisplayNode

    init(node: ASDisplayNode) {
        self.node = node
        super.init(frame: .zero)
        commonInit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        assert(Thread.isMainThread, "Texture node view access must stay on the main thread")
        node.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        node.setNeedsLayout()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        node.setNeedsLayout()
    }

    private func commonInit() {
        assert(Thread.isMainThread, "Texture node view access must stay on the main thread")
        backgroundColor = .clear
        addSubview(node.view)
    }
}
