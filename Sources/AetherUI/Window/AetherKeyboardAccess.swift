import UIKit

/// Compatibility shim retained for source compatibility with early AetherUI
/// builds. AetherUI no longer exposes UIKit keyboard internals.
///
/// Use `AetherKeyboardManager` for supported keyboard state tracking.
@available(*, deprecated, message: "Use AetherKeyboardManager. Direct keyboard internals are unavailable through AetherUI.")
public enum AetherKeyboardAccess {
    public static func keyboardWindow() -> UIWindow? {
        #if !APPSTORE_SAFE
        return AetherLegacyKeyboardRuntime.keyboardWindow()
        #else
        nil
        #endif
    }

    public static func keyboardView(in window: UIWindow? = nil) -> UIView? {
        #if !APPSTORE_SAFE
        return AetherLegacyKeyboardRuntime.keyboardView(in: window)
        #else
        _ = window
        return nil
        #endif
    }
}

#if !APPSTORE_SAFE
internal enum AetherLegacyKeyboardRuntime {
    private static weak var lastInteractiveKeyboardView: UIView?

    static func updateInteractiveKeyboardOffset(
        _ offset: CGFloat,
        transition: ContainedViewLayoutTransition,
        completion: (() -> Void)? = nil
    ) {
        let activeKeyboardView = keyboardView()
        guard let keyboardView = activeKeyboardView ?? (offset.isZero ? lastInteractiveKeyboardView : nil) else {
            completion?()
            return
        }

        if let previousView = lastInteractiveKeyboardView, previousView !== keyboardView {
            previousView.layer.bounds = CGRect(origin: .zero, size: previousView.bounds.size)
        }
        lastInteractiveKeyboardView = keyboardView

        // Keep this in sync with Telegram-iOS' KeyboardManager: the model
        // bounds are updated first, then an additive position animation is
        // applied only for the settling transition. Interactive updates are
        // immediate and therefore remain locked to the finger.
        let previousBounds = keyboardView.bounds
        let updatedBounds = CGRect(
            origin: CGPoint(x: 0.0, y: -offset),
            size: previousBounds.size
        )
        keyboardView.layer.bounds = updatedBounds
        let finish: () -> Void = {
            if offset.isZero, self.lastInteractiveKeyboardView === keyboardView {
                self.lastInteractiveKeyboardView = nil
            }
            completion?()
        }
        if transition.isAnimated {
            transition.animateOffsetAdditive(
                layer: keyboardView.layer,
                offset: previousBounds.minY - updatedBounds.minY,
                completion: { _ in finish() }
            )
        } else {
            finish()
        }
    }

    static func keyboardWindowTransform(
        from currentTransform: CATransform3D,
        horizontalOffset: CGFloat? = nil,
        verticalOffset: CGFloat? = nil
    ) -> CATransform3D {
        var targetTransform = currentTransform
        if let horizontalOffset {
            targetTransform.m41 = horizontalOffset
        }
        if let verticalOffset {
            targetTransform.m42 = verticalOffset
        }
        return targetTransform
    }

    static func keyboardWindow() -> UIWindow? {
        if let keyboardWindow = bridgedKeyboardWindow() {
            return keyboardWindow
        }

        let sceneWindows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)

        // UIKit-owned windows (notably `_UIKeyboardWindowScene`) can be
        // absent from `UIWindowScene.windows`. The private `_allWindows`
        // selector is the original Telegram-style path this runtime needs;
        // keep public scene windows as a safe fallback.
        let candidates = deduplicatedWindows(internalApplicationWindows() + sceneWindows)

        if let keyboardWindow = candidates.first(where: isKeyboardWindow) {
            return keyboardWindow
        }

        return candidates.first { window in
            NSStringFromClass(type(of: window)).contains("Keyboard")
        }
    }

    static func keyboardView(in window: UIWindow? = nil) -> UIView? {
        let resolvedWindow = window ?? keyboardWindow()
        guard let keyboardWindow = resolvedWindow else {
            return nil
        }

        for view in keyboardWindow.subviews where isKeyboardViewContainer(view) {
            for subview in view.subviews where isKeyboardView(subview) {
                return subview
            }
        }

        return findKeyboardView(in: keyboardWindow)
    }

    static func updateKeyboardLeftEdge(
        _ leftEdge: CGFloat,
        transition: ContainedViewLayoutTransition,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let keyboardWindow = keyboardWindow() else {
            completion?(false)
            return
        }

        let currentTransform = keyboardWindow.layer.sublayerTransform
        let targetTransform = keyboardWindowTransform(
            from: currentTransform,
            horizontalOffset: leftEdge
        )

        switch transition {
        case .immediate:
            keyboardWindow.layer.removeAnimation(forKey: "sublayerTransform")
            keyboardWindow.layer.sublayerTransform = targetTransform
            completion?(true)
        case let .animated(duration, curve):
            let fromTransform = keyboardWindow.layer.presentation()?.sublayerTransform ?? currentTransform
            keyboardWindow.layer.sublayerTransform = targetTransform

            let animation = CABasicAnimation(keyPath: "sublayerTransform")
            animation.fromValue = NSValue(caTransform3D: fromTransform)
            animation.toValue = NSValue(caTransform3D: targetTransform)
            animation.duration = duration
            animation.timingFunction = curve.mediaTimingFunction()
            keyboardWindow.layer.add(animation, forKey: "sublayerTransform")
            completion?(true)
        }
    }

    static func removeKeyboardAnimations() {
        guard let keyboardWindow = keyboardWindow() else {
            return
        }
        removeAnimationsRecursively(from: keyboardWindow)
    }

    static func isKeyboardVisible() -> Bool {
        guard let keyboardView = keyboardView() else {
            return false
        }
        return keyboardView.window != nil
            && !keyboardView.isHidden
            && keyboardView.alpha > 0.0
            && keyboardView.bounds.height > 0.0
    }

    private static func bridgedKeyboardWindow() -> UIWindow? {
        AetherLegacyKeyboardWindow()
    }

    private static func internalApplicationWindows() -> [UIWindow] {
        let application = UIApplication.shared
        let selector = NSSelectorFromString(ObfuscatedSymbols.allWindows)
        guard application.responds(to: selector),
              let value = application.perform(selector)?.takeUnretainedValue() else {
            return []
        }
        if let windows = value as? [UIWindow] {
            return windows
        }
        if let windows = value as? NSSet {
            return windows.compactMap { $0 as? UIWindow }
        }
        return []
    }

    private static func deduplicatedWindows(_ windows: [UIWindow]) -> [UIWindow] {
        var identifiers = Set<ObjectIdentifier>()
        return windows.filter { identifiers.insert(ObjectIdentifier($0)).inserted }
    }

    private static func isKeyboardWindow(_ window: UIWindow) -> Bool {
        let typeName = NSStringFromClass(type(of: window))
        if #available(iOS 9.0, *) {
            return typeName.hasPrefix(ObfuscatedSymbols.uiPrefix) && typeName.hasSuffix(ObfuscatedSymbols.remoteKeyboardWindowSuffix)
        } else {
            return typeName.hasPrefix(ObfuscatedSymbols.uiPrefix) && typeName.hasSuffix(ObfuscatedSymbols.textEffectsWindowSuffix)
        }
    }

    private static func isKeyboardView(_ view: UIView) -> Bool {
        let typeName = NSStringFromClass(type(of: view))
        guard typeName.hasPrefix(ObfuscatedSymbols.uiPrefix) || typeName.hasPrefix(ObfuscatedSymbols.uiUnderscorePrefix) else {
            return false
        }
        return typeName.hasSuffix(ObfuscatedSymbols.inputSetHostViewSuffix)
            || typeName.hasSuffix(ObfuscatedSymbols.keyboardItemContainerViewSuffix)
    }

    private static func isKeyboardViewContainer(_ view: UIView) -> Bool {
        let typeName = NSStringFromClass(type(of: view))
        return typeName.hasPrefix(ObfuscatedSymbols.uiPrefix) && typeName.hasSuffix(ObfuscatedSymbols.inputSetContainerViewSuffix)
    }

    private static func findKeyboardView(in view: UIView) -> UIView? {
        if isKeyboardView(view) {
            return view
        }
        for subview in view.subviews {
            if let result = findKeyboardView(in: subview) {
                return result
            }
        }
        return nil
    }

    private static func removeAnimationsRecursively(from view: UIView) {
        view.layer.removeAllAnimations()
        for subview in view.subviews {
            removeAnimationsRecursively(from: subview)
        }
    }
}
#else
internal enum AetherLegacyKeyboardRuntime {
    static func keyboardWindowTransform(
        from currentTransform: CATransform3D,
        horizontalOffset: CGFloat? = nil,
        verticalOffset: CGFloat? = nil
    ) -> CATransform3D {
        var targetTransform = currentTransform
        if let horizontalOffset {
            targetTransform.m41 = horizontalOffset
        }
        if let verticalOffset {
            targetTransform.m42 = verticalOffset
        }
        return targetTransform
    }

    static func updateInteractiveKeyboardOffset(
        _ offset: CGFloat,
        transition: ContainedViewLayoutTransition,
        completion: (() -> Void)? = nil
    ) {
        _ = offset
        _ = transition
        completion?()
    }

    static func keyboardSurfaceTransition(
        targetOffset: CGFloat,
        previousBoundsMinY: CGFloat,
        transition: ContainedViewLayoutTransition
    ) -> ContainedViewLayoutTransition {
        guard targetOffset.isZero, previousBoundsMinY < 0.0 else {
            return transition
        }
        guard case let .animated(duration, curve) = transition else {
            return transition
        }
        switch curve {
        case .spring, .customSpring:
            return .animated(duration: duration, curve: .easeInOut)
        default:
            return transition
        }
    }

    static func updateKeyboardLeftEdge(
        _ leftEdge: CGFloat,
        transition: ContainedViewLayoutTransition,
        completion: ((Bool) -> Void)? = nil
    ) {
        _ = leftEdge
        _ = transition
        completion?(false)
    }

    static func removeKeyboardAnimations() {}
    static func isKeyboardVisible() -> Bool { false }
}
#endif
