import UIKit

final class AetherModalPresentationController: UIPresentationController, UIGestureRecognizerDelegate {
    private let dimView = UIView()
    private var panGesture: UIPanGestureRecognizer?
    private var detent: AetherModalController.Detent = .stage1
    private var dragStartFrame: CGRect = .zero
    private var dragStartDetent: AetherModalController.Detent = .stage1
    private var dragDriving = false
    private var isPresenting = false
    private var isDismissing = false
    private var lastContainerBounds: CGRect = .zero
    private var lastContainerSafeAreaInsets: UIEdgeInsets = .zero
    private var pendingDetent: (detent: AetherModalController.Detent, animated: Bool)?

    private var settleLink: CADisplayLink?
    private var settleStartTime: CFTimeInterval = 0
    private var settleDuration: CFTimeInterval = 0
    private var settleStartFrame: CGRect = .zero
    private var settleTargetFrame: CGRect = .zero
    private var settleInitialSlope: CGFloat = 0
    private var motionGeneration = 0
    private var isInteractiveResizeActive = false

    deinit { settleLink?.invalidate() }

    private var modalController: AetherModalController? {
        presentedViewController as? AetherModalController
    }

    private var allowedDetents: Set<AetherModalController.Detent> {
        modalController?.config.detents ?? [.stage1, .stage2]
    }

    private func geometry(in container: UIView) -> AetherModalDragGeometry {
        AetherModalDragGeometry(
            compactFrame: frame(for: .stage1, in: container.bounds),
            expandedFrame: frame(for: .stage2, in: container.bounds),
            allowedDetents: allowedDetents
        )
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let container = containerView else { return .zero }
        return frame(for: detent, in: container.bounds)
    }

    override func presentationTransitionWillBegin() {
        super.presentationTransitionWillBegin()
        guard let container = containerView else { return }
        isPresenting = true
        lastContainerBounds = container.bounds
        lastContainerSafeAreaInsets = container.safeAreaInsets
        detent = modalController?.config.resolvedInitialDetent ?? .stage1
        dimView.backgroundColor = .black
        dimView.alpha = 0
        dimView.frame = container.bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleDimTap)))
        container.addSubview(dimView)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        presentedView?.addGestureRecognizer(pan)
        panGesture = pan
        modalController?.applyCurrentDetent(detent)
        let progress: CGFloat = detent == .stage2 ? 1 : 0
        modalController?.applyDetentProgress(progress)
        if let coordinator = presentedViewController.transitionCoordinator {
            coordinator.animate(alongsideTransition: { [weak self] _ in
                self?.dimView.alpha = self?.dimAlpha(forProgress: progress) ?? 0
            })
        } else {
            dimView.alpha = dimAlpha(forProgress: progress)
        }
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        super.presentationTransitionDidEnd(completed)
        isPresenting = false
        if !completed {
            pendingDetent = nil
            stopMotion()
            dimView.removeFromSuperview()
            if let panGesture { presentedView?.removeGestureRecognizer(panGesture) }
            panGesture = nil
        } else if let container = containerView {
            applyFrame(frame(for: detent, in: container.bounds), in: container)
            resumePendingDetentIfPossible()
        }
    }

    override func dismissalTransitionWillBegin() {
        super.dismissalTransitionWillBegin()
        isDismissing = true
        pendingDetent = nil
        stopMotion()
        if let coordinator = presentedViewController.transitionCoordinator
            ?? presentingViewController.transitionCoordinator {
            coordinator.animate(alongsideTransition: { [weak self] _ in
                self?.dimView.alpha = 0
            })
        } else {
            dimView.alpha = 0
        }
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        super.dismissalTransitionDidEnd(completed)
        isDismissing = false
        if completed {
            dimView.removeFromSuperview()
        } else if let container = containerView {
            applyFrame(frame(for: detent, in: container.bounds), in: container)
        }
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        guard let container = containerView else { return }
        dimView.frame = container.bounds
        if lastContainerBounds != container.bounds
            || lastContainerSafeAreaInsets != container.safeAreaInsets {
            lastContainerBounds = container.bounds
            lastContainerSafeAreaInsets = container.safeAreaInsets
            // Rotation/scene resizing invalidates the old endpoints. Finish
            // at the selected detent in the new geometry rather than allowing
            // a display link to write its obsolete frame back on the next tick.
            stopMotion()
            panGesture?.isEnabled = false
            panGesture?.isEnabled = true
        }
        // Presentation/dismissal animators own their frames until completion.
        // Content and material use the same visible bounds as the sheet.
        if !dragDriving && settleLink == nil && !isPresenting && !isDismissing
            && modalController?.isContentTransitioning != true {
            applyFrame(frame(for: detent, in: container.bounds), in: container)
            resumePendingDetentIfPossible()
        }
    }

    /// Navigation temporarily owns the viewport. Preserve the displayed frame
    /// and resume toward the selected detent after its transition completes.
    func suspendForContentTransition() {
        guard dragDriving || settleLink != nil else { return }
        let target: AetherModalController.Detent
        if dragDriving, let container = containerView, let frame = presentedView?.frame {
            target = nearestDetent(to: frame, in: container)
        } else {
            target = detent
        }
        if pendingDetent == nil {
            pendingDetent = (target, true)
        }
        // Store our continuation before notifying delegates. A delegate may
        // request a newer detent during resize-end; its request must win.
        // Clear drag state before recognizer cancellation so that callback
        // cannot start a competing rollback animation.
        stopMotion()
        panGesture?.isEnabled = false
        panGesture?.isEnabled = true
    }

    func resumePendingDetentIfPossible() {
        guard !isPresenting, !isDismissing,
              modalController?.isContentTransitioning != true,
              let pendingDetent else { return }
        self.pendingDetent = nil
        setDetent(pendingDetent.detent, animated: pendingDetent.animated)
    }

    func setDetent(_ newDetent: AetherModalController.Detent, animated: Bool) {
        guard !isDismissing, allowedDetents.contains(newDetent) else { return }
        if isPresenting || modalController?.isContentTransitioning == true {
            // One owner changes the viewport at a time. Keep the latest
            // request, then honor its animation once navigation/presentation
            // releases the sheet rather than losing it or changing mid-push.
            pendingDetent = (newDetent, animated)
            return
        }
        pendingDetent = nil
        if dragDriving {
            dragDriving = false
            // Cancel the old recognizer stream before starting a programmatic
            // motion, so subsequent .changed events cannot overwrite it.
            panGesture?.isEnabled = false
            panGesture?.isEnabled = true
        }
        animateTo(detent: newDetent, container: containerView, initialVelocityY: 0, animated: animated)
    }

    private func frame(for detent: AetherModalController.Detent, in bounds: CGRect) -> CGRect {
        let cfg = modalController?.config ?? .init()
        let safeArea = containerView?.safeAreaInsets ?? presentingViewController.view.safeAreaInsets
        if let contentFrame = contentSizedFrame(for: detent, in: bounds, safeAreaInsets: safeArea) {
            return contentFrame
        }
        if let fixedSize = cfg.fixedSize {
            let availableWidth = max(0.0, bounds.width - safeArea.left - safeArea.right)
            let availableHeight = max(0.0, bounds.height - safeArea.top - safeArea.bottom)
            let width = min(max(0.0, fixedSize.width), availableWidth)
            let height = min(max(0.0, fixedSize.height), availableHeight)
            return CGRect(
                x: safeArea.left + floor((availableWidth - width) / 2.0),
                y: safeArea.top + floor((availableHeight - height) / 2.0),
                width: width,
                height: height
            )
        }
        switch detent {
        case .stage1:
            let sideInset = min(max(0.0, cfg.sideInset), bounds.width / 2.0)
            let bottom = max(safeArea.top, bounds.height - max(0.0, cfg.bottomInsetStage1))
            let resolvedTopInset = cfg.topInsetStage1 < 0.0 ? bounds.height * 0.5 : cfg.topInsetStage1
            let configuredTop = safeArea.top + max(0.0, resolvedTopInset)
            let minimumHeight = bounds.height * 0.5
            let height = min(bottom - safeArea.top, max(bottom - configuredTop, minimumHeight))
            let top = bottom - height
            return CGRect(
                x: sideInset,
                y: top,
                width: max(0.0, bounds.width - sideInset * 2.0),
                height: max(0.0, height)
            )
        case .stage2:
            let bottom = max(safeArea.top, bounds.height - max(0.0, cfg.bottomInsetStage2))
            let top = min(bottom, safeArea.top + max(0.0, cfg.topInsetStage2))
            return CGRect(
                x: 0.0,
                y: top,
                width: bounds.width,
                height: max(0.0, bottom - top)
            )
        }
    }

    /// Shared by presentation and layout so a content-sized sheet is measured
    /// against the current scene, including changes to its bottom safe area.
    func contentSizedFrame(
        for detent: AetherModalController.Detent = .stage1,
        in bounds: CGRect,
        safeAreaInsets: UIEdgeInsets
    ) -> CGRect? {
        guard let modal = modalController, modal.config.sizesToContent else { return nil }
        let cfg = modal.config
        let sideInset = min(max(0, cfg.sideInset), max(0, bounds.width) / 2)
        let width = max(0, bounds.width - sideInset * 2)
        let safeTop = min(max(0, safeAreaInsets.top), max(0, bounds.height))
        let configuredBottomInset = detent == .stage1 ? cfg.bottomInsetStage1 : cfg.bottomInsetStage2
        let bottomInset = min(max(0, configuredBottomInset), max(0, bounds.height - safeTop))
        let bottom = bounds.maxY - bottomInset
        let availableHeight = max(0, bounds.height - safeTop - bottomInset)
        var contentSafeArea = safeAreaInsets
        contentSafeArea.bottom = max(0, safeAreaInsets.bottom - bottomInset)
        contentSafeArea.left = max(0, safeAreaInsets.left - sideInset)
        contentSafeArea.right = max(0, safeAreaInsets.right - sideInset)
        let requestedHeight = modal.contentHeight(forWidth: width, safeAreaInsets: contentSafeArea)
        let height = requestedHeight.isFinite ? min(max(0, requestedHeight), availableHeight) : availableHeight
        return CGRect(
            x: bounds.minX + sideInset,
            y: bottom - height,
            width: width,
            height: height
        )
    }

    override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        if modalController?.config.sizesToContent == true {
            containerView?.setNeedsLayout()
        }
    }

    @objc private func handleDimTap() {
        guard !presentedViewController.isModalInPresentation,
              !isPresenting, !isDismissing,
              modalController?.isContentTransitioning != true else { return }
        presentedViewController.dismiss(animated: true)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let container = containerView, let presentedView else { return }
        switch gesture.state {
        case .began:
            stopSettleLink()
            motionGeneration += 1
            dragStartFrame = presentedView.frame
            dragStartDetent = nearestDetent(to: dragStartFrame, in: container)
            dragDriving = true
            gesture.setTranslation(.zero, in: container)
            notifyResizeBeginIfNeeded()
            guard dragDriving, !isDismissing else { return }
            if let scroll = modalController?.primaryScrollView,
               gestureStartedInPrimaryScrollContent(gesture) {
                // Arbitration has already accepted sheet ownership; stop the
                // simultaneous scroll recognizer before it can bounce content.
                scroll.panGestureRecognizer.isEnabled = false
                scroll.panGestureRecognizer.isEnabled = true
            }
        case .changed:
            guard dragDriving else { return }
            applyDrag(gesture.translation(in: container).y, in: container)
        case .ended:
            guard dragDriving else { return }
            applyDrag(gesture.translation(in: container).y, in: container)
            guard dragDriving, !isDismissing else { return }
            dragDriving = false
            finishDrag(velocityY: gesture.velocity(in: container).y, in: container)
        case .cancelled, .failed:
            guard dragDriving else { return }
            dragDriving = false
            // Cancellation is a rollback, never a velocity-based dismissal.
            animateTo(detent: dragStartDetent, container: container, initialVelocityY: 0)
        default:
            break
        }
    }

    private func applyDrag(_ translationY: CGFloat, in container: UIView) {
        let newFrame = geometry(in: container).frame(from: dragStartFrame, translationY: translationY)
        applyFrame(newFrame, in: container)
    }

    private func finishDrag(velocityY: CGFloat, in container: UIView) {
        guard let currentFrame = presentedView?.frame else {
            notifyResizeEndIfNeeded()
            return
        }
        let geometry = geometry(in: container)
        let lowerFrame = allowedDetents.contains(.stage1) ? geometry.compactFrame : geometry.expandedFrame
        let dismissalDistance = currentFrame.minY - lowerFrame.minY
        if !presentedViewController.isModalInPresentation,
           dismissalDistance > 0,
           (dismissalDistance > 140 || velocityY > 800) {
            presentedViewController.dismiss(animated: true)
            return
        }
        let projected = currentFrame.offsetBy(dx: 0, dy: velocityY * 0.12)
        animateTo(
            detent: nearestDetent(to: projected, in: container),
            container: container,
            initialVelocityY: velocityY
        )
    }

    private func animateTo(
        detent targetDetent: AetherModalController.Detent,
        container: UIView?,
        initialVelocityY: CGFloat,
        animated: Bool = true
    ) {
        guard !isDismissing else { return }
        stopSettleLink()
        motionGeneration += 1
        let generation = motionGeneration
        detent = targetDetent
        modalController?.applyCurrentDetent(targetDetent)
        // Delegate callbacks may synchronously request another detent/dismiss.
        guard generation == motionGeneration, !isDismissing else { return }
        guard let container else {
            modalController?.applyDetentProgress(targetDetent == .stage2 ? 1 : 0)
            notifyResizeEndIfNeeded()
            return
        }
        let targetFrame = frame(for: targetDetent, in: container.bounds)
        let startFrame = presentedView?.frame ?? targetFrame
        guard animated, startFrame != targetFrame else {
            applyFrame(targetFrame, in: container)
            if generation == motionGeneration { notifyResizeEndIfNeeded() }
            return
        }

        settleStartFrame = startFrame
        settleTargetFrame = targetFrame
        let distance = abs(targetFrame.minY - startFrame.minY)
        let fullDistance = max(1, abs(geometry(in: container).compactFrame.minY - geometry(in: container).expandedFrame.minY))
        settleDuration = UIAccessibility.isReduceMotionEnabled
            ? 0.16
            : 0.30 + 0.12 * Double(min(1, distance / fullDistance))
        let signedDistance = targetFrame.minY - startFrame.minY
        settleInitialSlope = abs(signedDistance) > 0.5
            ? max(0, min(3, initialVelocityY / signedDistance * CGFloat(settleDuration)))
            : 0
        settleStartTime = CACurrentMediaTime()
        notifyResizeBeginIfNeeded()
        guard generation == motionGeneration, !isDismissing else { return }
        let target = AetherDisplayLinkTarget { [weak self] _ in self?.tickSettleLink() }
        let link = CADisplayLink(target: target, selector: #selector(AetherDisplayLinkTarget.tick(_:)))
        if #available(iOS 15.0, *) {
            let maximum = Float(container.window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
        }
        settleLink = link
        link.add(to: .main, forMode: .common)
    }

    private func tickSettleLink() {
        guard settleLink != nil, let container = containerView else {
            stopMotion()
            return
        }
        let generation = motionGeneration
        let t = max(0, min(1, CGFloat((CACurrentMediaTime() - settleStartTime) / settleDuration)))
        // A bounded Hermite settle preserves forward release velocity and
        // reaches an exact endpoint without spring overshoot outside the sheet.
        let slope = settleInitialSlope
        let eased = (slope - 2) * t * t * t + (3 - 2 * slope) * t * t + slope * t
        applyFrame(AetherModalDragGeometry.interpolate(from: settleStartFrame, to: settleTargetFrame, progress: eased), in: container)
        guard generation == motionGeneration else { return }
        if t >= 1 {
            stopSettleLink()
            notifyResizeEndIfNeeded()
        }
    }

    private func applyFrame(_ frame: CGRect, in container: UIView) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            presentedView?.frame = frame
            let progress = geometry(in: container).progress(for: frame)
            dimView.alpha = dimAlpha(forProgress: progress)
            modalController?.applyDetentProgress(progress)
            // Surface, clipping, content viewport and footer must commit in
            // the same display tick, with no stage2-sized hidden canvas.
            presentedView?.setNeedsLayout()
            presentedView?.layoutIfNeeded()
        }
        CATransaction.commit()
    }

    private func stopSettleLink() {
        settleLink?.invalidate()
        settleLink = nil
    }

    private func stopMotion() {
        motionGeneration += 1
        dragDriving = false
        stopSettleLink()
        notifyResizeEndIfNeeded()
    }

    private func notifyResizeBeginIfNeeded() {
        guard !isInteractiveResizeActive, let modal = modalController else { return }
        isInteractiveResizeActive = true
        modal.beginInteractiveResize()
        modal.delegate?.modalControllerWillBeginInteractiveResize(modal)
    }

    private func notifyResizeEndIfNeeded() {
        guard isInteractiveResizeActive else { return }
        isInteractiveResizeActive = false
        guard let modal = modalController else { return }
        modal.endInteractiveResize()
        modal.delegate?.modalControllerDidEndInteractiveResize(modal)
    }

    private func nearestDetent(to frame: CGRect, in container: UIView) -> AetherModalController.Detent {
        if allowedDetents == [.stage1] { return .stage1 }
        if allowedDetents == [.stage2] { return .stage2 }
        return geometry(in: container).progress(for: frame) < 0.5 ? .stage1 : .stage2
    }

    private func dimAlpha(forProgress progress: CGFloat) -> CGFloat {
        let compact = modalController?.config.dimAlphaStage1 ?? 0.25
        let expanded = modalController?.config.dimAlphaStage2 ?? 0.4
        return compact + (expanded - compact) * max(0, min(1, progress))
    }

    private func gestureStartedInPrimaryScrollContent(_ gesture: UIGestureRecognizer) -> Bool {
        guard let presentedView, let scroll = modalController?.primaryScrollView,
              let hit = presentedView.hitTest(gesture.location(in: presentedView), with: nil) else { return false }
        return hit === scroll || hit.isDescendant(of: scroll)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              let container = containerView, let presentedView else { return false }
        guard !isPresenting, !isDismissing,
              modalController?.isContentTransitioning != true else { return false }
        let velocity = pan.velocity(in: container)
        guard abs(velocity.y) > abs(velocity.x) else { return false }
        let scroll = modalController?.primaryScrollView
        return geometry(in: container).shouldDrive(
            translationY: velocity.y,
            currentFrame: presentedView.frame,
            startsInScrollContent: gestureStartedInPrimaryScrollContent(pan),
            scrollIsAtTop: scroll.map { $0.contentOffset.y + $0.adjustedContentInset.top <= 0.5 } ?? true
        )
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        other === modalController?.primaryScrollView?.panGestureRecognizer
    }
}
