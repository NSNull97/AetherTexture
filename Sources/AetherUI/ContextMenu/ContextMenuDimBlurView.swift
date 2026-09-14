import UIKit

// MARK: - ContextMenuDimBlurView

/// Dim layer for the context menu background. A public ultra-thin material
/// supplies the backdrop blur; its alpha maps the former continuous radius
/// input to a subtle 0...1 intensity range.
final class ContextMenuDimBlurView: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let tint = UIView()

    var blurRadius: CGFloat {
        didSet {
            guard oldValue != blurRadius else { return }
            applyBlur()
        }
    }

    var tintAlpha: CGFloat {
        didSet {
            guard oldValue != tintAlpha else { return }
            tint.backgroundColor = UIColor.black.withAlphaComponent(tintAlpha)
        }
    }

    init(blurRadius: CGFloat, tintAlpha: CGFloat) {
        self.blurRadius = blurRadius
        self.tintAlpha = tintAlpha

        super.init(frame: .zero)

        blurView.isUserInteractionEnabled = false
        addSubview(blurView)

        tint.isUserInteractionEnabled = false
        tint.backgroundColor = UIColor.black.withAlphaComponent(tintAlpha)
        addSubview(tint)

        applyBlur()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        tint.frame = bounds
    }

    private func applyBlur() {
        blurView.alpha = min(1.0, max(0.0, blurRadius / 4.0))
    }
}
