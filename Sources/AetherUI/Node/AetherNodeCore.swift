import Foundation
import CoreGraphics
import AsyncDisplayKit
import AetherUIBridging

public struct AetherAnimationIdentity: Hashable {
    public let rawValue: AnyHashable

    public init(_ rawValue: AnyHashable) {
        self.rawValue = rawValue
    }
}

public protocol AetherAnimatableNode: AnyObject {
    var animationIdentity: AetherAnimationIdentity { get }
}

open class AetherDisplayNode: AetherMainActorDisplayNode, AetherAnimatableNode {
    public let animationIdentity: AetherAnimationIdentity

    public override init() {
        self.animationIdentity = AetherAnimationIdentity(UUID().uuidString)
        super.init()
    }

    public init(animationIdentity: AetherAnimationIdentity) {
        self.animationIdentity = animationIdentity
        super.init()
    }
}

open class AetherControlNode: AetherMainActorControlNode, AetherAnimatableNode {
    public let animationIdentity: AetherAnimationIdentity

    public override init() {
        self.animationIdentity = AetherAnimationIdentity(UUID().uuidString)
        super.init()
    }

    public init(animationIdentity: AetherAnimationIdentity) {
        self.animationIdentity = animationIdentity
        super.init()
    }
}

public final class AetherNavigationItemNodeObservation {
    private let cancellation: () -> Void
    private var isCancelled = false

    fileprivate init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    deinit {
        cancel()
    }

    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        cancellation()
    }
}

public enum AetherStatusBarStyle: Equatable {
    case `default`
    case lightContent
    case darkContent
}

open class AetherNavigationItemNode: AetherDisplayNode {
    public var title: String? {
        didSet {
            setNeedsLayout()
            notifyChangeObservers()
        }
    }

    public var leadingNodes: [ASDisplayNode] = [] {
        didSet {
            replaceManagedSubnodes(oldValue, with: leadingNodes)
            notifyChangeObservers()
        }
    }

    public var trailingNodes: [ASDisplayNode] = [] {
        didSet {
            replaceManagedSubnodes(oldValue, with: trailingNodes)
            notifyChangeObservers()
        }
    }

    private var changeObservers: [UUID: () -> Void] = [:]

    public init(title: String? = nil) {
        self.title = title
        super.init()
    }

    public override init() {
        super.init()
    }

    private func replaceManagedSubnodes(_ oldNodes: [ASDisplayNode], with newNodes: [ASDisplayNode]) {
        for node in oldNodes where !newNodes.contains(where: { $0 === node }) {
            node.removeFromSupernode()
        }
        for node in newNodes where node.supernode !== self {
            addSubnode(node)
        }
        setNeedsLayout()
    }

    @discardableResult
    public func addChangeObserver(_ observer: @escaping () -> Void) -> AetherNavigationItemNodeObservation {
        let id = UUID()
        changeObservers[id] = observer
        return AetherNavigationItemNodeObservation { [weak self] in
            self?.changeObservers[id] = nil
        }
    }

    private func notifyChangeObservers() {
        for observer in changeObservers.values {
            observer()
        }
    }
}

open class AetherScreenNode: AetherDisplayNode {
    public let navigationItemNode: AetherNavigationItemNode
    public var preferredStatusBarStyle: AetherStatusBarStyle = .default

    public init(navigationItemNode: AetherNavigationItemNode = AetherNavigationItemNode()) {
        self.navigationItemNode = navigationItemNode
        super.init()
    }

    open func screenWillAppear() {}
    open func screenDidAppear() {}
    open func screenWillDisappear() {}
    open func screenDidDisappear() {}
}
