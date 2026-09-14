import UIKit

/// Semantic purpose of a chrome surface. Components describe what they are;
/// the active appearance decides how that role is rendered.
public enum AetherSurfaceRole: Sendable, Hashable {
    case attachedBar
    case floatingSurface
    case toolbar
    case button
    case card
    case input
    case popup
    case badge
    case selectionIndicator
    case overlay
}

internal struct AetherLegacySurfaceTokens {
    let surfaceColor: UIColor
    let secondarySurfaceColor: UIColor
    let floatingSurfaceColor: UIColor
    let separatorColor: UIColor
    let borderColor: UIColor
    let borderWidth: CGFloat
    let shadowColor: UIColor
    let shadowOpacity: Float
    let shadowRadius: CGFloat
    let shadowOffset: CGSize
    let cornerRadius: CGFloat
    let cornerCurve: CALayerCornerCurve
    let contentTint: UIColor
    let selectedTint: UIColor
    let disabledAlpha: CGFloat
    let pressedAlpha: CGFloat
    let pressedScale: CGFloat
    let highlightFill: UIColor
    let dimmingColor: UIColor
    let backgroundOpacity: CGFloat
    let blurStyle: UIBlurEffect.Style?
    let animationDuration: TimeInterval
    let animationCurve: UIView.AnimationCurve

    static func resolve(
        role: AetherSurfaceRole,
        traitCollection: UITraitCollection
    ) -> AetherLegacySurfaceTokens {
        let highContrast = traitCollection.accessibilityContrast == .high
        let reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        let reduceMotion = UIAccessibility.isReduceMotionEnabled

        let surfaceColor: UIColor
        let cornerRadius: CGFloat
        let shadowOpacity: Float
        let shadowRadius: CGFloat
        let shadowOffset: CGSize
        let borderWidth: CGFloat

        switch role {
        case .attachedBar:
            surfaceColor = .systemBackground
            cornerRadius = 0
            shadowOpacity = 0
            shadowRadius = 0
            shadowOffset = .zero
            // Attached bars draw one content-side separator themselves.
            // A perimeter border here would stack with that hairline at the
            // top of a tab bar (or bottom of a navigation bar), making it
            // look twice as heavy.
            borderWidth = 0
        case .input:
            surfaceColor = .tertiarySystemFill
            cornerRadius = 10
            shadowOpacity = 0
            shadowRadius = 0
            shadowOffset = .zero
            borderWidth = highContrast ? 1 : 0
        case .button, .selectionIndicator, .badge:
            surfaceColor = .secondarySystemFill
            cornerRadius = 10
            shadowOpacity = 0
            shadowRadius = 0
            shadowOffset = .zero
            borderWidth = highContrast ? 1 : 0
        case .floatingSurface, .toolbar, .card, .popup:
            surfaceColor = .secondarySystemBackground
            cornerRadius = role == .popup ? 14 : 12
            shadowOpacity = highContrast ? 0.24 : 0.16
            shadowRadius = 12
            shadowOffset = CGSize(width: 0, height: 4)
            borderWidth = 1.0 / max(traitCollection.displayScale, 1.0)
        case .overlay:
            surfaceColor = .secondarySystemBackground
            cornerRadius = 12
            shadowOpacity = 0
            shadowRadius = 0
            shadowOffset = .zero
            borderWidth = 0
        }

        return AetherLegacySurfaceTokens(
            surfaceColor: surfaceColor,
            secondarySurfaceColor: .secondarySystemBackground,
            floatingSurfaceColor: .secondarySystemBackground,
            separatorColor: .separator,
            borderColor: highContrast ? .label : .separator,
            borderWidth: borderWidth,
            shadowColor: .black,
            shadowOpacity: shadowOpacity,
            shadowRadius: shadowRadius,
            shadowOffset: shadowOffset,
            cornerRadius: cornerRadius,
            cornerCurve: .continuous,
            contentTint: .label,
            selectedTint: .systemBlue,
            disabledAlpha: highContrast ? 0.55 : 0.45,
            pressedAlpha: highContrast ? 0.78 : 0.68,
            pressedScale: reduceMotion ? 1 : 0.97,
            highlightFill: .quaternarySystemFill,
            dimmingColor: UIColor.black.withAlphaComponent(highContrast ? 0.42 : 0.32),
            backgroundOpacity: reduceTransparency ? 1 : 0.96,
            // Legacy uses UIKit's classic chrome material, never UIGlassEffect
            // or Aether's Liquid Glass backdrop/filter pipeline.
            blurStyle: .systemChromeMaterial,
            animationDuration: reduceMotion ? 0 : 0.2,
            animationCurve: .easeInOut
        )
    }
}

internal enum AetherSurfaceRendererKind: Equatable {
    case legacy
    case liquidGlass(AetherLiquidGlassGeneration)
}

internal struct AetherSurfaceRenderConfiguration {
    let kind: AetherSurfaceRendererKind
    let role: AetherSurfaceRole
    let legacyTokens: AetherLegacySurfaceTokens
    let glassEffectStyle: SystemGlassEffectStyle

    static func resolve(
        appearance: AetherAppearance,
        role: AetherSurfaceRole,
        traitCollection: UITraitCollection
    ) -> AetherSurfaceRenderConfiguration {
        let kind = appearance.style.liquidGlassGeneration
            .map(AetherSurfaceRendererKind.liquidGlass)
            ?? .legacy
        return AetherSurfaceRenderConfiguration(
            kind: kind,
            role: role,
            legacyTokens: .resolve(role: role, traitCollection: traitCollection),
            glassEffectStyle: appearance.edgeEffectStyle
        )
    }
}

/// Implemented by reusable renderer hosts that must replace their material
/// in-place when the global appearance changes.
internal protocol AetherAppearanceConsumer: AnyObject {
    func aetherApplyAppearance(_ appearance: AetherAppearance, animated: Bool)
}

private final class AetherWeakAppearanceConsumer {
    weak var value: AetherAppearanceConsumer?

    init(_ value: AetherAppearanceConsumer) {
        self.value = value
    }
}

internal enum AetherAppearanceConsumerRegistry {
    private static var consumers: [AetherWeakAppearanceConsumer] = []
    private static let accessibilityObservers: [NSObjectProtocol] = {
        let names: [Notification.Name] = [
            UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            UIAccessibility.darkerSystemColorsStatusDidChangeNotification
        ]
        return names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                AetherAppearanceConsumerRegistry.apply(.runtimeCurrent, animated: false)
            }
        }
    }()

    static func register(_ consumer: AetherAppearanceConsumer) {
        precondition(Thread.isMainThread, "Aether appearance consumers are UIKit objects and must register on the main thread")
        _ = accessibilityObservers
        compact()
        guard !consumers.contains(where: { $0.value === consumer }) else {
            return
        }
        consumers.append(AetherWeakAppearanceConsumer(consumer))
    }

    static func apply(_ appearance: AetherAppearance, animated: Bool) {
        precondition(Thread.isMainThread, "Aether appearance changes must run on the main thread")
        let liveConsumers = consumers.compactMap(\.value)
        consumers = liveConsumers.map(AetherWeakAppearanceConsumer.init)
        for consumer in liveConsumers {
            consumer.aetherApplyAppearance(appearance, animated: animated)
        }
    }

    internal static var liveConsumerCount: Int {
        compact()
        return consumers.count
    }

    private static func compact() {
        consumers.removeAll(where: { $0.value == nil })
    }
}

/// Non-cancelling touch tracker used for ordinary Legacy pressed feedback.
/// It deliberately has no glass deformation, highlight layer or display link.
internal final class AetherClassicPressGestureRecognizer: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
