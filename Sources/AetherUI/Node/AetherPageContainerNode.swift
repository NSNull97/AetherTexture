import UIKit
import AsyncDisplayKit

public final class AetherPageItemNode {
    public var title: String?
    public let contentNode: AetherScreenNode

    public init(title: String? = nil, contentNode: AetherScreenNode) {
        self.title = title
        self.contentNode = contentNode
    }
}

public final class AetherPageContainerNode: AetherDisplayNode {
    public var pages: [AetherPageItemNode] {
        didSet { reloadPages(previous: oldValue) }
    }

    public private(set) var selectedIndex: Int
    public var selectedIndexChanged: ((Int) -> Void)?

    private let scrollNode = ASScrollNode()
    private lazy var delegateProxy = AetherPageContainerScrollDelegate(owner: self)

    public init(pages: [AetherPageItemNode] = [], selectedIndex: Int = 0) {
        self.pages = pages
        self.selectedIndex = pages.isEmpty ? 0 : min(max(0, selectedIndex), pages.count - 1)
        super.init()
        addSubnode(scrollNode)
        scrollNode.view.isPagingEnabled = true
        scrollNode.view.showsHorizontalScrollIndicator = false
        scrollNode.view.showsVerticalScrollIndicator = false
        scrollNode.view.alwaysBounceVertical = false
        scrollNode.view.alwaysBounceHorizontal = true
        scrollNode.view.delegate = delegateProxy
        reloadPages(previous: [])
    }

    public override func layout() {
        super.layout()
        scrollNode.frame = bounds
        scrollNode.view.contentSize = CGSize(
            width: bounds.width * CGFloat(pages.count),
            height: bounds.height
        )

        for (index, page) in pages.enumerated() {
            page.contentNode.frame = CGRect(
                x: CGFloat(index) * bounds.width,
                y: 0.0,
                width: bounds.width,
                height: bounds.height
            )
        }
        scrollNode.view.contentOffset = CGPoint(x: CGFloat(selectedIndex) * bounds.width, y: 0.0)
    }

    public func setPages(_ pages: [AetherPageItemNode], selectedIndex: Int = 0) {
        self.pages = pages
        selectPage(at: selectedIndex, animated: false)
    }

    public func selectPage(at index: Int, animated: Bool) {
        guard !pages.isEmpty else {
            let selectionChanged = selectedIndex != 0
            selectedIndex = 0
            if selectionChanged {
                AetherChromeScrollSourceResolver.notifyDidChange(from: self)
            }
            return
        }
        let clamped = min(max(0, index), pages.count - 1)
        guard clamped != selectedIndex || scrollNode.view.contentOffset.x != CGFloat(clamped) * bounds.width else {
            return
        }
        let previousIndex = selectedIndex
        pages[previousIndex].contentNode.screenWillDisappear()
        updateSelectedIndex(clamped)
        pages[clamped].contentNode.screenWillAppear()
        scrollNode.view.setContentOffset(
            CGPoint(x: CGFloat(clamped) * bounds.width, y: 0.0),
            animated: animated
        )
        pages[previousIndex].contentNode.screenDidDisappear()
        pages[clamped].contentNode.screenDidAppear()
    }

    fileprivate func scrollViewDidEndPaging() {
        guard bounds.width > 0.0, !pages.isEmpty else { return }
        let index = min(max(0, Int(round(scrollNode.view.contentOffset.x / bounds.width))), pages.count - 1)
        guard index != selectedIndex else { return }
        pages[selectedIndex].contentNode.screenWillDisappear()
        updateSelectedIndex(index)
        pages[index].contentNode.screenWillAppear()
        pages[index].contentNode.screenDidAppear()
    }

    private func reloadPages(previous: [AetherPageItemNode]) {
        for page in previous {
            page.contentNode.removeFromSupernode()
        }
        selectedIndex = pages.isEmpty ? 0 : min(max(0, selectedIndex), pages.count - 1)
        for page in pages where page.contentNode.supernode !== scrollNode {
            scrollNode.addSubnode(page.contentNode)
        }
        if !pages.isEmpty {
            pages[selectedIndex].contentNode.screenWillAppear()
            pages[selectedIndex].contentNode.screenDidAppear()
        }
        selectedIndexChanged?(selectedIndex)
        AetherChromeScrollSourceResolver.notifyDidChange(from: self)
        setNeedsLayout()
    }

    private func updateSelectedIndex(_ index: Int) {
        guard index != selectedIndex else { return }
        selectedIndex = index
        selectedIndexChanged?(selectedIndex)
        AetherChromeScrollSourceResolver.notifyDidChange(from: self)
    }
}

private final class AetherPageContainerScrollDelegate: NSObject, UIScrollViewDelegate {
    weak var owner: AetherPageContainerNode?

    init(owner: AetherPageContainerNode) {
        self.owner = owner
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        owner?.scrollViewDidEndPaging()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        owner?.scrollViewDidEndPaging()
    }
}
