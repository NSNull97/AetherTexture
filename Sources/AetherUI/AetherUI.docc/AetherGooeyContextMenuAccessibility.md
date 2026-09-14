# Gooey Context Menu Accessibility

The gooey overlay is visual-only:

- overlay views are not accessibility elements;
- snapshots set `accessibilityElementsHidden = true`;
- connector and debug geometry are hidden from VoiceOver;
- real menu rows keep their existing labels and traits.

Legacy never creates this overlay. The real menu surface uses
`UIBlurEffect.Style.systemChromeMaterial`, while a public UIKit alpha/scale
animator changes only presentation state; the existing menu rows remain the
sole accessibility elements throughout open and close.

Reduce Motion:

- disables elastic lens/connector emphasis;
- shortens the transition;
- uses a simpler fade/scale handoff.

Reduce Transparency:

- increases tint opacity;
- keeps connector readable without relying only on blur.

Increased Contrast:

- increases stroke alpha around the transitional surface.

Focus restoration remains owned by the existing context menu/source lease pipeline.
