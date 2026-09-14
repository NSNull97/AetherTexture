# AetherAppearance Migration Guide

## Rename the style API

The canonical style cases now describe visual generations instead of OS
versions:

```swift
.iOS26  -> .liquidGlassV1
.iOS27  -> .liquidGlassV2
```

`.legacy` is new. It selects a classic non-Liquid-Glass renderer on every
supported OS: surfaces use public `UIBlurEffect(.systemChromeMaterial)` instead
of `UIGlassEffect`. It does not mean “an old iOS version.”

The old spellings remain temporary deprecated static aliases, so existing
source continues to compile while emitting a rename warning. They are not
additional enum cases, and `allCases` contains exactly Legacy, Liquid Glass v1
and Liquid Glass v2.

## Select the app style

Old code often passed full themes directly into navigation or tab controllers:

```swift
let nav = AetherNavigationController(mode: .single, theme: .liquidGlass())
let tabs = AetherTabBarController(tabBarTheme: TabBarView.Theme())
```

New code selects the app style once:

```swift
AetherApplication {
    AppearanceStyle(.legacy)
    WindowScene(id: "main") { _ in
        AetherNavigationController(rootViewController: RootController())
    }
}
```

The other two presets use the same API:

```swift
AppearanceStyle(.liquidGlassV1)
AppearanceStyle(.liquidGlassV2)
```

Controllers retain no-theme primary initializers:

```swift
let nav = AetherNavigationController(rootViewController: RootController())
let tabs = AetherTabBarController()
```

Deprecated theme initializers remain compatibility shims for staged migration;
new app-level code should use `AppearanceStyle`.

## Switch an existing hierarchy

Use the runtime rather than rebuilding the window or root controller:

```swift
AetherApplicationRuntime.shared?.updateAppearanceStyle(.legacy)
```

Switching back uses `.liquidGlassV1` or `.liquidGlassV2`. Content, constraints,
selected state and gestures remain owned by the component while its surface
renderer is replaced.

## Local surface overrides

Existing partial per-screen customization is still provided by
`AetherControllerAppearanceProviding`:

```swift
final class DetailController: AetherViewController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        AetherAppearanceOverride(
            navigationBar: AetherNavigationBarAppearanceOverride(
                separator: .visible(color: .separator, opacity: 0.4)
            )
        )
    }
}
```

These values refine the resolved app appearance; they should not recreate a
separate theme system.

## Migrate persisted values

`AetherAppearanceStyle` now encodes stable, OS-independent identifiers:

| Style | Encoded value |
| --- | --- |
| `.legacy` | `legacy` |
| `.liquidGlassV1` | `liquid-glass-v1` |
| `.liquidGlassV2` | `liquid-glass-v2` |

Manual decoding accepts old values such as `iOS26`, `ios26`, `iOS 26`,
`iOS27`, `ios27` and `iOS 27`. Consumers that stored a raw string outside
`Codable` can normalize it by decoding the string as `AetherAppearanceStyle`,
then persist `stableIdentifier` on the next save.

## Keep OS availability checks

Do not rename real platform checks such as:

```swift
if #available(iOS 26.0, *) {
    // UIGlassEffect-backed implementation
}
```

Appearance names and OS availability are separate. A Liquid Glass style can be
selected on any supported deployment target; the renderer keeps its existing
public-API fallback when a platform capability is unavailable.
