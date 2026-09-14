# AetherAppearance Style Specs

`AetherAppearanceStyle` is the single public style model used by the application
runtime and surface resolvers:

```swift
public enum AetherAppearanceStyle: Sendable, Hashable, CaseIterable, Codable {
    case legacy
    case liquidGlassV1
    case liquidGlassV2
}
```

There is no `.automatic` or `.custom` case. The default remains
`.liquidGlassV1`, preserving the behavior of the former `.iOS26` default.
Legacy is an explicitly selected classic theme; it is not selected from the
installed OS version.

## Names and stable identifiers

| Case | Display name | Encoded identifier | Liquid Glass |
| --- | --- | --- | ---: |
| `.legacy` | Legacy | `legacy` | No |
| `.liquidGlassV1` | Liquid Glass v1 | `liquid-glass-v1` | Yes |
| `.liquidGlassV2` | Liquid Glass v2 | `liquid-glass-v2` | Yes |

Use `displayName` for UI labels, `stableIdentifier` for non-Codable storage,
and `usesLiquidGlass` when a public caller needs the high-level capability.

## Preset values

| Field | `.legacy` | `.liquidGlassV1` | `.liquidGlassV2` |
| --- | --- | --- | --- |
| `overallDarkAppearance` | `false` | `false` | `false` |
| `emptyAreaColor` | `.systemBackground` | `.systemBackground` | `.systemBackground` |
| `edgeEffectColor` | `.clear` | `.systemBackground` | `.systemBackground` |
| `edgeEffectAlpha` | `0.0` | `0.82` | `0.82` |
| `edgeEffectBlurRadiusAtEdge` | `0.0` | `2.0` | `5.0` |
| `edgeEffectBlurRadiusAtFade` | `0.0` | `0.0` | `5.0` |
| `edgeEffectStyle` | `.regular` (unused) | `.regular` | `.strong` |
| `separatorColor` | `.separator` | `.separator` | `.separator` |

The Legacy surface renderer uses `UIBlurEffect.Style.systemChromeMaterial` and
resolves semantic colors, borders, shadows, pressed/disabled feedback and
motion values from the surface role. It never creates `UIGlassEffect` or a
Liquid Glass renderer and does not simulate Legacy by setting glass alpha or
blur radius to zero.

Use `AetherAppearanceSignature` when tests or caches need equality across
`UIColor` fields.

## Codable migration

New values encode only as the stable identifiers above. Decoding also accepts
the historical spellings `iOS26`, `ios26`, `iOS 26`, `iOS27`, `ios27` and
`iOS 27` (including their normalized hyphenated forms):

```swift
let data = try JSONEncoder().encode(AetherAppearanceStyle.legacy)
// "legacy"

let migrated = try JSONDecoder().decode(
    AetherAppearanceStyle.self,
    from: Data("\"iOS 26\"".utf8)
)
// .liquidGlassV1
```

For source compatibility, the old names remain deprecated static aliases, not
additional enum cases:

```swift
.iOS26  // deprecated; use .liquidGlassV1
.iOS27  // deprecated; use .liquidGlassV2
```
