import UIKit
import AsyncDisplayKit

public final class AetherNavigationBarNode: AetherDisplayNode {
    public var itemNode: AetherNavigationItemNode? {
        didSet { syncItemNode() }
    }

    public var presentationData: NavigationBarPresentationData {
        didSet {
            navigationBarView?.updatePresentationData(presentationData, transition: .immediate)
        }
    }

    public var backPressed: () -> Void = {} {
        didSet { navigationBarView?.backPressed = backPressed }
    }

    public var defaultHeight: CGFloat = 44.0 {
        didSet { setNeedsLayout() }
    }

    private let hostNode: ASDisplayNode
    private var navigationItemObservation: AetherNavigationItemNodeObservation?
    private weak var loadedNavigationBar: NavigationBarImpl?

    private var navigationBarView: NavigationBarImpl? {
        loadedNavigationBar
    }

    public init(
        itemNode: AetherNavigationItemNode? = nil,
        presentationData: NavigationBarPresentationData = NavigationBarPresentationData.defaultTheme(edgeColor: .clear)
    ) {
        self.itemNode = itemNode
        self.presentationData = presentationData
        let capturedPresentationData = presentationData
        self.hostNode = ASDisplayNode(viewBlock: {
            NavigationBarImpl(presentationData: capturedPresentationData)
        })
        super.init()
        addSubnode(hostNode)
        bindItemNode()
    }

    public override func didLoad() {
        super.didLoad()
        loadedNavigationBar = hostNode.view as? NavigationBarImpl
        navigationBarView?.backPressed = backPressed
        syncItemNode()
    }

    public override func layout() {
        super.layout()
        hostNode.frame = bounds
        navigationBarView?.updateLayout(
            size: bounds.size,
            defaultHeight: defaultHeight,
            additionalTopHeight: 0.0,
            additionalContentHeight: 0.0,
            additionalBackgroundHeight: 0.0,
            additionalCutout: nil,
            leftInset: 0.0,
            rightInset: 0.0,
            appearsHidden: false,
            isLandscape: bounds.width > bounds.height,
            transition: .immediate
        )
    }

    public func updateLayout(
        size: CGSize,
        additionalTopHeight: CGFloat = 0.0,
        additionalContentHeight: CGFloat = 0.0,
        additionalBackgroundHeight: CGFloat = 0.0,
        additionalCutout: CGSize? = nil,
        leftInset: CGFloat = 0.0,
        rightInset: CGFloat = 0.0,
        appearsHidden: Bool = false,
        isLandscape: Bool = false,
        transition: ContainedViewLayoutTransition
    ) {
        transition.updateFrame(node: self, frame: CGRect(origin: frame.origin, size: size))
        navigationBarView?.updateLayout(
            size: size,
            defaultHeight: defaultHeight,
            additionalTopHeight: additionalTopHeight,
            additionalContentHeight: additionalContentHeight,
            additionalBackgroundHeight: additionalBackgroundHeight,
            additionalCutout: additionalCutout,
            leftInset: leftInset,
            rightInset: rightInset,
            appearsHidden: appearsHidden,
            isLandscape: isLandscape,
            transition: transition
        )
    }

    public func setHidden(_ hidden: Bool, animated: Bool) {
        navigationBarView?.setHidden(hidden, animated: animated)
    }

    public func executeBack() -> Bool {
        navigationBarView?.executeBack() ?? false
    }

    private func bindItemNode() {
        navigationItemObservation?.cancel()
        navigationItemObservation = itemNode?.addChangeObserver { [weak self] in
            self?.syncItemNode()
        }
    }

    private func syncItemNode() {
        bindItemNode()
        guard let itemNode else {
            navigationBarView?.item = nil
            return
        }
        let item = NavigationBarItem()
        item.title = itemNode.title
        navigationBarView?.item = item
    }
}
