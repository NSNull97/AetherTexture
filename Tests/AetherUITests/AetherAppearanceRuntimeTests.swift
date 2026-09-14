import XCTest
import UIKit
@testable import AetherUI

final class AetherAppearanceRuntimeTests: XCTestCase {
    func testAppearanceStyleCanonicalMetadataAndCapabilities() {
        XCTAssertEqual(
            AetherAppearanceStyle.allCases,
            [.legacy, .liquidGlassV1, .liquidGlassV2]
        )
        XCTAssertEqual(AetherAppearanceStyle.legacy.displayName, "Legacy")
        XCTAssertEqual(AetherAppearanceStyle.liquidGlassV1.displayName, "Liquid Glass v1")
        XCTAssertEqual(AetherAppearanceStyle.liquidGlassV2.displayName, "Liquid Glass v2")

        XCTAssertFalse(AetherAppearanceStyle.legacy.usesLiquidGlass)
        XCTAssertNil(AetherAppearanceStyle.legacy.liquidGlassGeneration)
        XCTAssertEqual(AetherAppearanceStyle.liquidGlassV1.liquidGlassGeneration, .v1)
        XCTAssertEqual(AetherAppearanceStyle.liquidGlassV2.liquidGlassGeneration, .v2)
        XCTAssertEqual(AetherAppEnvironmentValues().appearanceStyle, .liquidGlassV1)
    }

    func testEnvironmentAppearanceIsTheSingleStyleSourceOfTruth() {
        var environment = AetherAppEnvironmentValues(appearance: .legacy)
        XCTAssertEqual(environment.appearanceStyle, .legacy)
        XCTAssertEqual(environment.appearance.style, .legacy)

        environment.appearanceStyle = .liquidGlassV2
        XCTAssertEqual(environment.appearanceStyle, .liquidGlassV2)
        XCTAssertEqual(
            environment.appearance.signature,
            AetherAppearance.liquidGlassV2.signature
        )

        var customAppearance = AetherAppearance.liquidGlassV1
        customAppearance.overallDarkAppearance = true
        environment.appearance = customAppearance
        XCTAssertEqual(environment.appearanceStyle, .liquidGlassV1)
        XCTAssertTrue(environment.appearance.overallDarkAppearance)
    }

    @MainActor
    func testDirectThemeInitializersHonorCanonicalLegacyAndStandaloneTabFollowsRuntime() {
        let navigationTheme = NavigationBarTheme(appearanceStyle: .legacy)
        XCTAssertEqual(navigationTheme.appearanceStyle, .legacy)
        guard case .legacy = navigationTheme.style else {
            return XCTFail("Explicit Legacy navigation appearance must resolve the coarse style")
        }

        let tabTheme = TabBarView.Theme(appearanceStyle: .legacy)
        XCTAssertEqual(tabTheme.appearanceStyle, .legacy)
        guard case .legacy = tabTheme.style else {
            return XCTFail("Explicit Legacy tab appearance must resolve the coarse style")
        }
        let figmaTabUnselectedTint = UIColor(
            red: 153.0 / 255.0,
            green: 153.0 / 255.0,
            blue: 153.0 / 255.0,
            alpha: 1.0
        )
        XCTAssertEqual(tabTheme.tabBarIconColor, figmaTabUnselectedTint)
        XCTAssertEqual(tabTheme.tabBarTextColor, figmaTabUnselectedTint)
        XCTAssertEqual(TabBarView.Theme().tabBarIconColor, .label)
        XCTAssertEqual(TabBarView.Theme().tabBarTextColor, .label)
        XCTAssertTrue(TabBarView.Theme().tabBarBackgroundColor.isEqual(UIColor.systemBackground))

        let runtimeTab = AetherAppearance.withRuntimeCurrent(.legacy) {
            TabBarView()
        }
        XCTAssertEqual(runtimeTab.appearanceStyleForTesting, .legacy)
        runtimeTab.aetherApplyAppearance(.liquidGlassV2, animated: false)
        XCTAssertEqual(runtimeTab.appearanceStyleForTesting, .liquidGlassV2)

        let pinnedTab = TabBarView(
            theme: TabBarView.Theme(appearanceStyle: .liquidGlassV1)
        )
        pinnedTab.aetherApplyAppearance(.legacy, animated: false)
        XCTAssertEqual(pinnedTab.appearanceStyleForTesting, .liquidGlassV1)
    }

    @MainActor
    func testTabBarChromeBackgroundColorDefaultsToSystemAndFollowsAppearance() {
        var appearance = AetherAppearance.liquidGlassV1
        XCTAssertTrue(appearance.tabBarBackgroundColor.isEqual(UIColor.systemBackground))

        appearance.tabBarBackgroundColor = .magenta
        let context = AetherAppearanceResolutionContext(
            appearance: appearance,
            surface: .tab,
            placement: .tab,
            traitCollection: UITraitCollection(userInterfaceStyle: .light)
        )
        let resolved = AetherTabBarAppearanceResolver.resolve(context: context)
        let theme = TabBarView.Theme(aetherResolvedAppearance: resolved)

        XCTAssertTrue(resolved.backgroundColor.isEqual(UIColor.magenta))
        XCTAssertTrue(theme.tabBarBackgroundColor.isEqual(UIColor.magenta))

        let tabBar = TabBarView(theme: theme)
        guard case let .custom(_, chromeColor) = tabBar.chromeGlassAppearance.tint.kind else {
            return XCTFail("The tab chrome must expose its appearance-driven custom tint")
        }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(chromeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(red, 1, accuracy: 0.001)
        XCTAssertEqual(green, 0, accuracy: 0.001)
        XCTAssertEqual(blue, 1, accuracy: 0.001)
        XCTAssertGreaterThan(alpha, 0)

        let transparent = AetherTabBarAppearanceResolver.resolve(
            context: context,
            override: AetherTabBarAppearanceOverride(
                background: .glass(.clear),
                backgroundColor: .clear
            )
        )
        let transparentTheme = TabBarView.Theme(aetherResolvedAppearance: transparent)
        XCTAssertEqual(transparentTheme.glassEffectStyle, .clear)
        XCTAssertTrue(transparentTheme.tabBarBackgroundColor.isEqual(UIColor.clear))
        let transparentTabBar = TabBarView(theme: transparentTheme)
        guard case .clear = transparentTabBar.chromeGlassAppearance.tint.kind else {
            return XCTFail("A transparent tab color must use untinted clear glass")
        }
    }

    func testAppearanceStyleDecodesLegacyIdentifiersAndEncodesCanonicalIdentifiers() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let aliases: [(String, AetherAppearanceStyle)] = [
            ("iOS26", .liquidGlassV1),
            ("ios26", .liquidGlassV1),
            ("iOS 26", .liquidGlassV1),
            ("iOS27", .liquidGlassV2),
            ("ios27", .liquidGlassV2),
            ("iOS 27", .liquidGlassV2)
        ]

        for (identifier, expected) in aliases {
            let data = try XCTUnwrap("\"\(identifier)\"".data(using: .utf8))
            XCTAssertEqual(try decoder.decode(AetherAppearanceStyle.self, from: data), expected)
        }

        let canonical: [(AetherAppearanceStyle, String)] = [
            (.legacy, "legacy"),
            (.liquidGlassV1, "liquid-glass-v1"),
            (.liquidGlassV2, "liquid-glass-v2")
        ]
        for (style, identifier) in canonical {
            let encoded = try encoder.encode(style)
            XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"\(identifier)\"")
            XCTAssertEqual(try decoder.decode(AetherAppearanceStyle.self, from: encoded), style)
        }

        let unknown = try XCTUnwrap("\"ios28\"".data(using: .utf8))
        XCTAssertThrowsError(try decoder.decode(AetherAppearanceStyle.self, from: unknown))
    }

    func testLegacyResolversDisableGlassAndEdgeEffects() {
        for role in [
            AetherSurfaceRole.attachedBar,
            .floatingSurface,
            .toolbar,
            .button,
            .card,
            .input,
            .popup,
            .badge,
            .selectionIndicator,
            .overlay
        ] {
            XCTAssertEqual(
                AetherLegacySurfaceTokens.resolve(
                    role: role,
                    traitCollection: UITraitCollection()
                ).blurStyle,
                .systemChromeMaterial
            )
        }
        XCTAssertEqual(
            AetherLegacySurfaceTokens.resolve(
                role: .attachedBar,
                traitCollection: UITraitCollection(displayScale: 3.0)
            ).borderWidth,
            0
        )

        let surfaces: [(AetherAppearanceSurface, AetherBarPlacement)] = [
            (.navigation, .navigation),
            (.tab, .tab),
            (.search, .top),
            (.inputBar, .inputAccessory)
        ]
        for (surface, placement) in surfaces {
            let context = AetherAppearanceResolutionContext(
                appearance: .legacy,
                surface: surface,
                placement: placement
            )
            switch surface {
            case .navigation:
                let resolved = AetherNavigationBarAppearanceResolver.resolve(context: context)
                if case .color = resolved.background {} else { XCTFail("Legacy navigation must use a color surface") }
                XCTAssertFalse(resolved.edgeEffect.isEnabled)
            case .tab:
                let resolved = AetherTabBarAppearanceResolver.resolve(context: context)
                if case .color = resolved.background {} else { XCTFail("Legacy tab bar must use a color surface") }
                XCTAssertFalse(resolved.edgeEffect.isEnabled)
                if case let .visible(_, opacity) = resolved.separator {
                    XCTAssertEqual(opacity, 0.25)
                } else {
                    XCTFail("Legacy tab bar must use the v2-strength hairline separator")
                }
                let figmaUnselectedTint = UIColor(
                    red: 153.0 / 255.0,
                    green: 153.0 / 255.0,
                    blue: 153.0 / 255.0,
                    alpha: 1.0
                )
                XCTAssertEqual(resolved.iconColor, figmaUnselectedTint)
                XCTAssertEqual(resolved.textColor, figmaUnselectedTint)
                XCTAssertEqual(resolved.selectedIconColor, .systemBlue)
                XCTAssertEqual(resolved.selectedTextColor, .systemBlue)
            case .search, .bottomSearch:
                let resolved = AetherSearchAppearanceResolver.resolve(context: context)
                if case .color = resolved.background {} else { XCTFail("Legacy search must use a color surface") }
                XCTAssertFalse(resolved.edgeEffect.isEnabled)
            case .inputBar:
                let resolved = AetherInputBarAppearanceResolver.resolve(context: context)
                if case .color = resolved.background {} else { XCTFail("Legacy input bar must use a color surface") }
                XCTAssertFalse(resolved.edgeEffect.isEnabled)
            }
        }
    }

    @MainActor
    func testSystemGlassHelperResolvesLegacyBeforeCreatingEffect() {
        let effect = SystemGlassEffect.make(
            style: .strong,
            isDark: true,
            appearanceStyle: .legacy
        )

        XCTAssertTrue(effect is UIBlurEffect)
        if #available(iOS 26.0, *) {
            XCTAssertFalse(effect is UIGlassEffect)
        }
    }

    @MainActor
    func testGlassBackgroundRendererLifecycleKeepsStableContentAndNoResidue() {
        let surface = AetherAppearance.withRuntimeCurrent(.legacy) {
            GlassBackgroundView(style: .regular)
        }
        let contentHost = surface.contentView
        let marker = UIView()
        contentHost.addSubview(marker)
        surface.glassIsInteractive = true
        surface.update(
            size: CGSize(width: 180, height: 52),
            cornerRadius: 12,
            transition: .immediate
        )

        XCTAssertTrue(surface.usesLegacySurfaceRendererForTesting)
        XCTAssertFalse(surface.usesAnyGlassRendererForTesting)
        XCTAssertEqual(surface.legacyBlurStyleForTesting, .systemChromeMaterial)
        let legacySubviewCount = surface.subviews.count
        let legacySublayerCount = surface.layer.sublayers?.count ?? 0

        var liquidSubviewCount: Int?
        var liquidSublayerCount: Int?
        for _ in 0 ..< 3 {
            surface.appearanceStyleOverride = .liquidGlassV1
            XCTAssertTrue(surface.usesAnyGlassRendererForTesting)
            XCTAssertFalse(surface.usesLegacySurfaceRendererForTesting)
            if let liquidSubviewCount {
                XCTAssertEqual(surface.subviews.count, liquidSubviewCount)
                XCTAssertEqual(Optional(surface.layer.sublayers?.count ?? 0), liquidSublayerCount)
            } else {
                liquidSubviewCount = surface.subviews.count
                liquidSublayerCount = surface.layer.sublayers?.count ?? 0
            }

            surface.appearanceStyleOverride = .legacy
            XCTAssertTrue(surface.usesLegacySurfaceRendererForTesting)
            XCTAssertFalse(surface.usesAnyGlassRendererForTesting)
            XCTAssertEqual(surface.subviews.count, legacySubviewCount)
            XCTAssertEqual(surface.layer.sublayers?.count ?? 0, legacySublayerCount)
            XCTAssertTrue(surface.contentView === contentHost)
            XCTAssertTrue(marker.superview === contentHost)
        }
    }

    @MainActor
    func testExplicitLegacyRendererInitializersNeverInstallLiquidBackends() {
        let surface = GlassBackgroundView(
            style: .regular,
            appearanceStyle: .legacy
        )
        let container = GlassBackgroundContainerView(
            spacing: 7,
            appearanceStyle: .legacy
        )
        let lens = LiquidLensView(
            kind: .builtinContainer,
            appearanceStyle: .legacy
        )

        XCTAssertTrue(surface.usesLegacySurfaceRendererForTesting)
        XCTAssertFalse(surface.usesAnyGlassRendererForTesting)
        XCTAssertFalse(container.isUsingAnyGlassContainerEffect)
        XCTAssertTrue(lens.usesClassicRendererForTesting)
        XCTAssertEqual(lens.classicTrackBlurStyleForTesting, .systemChromeMaterial)
        XCTAssertEqual(lens.classicSelectionBlurStyleForTesting, .systemChromeMaterial)
        XCTAssertFalse(lens.hasLiquidMaskForTesting)
    }

    @MainActor
    func testRuntimeAppearanceUpdateReachesExistingSurfaceConsumer() {
        let runtime = AetherApplicationRuntime(appType: RuntimeAppearanceApp.self)
        let surface = AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            GlassBackgroundView(style: .regular)
        }
        XCTAssertTrue(surface.usesAnyGlassRendererForTesting)

        runtime.updateAppearanceStyle(.legacy)

        XCTAssertTrue(surface.usesLegacySurfaceRendererForTesting)
        XCTAssertFalse(surface.usesAnyGlassRendererForTesting)
    }

    func testAppearancePresetsUseFixedSpecValues() {
        let liquidGlassV1 = AetherAppearance.liquidGlassV1
        XCTAssertEqual(liquidGlassV1.style, .liquidGlassV1)
        XCTAssertFalse(liquidGlassV1.overallDarkAppearance)
        XCTAssertEqual(liquidGlassV1.edgeEffectAlpha, 0.82)
        XCTAssertEqual(liquidGlassV1.edgeEffectBlurRadiusAtEdge, 2.0)
        XCTAssertEqual(liquidGlassV1.edgeEffectBlurRadiusAtFade, 0.0)
        XCTAssertEqual(liquidGlassV1.edgeEffectStyle, .regular)

        let liquidGlassV2 = AetherAppearance.liquidGlassV2
        XCTAssertEqual(liquidGlassV2.style, .liquidGlassV2)
        XCTAssertFalse(liquidGlassV2.overallDarkAppearance)
        XCTAssertEqual(liquidGlassV2.edgeEffectAlpha, 0.82)
        XCTAssertEqual(liquidGlassV2.edgeEffectBlurRadiusAtEdge, 5.0)
        XCTAssertEqual(liquidGlassV2.edgeEffectBlurRadiusAtFade, 5.0)
        XCTAssertEqual(liquidGlassV2.edgeEffectStyle, .strong)
    }

    func testAppearanceStyleNodeInstallsEnvironmentAppearance() {
        let configuration = AetherApplicationRuntime.makeConfiguration(for: AppearanceStyleApp.self)

        XCTAssertEqual(configuration.environment.appearanceStyle, .liquidGlassV2)
        XCTAssertEqual(configuration.environment.appearance.signature, AetherAppearance.liquidGlassV2.signature)
    }

    func testAppearanceStyleModifierInstallsEnvironmentAppearance() {
        let configuration = AetherApplicationRuntime.makeConfiguration(for: AppearanceStyleModifierApp.self)

        XCTAssertEqual(configuration.environment.appearanceStyle, .liquidGlassV2)
        XCTAssertEqual(configuration.environment.appearance.signature, AetherAppearance.liquidGlassV2.signature)
    }

    func testNavigationResolverAppliesPartialOverride() {
        let context = AetherAppearanceResolutionContext(
            appearance: .liquidGlassV2,
            surface: .navigation,
            placement: .navigation
        )
        let override = AetherNavigationBarAppearanceOverride(
            separator: .visible(color: .red, opacity: 0.5),
            edgeEffect: AetherEdgeEffectAppearance(
                tintColor: .green,
                alpha: 0.25,
                blurRadiusAtEdge: 9.0,
                blurRadiusAtFade: 4.0,
                style: .regular
            )
        )

        let resolved = AetherNavigationBarAppearanceResolver.resolve(context: context, override: override)

        if case let .visible(_, opacity) = resolved.separator {
            XCTAssertEqual(opacity, 0.5)
        } else {
            XCTFail("Expected visible separator override")
        }
        XCTAssertEqual(resolved.edgeEffect.alpha, 0.25)
        XCTAssertEqual(resolved.edgeEffect.blurRadiusAtEdge, 9.0)
        XCTAssertEqual(resolved.edgeEffect.blurRadiusAtFade, 4.0)
        XCTAssertFalse(resolved.edgeEffect.solidBlur)
        XCTAssertEqual(resolved.edgeEffect.style, .regular)
    }

    func testNavigationControllerConsumesRuntimeAppearanceWithoutThemeInit() {
        let navigationController = AetherNavigationController()

        navigationController.updateAppearance(.liquidGlassV2)

        let theme = navigationController.navigationBar.presentationData.theme
        XCTAssertEqual(theme.edgeEffectBlurRadiusAtEdge, 5.0)
        XCTAssertEqual(theme.edgeEffectBlurRadiusAtFade, 5.0)
        XCTAssertTrue(theme.edgeEffectSolidBlur)
        XCTAssertEqual(theme.edgeEffectStyle, .strong)
        XCTAssertEqual(theme.glassStyle, .strong)
    }

    func testNavigationControllerUsesScopedRenderAppearanceOnInit() {
        let navigationController = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            AetherNavigationController()
        }

        let theme = navigationController.navigationBar.presentationData.theme
        XCTAssertEqual(theme.edgeEffectBlurRadiusAtEdge, 5.0)
        XCTAssertEqual(theme.edgeEffectBlurRadiusAtFade, 5.0)
        XCTAssertTrue(theme.edgeEffectSolidBlur)
        XCTAssertEqual(theme.edgeEffectStyle, .strong)
        XCTAssertEqual(theme.glassStyle, .strong)
    }

    func testAetherPresentationDataUsesScopedAppearanceAndAccent() {
        let presentationData = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            NavigationBarPresentationData.aetherAppearance(accentButtonColor: .red)
        }

        XCTAssertEqual(presentationData.theme.edgeEffectBlurRadiusAtEdge, 5.0)
        XCTAssertEqual(presentationData.theme.edgeEffectBlurRadiusAtFade, 5.0)
        XCTAssertTrue(presentationData.theme.edgeEffectSolidBlur)
        XCTAssertEqual(presentationData.theme.edgeEffectStyle, .strong)
        XCTAssertEqual(presentationData.theme.glassStyle, .strong)
        XCTAssertEqual(presentationData.theme.accentButtonColor, .red)
    }

    func testDefaultThemePreservesScopedLiquidGlassV2StrongAppearance() {
        let presentationData = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            NavigationBarPresentationData.defaultTheme(edgeColor: .green)
        }

        XCTAssertEqual(presentationData.theme.edgeEffectStyle, .strong)
        XCTAssertEqual(presentationData.theme.glassStyle, .strong)
        XCTAssertTrue(presentationData.theme.edgeEffectSolidBlur)
        XCTAssertEqual(
            presentationData.theme.edgeEffectAlpha,
            AetherAppearance.liquidGlassV2.edgeEffectAlpha
        )
    }

    func testStrongNavigationBarShowsScrollSeparator() {
        let strongData = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            NavigationBarPresentationData.aetherAppearance()
        }
        let strongBar = NavigationBarImpl(presentationData: strongData)
        strongBar.updateBackgroundAlpha(1.0, transition: .immediate)
        XCTAssertEqual(strongBar.stripeNode.alpha, 1.0)

        let regularData = AetherAppearance.withRuntimeCurrent(.liquidGlassV1) {
            NavigationBarPresentationData.aetherAppearance()
        }
        let regularBar = NavigationBarImpl(presentationData: regularData)
        regularBar.updateBackgroundAlpha(1.0, transition: .immediate)
        XCTAssertEqual(regularBar.stripeNode.alpha, 0.0)
    }

    func testNavigationEdgeEffectFollowsScrollEdgeAlpha() throws {
        let presentationData = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            NavigationBarPresentationData.aetherAppearance()
        }
        let bar = NavigationBarImpl(presentationData: presentationData)
        bar.updateLayout(
            size: CGSize(width: 320.0, height: 100.0),
            defaultHeight: 60.0,
            additionalTopHeight: 0.0,
            additionalContentHeight: 0.0,
            additionalBackgroundHeight: 0.0,
            additionalCutout: nil,
            leftInset: 0.0,
            rightInset: 0.0,
            appearsHidden: false,
            isLandscape: false,
            transition: .immediate
        )

        let edgeEffectView = try XCTUnwrap(bar.debugEdgeEffectView)
        XCTAssertFalse(edgeEffectView.isHidden)
        XCTAssertEqual(edgeEffectView.alpha, 0.0, accuracy: 0.001)

        bar.updateBackgroundAlpha(0.42, transition: .immediate)
        XCTAssertEqual(bar.stripeNode.alpha, 0.42, accuracy: 0.001)
        XCTAssertEqual(edgeEffectView.alpha, 0.42, accuracy: 0.001)

        bar.updateBackgroundAlpha(2.0, transition: .immediate)
        XCTAssertEqual(edgeEffectView.alpha, 1.0, accuracy: 0.001)

        bar.updateBackgroundAlpha(-1.0, transition: .immediate)
        XCTAssertEqual(edgeEffectView.alpha, 0.0, accuracy: 0.001)
    }

    func testRegularNavigationAppearanceNeverResolvesSeparator() {
        var appearance = AetherAppearance.liquidGlassV2
        appearance.edgeEffectStyle = .regular
        let resolved = AetherNavigationBarAppearanceResolver.resolve(context: AetherAppearanceResolutionContext(
            appearance: appearance,
            surface: .navigation,
            placement: .navigation
        ))

        if case .hidden = resolved.separator {
        } else {
            XCTFail("Regular navigation glass must not resolve a separator")
        }

        let theme = NavigationBarTheme(aetherResolvedAppearance: resolved)
        XCTAssertEqual(theme.separatorColor.cgColor.alpha, 0.0)
    }

    func testRegularNavigationEdgeEffectDoesNotBleedBelowBar() throws {
        var appearance = AetherAppearance.liquidGlassV2
        appearance.edgeEffectStyle = .regular
        let resolved = AetherNavigationBarAppearanceResolver.resolve(context: AetherAppearanceResolutionContext(
            appearance: appearance,
            surface: .navigation,
            placement: .navigation
        ))
        let bar = NavigationBarImpl(presentationData: NavigationBarPresentationData(
            theme: NavigationBarTheme(aetherResolvedAppearance: resolved)
        ))
        let size = CGSize(width: 320.0, height: 144.0)

        bar.updateLayout(
            size: size,
            defaultHeight: 60.0,
            additionalTopHeight: 0.0,
            additionalContentHeight: 0.0,
            additionalBackgroundHeight: 0.0,
            leftInset: 0.0,
            rightInset: 0.0,
            appearsHidden: false,
            isLandscape: false,
            transition: .immediate
        )

        let edgeEffectView = try XCTUnwrap(bar.debugEdgeEffectView)
        XCTAssertEqual(edgeEffectView.frame.maxY, size.height, accuracy: 0.1)
        XCTAssertEqual(edgeEffectView.debugLastEdgeSize ?? -1.0, edgeEffectView.bounds.height + 1.0, accuracy: 0.1)
        XCTAssertEqual(edgeEffectView.debugLastSolidBlur, false)
        XCTAssertGreaterThan(edgeEffectView.debugLastBlurRadiusAtEdge ?? -1.0, edgeEffectView.debugLastBlurRadiusAtFade ?? -2.0)
        XCTAssertEqual(edgeEffectView.debugLastBlurRadiusAtFade ?? -1.0, 0.0, accuracy: 0.001)
        XCTAssertEqual(edgeEffectView.debugLastPrefersStaticVariableBlurMask, true)
        XCTAssertNotEqual(edgeEffectView.debugLastContentRGBA, 0)
        XCTAssertEqual(edgeEffectView.debugLastFadeCurveExponent ?? -1.0, 2.0, accuracy: 0.001)
    }

    func testTabBarControllerConsumesRuntimeAppearanceWithoutThemeInit() {
        let tabBarController = AetherTabBarController()

        tabBarController.updateAppearance(.liquidGlassV2)

        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.alpha, 0.0)
        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.blurRadiusAtEdge, 0.0)
        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.blurRadiusAtFade, 0.0)
        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.style, .strong)
    }

    func testLiquidGlassV2MakesTabSearchAndInputEdgeEffectsTransparentByDefault() {
        let tab = AetherTabBarAppearanceResolver.resolve(context: AetherAppearanceResolutionContext(
            appearance: .liquidGlassV2,
            surface: .tab,
            placement: .tab
        ))
        let search = AetherSearchAppearanceResolver.resolve(context: AetherAppearanceResolutionContext(
            appearance: .liquidGlassV2,
            surface: .search,
            placement: .top
        ))
        let input = AetherInputBarAppearanceResolver.resolve(context: AetherAppearanceResolutionContext(
            appearance: .liquidGlassV2,
            surface: .inputBar,
            placement: .inputAccessory
        ))

        for edgeEffect in [tab.edgeEffect, search.edgeEffect, input.edgeEffect] {
            XCTAssertEqual(edgeEffect.alpha, 0.0)
            XCTAssertEqual(edgeEffect.blurRadiusAtEdge, 0.0)
            XCTAssertEqual(edgeEffect.blurRadiusAtFade, 0.0)
            XCTAssertTrue(edgeEffect.solidBlur)
            XCTAssertEqual(edgeEffect.style, .strong)
            XCTAssertEqual(edgeEffect.tintColor?.cgColor.alpha ?? -1.0, 0.0)
        }
    }

    func testTabBarControllerUsesTopControllerAppearanceOverride() {
        let content = TabBarOverrideController()
        let navigationController = AetherNavigationController(rootViewController: content)
        let tabBarController = AetherTabBarController()
        tabBarController.setControllers([navigationController], selectedIndex: 0)

        tabBarController.updateAppearance(.liquidGlassV2)

        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.alpha, 0.33)
        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.blurRadiusAtEdge, 7.0)
        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.blurRadiusAtFade, 3.0)
    }

    func testTabBarControllerMergesOwnOverrideWithTopControllerOverride() {
        let content = TabBarSelectedTextOverrideController()
        let navigationController = AetherNavigationController(rootViewController: content)
        let tabBarController = BaseTabBarOverrideController()
        tabBarController.setControllers([navigationController], selectedIndex: 0)

        tabBarController.updateAppearance(.liquidGlassV2)

        XCTAssertEqual(tabBarController.resolvedAppearance.selectedIconColor, .red)
        XCTAssertEqual(tabBarController.resolvedAppearance.selectedTextColor, .green)
    }

    func testTabBarDarkOverrideCanForceEitherInterfaceStyle() {
        let context = AetherAppearanceResolutionContext(
            appearance: .liquidGlassV2,
            surface: .tab,
            placement: .tab,
            traitCollection: UITraitCollection(userInterfaceStyle: .dark)
        )
        let forcedLight = AetherTabBarAppearanceResolver.resolve(
            context: context,
            override: AetherTabBarAppearanceOverride(overallDarkAppearance: false)
        )
        let forcedDark = AetherTabBarAppearanceResolver.resolve(
            context: context,
            override: AetherTabBarAppearanceOverride(overallDarkAppearance: true)
        )

        XCTAssertTrue(forcedLight.hasExplicitDarkAppearanceOverride)
        XCTAssertFalse(forcedLight.overallDarkAppearance)
        XCTAssertTrue(forcedDark.hasExplicitDarkAppearanceOverride)
        XCTAssertTrue(forcedDark.overallDarkAppearance)

        let lightView = TabBarView(theme: TabBarView.Theme(aetherResolvedAppearance: forcedLight))
        lightView.overrideUserInterfaceStyle = .dark
        XCTAssertFalse(lightView.effectiveDarkAppearanceForTesting)

        let darkView = TabBarView(theme: TabBarView.Theme(aetherResolvedAppearance: forcedDark))
        darkView.overrideUserInterfaceStyle = .light
        XCTAssertTrue(darkView.effectiveDarkAppearanceForTesting)
    }

    func testTabBarRestoresLightIconAppearanceAfterDarkScreenPopCompletes() {
        let rootController = AetherViewController()
        rootController.tabBarItem = UITabBarItem(title: "Root", image: nil, selectedImage: nil)
        let darkController = ForcedDarkTabBarOverrideController()
        let navigationController = AetherNavigationController(rootViewController: rootController)
        let tabBarController = AetherTabBarController()
        tabBarController.setControllers([navigationController], selectedIndex: 0)

        navigationController.pushViewController(darkController, animated: false)
        tabBarController.invalidateAppearance()

        XCTAssertTrue(tabBarController.resolvedAppearance.overallDarkAppearance)
        XCTAssertEqual(tabBarController.resolvedAppearance.iconColor, .white)

        _ = navigationController.popViewController(animated: false)
        // This is the same resolution callback emitted by both a completed
        // interactive pop and a regular animated pop.
        navigationController.bottomBarVisibilityTransitionEnded?(true)

        XCTAssertFalse(tabBarController.resolvedAppearance.overallDarkAppearance)
        XCTAssertEqual(tabBarController.resolvedAppearance.iconColor, .label)
    }

    func testNavigationContainerLegacyStyleUsesPresetAndKeepsContentPartialOverride() {
        let content = LegacyNavigationContentOverrideController()
        let navigationController = LegacyNavigationContainerOverrideController(
            rootViewController: content
        )

        navigationController.updateAppearance(.liquidGlassV2)

        let theme = navigationController.navigationBar.presentationData.theme
        if case .legacy = theme.style {
        } else {
            XCTFail("A local legacy style must select the non-glass navigation renderer")
        }
        XCTAssertTrue(theme.enableBackgroundBlur)
        XCTAssertEqual(theme.edgeEffectAlpha, 0.0)
        XCTAssertEqual(theme.edgeEffectBlurRadiusAtEdge, 0.0)
        XCTAssertEqual(theme.edgeEffectBlurRadiusAtFade, 0.0)
        XCTAssertEqual(theme.buttonColor, .red)
        XCTAssertEqual(theme.primaryTextColor, .green)
    }

    func testTabContentStyleOverridesContainerStyleAndMergesPartialFields() {
        let content = LiquidGlassV1TabContentOverrideController()
        let navigationController = AetherNavigationController(rootViewController: content)
        let tabBarController = LegacyTabContainerOverrideController()
        tabBarController.setControllers([navigationController], selectedIndex: 0)

        tabBarController.updateAppearance(.liquidGlassV2)

        if case .glass(.regular) = tabBarController.resolvedAppearance.background {
        } else {
            XCTFail("The higher-priority content style must replace the container preset")
        }
        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.alpha, 0.82)
        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.blurRadiusAtEdge, 2.0)
        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.blurRadiusAtFade, 0.0)
        XCTAssertEqual(tabBarController.resolvedAppearance.selectedIconColor, .red)
        XCTAssertEqual(tabBarController.resolvedAppearance.selectedTextColor, .green)
    }

    func testViewControllerSurfaceResolversUseContainerStyleBeforeContentFields() {
        let container = LegacySurfaceContainerOverrideController()
        let content = PartialSurfaceContentOverrideController()
        container.addChild(content)
        content.didMove(toParent: container)

        let resolved = AetherAppearance.withRuntimeCurrent(.liquidGlassV2) {
            (content.resolvedSearchAppearance(), content.resolvedInputBarAppearance())
        }

        if case .color = resolved.0.background {
        } else {
            XCTFail("Search must resolve a non-glass legacy background")
        }
        XCTAssertFalse(resolved.0.edgeEffect.isEnabled)
        XCTAssertEqual(resolved.0.textColor, .green)

        if case .color = resolved.1.background {
        } else {
            XCTFail("Input bar must resolve a non-glass legacy background")
        }
        if case .hidden = resolved.1.separator {
        } else {
            XCTFail("The content input-bar field must override the container preset")
        }
        XCTAssertFalse(resolved.1.edgeEffect.isEnabled)
    }

    @available(*, deprecated)
    func testDeprecatedNavigationThemeRemainsContainerOverrideBelowContent() {
        let compatibilityBarTheme = NavigationBarTheme(
            buttonColor: .red,
            primaryTextColor: .blue,
            style: .legacy,
            appearanceStyle: .legacy
        )
        let compatibilityTheme = NavigationControllerTheme(
            statusBar: .black,
            navigationBar: compatibilityBarTheme,
            emptyAreaColor: .systemBackground
        )
        let content = LiquidGlassV1NavigationContentOverrideController()
        let navigationController = AetherNavigationController(
            rootViewController: content,
            mode: .single,
            theme: compatibilityTheme
        )

        navigationController.updateAppearance(.liquidGlassV2)

        let resolvedTheme = navigationController.navigationBar.presentationData.theme
        XCTAssertEqual(resolvedTheme.appearanceStyle, .liquidGlassV1)
        if case .glass = resolvedTheme.style {
        } else {
            XCTFail("A content style override must replace the compatibility container renderer")
        }
        XCTAssertEqual(resolvedTheme.buttonColor, .red)
        XCTAssertEqual(resolvedTheme.primaryTextColor, .green)
    }

    @available(*, deprecated)
    func testDeprecatedTabThemeRemainsContainerOverrideBelowContent() {
        let compatibilityTheme = TabBarView.Theme(
            appearanceStyle: .legacy,
            tabBarSelectedIconColor: .red,
            tabBarSelectedTextColor: .red,
            style: .legacy
        )
        let content = LiquidGlassV1TabContentOverrideController()
        let navigationController = AetherNavigationController(rootViewController: content)
        let tabBarController = AetherTabBarController(tabBarTheme: compatibilityTheme)
        XCTAssertEqual(tabBarController.tabBarTheme.appearanceStyle, .legacy)
        tabBarController.tabBarTheme = TabBarView.Theme(
            appearanceStyle: .legacy,
            tabBarSelectedIconColor: .purple,
            tabBarSelectedTextColor: .purple,
            style: .legacy
        )
        tabBarController.setControllers([navigationController], selectedIndex: 0)

        tabBarController.updateAppearance(.liquidGlassV2)

        XCTAssertEqual(tabBarController.resolvedAppearance.appearanceStyle, .liquidGlassV1)
        if case .glass(.regular) = tabBarController.resolvedAppearance.background {
        } else {
            XCTFail("A content style override must replace the compatibility container renderer")
        }
        XCTAssertEqual(tabBarController.resolvedAppearance.selectedIconColor, .purple)
        XCTAssertEqual(tabBarController.resolvedAppearance.selectedTextColor, .green)
    }

    @available(*, deprecated)
    func testDeprecatedLegacyTabThemeKeepsCanonicalSeparatorStrength() {
        let controller = AetherTabBarController(
            tabBarTheme: TabBarView.Theme(
                appearanceStyle: .legacy,
                tabBarSeparatorColor: .separator,
                style: .legacy
            )
        )

        guard case let .visible(_, opacity) = controller.resolvedAppearance.separator else {
            return XCTFail("The compatibility theme must retain the Legacy separator")
        }
        XCTAssertEqual(opacity, 0.25, accuracy: 0.001)
    }

    @MainActor
    func testLegacyChromeKeepsRealBlurAndVisibleLocalBackgroundTint() {
        let background = NavigationBackgroundView(
            color: .systemRed,
            enableBlur: true,
            blurStyle: .systemChromeMaterial
        )

        if UIAccessibility.isReduceTransparencyEnabled {
            XCTAssertFalse(background.usesPublicBlurEffectForTesting)
            XCTAssertEqual(background.backgroundTintAlphaForTesting, 1.0)
        } else {
            XCTAssertTrue(background.usesPublicBlurEffectForTesting)
            XCTAssertGreaterThan(background.backgroundTintAlphaForTesting, 0.0)
            XCTAssertLessThan(background.backgroundTintAlphaForTesting, 0.25)
        }
    }
}

private final class AppearanceStyleApp: AetherApp {
    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            AppearanceStyle(.liquidGlassV2)
        }
    }
}

private final class RuntimeAppearanceApp: AetherApp {
    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            AppearanceStyle(.liquidGlassV1)
        }
    }
}

private final class AppearanceStyleModifierApp: AetherApp {
    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            WindowScene(id: "main") { _ in UIViewController() }
        }
        .appearanceStyle(.liquidGlassV2)
    }
}

private final class TabBarOverrideController: AetherViewController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .tab else {
            return nil
        }
        return AetherAppearanceOverride(
            tabBar: AetherTabBarAppearanceOverride(
                edgeEffect: AetherEdgeEffectAppearance(
                    tintColor: .green,
                    alpha: 0.33,
                    blurRadiusAtEdge: 7.0,
                    blurRadiusAtFade: 3.0,
                    style: .regular
                )
            )
        )
    }
}

private final class BaseTabBarOverrideController: AetherTabBarController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .tab else {
            return nil
        }
        return AetherAppearanceOverride(
            tabBar: AetherTabBarAppearanceOverride(
                selectedIconColor: .red,
                selectedTextColor: .red
            )
        )
    }
}

private final class TabBarSelectedTextOverrideController: AetherViewController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .tab else {
            return nil
        }
        return AetherAppearanceOverride(
            tabBar: AetherTabBarAppearanceOverride(
                selectedTextColor: .green
            )
        )
    }
}

private final class ForcedDarkTabBarOverrideController: AetherViewController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .tab else {
            return nil
        }
        return AetherAppearanceOverride(
            tabBar: AetherTabBarAppearanceOverride(
                overallDarkAppearance: true,
                iconColor: .white,
                textColor: .white
            )
        )
    }
}

private final class LegacyNavigationContainerOverrideController: AetherNavigationController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .navigation else {
            return nil
        }
        return AetherAppearanceOverride(
            appearanceStyle: .legacy,
            navigationBar: AetherNavigationBarAppearanceOverride(buttonColor: .red)
        )
    }
}

private final class LegacyNavigationContentOverrideController: AetherViewController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .navigation, context.appearance.style == .legacy else {
            return nil
        }
        return AetherAppearanceOverride(
            navigationBar: AetherNavigationBarAppearanceOverride(primaryTextColor: .green)
        )
    }
}

private final class LiquidGlassV1NavigationContentOverrideController: AetherViewController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .navigation, context.appearance.style == .legacy else {
            return nil
        }
        return AetherAppearanceOverride(
            appearanceStyle: .liquidGlassV1,
            navigationBar: AetherNavigationBarAppearanceOverride(primaryTextColor: .green)
        )
    }
}

private final class LegacyTabContainerOverrideController: AetherTabBarController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .tab else {
            return nil
        }
        return AetherAppearanceOverride(
            appearanceStyle: .legacy,
            tabBar: AetherTabBarAppearanceOverride(selectedIconColor: .red)
        )
    }
}

private final class LiquidGlassV1TabContentOverrideController: AetherViewController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .tab, context.appearance.style == .legacy else {
            return nil
        }
        return AetherAppearanceOverride(
            appearanceStyle: .liquidGlassV1,
            tabBar: AetherTabBarAppearanceOverride(selectedTextColor: .green)
        )
    }
}

private final class LegacySurfaceContainerOverrideController: AetherViewController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .search || context.surface == .inputBar else {
            return nil
        }
        return AetherAppearanceOverride(appearanceStyle: .legacy)
    }
}

private final class PartialSurfaceContentOverrideController: AetherViewController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.appearance.style == .legacy else {
            return nil
        }
        switch context.surface {
        case .search:
            return AetherAppearanceOverride(
                search: AetherSearchAppearanceOverride(textColor: .green)
            )
        case .inputBar:
            return AetherAppearanceOverride(
                inputBar: AetherInputBarAppearanceOverride(separator: .hidden)
            )
        default:
            return nil
        }
    }
}
