import UIKit

/// A footer is always owned by the sheet. Its material and controls travel
/// together in sheet coordinates, independently of a page's scroll viewport.
struct AetherModalFooterConfiguration {
    var view: UIView?
    var height: CGFloat = 0
    var fadeHeight: CGFloat = 28
    var tintColor: UIColor?
    var blurRadius: CGFloat = 2
    var drawsEdge: Bool = true

    var visibleHeight: CGFloat { view == nil ? 0 : max(0, height) }
}

final class AetherModalFooterHostView: UIView {
    private(set) var configuration = AetherModalFooterConfiguration()
    private var edgeSignature: EdgeSignature?

    private struct EdgeSignature: Equatable {
        let height: CGFloat
        let fade: CGFloat
        let tint: UIColor
        let blur: CGFloat
    }

    var hasEdgeEffect: Bool { edgeSignature != nil }

    func configure(_ configuration: AetherModalFooterConfiguration) {
        if self.configuration.view !== configuration.view {
            self.configuration.view?.removeFromSuperview()
        }
        self.configuration = configuration
        if let content = configuration.view, content.superview !== self {
            addSubview(content)
        }
        setNeedsLayout()
    }

    func update(width: CGFloat, bottom: CGFloat, offsetX: CGFloat, visibleWidth: CGFloat? = nil,
                usesLiquidGlass: Bool, defaultTint: UIColor) {
        let height = configuration.visibleHeight
        let fade = height > 0 ? max(0, configuration.fadeHeight) : 0
        frame = CGRect(x: offsetX, y: bottom - height - fade,
                       width: max(0, min(width, visibleWidth ?? width)), height: height + fade)
        clipsToBounds = true
        isHidden = height <= 0
        let signature: EdgeSignature? = height > 0 && configuration.drawsEdge && usesLiquidGlass
            ? EdgeSignature(height: height + fade, fade: fade,
                            tint: configuration.tintColor ?? defaultTint.withAlphaComponent(0.86),
                            blur: max(0, configuration.blurRadius))
            : nil
        if signature != edgeSignature {
            edgeSignature = signature
            setEdgeEffect(signature.map {
                .init(edge: .bottom, thickness: $0.height, fadeHeight: $0.fade,
                      tintColor: $0.tint, tintAlpha: 1, blurRadius: $0.blur)
            })
        }
        if let content = configuration.view, content.superview === self {
            content.frame = CGRect(x: 0, y: fade, width: width, height: height)
            bringSubviewToFront(content)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // The fade is decorative and must not intercept scrolling above a button.
        guard let content = configuration.view, let hit,
              hit === content || hit.isDescendant(of: content) else { return nil }
        return hit
    }
}
