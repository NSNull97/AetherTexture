# AetherAppearance Runtime Overview

`AetherAppearance` is the app-level source of visual style for AetherUI chrome
and reusable surface renderers. Applications choose one of three fixed styles:

- **Legacy** — classic non-Liquid-Glass rendering using public
  `UIBlurEffect(.systemChromeMaterial)` plus semantic system tokens.
- **Liquid Glass v1** — the first Liquid Glass generation, formerly named the
  iOS 26 style.
- **Liquid Glass v2** — the second Liquid Glass generation, formerly named the
  iOS 27 style.

These names describe design generations, not the installed operating system.
The default is `.liquidGlassV1`, preserving existing app behavior.

## Application DSL

Select a style in the application builder:

```swift
AetherApplication {
    AppearanceStyle(.legacy)
    WindowScene(id: "main") { _ in
        AetherNavigationController(rootViewController: RootController())
    }
}
```

The modifier spelling is equivalent:

```swift
AetherApplication {
    WindowScene(id: "main") { _ in RootController() }
}
.appearanceStyle(.liquidGlassV1)
```

Use `.liquidGlassV2` in either form when the second-generation preset is
desired. `AetherAppEnvironmentValues` stores both `appearanceStyle` and the
resolved `appearance`, so app and scene handlers receive the same contract.

## Runtime switching

Runtime changes are explicit and update the existing controller/view hierarchy:

```swift
AetherApplicationRuntime.shared?.updateAppearanceStyle(.legacy)
AetherApplicationRuntime.shared?.updateAppearanceStyle(.liquidGlassV1)
AetherApplicationRuntime.shared?.updateAppearanceStyle(.liquidGlassV2)
```

The runtime keeps windows, root controllers, content views, layout and
interaction state in place. Registered surface consumers replace only their
renderer. A transition to Legacy removes Liquid Glass effects instead of
hiding an active glass pipeline, then installs one classic UIKit chrome
material host.

## Surface pipeline

1. The app style produces an `AetherAppearance` preset.
2. A component identifies its semantic role, such as attached bar, floating
   surface, toolbar, button, card, input, popup, badge or overlay.
3. Resolvers produce navigation, tab, search and input appearances; reusable
   surface hosts resolve the same style into either Legacy tokens or a Liquid
   Glass generation.
4. `AetherControllerAppearanceProviding` may apply existing partial surface
   overrides after the app appearance is resolved.

Legacy tokens use dynamic UIKit colors and account for high contrast, Reduce
Transparency and Reduce Motion. Liquid Glass renderers keep real
`#available(iOS 26.0, *)` checks around `UIGlassEffect`; selecting an appearance
never rewrites or bypasses platform availability.

## Persistence

`AetherAppearanceStyle` has manual `Codable` conformance. New data uses
`legacy`, `liquid-glass-v1` and `liquid-glass-v2`. Historical iOS 26/27 style
strings decode to the corresponding Liquid Glass generation so existing saved
settings continue to load.
