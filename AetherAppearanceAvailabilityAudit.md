# AetherAppearance Availability Audit

Phase 17 audit for the new appearance runtime.

## Public Runtime Contract

- `AetherAppearanceStyle` is a fixed public enum with exactly `.legacy`, `.liquidGlassV1`, and `.liquidGlassV2`.
- `AetherAppearance` is pure data and does not resolve style from OS version, process state, feature flags, or user defaults.
- `AppearanceStyle(.legacy/.liquidGlassV1/.liquidGlassV2)` writes directly into `AetherApplicationRuntimeConfiguration.environment`.
- Runtime updates use `AetherApplicationRuntime.updateAppearanceStyle(_:)` / `updateAppearance(_:)` and update existing controllers and registered surface consumers in place.

## Availability Boundary

| Area | Existing availability/private risk | New runtime action |
| --- | --- | --- |
| `SystemGlassEffect` | Uses public `UIGlassEffect` behind `#available(iOS 26.0, *)` and material blur fallback otherwise. | Reuses the helper; adds `.strong` mapping without adding new private lookups. |
| `GlassBackgroundView` / surface controls | Existing glass infrastructure already gates native glass availability. | Liquid Glass keeps that capability gate; Legacy removes the glass backend and installs public `UIBlurEffect(.systemChromeMaterial)`. |
| `EdgeEffectView` | Existing implementation can use private CoreAnimation filters for variable blur. | Appearance runtime only supplies data (`AetherEdgeEffectAppearance`) and does not introduce new private API. |
| `VisualEffectView` compatibility blur helpers | Existing renderer internals contain reflection/KVC paths. | They are Liquid Glass compatibility backends, not the `.legacy` appearance, and are not created by the canonical Legacy renderer. |
| Liquid Glass generations | The old iOS 26/27 names described design presets, not SDK branches. | `.liquidGlassV1` and `.liquidGlassV2` can be selected on any supported deployment target and fall back through renderer capabilities. |

## Compliance Notes

- No `.automatic`, `.custom`, style id, OS-version resolver, or fallback chain was added to `AetherAppearanceStyle`.
- `.clear` remains on existing `SystemGlassEffectStyle` because it was already public API used by glass configuration; it is not an app appearance style.
- `.legacy` is never selected automatically from the OS version. It is a classic theme available on current systems as well as older supported systems.
- The new runtime does not recreate windows or root controllers when appearance changes. It traverses connected controller hierarchies and updates visible nav/tab/standalone bar renderers plus registered reusable surface hosts.
- `LegacyGlassBackdropView` and `LegacyBlurBackend` retain their historical names as Liquid Glass compatibility implementation details; neither represents `AetherAppearanceStyle.legacy`.

## Persistence boundary

- New Codable output is OS-independent: `legacy`, `liquid-glass-v1`, and `liquid-glass-v2`.
- Historical `iOS26` / `ios26` / `iOS 26` values decode as `.liquidGlassV1`; the corresponding iOS 27 spellings decode as `.liquidGlassV2`.
- Deprecated `.iOS26` and `.iOS27` source aliases do not participate in `allCases` and do not add switch branches.
