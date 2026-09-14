import Foundation
import CoreGraphics

/// Shared motion values used by AetherUI's glass and navigation surfaces.
///
/// The profiles intentionally describe *semantic* transitions instead of
/// individual animation APIs. A source morph may be rendered by a
/// `UIViewPropertyAnimator`, a display-link geometry driver, or a private
/// liquid-lens implementation while still sharing the same response.
public enum AetherMotion {
    public struct Spring: Equatable {
        public var duration: TimeInterval
        public var dampingRatio: CGFloat
        public var initialVelocity: CGFloat

        public init(
            duration: TimeInterval,
            dampingRatio: CGFloat,
            initialVelocity: CGFloat = 0.0
        ) {
            self.duration = duration
            self.dampingRatio = dampingRatio
            self.initialVelocity = initialVelocity
        }
    }

    public struct SourceMorph: Equatable {
        public var presentation: Spring
        public var dismissal: Spring
        public var sourceFadeDuration: TimeInterval
        public var contentBlurRadius: CGFloat
        public var contentRevealStart: CGFloat
        public var contentRevealEnd: CGFloat

        public init(
            presentation: Spring,
            dismissal: Spring,
            sourceFadeDuration: TimeInterval,
            contentBlurRadius: CGFloat,
            contentRevealStart: CGFloat,
            contentRevealEnd: CGFloat
        ) {
            self.presentation = presentation
            self.dismissal = dismissal
            self.sourceFadeDuration = sourceFadeDuration
            self.contentBlurRadius = contentBlurRadius
            self.contentRevealStart = contentRevealStart
            self.contentRevealEnd = contentRevealEnd
        }
    }

    public struct Press: Equatable {
        public var press: Spring
        public var release: Spring
        /// Increase applied to the shorter surface dimension, in points.
        public var pressedSizeIncrease: CGFloat
        public var maximumTranslation: CGFloat
        public var movementHysteresis: CGFloat
        public var cancellationInset: CGFloat
        public var highlightAlpha: Float
        public var highlightDiameter: CGFloat
        public var highlightInDuration: TimeInterval
        public var highlightOutDuration: TimeInterval

        public init(
            press: Spring,
            release: Spring,
            pressedSizeIncrease: CGFloat,
            maximumTranslation: CGFloat,
            movementHysteresis: CGFloat = 5.0,
            cancellationInset: CGFloat = 16.0,
            highlightAlpha: Float = 0.10,
            highlightDiameter: CGFloat = 300.0,
            highlightInDuration: TimeInterval = 0.14,
            highlightOutDuration: TimeInterval = 0.30
        ) {
            self.press = press
            self.release = release
            self.pressedSizeIncrease = pressedSizeIncrease
            self.maximumTranslation = maximumTranslation
            self.movementHysteresis = movementHysteresis
            self.cancellationInset = cancellationInset
            self.highlightAlpha = highlightAlpha
            self.highlightDiameter = highlightDiameter
            self.highlightInDuration = highlightInDuration
            self.highlightOutDuration = highlightOutDuration
        }
    }

    public struct Chrome: Equatable {
        public var geometry: Spring
        public var contentAppearanceDuration: TimeInterval
        public var contentDisappearanceDuration: TimeInterval
        public var contentBlurRadius: CGFloat
        public var contentScale: CGFloat
        public var replacementContentScale: CGFloat
        public var replacementContentDelay: TimeInterval
        public var appearancePulseAmplitude: CGFloat
        public var replacementPulseAmplitude: CGFloat
        public var disappearancePulseAmplitude: CGFloat
        public var separatedGeometryDuration: TimeInterval
        /// Independent pulse layered over a real bounds change. Keeping this
        /// separate from the glyph handoff prevents content replacement from
        /// swallowing the characteristic liquid-glass size response.
        public var sizeMorphPulseDuration: TimeInterval
        public var sizeMorphPrimaryAmplitude: CGFloat
        public var sizeMorphCrossAmplitude: CGFloat
        public var sizeMorphCounterAmplitude: CGFloat

        public init(
            geometry: Spring,
            contentAppearanceDuration: TimeInterval,
            contentDisappearanceDuration: TimeInterval,
            contentBlurRadius: CGFloat,
            contentScale: CGFloat,
            replacementContentScale: CGFloat,
            replacementContentDelay: TimeInterval,
            appearancePulseAmplitude: CGFloat,
            replacementPulseAmplitude: CGFloat,
            disappearancePulseAmplitude: CGFloat,
            separatedGeometryDuration: TimeInterval,
            sizeMorphPulseDuration: TimeInterval = 0.24,
            sizeMorphPrimaryAmplitude: CGFloat = 0.075,
            sizeMorphCrossAmplitude: CGFloat = 0.025,
            sizeMorphCounterAmplitude: CGFloat = 0.008
        ) {
            self.geometry = geometry
            self.contentAppearanceDuration = contentAppearanceDuration
            self.contentDisappearanceDuration = contentDisappearanceDuration
            self.contentBlurRadius = contentBlurRadius
            self.contentScale = contentScale
            self.replacementContentScale = replacementContentScale
            self.replacementContentDelay = replacementContentDelay
            self.appearancePulseAmplitude = appearancePulseAmplitude
            self.replacementPulseAmplitude = replacementPulseAmplitude
            self.disappearancePulseAmplitude = disappearancePulseAmplitude
            self.separatedGeometryDuration = separatedGeometryDuration
            self.sizeMorphPulseDuration = sizeMorphPulseDuration
            self.sizeMorphPrimaryAmplitude = sizeMorphPrimaryAmplitude
            self.sizeMorphCrossAmplitude = sizeMorphCrossAmplitude
            self.sizeMorphCounterAmplitude = sizeMorphCounterAmplitude
        }
    }

    internal struct NavigationChromeMaterializationSample: Equatable {
        let opacity: CGFloat
        let blurRadius: CGFloat
    }

    /// Dense, endpoint-exact content materialization. Appearance and
    /// disappearance deliberately use the same samples in reverse so a push
    /// and a pop cannot acquire subtly different easing as UIKit interrupts
    /// or resumes their animations.
    internal static func navigationChromeMaterializationSamples(
        appearing: Bool,
        sampleCount: Int = 41
    ) -> [NavigationChromeMaterializationSample] {
        let count = max(2, sampleCount)
        let maximumBlur = navigationChrome.contentBlurRadius * 1.35
        let appearingSamples = (0 ..< count).map { index in
            let t = CGFloat(index) / CGFloat(count - 1)
            let opacityTime = max(0.0, min(1.0, (t - 0.055) / 0.945))
            let blurTime = max(0.0, min(1.0, t / 0.92))
            let opacityProgress = smootherStep(opacityTime)
            let blurProgress = smootherStep(blurTime)
            return NavigationChromeMaterializationSample(
                opacity: opacityProgress,
                blurRadius: maximumBlur * (1.0 - blurProgress)
            )
        }
        return appearing ? appearingSamples : Array(appearingSamples.reversed())
    }

    private static func smootherStep(_ value: CGFloat) -> CGFloat {
        let value = max(0.0, min(1.0, value))
        return value * value * value * (value * (value * 6.0 - 15.0) + 10.0)
    }

    /// Full-screen stack transition. The duration includes the quiet settle
    /// after the card reaches most of its travel; keeping that tail visible is
    /// what prevents the transition from reading as a quick slide.
    public static let navigation = Spring(
        duration: 0.34,
        dampingRatio: 0.88
    )

    /// Navbar glass geometry and glyph handoff now use the full navigation
    /// clock. The material pulse keeps a short independent settle tail so the
    /// glass still reads after the blur/fade reaches its exact endpoint.
    public static let navigationChrome = Chrome(
        geometry: Spring(duration: 0.34, dampingRatio: 0.92),
        contentAppearanceDuration: 0.34,
        contentDisappearanceDuration: 0.34,
        contentBlurRadius: 12.0,
        contentScale: 1.0,
        replacementContentScale: 1.0,
        replacementContentDelay: 0.0,
        appearancePulseAmplitude: 0.08,
        replacementPulseAmplitude: 0.08,
        disappearancePulseAmplitude: -0.08,
        separatedGeometryDuration: 0.34,
        sizeMorphPulseDuration: 0.40,
        sizeMorphPrimaryAmplitude: 0.23,
        sizeMorphCrossAmplitude: 0.23,
        sizeMorphCounterAmplitude: 0.032
    )

    /// Movement of the liquid selection lens between tab items.
    public static let tabBarSelection = Spring(
        duration: 0.54,
        dampingRatio: 0.88
    )

    /// Large tab-bar geometry changes such as pill ↔ minimized circle.
    ///
    /// The slightly under-damped response gives the chrome a small
    /// over/under-scale settle without applying a separate transform to the
    /// glass. That keeps the pill, search item, and an optional bottom
    /// accessory on one interruptible geometry spring.
    public static let tabBarMorph = Spring(
        duration: 0.58,
        dampingRatio: 0.77,
        initialVelocity: 0.12
    )

    /// Intrinsic height/size changes requested by a bottom-bar accessory.
    /// This is intentionally quicker and a touch more damped than the full
    /// tab-bar mode morph because the surrounding chrome is not changing
    /// modes, only adapting to the accessory's new content size.
    public static let bottomBarAccessoryResize = Spring(
        duration: 0.38,
        dampingRatio: 0.80,
        initialVelocity: 0.10
    )

    /// Drag-release settling for compact floating surfaces such as video PiP.
    public static let floatingOverlaySettle = Spring(
        duration: 0.42,
        dampingRatio: 0.86
    )

    /// Button/capsule to menu morph. The ease-out geometry reaches its main
    /// target around 300 ms and uses the remaining time for a subtle settle.
    public static let contextMenu = SourceMorph(
        presentation: Spring(duration: 0.66, dampingRatio: 0.86),
        dismissal: Spring(duration: 0.34, dampingRatio: 0.90),
        sourceFadeDuration: 0.14,
        contentBlurRadius: 14.0,
        contentRevealStart: 0.12,
        contentRevealEnd: 0.72
    )

    /// Bottom-corner source to full modal sheet matched-geometry transition.
    public static let sourceModal = SourceMorph(
        presentation: Spring(duration: 0.72, dampingRatio: 0.88, initialVelocity: 0.18),
        dismissal: Spring(duration: 0.52, dampingRatio: 0.90, initialVelocity: 0.12),
        sourceFadeDuration: 0.14,
        contentBlurRadius: 12.0,
        contentRevealStart: 0.10,
        contentRevealEnd: 0.70
    )

    public static let search = SourceMorph(
        presentation: Spring(duration: 0.86, dampingRatio: 0.86, initialVelocity: 0.16),
        dismissal: Spring(duration: 0.60, dampingRatio: 0.90, initialVelocity: 0.10),
        sourceFadeDuration: 0.14,
        contentBlurRadius: 10.0,
        contentRevealStart: 0.14,
        contentRevealEnd: 0.72
    )

    /// Native navbar controls expand by roughly 10–15% in the reference.
    public static let navigationButtonPress = Press(
        press: Spring(duration: 0.38, dampingRatio: 0.84),
        release: Spring(duration: 0.52, dampingRatio: 0.88),
        pressedSizeIncrease: 6.0,
        maximumTranslation: 18.0
    )

    public static let tabBarPress = Press(
        press: Spring(duration: 0.42, dampingRatio: 0.86),
        release: Spring(duration: 0.56, dampingRatio: 0.90),
        pressedSizeIncrease: 8.0,
        maximumTranslation: 16.0,
        highlightAlpha: 0.08,
        highlightDiameter: 340.0
    )

    /// Compact player feedback deliberately stays much tighter than the
    /// system interactive-glass deformation. A very wide 48–56pt capsule can
    /// otherwise be pulled tens of points away from its dock by a plain tap.
    /// This profile keeps the surface alive without allowing that gesture to
    /// become a second geometry transition.
    public static let bottomBarAccessoryPress = Press(
        press: Spring(duration: 0.16, dampingRatio: 0.98),
        release: Spring(duration: 0.28, dampingRatio: 0.97),
        pressedSizeIncrease: 1.0,
        maximumTranslation: 2.0,
        movementHysteresis: 6.0,
        cancellationInset: 14.0,
        highlightAlpha: 0.035,
        highlightDiameter: 240.0,
        highlightInDuration: 0.08,
        highlightOutDuration: 0.16
    )

    public static let standaloneButtonPress = Press(
        press: Spring(duration: 0.38, dampingRatio: 0.84),
        release: Spring(duration: 0.52, dampingRatio: 0.88),
        pressedSizeIncrease: 6.0,
        maximumTranslation: 18.0
    )
}
