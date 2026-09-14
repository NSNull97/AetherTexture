import CoreGraphics
import AsyncDisplayKit

public final class AetherNavigationNode: AetherDisplayNode {
    public private(set) var stack: [AetherScreenNode] = []
    public var topNode: AetherScreenNode? { stack.last }

    public override init() {
        super.init()
        clipsToBounds = true
    }

    public func push(_ node: AetherScreenNode, animated: Bool) {
        let previous = topNode
        previous?.screenWillDisappear()
        node.screenWillAppear()
        stack.append(node)
        transition(from: previous, to: node, animated: animated) { [weak previous, weak node] finished in
            previous?.screenDidDisappear()
            if finished {
                node?.screenDidAppear()
            }
        }
        // `transition` mounts the destination synchronously before starting
        // any animation. Publish afterwards so chrome resolution can see its
        // real view hierarchy on the first sample.
        AetherChromeScrollSourceResolver.notifyDidChange(from: self)
    }

    @discardableResult
    public func pop(animated: Bool) -> AetherScreenNode? {
        guard stack.count > 1 else { return nil }
        let removed = stack.removeLast()
        let target = stack.last
        removed.screenWillDisappear()
        target?.screenWillAppear()
        transition(from: removed, to: target, animated: animated) { [weak removed, weak target] finished in
            removed?.screenDidDisappear()
            if finished {
                target?.screenDidAppear()
            }
        }
        AetherChromeScrollSourceResolver.notifyDidChange(from: self)
        return removed
    }

    public func setStack(_ nodes: [AetherScreenNode], animated: Bool) {
        let previous = topNode
        stack = nodes
        let target = nodes.last
        guard previous !== target else {
            for node in subnodes ?? [] where node !== target {
                node.removeFromSupernode()
            }
            target?.frame = bounds
            setNeedsLayout()
            AetherChromeScrollSourceResolver.notifyDidChange(from: self)
            return
        }

        previous?.screenWillDisappear()
        target?.screenWillAppear()
        transition(from: previous, to: target, animated: animated) { [weak previous, weak target] finished in
            previous?.screenDidDisappear()
            if finished {
                target?.screenDidAppear()
            }
        }
        AetherChromeScrollSourceResolver.notifyDidChange(from: self)
    }

    public override func layout() {
        super.layout()
        for node in stack where node.supernode === self {
            node.frame = bounds
        }
    }

    private func transition(
        from oldNode: AetherScreenNode?,
        to newNode: AetherScreenNode?,
        animated: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        if let newNode, newNode.supernode !== self {
            newNode.frame = bounds
            addSubnode(newNode)
        }

        guard animated, let newNode else {
            for node in subnodes ?? [] where node !== newNode {
                node.removeFromSupernode()
            }
            completion(true)
            return
        }

        newNode.alpha = 0.0
        AetherAnimationEngine.shared.animate(
            AetherNodeAnimation(duration: 0.24, curve: .easeInOut)
        ) {
            oldNode?.alpha = 0.0
            newNode.alpha = 1.0
        } completion: { [weak self, weak oldNode, weak newNode] finished in
            guard let self else { return }
            oldNode?.alpha = 1.0
            newNode?.alpha = 1.0
            for node in self.subnodes ?? [] where node !== newNode {
                node.removeFromSupernode()
            }
            completion(finished)
        }
    }
}
