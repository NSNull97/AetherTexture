# Gooey Context Menu Guide

Enable the transition with the new presentation style:

```swift
let menu = ContextMenuController(
    source: ContextMenuController.Source(view: button, cornerRadius: button.bounds.height / 2),
    items: items,
    presentationStyle: .gooey()
)
menu.present()
```

Customize timing and surface behavior by passing a configuration:

```swift
var configuration = AetherGooeyContextMenuTransitionConfiguration.default(appearance: .liquidGlassV2)
configuration.connectorMaximumThickness = 34.0
configuration.debugShowsControlPoints = true

ContextMenuController.present(
    source: button,
    cornerRadius: button.bounds.height / 2,
    items: items,
    presentationStyle: .gooey(configuration: configuration)
)
```

Defaults are appearance-aware:

- `.legacy`: public UIKit alpha/scale motion over
  `UIBlurEffect.Style.systemChromeMaterial`, without a Liquid overlay,
  connector, Metal/SDF renderer, source preview or custom display link.
- `.liquidGlassV1`: regular glass, softer stroke, more elastic connector.
- `.liquidGlassV2`: stronger glass, stronger stroke, denser connector.

## Direct transition API and appearance ownership

The public transition can also be driven directly:

```swift
let configuration =
    AetherGooeyContextMenuTransitionConfiguration.default(appearance: .legacy)
let transition = AetherGooeyContextMenuTransition(
    configuration: configuration
)

transition.animateOpen(
    sourceView: button,
    menuView: menuView,
    containerView: overlayHost,
    placement: .below,
    completion: { finished in /* update ownership */ }
)
```

`configuration.appearanceStyle` is the canonical renderer selection and
`configuration.usesLiquidGlassTransition` exposes its capability. The
`default(appearance:)` factory pins the supplied style. When the full public
initializer omits `appearanceStyle`, it snapshots the current application
runtime at configuration creation time; it does not change underneath an
active transition.

The Legacy capability check is the first branch in `animateOpen` and
`animateClose`. It runs before geometry capture or allocation of the overlay,
morph surface, Metal/SDF objects and `AetherGooeyAnimator` display link.
Cancellation and completion restore the real source/menu alpha, transform and
interaction state without leaving transition views in the container.

The Liquid Glass implementation captures geometry from presentation layers
when possible and converts source/menu frames into the window overlay
coordinate space. If the source disappears before close, it falls back to an
anchor near the menu edge instead of crashing. Legacy does not need this
overlay geometry capture.

Do not route menu actions through `AetherGooeyContextMenuTransition`. Keep actions in `ContextMenuItem` and dismissal in `ContextMenuDismissHandle`.
