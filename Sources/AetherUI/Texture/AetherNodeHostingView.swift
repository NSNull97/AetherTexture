import UIKit
import AsyncDisplayKit

/// Deprecated compatibility host for embedding a Texture node in UIKit.
/// New AetherUI internals route nodes through `AetherViewController.contentNode`;
/// public app code should compose `ASDisplayNode`/`AetherScreenNode` through
/// node controllers instead of owning host views directly.
@available(*, deprecated, message: "Use AetherScreenController or node-first container APIs instead of hosting views directly.")
public final class AetherNodeHostingView: UIView {
    public let node: ASDisplayNode

    public init(node: ASDisplayNode) {
        self.node = node
        super.init(frame: .zero)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        assert(Thread.isMainThread, "Texture node view access must stay on the main thread")
        node.frame = bounds
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        node.setNeedsLayout()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        node.setNeedsLayout()
    }

    private func commonInit() {
        assert(Thread.isMainThread, "Texture node view access must stay on the main thread")
        backgroundColor = .clear
        addSubview(node.view)
    }
}
