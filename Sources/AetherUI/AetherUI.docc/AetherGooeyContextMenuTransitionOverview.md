# Aether Gooey Context Menu Transition

`AetherGooeyContextMenuTransition` is an appearance-aware visual transition
primitive for Aether context menus. It is not a menu controller.

The Liquid Glass implementation owns:

- temporary source snapshot;
- non-interactive overlay cleanup;
- gooey connector path generation;
- temporary shell frame/corner choreography;
- optical highlight choreography that never distorts readable menu content;
- Reduce Motion / Reduce Transparency visual fallbacks.

The Legacy implementation takes a hard-gated classic path instead. It owns a
public `UIViewPropertyAnimator` alpha/scale handoff and uses the menu's
`UIBlurEffect.Style.systemChromeMaterial` surface. It does not allocate the
temporary gooey overlay, source preview, morph surface, Metal renderer, SDF
layers or custom `CADisplayLink` animator.

The existing context menu still owns:

- menu items and actions;
- submenu behavior;
- row highlight and selection;
- dismissal policy;
- tap-outside handling;
- final hit testing;
- accessibility of real menu rows.

Liquid Glass open flow:

1. `ContextMenuController` creates the real `MenuGlassSurfaceView` pre-staged invisible.
2. The source is leased through `SourcePresentationLease`.
3. `AetherGooeyContextMenuTransition` adds a non-interactive overlay.
4. The temporary shell grows from the source frame toward the final menu frame.
5. Source snapshot, metaball connector and morph surface bridge the handoff.
6. Menu rows reveal only after the surface is near final size.
7. The overlay is removed and the menu becomes interactive after completion.

Liquid Glass close flow:

1. Menu rows fade out before any visible squeeze.
2. The temporary shell collapses back toward the source proxy.
3. The source proxy fades in during the tail of the collapse.
4. Shared controller cleanup releases the source lease and removes the host.

The `.gooey` mode is intentionally separate from `.fluidMorph`, so callers can compare both transitions.

## Appearance resolution

``AetherGooeyContextMenuTransitionConfiguration`` retains the canonical
``AetherAppearanceStyle`` used by the transition. Its
`usesLiquidGlassTransition` capability decides the implementation before any
generation-specific resources are created.

`default(appearance:)` pins the supplied appearance. The full configuration
initializer remains source-compatible with existing calls; omitting its
optional `appearanceStyle` snapshots the application runtime when the
configuration is built. A later global appearance update therefore cannot
turn an already configured Legacy transition into Liquid Glass.
