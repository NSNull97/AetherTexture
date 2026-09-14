# Gooey Context Menu Performance

The Liquid Glass transition avoids per-frame hierarchy rendering. The source
snapshot is captured once, while the readable menu stays at its final layout
size. Gooey motion is rendered by frame/corner updates on the temporary shell
plus `CAShapeLayer` bridge paths.

Liquid Glass hot-path work:

- one display link per active transition;
- `CAShapeLayer.path` updates for connector and morph surface;
- one temporary shell frame/corner update;
- no Auto Layout in display-link updates;
- no repeated `UIVisualEffectView` creation per frame.

Legacy does not enter that hot path. The configuration capability is checked
before the transition captures geometry or constructs an overlay. The classic
path uses the existing `UIBlurEffect.Style.systemChromeMaterial` menu surface
and one public `UIViewPropertyAnimator` alpha/scale animation. It allocates no
source snapshot, gooey shell, connector, Metal pipeline, SDF surface or custom
`CADisplayLink`.

Cleanup requirements:

- display link invalidates on finish/cancel;
- overlay removes itself on finish/cancel;
- source/menu alpha and interaction are restored on cancellation;
- controller cleanup remains idempotent.

The same finish/cancel contract applies to Legacy's property animator: the
temporary animator is released, the container receives no overlay subview, and
source/menu transform, alpha and interaction are restored on cancellation.

The `.gooey` path intentionally does not apply private displacement filters to menu snapshots or row content. Optical emphasis is handled by non-interactive overlay layers so text and icons stay readable during close.
