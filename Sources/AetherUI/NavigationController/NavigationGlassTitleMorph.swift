import UIKit

/// Lets a glass title view hand the transition a copy of its text without
/// its glass. Text inside native glass is drawn with vibrancy, so rendering
/// the on-screen labels would not give their real colors; a fresh copy
/// does. Title views that do not adopt it are rendered as a whole.
public protocol NavigationGlassTitleContentProviding: AnyObject {
    /// A standalone copy of the title's text and its frame in the title
    /// view's coordinates.
    func makeGlassTitleContentCopy() -> (view: UIView, frame: CGRect)?
}

/// Liquid stand-in for a glass title view (`NavigationBarTitleViewStyle.glass`)
/// during a push or pop.
///
/// On push the capsule flows out of the glass button nearest to the title
/// (for example a "+" in the trailing group): the edge facing the title runs
/// ahead, the other one lags and settles with a small elastic wobble, and the
/// title's text materialises inside the moving capsule, sharpening as the
/// capsule comes to rest. On pop the text dissolves inside the capsule while
/// it flows back into the button, which absorbs it with an elastic bump.
/// The title view itself never slides with the page.
final class NavigationGlassTitleMorph {
    enum Direction {
        case appear
        case disappear
    }

    typealias Spring = (omega: CGFloat, damping: CGFloat, delay: CGFloat)

    private struct Springs {
        let leading: Spring
        let trailing: Spring
        let vertical: Spring
        /// 0 → 1: the text materialising (appear) or dissolving (disappear).
        let content: Spring
    }

    private static let maximumContentBlur: CGFloat = 10.0

    private let direction: Direction
    private let anchor: CGRect
    private let title: CGRect
    private let overlay = UIView()
    /// Configured exactly like a glass title view's own material, so the
    /// hand-over at the end is invisible: standalone (a merge container
    /// renders a different rim), layer-rounded and interactive.
    private let drop = GlassBackgroundView(style: .regular)
    private let contentHost = UIView()
    private let contentMask = CAShapeLayer()
    private let contentView: UIView?
    /// Offset of the text's center from the title view's center.
    private let contentOffset: CGPoint
    private let isDark: Bool
    private let anchorScale: ((CGPoint) -> Void)?
    private var displayLink: CADisplayLink?
    /// Animation time: starts at the first rendered frame and advances by
    /// at most 1/30 s per frame, so a busy main thread at the start of a
    /// push (building the incoming screen) slows the morph down instead of
    /// skipping its first half.
    private var elapsed: CGFloat = 0.0
    private var lastTimestamp: CFTimeInterval?
    private var previousSample: (time: CGFloat, midX: CGFloat)?
    private var squash: CGFloat = 0.0
    private var isSettled = false
    private var isContentSettled = false
    private var pendingReveal: (() -> Void)?
    private(set) var isFinished = false

    /// - Parameters:
    ///   - anchor: the glass button the capsule flows out of / back into.
    ///   - title: the settled title view frame.
    ///   - content: the rendered text and its frame, in the same space.
    ///   - anchorScale: applies the anchor button's elastic response.
    init(
        hostView: UIView,
        below sibling: UIView?,
        direction: Direction,
        anchor: CGRect,
        title: CGRect,
        content: (view: UIView, frame: CGRect)?,
        isDark: Bool,
        anchorScale: ((CGPoint) -> Void)?
    ) {
        self.direction = direction
        self.anchor = anchor
        self.title = title
        self.contentView = content?.view
        self.contentOffset = content.map {
            CGPoint(x: $0.frame.midX - title.midX, y: $0.frame.midY - title.midY)
        } ?? .zero
        self.isDark = isDark
        self.anchorScale = anchorScale

        overlay.isUserInteractionEnabled = false
        overlay.frame = hostView.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if let sibling, sibling.superview === hostView {
            hostView.insertSubview(overlay, belowSubview: sibling)
        } else {
            hostView.addSubview(overlay)
        }

        drop.isUserInteractionEnabled = false
        drop.glassIsInteractive = true
        overlay.addSubview(drop)

        // The text lives inside the capsule: it is clipped by the capsule's
        // current shape and travels with it.
        contentHost.isUserInteractionEnabled = false
        contentHost.frame = overlay.bounds
        contentHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentMask.fillColor = UIColor.black.cgColor
        contentHost.layer.mask = contentMask
        overlay.addSubview(contentHost)
        if let content {
            content.view.isUserInteractionEnabled = false
            if content.view.bounds.size != content.frame.size {
                content.view.bounds = CGRect(origin: .zero, size: content.frame.size)
                content.view.layoutIfNeeded()
            }
            contentHost.addSubview(content.view)
        }

        let start = direction == .appear ? anchor : title
        apply(rect: start, contentProgress: direction == .appear ? 0.0 : 1.0)
        drop.alpha = direction == .appear ? 0.0 : 1.0
    }

    deinit {
        displayLink?.invalidate()
        // The stand-in must never outlive its morph.
        overlay.removeFromSuperview()
    }

    func start() {
        elapsed = 0.0
        lastTimestamp = nil
        let target = NavigationGlassTitleMorphLinkTarget { [weak self] in
            self?.step()
        }
        let link = CADisplayLink(target: target, selector: #selector(NavigationGlassTitleMorphLinkTarget.tick))
        if #available(iOS 15.0, *) {
            let maximum = Float(UIScreen.main.maximumFramesPerSecond)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60.0, maximum: maximum, preferred: maximum)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Called once the real title view sits at its settled place. It takes
    /// over as soon as the capsule has come to rest with its text sharp; the
    /// stand-in text matches it pixel for pixel, so the swap is invisible.
    func reveal(_ showTitle: @escaping () -> Void) {
        guard direction == .appear else {
            showTitle()
            return
        }
        if isSettled {
            finishReveal(showTitle)
        } else {
            pendingReveal = showTitle
        }
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        pendingReveal = nil
        isFinished = true
        anchorScale?(CGPoint(x: 1.0, y: 1.0))
        overlay.removeFromSuperview()
    }

    // MARK: - Motion

    /// Calibrated on the reference recording: the leading edge covers ~40%
    /// of the way in 50 ms, the trailing edge starts ~50 ms later and lands
    /// with a slight overshoot; the text shows up at ~80% of the way and is
    /// sharp ~0.17 s after it appeared.
    private var springs: Springs {
        switch direction {
        case .appear:
            return Springs(
                leading: (26.0, 0.92, 0.07),
                trailing: (20.0, 0.66, 0.12),
                vertical: (24.0, 0.82, 0.07),
                content: (18.0, 1.0, 0.17)
            )
        case .disappear:
            return Springs(
                leading: (26.0, 0.9, 0.0),
                trailing: (19.0, 0.8, 0.03),
                vertical: (24.0, 0.86, 0.0),
                content: (30.0, 1.0, 0.0)
            )
        }
    }

    private func step() {
        let now = CACurrentMediaTime()
        if let lastTimestamp {
            elapsed += min(CGFloat(now - lastTimestamp), 1.0 / 30.0)
        }
        lastTimestamp = now
        let time = elapsed
        let springs = self.springs
        let from = direction == .appear ? anchor : title
        let to = direction == .appear ? title : anchor
        // The edge facing the destination leads.
        let movesLeft = to.midX < from.midX
        let leftSpring = movesLeft ? springs.leading : springs.trailing
        let rightSpring = movesLeft ? springs.trailing : springs.leading

        let left = Self.lerp(from.minX, to.minX, Self.spring(time, leftSpring))
        let right = Self.lerp(from.maxX, to.maxX, Self.spring(time, rightSpring))
        let vertical = Self.spring(time, springs.vertical)
        let top = Self.lerp(from.minY, to.minY, vertical)
        let bottom = Self.lerp(from.maxY, to.maxY, vertical)
        var rect = CGRect(x: left, y: top, width: max(1.0, right - left), height: max(1.0, bottom - top))

        // Liquid: the capsule thins while it travels fast and swells back
        // as it slows down.
        let midX = rect.midX
        var targetSquash: CGFloat = 0.0
        if let previousSample, time > previousSample.time {
            let velocity = abs(midX - previousSample.midX) / (time - previousSample.time)
            targetSquash = min(0.14, velocity / 4200.0)
        }
        previousSample = (time, midX)
        squash += (targetSquash - squash) * 0.35
        rect = rect.insetBy(dx: 0.0, dy: rect.height * squash * 0.5)

        let contentSpring = Self.spring(time, springs.content)
        let contentProgress = direction == .appear ? contentSpring : 1.0 - contentSpring
        apply(rect: rect, contentProgress: contentProgress)

        switch direction {
        case .appear:
            drop.alpha = min(1.0, max(0.0, (time - springs.leading.delay) / 0.05))
            // The button gives way as the capsule pulls out of it.
            let pull = Self.bump(time - springs.leading.delay, duration: 0.24)
            anchorScale?(CGPoint(x: 1.0 + 0.10 * pull, y: 1.0 - 0.06 * pull))
        case .disappear:
            // The button absorbs the capsule over its last stretch and
            // answers with an elastic bump.
            let remaining = 1.0 - Self.spring(time, springs.trailing)
            drop.alpha = min(1.0, max(0.0, remaining / 0.3))
            let absorbTime = time - 0.12
            let bump = Self.elastic(absorbTime)
            anchorScale?(CGPoint(x: 1.0 + 0.12 * bump, y: 1.0 + 0.12 * bump))
        }

        let shapeSettled = [leftSpring, rightSpring, springs.vertical].allSatisfy { Self.isSettled(time, $0) } && squash < 0.004
        isContentSettled = Self.isSettled(time, springs.content)
        let anchorSettled = direction == .appear ? time > springs.leading.delay + 0.24 : time > 0.12 + 0.55
        guard (shapeSettled && isContentSettled && anchorSettled) || time > 1.4 else { return }
        displayLink?.invalidate()
        displayLink = nil
        isSettled = true
        anchorScale?(CGPoint(x: 1.0, y: 1.0))
        switch direction {
        case .appear:
            apply(rect: title, contentProgress: 1.0)
            if let pendingReveal {
                self.pendingReveal = nil
                finishReveal(pendingReveal)
            }
        case .disappear:
            isFinished = true
            overlay.removeFromSuperview()
        }
    }

    /// Hard swap in a single transaction, no crossfade: two half-transparent
    /// copies of the same glass and text read as a visible dip, and two
    /// opaque copies stacked for a few frames read as a flash. The stand-in
    /// sits at the same compositing level as the real title, so swapping
    /// them in one commit is invisible.
    private func finishReveal(_ showTitle: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        showTitle()
        isFinished = true
        displayLink?.invalidate()
        displayLink = nil
        overlay.removeFromSuperview()
        CATransaction.commit()
    }

    private func apply(rect: CGRect, contentProgress: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let radius = min(rect.width, rect.height) / 2.0
        drop.frame = rect
        drop.update(
            size: rect.size,
            cornerRadius: radius,
            isDark: isDark,
            tintColor: .init(kind: .panel),
            isInteractive: true,
            isVisible: true,
            transition: .immediate
        )

        contentMask.frame = contentHost.bounds
        contentMask.path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
        guard let contentView else { return }
        contentView.center = CGPoint(x: rect.midX + contentOffset.x, y: rect.midY + contentOffset.y)
        let progress = min(1.0, max(0.0, contentProgress))
        contentView.alpha = Self.smoothStep(progress / 0.45)
        let blur = Self.maximumContentBlur * (1.0 - progress)
        ContainedViewLayoutTransition.immediate.setBlur(layer: contentView.layer, radius: blur < 0.2 ? 0.0 : blur)
    }

    // MARK: - Кривые

    private static func spring(_ time: CGFloat, _ parameters: Spring) -> CGFloat {
        let t = time - parameters.delay
        guard t > 0.0 else { return 0.0 }
        let w = parameters.omega
        let z = parameters.damping
        if z < 0.999 {
            let wd = w * sqrt(1.0 - z * z)
            return 1.0 - exp(-z * w * t) * (cos(wd * t) + (z * w / wd) * sin(wd * t))
        }
        return 1.0 - (1.0 + w * t) * exp(-w * t)
    }

    private static func isSettled(_ time: CGFloat, _ parameters: Spring) -> Bool {
        let now = spring(time, parameters)
        let next = spring(time + 1.0 / 60.0, parameters)
        return time > parameters.delay && abs(1.0 - now) < 0.003 && abs(next - now) < 0.003
    }

    /// Одиночный плавный подъём: 0 → 1 → 0 в течение `duration`.
    private static func bump(_ time: CGFloat, duration: CGFloat) -> CGFloat {
        guard time > 0.0, time < duration else { return 0.0 }
        return sin(.pi * time / duration)
    }

    /// Упругий отклик на импульс: отклоняется, слегка проседает ниже уровня равновесия, затем приходит в состояние покоя.
    private static func elastic(_ time: CGFloat) -> CGFloat {
        guard time > 0.0 else { return 0.0 }
        let omega: CGFloat = 18.0
        let damping: CGFloat = 0.42
        let wd = omega * sqrt(1.0 - damping * damping)
        return exp(-damping * omega * time) * sin(wd * time)
    }

    private static func smoothStep(_ value: CGFloat) -> CGFloat {
        let t = min(1.0, max(0.0, value))
        return t * t * (3.0 - 2.0 * t)
    }

    private static func lerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat {
        from + (to - from) * t
    }
}

private final class NavigationGlassTitleMorphLinkTarget: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func tick() {
        handler()
    }
}
