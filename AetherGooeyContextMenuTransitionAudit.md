# Aether Gooey Context Menu Transition Audit

| Area | Current implementation | Needed for gooey transition | Risk | Migration action | Notes |
| --- | --- | --- | --- | --- | --- |
| Menu implementation | Custom `ContextMenuController` with `ContextMenuActionsView`; no `UIContextMenuInteraction` path for this menu. | Keep custom controller and add transition-only visual layer. | Rewriting actions/gestures would regress selection and submenu behavior. | Added `.gooey(configuration:)` next to `.morph`, `.preview`, `.fluidMorph`. | System context menu limitations do not apply to this path. |
| Opening control | Controller manually creates host, dim, menu frame and style-specific views. | Transition needs source, menu, container, placement. | Wrong hierarchy order can leave source/menu visible underneath. | `.gooey` creates final `MenuGlassSurfaceView` pre-staged invisible, then `AetherGooeyContextMenuTransition.animateOpen` drives a temporary shell plus connector overlay. | Menu creation stays in controller; readable rows keep final layout size. |
| Closing control | `dismiss(animated:)` branches per `PresentationStyle`, then runs shared cleanup. | Reverse transition must call cleanup once. | Overlay/filter leaks if cancellation races completion. | `.gooey` uses transition completion to call existing cleanup; transition cleanup is idempotent. | Shared dismiss policy is unchanged. |
| Source view | `.fluidMorph` already uses `SourcePresentationLease` to hide original and provide a proxy. | Gooey needs a stable source visual for open and close. | Original source can be hidden by menu lifetime; close snapshot may be blank. | `.gooey` reuses lease proxy and snapshots it, temporarily restoring proxy alpha for close capture. | Original source state restoration remains lease-owned. |
| Target menu frame | `computeMenuFrame` knows source rect, safe area and clamping. | Transition needs final menu frame in host coordinates. | Edge-clamped menu can detach from connector. | `captureGooeyGeometry` converts presentation-layer frames and infers placement from final frames. | `.gooey` uses `.fluidMorph`-style overlapping placement. |
| Transition container | Window-sized `host` view owns dim/menu/transition views. | Overlay must live above source/menu only during transition. | Hit testing or accessibility duplication if overlay remains. | Overlay is non-interactive and `accessibilityElementsHidden = true`; removed on completion/cancel. | Controller still owns tap-outside blocker. |
| Menu actions | `ContextMenuActionsView` owns rows, highlight, callbacks; controller wires actions to dismiss handle. | Transition should only choreograph reveal progress. | Moving callbacks into transition would break submenu/dismiss semantics. | Added `AetherContextMenuContentAnimatable`; `ContextMenuActionsView` maps it to `setRevealProgress`. | Action callbacks unchanged. |
| Dismissal | Background tap, action handle and submenu collapse all call controller dismissal. | Gooey close should be a visual reverse only. | Double cleanup if transition cancel fires after dismiss. | Transition completion is cleared before callback; controller cleanup remains central. | No new recognizers for dismissal. |
| Blur/glass | `MenuGlassSurfaceView` uses `UIGlassEffect` on iOS 26+ or legacy glass; existing non-gooey lens code uses obfuscated private CA/SDF filters. | Gooey needs glass continuity without deforming readable rows. | Applying private displacement to menu snapshots warps text/icons during close. | `.gooey` now animates the live glass surface and uses non-interactive overlay layers only for connector/highlight. | Private displacement is intentionally not applied to `.gooey` menu content. |
| Accessibility | Row cells set labels/traits; controller does not expose snapshots. | Snapshots/connector must be hidden from VoiceOver; Reduce Motion/Transparency fallbacks. | Duplicate elements from snapshots. | Overlay/snapshots hide accessibility; config respects `UIAccessibility` reduce flags. | Screen-changed focus behavior remains current controller behavior. |
| Current animations to preserve | `.morph`, `.preview`, `.fluidMorph`, glass stretch, submenu animations. | New mode should not mutate existing modes. | Tuning `.fluidMorph` would hide regression. | `.gooey` is a new enum case and code path. | Existing `.fluidMorph` examples remain available unless caller opts in. |
| Places not to touch | Item action model, `ContextMenuDismissHandle`, submenu routing, background tap, row hit testing. | Only visual transition may change. | Behavioral regressions. | No menu item/action code moved into transition. | `wireActionsView` stays controller-owned. |

## Direct Answers

- The context menu here is custom Aether UI, not system `UIContextMenuInteraction`.
- Opening and closing transitions are manually controllable in `ContextMenuController`.
- Menu view creation happens in style-specific setup methods; `.gooey` creates a normal `MenuGlassSurfaceView`.
- Source frame and target menu frame are known in `present()` as `sourceRectInHost` and `menuFrameInHost`.
- The transition container is the window-sized `host` view.
- Menu item actions live in `ContextMenuActionsView` and are wired by `ContextMenuController.wireActionsView`.
- Dismissal starts in `ContextMenuController.dismiss(animated:)`.
- Glass lives in `MenuGlassSurfaceView`; `.gooey` keeps readable content off private displacement/filter paths.
- Accessibility for rows lives in row/cell views; transition snapshots are explicitly hidden.
- Existing `.morph`, `.preview`, `.fluidMorph`, submenu and stretch animations must be preserved.
- Gesture/action/dismissal ownership should not move into the transition layer.

## Checkpoint — 2026-07-13

Work is intentionally paused after simulator comparison with the Messages
reference (`/Users/nullptr/Downloads/ScreenRecording_07-10-2026 23-09-12_1.MP4`).

### Accepted direction

- The reverse flow is broadly correct: menu content blurs/dissolves, the body
  contracts into a pear/egg and returns to the navigation-bar button.
- The transition uses sibling native glass surfaces in one glass container;
  the source head, curved neck and destination body are geometry, not a large
  storyboard or raster sequence.
- Content has directional pull, blur/fade handoff and SDF distortion with exact
  endpoint cleanup. Reduce Motion keeps transforms and displacement disabled.
- The content SDF decay now consumes the logical `liveMix`, rather than its
  equal-power square-root gain.

### Current opening mismatch — do not treat as finished

The opening still does not match the reference. Its visible order currently is
an elongated head followed by a small destination seed near the original
top-trailing corner and only then the platter. In the reference the order is:

1. source circle;
2. vertical egg pulled from the **bottom** of the button;
3. egg travels down/leading and becomes one continuous pear/drop;
4. the lower lobe rapidly inflates into the platter while retaining the curved
   connection; content resolves during that inflation.

The concrete geometry defect is that the opening body and bridge are born
before a below/leading body contact is geometrically possible. During the
visible-neck interval the quadratic curve can therefore hairpin upward/right
inside the merged glass. The current X clamp is also relative to `headCenter`;
it must be relative to `bridgeOrigin` to guarantee a leading continuation.

### Resume from here

- Change **opening only** first; keep closing and content choreography stable.
- Delay/gate destination-body birth and neck visibility until the body can
  receive the neck below and leading of `bridgeOrigin`, or anchor the newborn
  body at that lower contact instead of the final top-trailing corner.
- Enforce the curve invariant for every sample with a visible neck, not only a
  few checkpoints: the first tangent exits down, the continuation turns
  leading/inward, and neither segment reverses upward.
- Add early head-bound tests against `source.union(target)`. Existing outer
  bounds tests begin too late to cover the early egg displacement.
- Re-record opening and closing separately on iPhone 17 Pro, then compare
  frame-by-frame with reference frames 174–183 before tuning duration/easing.

Last verified candidate before this checkpoint passed `AetherMotionTests`
30/30. Re-run the suite and build Twitty after the opening geometry change.
