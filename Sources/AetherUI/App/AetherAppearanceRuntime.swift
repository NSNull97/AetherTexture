import UIKit

private enum AetherAppearanceRuntimeCurrentStorage {
    static let key = "AetherUI.AetherAppearance.runtimeCurrent"
}

// MARK: - App Appearance

public enum AetherAppearanceStyle: Sendable, Hashable, CaseIterable, Codable {
    case legacy
    case liquidGlassV1
    case liquidGlassV2

    public var displayName: String {
        switch self {
        case .legacy:
            return "Legacy"
        case .liquidGlassV1:
            return "Liquid Glass v1"
        case .liquidGlassV2:
            return "Liquid Glass v2"
        }
    }

    public var stableIdentifier: String {
        switch self {
        case .legacy:
            return "legacy"
        case .liquidGlassV1:
            return "liquid-glass-v1"
        case .liquidGlassV2:
            return "liquid-glass-v2"
        }
    }

    public var usesLiquidGlass: Bool {
        liquidGlassGeneration != nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        switch normalized {
        case "legacy":
            self = .legacy
        case "liquid-glass-v1", "liquidglassv1", "ios26", "ios-26":
            self = .liquidGlassV1
        case "liquid-glass-v2", "liquidglassv2", "ios27", "ios-27":
            self = .liquidGlassV2
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown Aether appearance style: \(value)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stableIdentifier)
    }
}

internal enum AetherLiquidGlassGeneration: Sendable, Hashable {
    case v1
    case v2
}

internal extension AetherAppearanceStyle {
    var liquidGlassGeneration: AetherLiquidGlassGeneration? {
        switch self {
        case .legacy:
            return nil
        case .liquidGlassV1:
            return .v1
        case .liquidGlassV2:
            return .v2
        }
    }
}

public extension AetherAppearanceStyle {
    @available(*, deprecated, renamed: "liquidGlassV1")
    static var iOS26: Self { .liquidGlassV1 }

    @available(*, deprecated, renamed: "liquidGlassV2")
    static var iOS27: Self { .liquidGlassV2 }
}

public struct AetherAppearance {
    public var style: AetherAppearanceStyle
    public var overallDarkAppearance: Bool
    public var emptyAreaColor: UIColor
    /// Base tint used by the floating tab-bar chrome. The system background
    /// preserves the historical appearance while keeping the color in the
    /// appearance pipeline instead of hard-coding it in `TabBarView`.
    public var tabBarBackgroundColor: UIColor
    public var edgeEffectColor: UIColor
    public var edgeEffectAlpha: CGFloat
    public var edgeEffectBlurRadiusAtEdge: CGFloat
    public var edgeEffectBlurRadiusAtFade: CGFloat
    public var edgeEffectStyle: SystemGlassEffectStyle
    public var separatorColor: UIColor

    public init(
        style: AetherAppearanceStyle,
        overallDarkAppearance: Bool,
        emptyAreaColor: UIColor,
        tabBarBackgroundColor: UIColor = .systemBackground,
        edgeEffectColor: UIColor,
        edgeEffectAlpha: CGFloat,
        edgeEffectBlurRadiusAtEdge: CGFloat,
        edgeEffectBlurRadiusAtFade: CGFloat,
        edgeEffectStyle: SystemGlassEffectStyle,
        separatorColor: UIColor
    ) {
        self.style = style
        self.overallDarkAppearance = overallDarkAppearance
        self.emptyAreaColor = emptyAreaColor
        self.tabBarBackgroundColor = tabBarBackgroundColor
        self.edgeEffectColor = edgeEffectColor
        self.edgeEffectAlpha = edgeEffectAlpha
        self.edgeEffectBlurRadiusAtEdge = edgeEffectBlurRadiusAtEdge
        self.edgeEffectBlurRadiusAtFade = edgeEffectBlurRadiusAtFade
        self.edgeEffectStyle = edgeEffectStyle
        self.separatorColor = separatorColor
    }

    public init(style: AetherAppearanceStyle) {
        switch style {
        case .legacy:
            self.init(
                style: .legacy,
                overallDarkAppearance: false,
                emptyAreaColor: .systemBackground,
                edgeEffectColor: .clear,
                edgeEffectAlpha: 0.0,
                edgeEffectBlurRadiusAtEdge: 0.0,
                edgeEffectBlurRadiusAtFade: 0.0,
                edgeEffectStyle: .regular,
                separatorColor: .separator
            )
        case .liquidGlassV1:
            self.init(
                style: .liquidGlassV1,
                overallDarkAppearance: false,
                emptyAreaColor: .systemBackground,
                edgeEffectColor: .systemBackground,
                edgeEffectAlpha: 0.82,
                edgeEffectBlurRadiusAtEdge: 2.0,
                edgeEffectBlurRadiusAtFade: 0.0,
                edgeEffectStyle: .regular,
                separatorColor: .separator
            )
        case .liquidGlassV2:
            self.init(
                style: .liquidGlassV2,
                overallDarkAppearance: false,
                emptyAreaColor: .systemBackground,
                edgeEffectColor: .systemBackground,
                edgeEffectAlpha: 0.82,
                edgeEffectBlurRadiusAtEdge: 5.0,
                edgeEffectBlurRadiusAtFade: 5.0,
                edgeEffectStyle: .strong,
                separatorColor: .separator
            )
        }
    }

    public static let legacy = AetherAppearance(style: .legacy)
    public static let liquidGlassV1 = AetherAppearance(style: .liquidGlassV1)
    public static let liquidGlassV2 = AetherAppearance(style: .liquidGlassV2)

    @available(*, deprecated, renamed: "liquidGlassV1")
    public static var iOS26: AetherAppearance { .liquidGlassV1 }

    @available(*, deprecated, renamed: "liquidGlassV2")
    public static var iOS27: AetherAppearance { .liquidGlassV2 }

    public static func preset(_ style: AetherAppearanceStyle) -> AetherAppearance {
        AetherAppearance(style: style)
    }

    public var signature: AetherAppearanceSignature {
        AetherAppearanceSignature(appearance: self)
    }
}

public struct AetherAppearanceSignature: Equatable, Sendable {
    public var style: AetherAppearanceStyle
    public var overallDarkAppearance: Bool
    public var emptyAreaColor: String
    public var tabBarBackgroundColor: String
    public var edgeEffectColor: String
    public var edgeEffectAlpha: CGFloat
    public var edgeEffectBlurRadiusAtEdge: CGFloat
    public var edgeEffectBlurRadiusAtFade: CGFloat
    public var edgeEffectStyle: SystemGlassEffectStyle
    public var separatorColor: String

    public init(appearance: AetherAppearance, traitCollection: UITraitCollection = UITraitCollection(userInterfaceStyle: .unspecified)) {
        self.style = appearance.style
        self.overallDarkAppearance = appearance.overallDarkAppearance
        self.emptyAreaColor = Self.colorSignature(appearance.emptyAreaColor, traitCollection: traitCollection)
        self.tabBarBackgroundColor = Self.colorSignature(
            appearance.tabBarBackgroundColor,
            traitCollection: traitCollection
        )
        self.edgeEffectColor = Self.colorSignature(appearance.edgeEffectColor, traitCollection: traitCollection)
        self.edgeEffectAlpha = appearance.edgeEffectAlpha
        self.edgeEffectBlurRadiusAtEdge = appearance.edgeEffectBlurRadiusAtEdge
        self.edgeEffectBlurRadiusAtFade = appearance.edgeEffectBlurRadiusAtFade
        self.edgeEffectStyle = appearance.edgeEffectStyle
        self.separatorColor = Self.colorSignature(appearance.separatorColor, traitCollection: traitCollection)
    }

    private static func colorSignature(_ color: UIColor, traitCollection: UITraitCollection) -> String {
        let resolved = color.resolvedColor(with: traitCollection)
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        if resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return "\(red):\(green):\(blue):\(alpha)"
        }
        return resolved.description
    }
}

// MARK: - Resolved Surface Primitives

public enum AetherAppearanceSurface: Equatable, Sendable {
    case navigation
    case tab
    case search
    case bottomSearch
    case inputBar
}

public enum AetherBarPlacement: Equatable, Sendable {
    case top
    case bottom
    case navigation
    case tab
    case standaloneBottom
    case inputAccessory
}

public enum AetherBarBackgroundAppearance {
    case none
    case transparent
    case glass(SystemGlassEffectStyle)
    case color(UIColor)
}

public enum AetherGlassStrokeAppearance {
    case none
    case hairline(color: UIColor?, opacity: CGFloat)
}

public enum AetherSeparatorAppearance {
    case hidden
    case visible(color: UIColor?, opacity: CGFloat)
    case scrollActivated(threshold: CGFloat, hysteresis: CGFloat, color: UIColor?)
}

public struct AetherEdgeEffectAppearance {
    public var isEnabled: Bool
    public var tintColor: UIColor?
    public var alpha: CGFloat
    public var blurRadiusAtEdge: CGFloat
    public var blurRadiusAtFade: CGFloat
    public var solidBlur: Bool
    public var style: SystemGlassEffectStyle
    public var edgeSize: CGFloat

    public init(
        isEnabled: Bool = true,
        tintColor: UIColor?,
        alpha: CGFloat,
        blurRadiusAtEdge: CGFloat,
        blurRadiusAtFade: CGFloat,
        solidBlur: Bool = false,
        style: SystemGlassEffectStyle,
        edgeSize: CGFloat = 48.0
    ) {
        self.isEnabled = isEnabled
        self.tintColor = tintColor
        self.alpha = alpha
        self.blurRadiusAtEdge = blurRadiusAtEdge
        self.blurRadiusAtFade = blurRadiusAtFade
        self.solidBlur = solidBlur
        self.style = style
        self.edgeSize = edgeSize
    }

    public init(appearance: AetherAppearance, edgeSize: CGFloat = 48.0) {
        self.init(
            isEnabled: appearance.style.usesLiquidGlass,
            tintColor: appearance.edgeEffectColor,
            alpha: appearance.edgeEffectAlpha,
            blurRadiusAtEdge: appearance.edgeEffectBlurRadiusAtEdge,
            blurRadiusAtFade: appearance.edgeEffectBlurRadiusAtFade,
            solidBlur: appearance.style == .liquidGlassV2,
            style: appearance.edgeEffectStyle,
            edgeSize: edgeSize
        )
    }

    public static func transparent(
        style: SystemGlassEffectStyle,
        edgeSize: CGFloat = 48.0,
        isEnabled: Bool = true
    ) -> AetherEdgeEffectAppearance {
        AetherEdgeEffectAppearance(
            isEnabled: isEnabled,
            tintColor: .clear,
            alpha: 0.0,
            blurRadiusAtEdge: 0.0,
            blurRadiusAtFade: 0.0,
            solidBlur: true,
            style: style,
            edgeSize: edgeSize
        )
    }
}

public extension AetherAppearance {
    func edgeEffectAppearance(
        for surface: AetherAppearanceSurface,
        edgeSize: CGFloat = 48.0
    ) -> AetherEdgeEffectAppearance {
        guard style.usesLiquidGlass else {
            return .transparent(
                style: edgeEffectStyle,
                edgeSize: edgeSize,
                isEnabled: false
            )
        }
        if style == .liquidGlassV2 {
            switch surface {
            case .tab, .search, .bottomSearch, .inputBar:
                return .transparent(style: edgeEffectStyle, edgeSize: edgeSize)
            case .navigation:
                break
            }
        }
        return AetherEdgeEffectAppearance(appearance: self, edgeSize: edgeSize)
    }
}

public struct AetherNavigationBarResolvedAppearance {
    public var appearanceStyle: AetherAppearanceStyle
    public var background: AetherBarBackgroundAppearance
    public var stroke: AetherGlassStrokeAppearance
    public var separator: AetherSeparatorAppearance
    public var edgeEffect: AetherEdgeEffectAppearance
    public var overallDarkAppearance: Bool
    public var emptyAreaColor: UIColor
    public var buttonColor: UIColor
    public var primaryTextColor: UIColor

    public init(
        appearanceStyle: AetherAppearanceStyle = .liquidGlassV1,
        background: AetherBarBackgroundAppearance,
        stroke: AetherGlassStrokeAppearance,
        separator: AetherSeparatorAppearance,
        edgeEffect: AetherEdgeEffectAppearance,
        overallDarkAppearance: Bool,
        emptyAreaColor: UIColor,
        buttonColor: UIColor,
        primaryTextColor: UIColor
    ) {
        self.appearanceStyle = appearanceStyle
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
        self.overallDarkAppearance = overallDarkAppearance
        self.emptyAreaColor = emptyAreaColor
        self.buttonColor = buttonColor
        self.primaryTextColor = primaryTextColor
    }
}

public struct AetherTabBarResolvedAppearance {
    public var appearanceStyle: AetherAppearanceStyle
    public var background: AetherBarBackgroundAppearance
    public var stroke: AetherGlassStrokeAppearance
    public var separator: AetherSeparatorAppearance
    public var edgeEffect: AetherEdgeEffectAppearance
    public var overallDarkAppearance: Bool
    /// Distinguishes a local, per-screen light override from the default
    /// `false`, which means "follow the current trait collection".
    public var hasExplicitDarkAppearanceOverride: Bool
    public var iconColor: UIColor
    public var selectedIconColor: UIColor
    public var textColor: UIColor
    public var selectedTextColor: UIColor
    public var backgroundColor: UIColor

    public init(
        appearanceStyle: AetherAppearanceStyle = .liquidGlassV1,
        background: AetherBarBackgroundAppearance,
        stroke: AetherGlassStrokeAppearance,
        separator: AetherSeparatorAppearance,
        edgeEffect: AetherEdgeEffectAppearance,
        overallDarkAppearance: Bool,
        hasExplicitDarkAppearanceOverride: Bool = false,
        iconColor: UIColor,
        selectedIconColor: UIColor,
        textColor: UIColor,
        selectedTextColor: UIColor,
        backgroundColor: UIColor = .systemBackground
    ) {
        self.appearanceStyle = appearanceStyle
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
        self.overallDarkAppearance = overallDarkAppearance
        self.hasExplicitDarkAppearanceOverride = hasExplicitDarkAppearanceOverride
        self.iconColor = iconColor
        self.selectedIconColor = selectedIconColor
        self.textColor = textColor
        self.selectedTextColor = selectedTextColor
        self.backgroundColor = backgroundColor
    }
}

public struct AetherSearchResolvedAppearance {
    public var appearanceStyle: AetherAppearanceStyle
    public var background: AetherBarBackgroundAppearance
    public var stroke: AetherGlassStrokeAppearance
    public var separator: AetherSeparatorAppearance
    public var edgeEffect: AetherEdgeEffectAppearance
    public var overallDarkAppearance: Bool
    public var textColor: UIColor
    public var placeholderColor: UIColor

    public init(
        appearanceStyle: AetherAppearanceStyle = .liquidGlassV1,
        background: AetherBarBackgroundAppearance,
        stroke: AetherGlassStrokeAppearance,
        separator: AetherSeparatorAppearance,
        edgeEffect: AetherEdgeEffectAppearance,
        overallDarkAppearance: Bool,
        textColor: UIColor,
        placeholderColor: UIColor
    ) {
        self.appearanceStyle = appearanceStyle
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
        self.overallDarkAppearance = overallDarkAppearance
        self.textColor = textColor
        self.placeholderColor = placeholderColor
    }
}

public struct AetherInputBarResolvedAppearance {
    public var appearanceStyle: AetherAppearanceStyle
    public var background: AetherBarBackgroundAppearance
    public var stroke: AetherGlassStrokeAppearance
    public var separator: AetherSeparatorAppearance
    public var edgeEffect: AetherEdgeEffectAppearance
    public var overallDarkAppearance: Bool

    public init(
        appearanceStyle: AetherAppearanceStyle = .liquidGlassV1,
        background: AetherBarBackgroundAppearance,
        stroke: AetherGlassStrokeAppearance,
        separator: AetherSeparatorAppearance,
        edgeEffect: AetherEdgeEffectAppearance,
        overallDarkAppearance: Bool
    ) {
        self.appearanceStyle = appearanceStyle
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
        self.overallDarkAppearance = overallDarkAppearance
    }
}

// MARK: - Overrides

public struct AetherAppearanceOverrideContext {
    public var appearance: AetherAppearance
    public var surface: AetherAppearanceSurface
    public var placement: AetherBarPlacement
    public var traitCollection: UITraitCollection?
    public var viewController: UIViewController?

    public init(
        appearance: AetherAppearance,
        surface: AetherAppearanceSurface,
        placement: AetherBarPlacement,
        traitCollection: UITraitCollection? = nil,
        viewController: UIViewController? = nil
    ) {
        self.appearance = appearance
        self.surface = surface
        self.placement = placement
        self.traitCollection = traitCollection
        self.viewController = viewController
    }
}

public protocol AetherControllerAppearanceProviding: AnyObject {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride?
}

public extension AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        nil
    }
}

public struct AetherAppearanceOverride {
    /// Replaces the inherited appearance preset for this local scope before
    /// any surface-specific fields are applied.
    public var appearanceStyle: AetherAppearanceStyle?
    public var navigationBar: AetherNavigationBarAppearanceOverride?
    public var tabBar: AetherTabBarAppearanceOverride?
    public var search: AetherSearchAppearanceOverride?
    public var inputBar: AetherInputBarAppearanceOverride?

    public init(
        appearanceStyle: AetherAppearanceStyle? = nil,
        navigationBar: AetherNavigationBarAppearanceOverride? = nil,
        tabBar: AetherTabBarAppearanceOverride? = nil,
        search: AetherSearchAppearanceOverride? = nil,
        inputBar: AetherInputBarAppearanceOverride? = nil
    ) {
        self.appearanceStyle = appearanceStyle
        self.navigationBar = navigationBar
        self.tabBar = tabBar
        self.search = search
        self.inputBar = inputBar
    }
}

public struct AetherNavigationBarAppearanceOverride {
    public var background: AetherBarBackgroundAppearance?
    public var stroke: AetherGlassStrokeAppearance?
    public var separator: AetherSeparatorAppearance?
    public var edgeEffect: AetherEdgeEffectAppearance?
    public var emptyAreaColor: UIColor?
    public var buttonColor: UIColor?
    public var primaryTextColor: UIColor?

    public init(
        background: AetherBarBackgroundAppearance? = nil,
        stroke: AetherGlassStrokeAppearance? = nil,
        separator: AetherSeparatorAppearance? = nil,
        edgeEffect: AetherEdgeEffectAppearance? = nil,
        emptyAreaColor: UIColor? = nil,
        buttonColor: UIColor? = nil,
        primaryTextColor: UIColor? = nil
    ) {
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
        self.emptyAreaColor = emptyAreaColor
        self.buttonColor = buttonColor
        self.primaryTextColor = primaryTextColor
    }
}

public extension AetherNavigationBarAppearanceOverride {
    func merged(with override: AetherNavigationBarAppearanceOverride?) -> AetherNavigationBarAppearanceOverride {
        guard let override else {
            return self
        }
        return AetherNavigationBarAppearanceOverride(
            background: override.background ?? background,
            stroke: override.stroke ?? stroke,
            separator: override.separator ?? separator,
            edgeEffect: override.edgeEffect ?? edgeEffect,
            emptyAreaColor: override.emptyAreaColor ?? emptyAreaColor,
            buttonColor: override.buttonColor ?? buttonColor,
            primaryTextColor: override.primaryTextColor ?? primaryTextColor
        )
    }
}

public struct AetherTabBarAppearanceOverride {
    public var background: AetherBarBackgroundAppearance?
    /// Overrides the tint carried by the tab bar's glass surfaces without
    /// changing which renderer (`glass`, `color`, or transparent) is used.
    public var backgroundColor: UIColor?
    public var stroke: AetherGlassStrokeAppearance?
    public var separator: AetherSeparatorAppearance?
    public var edgeEffect: AetherEdgeEffectAppearance?
    /// `nil` follows the inherited/system appearance. Supplying either value
    /// pins the complete tab chrome, including legacy glass and the lens.
    public var overallDarkAppearance: Bool?
    public var iconColor: UIColor?
    public var selectedIconColor: UIColor?
    public var textColor: UIColor?
    public var selectedTextColor: UIColor?

    public init(
        background: AetherBarBackgroundAppearance? = nil,
        backgroundColor: UIColor? = nil,
        stroke: AetherGlassStrokeAppearance? = nil,
        separator: AetherSeparatorAppearance? = nil,
        edgeEffect: AetherEdgeEffectAppearance? = nil,
        overallDarkAppearance: Bool? = nil,
        iconColor: UIColor? = nil,
        selectedIconColor: UIColor? = nil,
        textColor: UIColor? = nil,
        selectedTextColor: UIColor? = nil
    ) {
        self.background = background
        self.backgroundColor = backgroundColor
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
        self.overallDarkAppearance = overallDarkAppearance
        self.iconColor = iconColor
        self.selectedIconColor = selectedIconColor
        self.textColor = textColor
        self.selectedTextColor = selectedTextColor
    }
}

public extension AetherTabBarAppearanceOverride {
    func merged(with override: AetherTabBarAppearanceOverride?) -> AetherTabBarAppearanceOverride {
        guard let override else {
            return self
        }
        return AetherTabBarAppearanceOverride(
            background: override.background ?? background,
            backgroundColor: override.backgroundColor ?? backgroundColor,
            stroke: override.stroke ?? stroke,
            separator: override.separator ?? separator,
            edgeEffect: override.edgeEffect ?? edgeEffect,
            overallDarkAppearance: override.overallDarkAppearance ?? overallDarkAppearance,
            iconColor: override.iconColor ?? iconColor,
            selectedIconColor: override.selectedIconColor ?? selectedIconColor,
            textColor: override.textColor ?? textColor,
            selectedTextColor: override.selectedTextColor ?? selectedTextColor
        )
    }
}

public struct AetherSearchAppearanceOverride {
    public var background: AetherBarBackgroundAppearance?
    public var stroke: AetherGlassStrokeAppearance?
    public var separator: AetherSeparatorAppearance?
    public var edgeEffect: AetherEdgeEffectAppearance?
    public var textColor: UIColor?
    public var placeholderColor: UIColor?

    public init(
        background: AetherBarBackgroundAppearance? = nil,
        stroke: AetherGlassStrokeAppearance? = nil,
        separator: AetherSeparatorAppearance? = nil,
        edgeEffect: AetherEdgeEffectAppearance? = nil,
        textColor: UIColor? = nil,
        placeholderColor: UIColor? = nil
    ) {
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
        self.textColor = textColor
        self.placeholderColor = placeholderColor
    }
}

public extension AetherSearchAppearanceOverride {
    func merged(with override: AetherSearchAppearanceOverride?) -> AetherSearchAppearanceOverride {
        guard let override else {
            return self
        }
        return AetherSearchAppearanceOverride(
            background: override.background ?? background,
            stroke: override.stroke ?? stroke,
            separator: override.separator ?? separator,
            edgeEffect: override.edgeEffect ?? edgeEffect,
            textColor: override.textColor ?? textColor,
            placeholderColor: override.placeholderColor ?? placeholderColor
        )
    }
}

public struct AetherInputBarAppearanceOverride {
    public var background: AetherBarBackgroundAppearance?
    public var stroke: AetherGlassStrokeAppearance?
    public var separator: AetherSeparatorAppearance?
    public var edgeEffect: AetherEdgeEffectAppearance?

    public init(
        background: AetherBarBackgroundAppearance? = nil,
        stroke: AetherGlassStrokeAppearance? = nil,
        separator: AetherSeparatorAppearance? = nil,
        edgeEffect: AetherEdgeEffectAppearance? = nil
    ) {
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
    }
}

public extension AetherInputBarAppearanceOverride {
    func merged(with override: AetherInputBarAppearanceOverride?) -> AetherInputBarAppearanceOverride {
        guard let override else {
            return self
        }
        return AetherInputBarAppearanceOverride(
            background: override.background ?? background,
            stroke: override.stroke ?? stroke,
            separator: override.separator ?? separator,
            edgeEffect: override.edgeEffect ?? edgeEffect
        )
    }
}

public extension AetherAppearanceOverride {
    /// Returns an override where `override` has the higher priority while
    /// retaining every lower-priority field it does not replace.
    func merged(with override: AetherAppearanceOverride?) -> AetherAppearanceOverride {
        guard let override else {
            return self
        }
        return AetherAppearanceOverride(
            appearanceStyle: override.appearanceStyle ?? appearanceStyle,
            navigationBar: navigationBar?.merged(with: override.navigationBar) ?? override.navigationBar,
            tabBar: tabBar?.merged(with: override.tabBar) ?? override.tabBar,
            search: search?.merged(with: override.search) ?? override.search,
            inputBar: inputBar?.merged(with: override.inputBar) ?? override.inputBar
        )
    }
}

internal extension AetherAppearance {
    /// A style override selects a complete target preset so values unique to
    /// another generation cannot leak into it. Semantic palette choices stay
    /// inherited because they are independent from the renderer generation.
    func resolvingAppearanceStyle(_ overrideStyle: AetherAppearanceStyle?) -> AetherAppearance {
        guard let overrideStyle, overrideStyle != style else {
            return self
        }
        var result = AetherAppearance.preset(overrideStyle)
        result.overallDarkAppearance = overallDarkAppearance
        result.emptyAreaColor = emptyAreaColor
        result.separatorColor = separatorColor
        return result
    }
}

internal struct AetherAppearanceOverrideResolution {
    var appearance: AetherAppearance
    var override: AetherAppearanceOverride?
}

/// Resolves the common local precedence chain: content/component, then its
/// container, then the supplied global appearance. Providers are evaluated in
/// inheritance order so content observes the container-selected preset.
internal func resolveAetherAppearanceOverride(
    appearance: AetherAppearance,
    surface: AetherAppearanceSurface,
    placement: AetherBarPlacement,
    traitCollection: UITraitCollection?,
    container: UIViewController?,
    content: UIViewController?
) -> AetherAppearanceOverrideResolution {
    var resolvedAppearance = appearance
    var resolvedOverride: AetherAppearanceOverride?

    func apply(provider viewController: UIViewController) {
        let context = AetherAppearanceOverrideContext(
            appearance: resolvedAppearance,
            surface: surface,
            placement: placement,
            traitCollection: traitCollection,
            viewController: viewController
        )
        guard let localOverride = (viewController as? AetherControllerAppearanceProviding)?
            .aetherAppearanceOverride(for: context) else {
            return
        }
        resolvedAppearance = resolvedAppearance.resolvingAppearanceStyle(localOverride.appearanceStyle)
        resolvedOverride = resolvedOverride?.merged(with: localOverride) ?? localOverride
    }

    if let container {
        apply(provider: container)
    }
    if let content, content !== container {
        apply(provider: content)
    }

    return AetherAppearanceOverrideResolution(
        appearance: resolvedAppearance,
        override: resolvedOverride
    )
}

// MARK: - Resolution

public struct AetherAppearanceResolutionContext {
    public var appearance: AetherAppearance
    public var surface: AetherAppearanceSurface
    public var placement: AetherBarPlacement
    public var traitCollection: UITraitCollection?
    public var scrollProgress: CGFloat

    public init(
        appearance: AetherAppearance,
        surface: AetherAppearanceSurface,
        placement: AetherBarPlacement,
        traitCollection: UITraitCollection? = nil,
        scrollProgress: CGFloat = 0.0
    ) {
        self.appearance = appearance
        self.surface = surface
        self.placement = placement
        self.traitCollection = traitCollection
        self.scrollProgress = scrollProgress
    }
}

public enum AetherNavigationBarAppearanceResolver {
    /// Figma's `miscellaneous/bar-border`: black in Light and the matching
    /// high-contrast white hairline in Dark. Opacity is applied separately by
    /// `AetherSeparatorAppearance` so both variants remain exactly 30%.
    private static let legacyBarBorderColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : .black
    }

    public static func resolve(
        context: AetherAppearanceResolutionContext,
        override: AetherNavigationBarAppearanceOverride? = nil
    ) -> AetherNavigationBarResolvedAppearance {
        let appearance = context.appearance
        let tokens = AetherLegacySurfaceTokens.resolve(
            role: .attachedBar,
            traitCollection: context.traitCollection ?? UITraitCollection.current
        )
        let showsScrollSeparator = appearance.style == .liquidGlassV2 && appearance.edgeEffectStyle != .regular
        var resolved = AetherNavigationBarResolvedAppearance(
            appearanceStyle: appearance.style,
            background: appearance.style.usesLiquidGlass
                ? .glass(appearance.edgeEffectStyle)
                : .color(tokens.surfaceColor),
            stroke: appearance.style == .liquidGlassV2
                ? .hairline(color: appearance.separatorColor, opacity: 0.35)
                : .none,
            separator: appearance.style == .legacy
                ? .visible(color: legacyBarBorderColor, opacity: 0.3)
                : (showsScrollSeparator
                    ? .scrollActivated(threshold: 8.0, hysteresis: 2.0, color: appearance.separatorColor)
                    : .hidden),
            edgeEffect: appearance.edgeEffectAppearance(for: context.surface),
            overallDarkAppearance: appearance.overallDarkAppearance,
            emptyAreaColor: appearance.emptyAreaColor,
            buttonColor: appearance.style == .legacy
                ? .systemBlue
                : (appearance.overallDarkAppearance ? .white : .label),
            primaryTextColor: appearance.overallDarkAppearance ? .white : .label
        )
        resolved.apply(override)
        return resolved
    }
}

public enum AetherTabBarAppearanceResolver {
    /// iOS 18 design resource: `Miscellaneous / Tab - Unselected`.
    /// Keep this separate from `.label`: an unselected tab is intentionally
    /// lighter than ordinary body text in both the icon and caption.
    private static let legacyUnselectedTint = UIColor(
        red: 153.0 / 255.0,
        green: 153.0 / 255.0,
        blue: 153.0 / 255.0,
        alpha: 1.0
    )

    public static func resolve(
        context: AetherAppearanceResolutionContext,
        override: AetherTabBarAppearanceOverride? = nil
    ) -> AetherTabBarResolvedAppearance {
        let appearance = context.appearance
        let tokens = AetherLegacySurfaceTokens.resolve(
            role: .attachedBar,
            traitCollection: context.traitCollection ?? UITraitCollection.current
        )
        var resolved = AetherTabBarResolvedAppearance(
            appearanceStyle: appearance.style,
            background: appearance.style.usesLiquidGlass
                ? .glass(appearance.edgeEffectStyle)
                : .color(tokens.surfaceColor),
            stroke: appearance.style == .liquidGlassV2
                ? .hairline(color: appearance.separatorColor, opacity: 0.25)
                : .none,
            separator: appearance.style == .legacy
                ? .visible(color: appearance.separatorColor, opacity: 0.25)
                : .hidden,
            edgeEffect: appearance.edgeEffectAppearance(for: context.surface),
            overallDarkAppearance: appearance.overallDarkAppearance,
            iconColor: appearance.style == .legacy ? legacyUnselectedTint : .label,
            selectedIconColor: .systemBlue,
            textColor: appearance.style == .legacy ? legacyUnselectedTint : .label,
            selectedTextColor: .systemBlue,
            backgroundColor: appearance.tabBarBackgroundColor
        )
        resolved.apply(override)
        return resolved
    }
}

public enum AetherSearchAppearanceResolver {
    public static func resolve(
        context: AetherAppearanceResolutionContext,
        override: AetherSearchAppearanceOverride? = nil
    ) -> AetherSearchResolvedAppearance {
        let appearance = context.appearance
        let tokens = AetherLegacySurfaceTokens.resolve(
            role: .input,
            traitCollection: context.traitCollection ?? UITraitCollection.current
        )
        var resolved = AetherSearchResolvedAppearance(
            appearanceStyle: appearance.style,
            background: appearance.style.usesLiquidGlass
                ? .glass(appearance.edgeEffectStyle)
                : .color(tokens.surfaceColor),
            stroke: appearance.style == .legacy
                ? .hairline(color: tokens.borderColor, opacity: tokens.borderWidth > 0 ? 1 : 0)
                : (appearance.style == .liquidGlassV2
                    ? .hairline(color: appearance.separatorColor, opacity: 0.25)
                    : .none),
            separator: .hidden,
            edgeEffect: appearance.edgeEffectAppearance(for: context.surface),
            overallDarkAppearance: appearance.overallDarkAppearance,
            textColor: .label,
            placeholderColor: .secondaryLabel
        )
        resolved.apply(override)
        return resolved
    }
}

public enum AetherInputBarAppearanceResolver {
    public static func resolve(
        context: AetherAppearanceResolutionContext,
        override: AetherInputBarAppearanceOverride? = nil
    ) -> AetherInputBarResolvedAppearance {
        let appearance = context.appearance
        let tokens = AetherLegacySurfaceTokens.resolve(
            role: .input,
            traitCollection: context.traitCollection ?? UITraitCollection.current
        )
        var resolved = AetherInputBarResolvedAppearance(
            appearanceStyle: appearance.style,
            background: appearance.style.usesLiquidGlass
                ? .glass(appearance.edgeEffectStyle)
                : .color(tokens.surfaceColor),
            stroke: appearance.style == .legacy
                ? .hairline(color: tokens.borderColor, opacity: tokens.borderWidth > 0 ? 1 : 0)
                : (appearance.style == .liquidGlassV2
                    ? .hairline(color: appearance.separatorColor, opacity: 0.25)
                    : .none),
            separator: .visible(
                color: appearance.style == .legacy ? tokens.separatorColor : appearance.separatorColor,
                opacity: appearance.style == .legacy ? 1 : (appearance.style == .liquidGlassV2 ? 0.35 : 0.0)
            ),
            edgeEffect: appearance.edgeEffectAppearance(for: context.surface),
            overallDarkAppearance: appearance.overallDarkAppearance
        )
        resolved.apply(override)
        return resolved
    }
}

private extension AetherNavigationBarResolvedAppearance {
    mutating func apply(_ override: AetherNavigationBarAppearanceOverride?) {
        guard let override else { return }
        if let background = override.background { self.background = background }
        if let stroke = override.stroke { self.stroke = stroke }
        if let separator = override.separator { self.separator = separator }
        if let edgeEffect = override.edgeEffect { self.edgeEffect = edgeEffect }
        if let emptyAreaColor = override.emptyAreaColor { self.emptyAreaColor = emptyAreaColor }
        if let buttonColor = override.buttonColor { self.buttonColor = buttonColor }
        if let primaryTextColor = override.primaryTextColor { self.primaryTextColor = primaryTextColor }
    }
}

private extension AetherTabBarResolvedAppearance {
    mutating func apply(_ override: AetherTabBarAppearanceOverride?) {
        guard let override else { return }
        if let background = override.background { self.background = background }
        if let backgroundColor = override.backgroundColor { self.backgroundColor = backgroundColor }
        if let stroke = override.stroke { self.stroke = stroke }
        if let separator = override.separator { self.separator = separator }
        if let edgeEffect = override.edgeEffect { self.edgeEffect = edgeEffect }
        if let overallDarkAppearance = override.overallDarkAppearance {
            self.overallDarkAppearance = overallDarkAppearance
            self.hasExplicitDarkAppearanceOverride = true
        }
        if let iconColor = override.iconColor { self.iconColor = iconColor }
        if let selectedIconColor = override.selectedIconColor { self.selectedIconColor = selectedIconColor }
        if let textColor = override.textColor { self.textColor = textColor }
        if let selectedTextColor = override.selectedTextColor { self.selectedTextColor = selectedTextColor }
    }
}

private extension AetherSearchResolvedAppearance {
    mutating func apply(_ override: AetherSearchAppearanceOverride?) {
        guard let override else { return }
        if let background = override.background { self.background = background }
        if let stroke = override.stroke { self.stroke = stroke }
        if let separator = override.separator { self.separator = separator }
        if let edgeEffect = override.edgeEffect { self.edgeEffect = edgeEffect }
        if let textColor = override.textColor { self.textColor = textColor }
        if let placeholderColor = override.placeholderColor { self.placeholderColor = placeholderColor }
    }
}

private extension AetherInputBarResolvedAppearance {
    mutating func apply(_ override: AetherInputBarAppearanceOverride?) {
        guard let override else { return }
        if let background = override.background { self.background = background }
        if let stroke = override.stroke { self.stroke = stroke }
        if let separator = override.separator { self.separator = separator }
        if let edgeEffect = override.edgeEffect { self.edgeEffect = edgeEffect }
    }
}

// MARK: - Legacy Renderer Adapters

public extension NavigationControllerTheme {
    convenience init(aetherAppearance appearance: AetherAppearance) {
        let context = AetherAppearanceResolutionContext(
            appearance: appearance,
            surface: .navigation,
            placement: .navigation
        )
        let resolved = AetherNavigationBarAppearanceResolver.resolve(context: context)
        self.init(
            statusBar: appearance.overallDarkAppearance ? .white : .black,
            navigationBar: NavigationBarTheme(aetherResolvedAppearance: resolved),
            emptyAreaColor: resolved.emptyAreaColor
        )
    }

    static func aetherAppearance(_ appearance: AetherAppearance) -> NavigationControllerTheme {
        NavigationControllerTheme(aetherAppearance: appearance)
    }
}

public extension NavigationBarTheme {
    convenience init(
        aetherResolvedAppearance appearance: AetherNavigationBarResolvedAppearance,
        accentButtonColor: UIColor = .systemBlue,
        accentForegroundColor: UIColor = .white
    ) {
        let backgroundColor: UIColor
        let enableBlur: Bool
        let style: NavigationBarStyle
        let glassStyle: NavigationBarGlassStyle

        switch appearance.background {
        case .none, .transparent:
            backgroundColor = .clear
            enableBlur = false
            style = .glass
            glassStyle = .clear
        case let .glass(glass):
            backgroundColor = .clear
            enableBlur = true
            style = .glass
            switch glass {
            case .clear:
                glassStyle = .clear
            case .strong:
                glassStyle = .strong
            case .regular:
                glassStyle = .default
            }
        case let .color(color):
            backgroundColor = color
            enableBlur = appearance.appearanceStyle == .legacy
            style = .legacy
            glassStyle = .default
        }

        self.init(
            overallDarkAppearance: appearance.overallDarkAppearance,
            buttonColor: appearance.buttonColor,
            disabledButtonColor: .secondaryLabel,
            primaryTextColor: appearance.primaryTextColor,
            backgroundColor: backgroundColor,
            opaqueBackgroundColor: appearance.emptyAreaColor,
            enableBackgroundBlur: enableBlur,
            separatorColor: appearance.separator.legacyColor(defaultColor: appearance.emptyAreaColor),
            badgeBackgroundColor: .systemRed,
            badgeStrokeColor: .systemBackground,
            badgeTextColor: .white,
            edgeEffectColor: appearance.edgeEffect.tintColor,
            accentButtonColor: accentButtonColor,
            accentForegroundColor: accentForegroundColor,
            style: style,
            appearanceStyle: appearance.appearanceStyle,
            glassStyle: glassStyle,
            edgeEffectAlpha: appearance.edgeEffect.alpha,
            edgeEffectBlurRadiusAtEdge: appearance.edgeEffect.blurRadiusAtEdge,
            edgeEffectBlurRadiusAtFade: appearance.edgeEffect.blurRadiusAtFade,
            edgeEffectSolidBlur: appearance.edgeEffect.solidBlur,
            edgeEffectStyle: appearance.edgeEffect.style
        )
    }
}

public extension NavigationBarPresentationData {
    static func aetherAppearance(
        accentButtonColor: UIColor = .systemBlue,
        accentForegroundColor: UIColor = .white,
        edgeEffectAlpha: CGFloat = 0.86,
        edgeEffectColor: UIColor = AetherAppearance.runtimeCurrent.edgeEffectColor,
        edgeEffectBlurRadiusAtEdge: CGFloat = AetherAppearance.runtimeCurrent.edgeEffectBlurRadiusAtEdge,
        edgeEffectBlurRadiusAtFade: CGFloat = AetherAppearance.runtimeCurrent.edgeEffectBlurRadiusAtFade,
        edgeEffectStyle: SystemGlassEffectStyle = AetherAppearance.runtimeCurrent.edgeEffectStyle,
        strings: NavigationBarStrings = NavigationBarStrings()
    ) -> NavigationBarPresentationData {
        var appearance = AetherAppearance.runtimeCurrent
        appearance.edgeEffectColor = edgeEffectColor
        appearance.edgeEffectAlpha = edgeEffectAlpha
        appearance.edgeEffectStyle = edgeEffectStyle
        appearance.edgeEffectBlurRadiusAtEdge = edgeEffectBlurRadiusAtEdge
        appearance.edgeEffectBlurRadiusAtFade = edgeEffectBlurRadiusAtFade

        let context = AetherAppearanceResolutionContext(
            appearance: appearance,
            surface: .navigation,
            placement: .navigation
        )
        let resolved = AetherNavigationBarAppearanceResolver.resolve(context: context)
        return NavigationBarPresentationData(
            theme: NavigationBarTheme(
                aetherResolvedAppearance: resolved,
                accentButtonColor: accentButtonColor,
                accentForegroundColor: accentForegroundColor
            ),
            strings: strings
        )
    }
}

public extension TabBarView.Theme {
    init(aetherResolvedAppearance appearance: AetherTabBarResolvedAppearance) {
        let backgroundColor: UIColor
        let enableBlur: Bool
        let style: TabBarView.Style
        let glassEffectStyle: SystemGlassEffectStyle
        switch appearance.background {
        case .none, .transparent:
            backgroundColor = .clear
            enableBlur = false
            style = .liquidGlass
            glassEffectStyle = appearance.edgeEffect.style
        case let .glass(backgroundStyle):
            backgroundColor = appearance.backgroundColor
            enableBlur = true
            style = .liquidGlass
            glassEffectStyle = backgroundStyle
        case let .color(color):
            backgroundColor = color
            enableBlur = appearance.appearanceStyle == .legacy
            style = .legacy
            glassEffectStyle = appearance.edgeEffect.style
        }

        self.init(
            appearanceStyle: appearance.appearanceStyle,
            tabBarBackgroundColor: backgroundColor,
            tabBarSeparatorColor: appearance.separator.legacyColor(defaultColor: .clear),
            tabBarIconColor: appearance.iconColor,
            tabBarSelectedIconColor: appearance.selectedIconColor,
            tabBarTextColor: appearance.textColor,
            tabBarSelectedTextColor: appearance.selectedTextColor,
            enableBlur: enableBlur,
            isDark: appearance.overallDarkAppearance,
            isDarkAppearanceExplicit: appearance.hasExplicitDarkAppearanceOverride
                || appearance.overallDarkAppearance,
            style: style,
            edgeEffectAlpha: appearance.edgeEffect.alpha,
            edgeEffectBlurRadiusAtEdge: appearance.edgeEffect.blurRadiusAtEdge,
            edgeEffectBlurRadiusAtFade: appearance.edgeEffect.blurRadiusAtFade,
            edgeEffectSolidBlur: appearance.edgeEffect.solidBlur,
            glassEffectStyle: glassEffectStyle,
            edgeEffectTintColor: appearance.edgeEffect.tintColor
        )
    }
}

private extension AetherSeparatorAppearance {
    func legacyColor(defaultColor: UIColor) -> UIColor {
        switch self {
        case .hidden:
            return .clear
        case let .visible(color, opacity):
            return (color ?? defaultColor).withAlphaComponent(opacity)
        case let .scrollActivated(_, _, color):
            return color ?? defaultColor
        }
    }
}

public extension AetherAppearance {
    static func withRuntimeCurrent<Result>(_ appearance: AetherAppearance, _ body: () -> Result) -> Result {
        let threadDictionary = Thread.current.threadDictionary
        let previous = threadDictionary[AetherAppearanceRuntimeCurrentStorage.key]
        threadDictionary[AetherAppearanceRuntimeCurrentStorage.key] = appearance
        defer {
            if let previous {
                threadDictionary[AetherAppearanceRuntimeCurrentStorage.key] = previous
            } else {
                threadDictionary.removeObject(forKey: AetherAppearanceRuntimeCurrentStorage.key)
            }
        }
        return body()
    }

    static var runtimeCurrent: AetherAppearance {
        if let scoped = Thread.current.threadDictionary[AetherAppearanceRuntimeCurrentStorage.key] as? AetherAppearance {
            return scoped
        }
        return AetherApplicationRuntime.shared?.currentEnvironment.appearance ?? .liquidGlassV1
    }
}
