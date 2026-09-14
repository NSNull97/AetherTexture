import UIKit
import AsyncDisplayKit

public struct AetherSkeletonTheme: Equatable {
    /// Base fill color of the placeholder shape.
    public let baseColor: UIColor
    /// Highlight color that sweeps across during shimmer.
    public let highlightColor: UIColor
    /// Cycle length (one full sweep). Defaults to 1.3s.
    public let shimmerDuration: TimeInterval
    /// Horizontal fraction of the view the highlight gradient occupies.
    public let shimmerWidthFraction: CGFloat

    public init(
        baseColor: UIColor,
        highlightColor: UIColor,
        shimmerDuration: TimeInterval = 1.3,
        shimmerWidthFraction: CGFloat = 0.45
    ) {
        self.baseColor = baseColor
        self.highlightColor = highlightColor
        self.shimmerDuration = shimmerDuration
        self.shimmerWidthFraction = shimmerWidthFraction
    }

    public static let light = AetherSkeletonTheme(
        baseColor: UIColor(white: 0.9, alpha: 1.0),
        highlightColor: UIColor(white: 0.97, alpha: 1.0)
    )

    public static let dark = AetherSkeletonTheme(
        baseColor: UIColor(white: 0.18, alpha: 1.0),
        highlightColor: UIColor(white: 0.32, alpha: 1.0)
    )

    /// Adapts to the current `UITraitCollection.userInterfaceStyle`.
    public static let system = AetherSkeletonTheme(
        baseColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.18, alpha: 1.0)
                : UIColor(white: 0.9, alpha: 1.0)
        },
        highlightColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.32, alpha: 1.0)
                : UIColor(white: 0.97, alpha: 1.0)
        }
    )
}

/// Compatibility host for `AetherSkeletonNode`.
///
/// New code should prefer `AetherSkeletonNode` and its shape-specific
/// subclasses directly. This view remains for Auto Layout and older callers,
/// but rendering and shimmer ownership live in Texture.
open class AetherSkeletonView: UIView {
    public let contentNode: AetherSkeletonNode

    public var theme: AetherSkeletonTheme {
        get { contentNode.theme }
        set {
            contentNode.theme = newValue
            setNeedsLayout()
        }
    }

    public var isAnimating: Bool {
        get { requestedAnimationState }
        set {
            requestedAnimationState = newValue
            contentNode.isAnimating = newValue
        }
    }

    private var requestedAnimationState = false

    public init(theme: AetherSkeletonTheme = .light) {
        self.contentNode = AetherSkeletonNode(theme: theme, isAnimating: false)
        super.init(frame: .zero)
        setupNodeHost()
    }

    fileprivate init(contentNode: AetherSkeletonNode) {
        self.contentNode = contentNode
        super.init(frame: .zero)
        setupNodeHost()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        contentNode.frame = bounds
    }

    open override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        isAnimating = newWindow != nil
    }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            contentNode.refreshThemeForCurrentTraits()
            contentNode.isAnimating = requestedAnimationState
        }
    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            contentNode.refreshThemeForCurrentTraits()
        }
    }

    private func setupNodeHost() {
        contentNode.view.isUserInteractionEnabled = false
        addSubview(contentNode.view)
        contentNode.isAnimating = false
    }
}

/// Convenience: a capsule-shaped skeleton (for single-line text placeholders).
public final class AetherSkeletonLineView: AetherSkeletonView {
    /// Height of the capsule. Width is inferred from auto-layout or frame.
    public var lineHeight: CGFloat {
        get { lineNode.lineHeight }
        set {
            lineNode.lineHeight = newValue
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    private var lineNode: AetherSkeletonLineNode {
        contentNode as! AetherSkeletonLineNode
    }

    public override init(theme: AetherSkeletonTheme = .light) {
        super.init(contentNode: AetherSkeletonLineNode(theme: theme, isAnimating: false))
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: lineHeight)
    }
}

/// Convenience: a rounded-rect skeleton (for card / avatar placeholders).
public final class AetherSkeletonBlockView: AetherSkeletonView {
    /// Corner radius applied after layout. Defaults to 10pt.
    public var cornerRadius: CGFloat {
        get { contentNode.cornerRadius }
        set {
            contentNode.cornerRadius = newValue
            setNeedsLayout()
        }
    }

    public override init(theme: AetherSkeletonTheme = .light) {
        super.init(contentNode: AetherSkeletonBlockNode(theme: theme, isAnimating: false))
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Convenience: a circular skeleton (for avatar placeholders).
public final class AetherSkeletonCircleView: AetherSkeletonView {
    public override init(theme: AetherSkeletonTheme = .light) {
        super.init(contentNode: AetherSkeletonCircleNode(theme: theme, isAnimating: false))
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
