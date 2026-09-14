import UIKit

enum AetherChromeScrollTransitions {
    /// Classic attached chrome fades at a stable endpoint instead of snapping.
    /// Intermediate samples remain finger-driven and immediate.
    static let legacyEndpoint: ContainedViewLayoutTransition = .animated(
        duration: 0.20,
        curve: .easeInOut
    )
}

final class AetherNavigationScrollSourceState {
    var previousAlpha: CGFloat?
}

/// Lightweight standalone navigation-bar observation. Tab containers own a
/// richer coordinator (including minimize intent); screens outside a tab tree
/// only need the normalized navigation scroll edge and must not steal the
/// host's `UIScrollViewDelegate`.
final class AetherNavigationScrollEdgeObserver {
    private weak var scrollView: UIScrollView?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var contentSizeObservation: NSKeyValueObservation?
    private var boundsObservation: NSKeyValueObservation?
    private var contentInsetObservation: NSKeyValueObservation?
    private let onUpdate: (UIScrollView) -> Void

    init(
        scrollView: UIScrollView,
        onUpdate: @escaping (UIScrollView) -> Void
    ) {
        self.scrollView = scrollView
        self.onUpdate = onUpdate

        contentOffsetObservation = scrollView.observe(
            \.contentOffset,
            options: [.new]
        ) { [weak self] scrollView, _ in
            self?.emit(scrollView)
        }
        contentSizeObservation = scrollView.observe(
            \.contentSize,
            options: [.new]
        ) { [weak self] scrollView, _ in
            self?.emit(scrollView)
        }
        boundsObservation = scrollView.observe(
            \.bounds,
            options: [.new]
        ) { [weak self] scrollView, _ in
            self?.emit(scrollView)
        }
        contentInsetObservation = scrollView.observe(
            \.contentInset,
            options: [.new]
        ) { [weak self] scrollView, _ in
            self?.emit(scrollView)
        }

        emit(scrollView)
    }

    func refresh() {
        guard let scrollView else { return }
        emit(scrollView)
    }

    func invalidate() {
        contentOffsetObservation?.invalidate()
        contentOffsetObservation = nil
        contentSizeObservation?.invalidate()
        contentSizeObservation = nil
        boundsObservation?.invalidate()
        boundsObservation = nil
        contentInsetObservation?.invalidate()
        contentInsetObservation = nil
        scrollView = nil
    }

    deinit {
        contentOffsetObservation?.invalidate()
        contentSizeObservation?.invalidate()
        boundsObservation?.invalidate()
        contentInsetObservation?.invalidate()
    }

    private func emit(_ scrollView: UIScrollView) {
        guard self.scrollView === scrollView else { return }
        onUpdate(scrollView)
    }
}
