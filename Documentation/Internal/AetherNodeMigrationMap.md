# AetherUI Texture Node Migration Map

Last updated: October 24, 2026.

## Texture-Native Now

- `TextNode`: `ASDisplayNode` backed by `ASTextNode`; TextKit remains only for
  geometry/hit-test parity.
- `AetherListItemNode`: `ASDisplayNode` row primitive.
- `AetherListNode`: `ASScrollNode` list engine with item storage,
  transactions, virtualization/reuse, sticky headers, async prepared layouts,
  selection, reorder, boundary triggers, overscroll callbacks, custom indicator
  support, node-native swipe action buttons, animated transaction replay,
  particle-dissolve removal, and scroll helper APIs.
- `AetherListItem`: primary callbacks are node-first
  (`selected(listNode:)`, `swipeActionSelected(_:listNode:isFullSwipe:)`).
- `AetherDisplayNode`, `AetherControlNode`, `AetherScreenNode`: base
  node-first composition primitives.
- `AetherNavigationNode`: Texture screen-stack container.
- `AetherTabContainerNode`, `AetherTabBarItemNode`: Texture tab container and
  tab item nodes.
- `AetherScreenController`, `AetherNodeNavigationController`, and
  `AetherNodeTabContainerController`, `AetherNodePageController`: UIKit
  boundary adapters whose public content/stack/tab/page APIs are
  `AetherScreenNode` / Texture nodes, including navigation-title observation
  and container lifecycle forwarding.
- `AetherGlassButtonNode`, `AetherSegmentedControlNode`: Texture-native
  controls; no legacy `UIView` control hosting.
- `AetherToolbarNode`, `AetherNavigationBarNode`, `AetherSliderNode`,
  `AetherContentUnavailableNode`, and `AetherSkeletonNode`: node-first public
  wrappers for remaining reusable surfaces. Animation-critical glass/shimmer
  internals stay on UIKit/CoreAnimation behind private node hosts.
- `AetherNativeWindow.contentNode`, node overlay presentation overloads,
  `AetherModalNodeNavigationController`, and node overloads for modal content,
  alert custom content, action-sheet overlays, toast/tooltip/context-menu
  sources: public entry points can now be composed from nodes.

## Compatibility Boundaries

- `_AetherNodeHostView` is the internal UIKit host boundary for embedding an
  `ASDisplayNode` in node controllers. Public `AetherNodeHostingView` remains
  only as a deprecated compatibility shim.
- The former `AetherListView` UIKit engine was removed from the package target;
  consumers should migrate to ``AetherListNode``.
- `AetherListNode.scroller`, `keyboardDismissMode`,
  `topOverscrollBackgroundView`, `bottomOverscrollBackgroundView`, and
  `panVelocity(in:)` are deprecated escape hatches. Prefer
  `keyboardDismissBehavior`, `topOverscrollBackgroundNode`,
  `bottomOverscrollBackgroundNode`, and `panVelocity(relativeTo:)`.
- UIKit delegate plumbing for `AetherListNode` is internalized behind a private
  proxy, so scroll/gesture delegate methods are not public API.

## Still To Move

- Keep historical migration notes clearly marked while current guides describe
  only the public node-first API.
- Remaining deep glass/backdrop implementation classes can stay UIKit-backed
  while public construction moves to node wrappers.

## Verification Anchors

- `AetherListCoreTests`: list transaction, virtualization, selection, reorder,
  sticky header, scroll helper, refresh/overscroll, and prepared layout parity.
- `TextNodeTests`: Texture text rendering and hit-test parity.
- `AetherNodeArchitectureTests`: node-first animation, navigation, tabs,
  controls, list compatibility replacements, and public API guardrails.
