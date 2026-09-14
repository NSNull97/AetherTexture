# AetherUI ASDK / Texture Migration Plan

## Current State

AetherUI started as a UIKit-first SwiftPM package inspired by Telegram Display.
The current line is now a Texture-first migration line: old consumers can stay
on the legacy framework, while this package can make source-breaking moves
where that helps complete the ASDK / Texture port cleanly.

Key local surfaces:

- `Package.swift` exposes a single `AetherUI` SwiftPM library product with an
  iOS 15+ floor for the Texture migration line.
- `AetherListView` is now the deprecated legacy `UIView` + `UIScrollView`
  virtualization stack kept for old consumers and parity tests.
- `AetherListNode` is now the migration home for list logic: an
  `ASDisplayNode` / `ASScrollNode` container that owns item storage,
  Texture-row materialization, reuse, offsets, scroll state, sticky headers,
  prepared-layout caches, and transaction size/inset updates. It no longer
  wraps `AetherListView`.
- The node-first core now includes `AetherDisplayNode`, `AetherControlNode`,
  `AetherScreenNode`, `AetherNavigationNode`, `AetherTabContainerNode`, and a
  node animation bridge. These types make Texture the public composition API
  for new screens/navigation/tabs while UIKit remains an internal system
  boundary.
- `AetherGlassButtonNode` and `AetherSegmentedControlNode` are Texture-native
  control nodes. They no longer host `GlassButton` or
  `AetherSegmentedControl` through `setViewBlock`.
- `TextNode` is now an `ASDisplayNode` backed by `ASTextNode`, with TextKit
  retained as the geometry engine for link rects, hit testing, and invisible
  ink.
- `AetherListItemNode` is now an `ASDisplayNode`; `AetherListItem` primary
  callbacks target `AetherListNode`, with old `AetherListView` callbacks
  isolated behind `AetherLegacyListItem`.
- Window, controller, keyboard, presentation, and Metal surfaces are tightly
  bound to UIKit system APIs. Their hosting shells may remain UIKit objects, but
  their renderable content should move to Texture nodes wherever Texture can own
  layout, display, and lifecycle safely.

## Target State

The final goal is not optional Texture support. The final goal is a
Texture-native `AetherUI` core:

- `AetherUI` directly depends on Texture / AsyncDisplayKit.
- `ASDisplayNode` becomes the default primitive for reusable renderable
  components.
- UIKit remains only for system integration boundaries: `UIWindow`,
  `UIViewController`, gesture recognizers, presentation controllers, responder
  chain, keyboard, accessibility escape hatches, and view/layer APIs that
  Texture intentionally exposes through `node.view` / `node.layer`.
- Transitional UIKit backends exist only where a system boundary or temporary
  migration adapter requires them. They are not a long-term product promise.
- Legacy app/runtime support stays in the old framework line; the new line can
  raise platform/API requirements when that simplifies the Texture port.
- A separate `AetherUITexture` target is useful only as a temporary spike or
  bridge. It is not the desired product architecture.

## External Dependency Reality Check

Texture's own docs describe `ASDisplayNode` as the basic unit: a thread-safe
abstraction above `UIView` / `CALayer` that can be created and configured off
the main thread. The official installation docs list CocoaPods and Carthage.
As of July 8, 2026, the Texture GitHub PR list shows active Xcode 26 fixes and
an open "Added Swift Package Manager Support" PR, so SwiftPM integration must
be treated as a spike, not assumed production-ready.

Useful references:

- https://github.com/TextureGroup/Texture
- https://texturegroup.org/docs/getting-started.html
- https://texturegroup.org/docs/installation.html
- https://texturegroup.org/development/layout-specs.html
- https://github.com/FluidGroup/Texture

## Migration Principles

- Prefer node-native replacements over preserving UIKit inheritance. If a type
  is renderable and reusable, its target form is `ASDisplayNode`.
- Keep convenient Aether-owned APIs when they still make sense, but do not keep
  source compatibility with UIKit-only call sites as a migration constraint.
- Use UIKit adapters only at system boundaries or as short-lived bridges while a
  larger surface is being moved.
- Preserve the existing list transaction model in `AetherListNode`. Do not
  replace the custom `ASScrollNode` engine with `ASTableNode` /
  `ASCollectionNode` unless the Telegram-specific behaviors keep parity tests.
- Move high-cost rendering first: text measurement/rendering, image decoding,
  row preparation, and list item subtrees.
- Keep UIKit integration surfaces UIKit-hosted: `UIWindow`, `UIViewController`,
  gestures, keyboard bridges, glass/backdrop effects, portal/snapshot flows,
  and Metal dust rendering. Prefer Texture for their child/content trees.
- Use feature flags only as rollout controls, not as a permanent dual-backend
  product promise.

## Phase 0: Baseline And Decision Gates

Deliverables:

- Run the current test suite and record the baseline.
- Add demo-level performance baselines for:
  - 10k mixed-height list rows.
  - chat-style bottom anchoring with keyboard/input changes.
  - sticky headers and reorder.
  - `TextNode` link hit testing and truncation.
  - particle dissolve removal.
- Capture Instruments numbers for main-thread layout time, frame pacing, memory,
  and first visible row time.
- Decide packaging strategy.

Decision gate:

- If upstream Texture cannot build reliably with Xcode 26 and iOS 15+ through
  SwiftPM, choose a vendoring strategy before changing AetherUI internals:
  reviewed Texture fork with package support, checked-in vendor target, or
  Xcode project integration for the example app while the fork is prepared.
- Do not start replacing core AetherUI types until there is a reproducible
  dependency path that consumers can build.

## Phase 1: Dependency Spike

Goal: prove that Texture can become a hard dependency of AetherUI without
destabilizing the build and distribution model.

Tasks:

- Work directly in the current workspace unless the project is later placed
  back under git metadata.
- Test Texture consumption through the final-intent path first:
  - preferred for package purity: SwiftPM only if upstream support is merged or
    a reviewed fork is accepted;
  - second choice: vendored Texture sources or a local package target owned by
    this repository;
  - temporary spike only: example-app-only CocoaPods/Carthage integration.
- Verify Swift imports, Objective-C module visibility, simulator/device builds,
  DocC generation, and CI behavior.
- Add a minimal `ASDisplayNode` hosted inside an existing `AetherViewController`.

Exit criteria:

- `AetherUI` builds with Texture as a required dependency in the chosen
  integration model.
- The example app renders a Texture node on iOS 15+ and Xcode 26+.
- Dependency and license implications are documented.

Implementation result, July 8, 2026:

- Chosen first integration path: SwiftPM dependency on
  `https://github.com/FluidGroup/Texture.git`, exact `3.0.4`.
- `AetherUI` now depends on product `AsyncDisplayKit`.
- `Package.swift` now declares `.iOS(.v15)` for the new Texture migration line.
- `Package.resolved` locks Texture revision
  `9620825e5f97dfbd1ce653443e5165d5eb405b9b`.
- Added `AetherNodeHostingView` as the first UIKit boundary wrapper around an
  `ASDisplayNode`; it is now deprecated in favour of internal
  `_AetherNodeHostView` plus node controllers.
- Added an Example `TextureDemoController` with a real `ASDisplayNode` layout
  hosted directly at the demo UIKit boundary.
- Verified `Example` build with:
  `xcodebuild -project Example/Example.xcodeproj -scheme Example -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/AetherUITextureBuild -skipMacroValidation build`
- Package scheme `AetherUI` can run iOS simulator tests through `xcodebuild`.
- Building Texture's own `AsyncDisplayKit.xcodeproj` under Xcode 26 requires
  `ENABLE_MODULE_VERIFIER=NO` because its framework umbrella headers still use
  double-quoted includes. The SwiftPM static-library path used by AetherUI does
  not require that flag in the verified Example build.

## Phase 2: Aether Texture Boundary Layer

Goal: define the Aether-facing node architecture while replacing concrete UIKit
rendering subclasses. This keeps system integration explicit while making
Texture the required rendering substrate.

Proposed types:

- `_AetherNodeHostView`: internal `UIView` bridge used by node controllers to
  own an `ASDisplayNode` and forward lifecycle/layout updates safely.
- `AetherTextureBacked`: internal protocol for components whose primary
  implementation is an `ASDisplayNode`, with `node.view` exposed only where a
  system API requires it.
- `AetherTextureLayoutContext`: bridge from `ContainerViewLayout`,
  `ContainedViewLayoutTransition`, safe-area, keyboard, and theme state into
  node layout.
- `AetherTextureFeatureFlags`: temporary runtime rollout switches for comparing
  old and new paths during migration.
- `AetherMainThreadBridge`: helper for the few operations that must touch
  `node.view`, `node.layer`, UIKit gestures, or animation coordination.

Tasks:

- Add Texture imports to the core target after the dependency path is chosen.
- Define ownership rules for `node.view` access.
- Provide debug assertions for accidental off-main UIKit access.
- Add smoke tests for host view sizing, trait propagation, and node teardown.

Exit criteria:

- UIKit system shells can host Texture content without flashing, lifecycle leaks,
  or layout recursion.

Implementation result, July 8, 2026:

- Added `AetherAnimationIdentity`, `AetherAnimatableNode`,
  `AetherDisplayNode`, `AetherControlNode`, `AetherNavigationItemNode`, and
  `AetherScreenNode`.
- Added `AetherAnimationEngine`, `AetherNodeAnimation`,
  `AetherNodeTransition`, `AetherInteractiveTransition`, and
  `AetherGestureTransitionDriver`. The public API is node-first; UIKit
  animation primitives are hidden behind an internal bridge.
- Added `AetherNavigationNode` for Texture-screen stack ownership with
  push/pop/set-stack lifecycle callbacks.
- Added `AetherTabContainerNode`, `AetherTabItemNode`, and
  `AetherTabBarItemNode` for node-first tabs without `UIViewController` as the
  public tab primitive.
- Added Texture-native `AetherGlassButtonNode` and
  `AetherSegmentedControlNode`; both are built from `ASDisplayNode` /
  `ASControlNode` subtrees rather than legacy UIKit controls.
- Added `AetherScreenController`, `AetherNodeNavigationController`, and
  `AetherNodeTabContainerController` as UIKit boundary adapters for
  node-first screens, navigation stacks, and tabs.
- Added `AetherNodeArchitectureTests` covering immediate animations,
  interactive transition progress, navigation stack lifecycle, tab selection,
  control-node migration guards, node-first controller adapters, and public API
  scans for UIKit container leakage.

## Phase 3: TextNode Migration

Goal: make Aether text rendering Texture-native.

Tasks:

- Introduce `AetherTextDisplayNode` backed by `ASTextNode`.
- Change `TextNode` itself to an `ASDisplayNode`.
- Keep TextKit as a geometry engine until hit testing, link rects, and cover
  rects have node-native equivalents.
- Preserve Aether-level API where it still maps cleanly:
  - `attributedText`;
  - vertical alignment;
  - truncation and line count reporting;
  - link hit testing;
  - `attributeRects`;
  - invisible ink integration.
- Add parity tests for `TextNodeTests`.
- Add visual snapshots in the example app for truncation, multiline links, RTL,
  Dynamic Type, and highlighted links.

Exit criteria:

- `TextNode` inherits from `ASDisplayNode`.
- Text rendering is backed by `ASTextNode`.
- Text layout/hit-test parity passes before removing the TextKit geometry layer.

Implementation result, July 8, 2026:

- Added `AetherTextDisplayNode` backed by `ASTextNode`.
- Migrated `TextNode` from `UIView` to `ASDisplayNode`.
- Moved text rendering to the Texture node path while retaining TextKit for
  measurement, link hit testing, `attributeRects`, and text cover rects.
- Added node-level invisible ink support for `TextNode` using `TextNode.view`
  only as the overlay hosting boundary.
- Updated the chat example to host `TextNode` through Texture's `addSubnode`.
- Verified focused text tests with:
  `xcodebuild -scheme AetherUI -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/AetherUITextureTests -skipMacroValidation test -only-testing:AetherUITests/TextNodeTests`

## Phase 4: List Item Node Migration

Goal: move list rendering and list-owned behavior to Texture while preserving
the transaction semantics and custom scroll behavior.

Current direction:

- `AetherListItemNode` now inherits from `ASDisplayNode`.
- `AetherListNode` owns the canonical Texture-native list engine over
  `ASScrollNode`; `AetherListView` is deprecated legacy compatibility.
- `AetherListItem` exposes node-native row creation/update hooks and
  node-first selection/swipe callbacks.
- Do not replace the whole list with `ASTableNode` in the first migration pass;
  Aether's custom transaction engine may be better expressed as an
  `ASScrollNode` / custom node-backed scroller.

Remaining tasks:

- Finish any demo-only polish found during device verification.
- Remove or quarantine old `AetherListView` tests/docs once the legacy package
  split is ready.
- Explore a higher-level spec-based item protocol only where it improves
  background layout/display over the current node contract.
- Map more row implementations to Texture layout specs instead of manual frame
  layout where it buys background measurement/display.
- Preserve reuse identifiers, stable IDs, sticky-header state, display
  lifecycle callbacks, and debug counters as `AetherListNode` evolves.
- Ensure particle dissolve snapshots Texture-backed node views through the
  correct main-thread `node.view` access path.

Exit criteria:

- Existing list tests pass.
- A node-backed row demo supports insert/update/move/delete, sticky headers,
  reorder, bottom anchoring, and keyboard inset compensation.

Implementation result, July 8, 2026:

- Replaced the temporary `AetherListNode` facade with a Texture-native
  `ASScrollNode` container.
- `AetherListNode` now owns items, estimated heights, offsets, content size,
  scroll APIs, transaction mutation, node creation/update, swipe reveal state,
  visibility snapshots, and debug instrumentation.
- Added Texture-node virtualization and reuse using the existing UIKit-free
  `AetherListVirtualizationCommandPlanner`.
- Added sticky header mounting/layout using
  `AetherListStickyHeaderCommandPlanner`.
- Added prepared layout cache/prefetch/application using
  `AetherListAsyncLayoutCommandPlanner`.
- Added transaction `updateSizeAndInsets` handling for size, content insets,
  header insets, scroll indicator insets, item offset insets, and virtual
  content insets.
- Added focused tests for Texture-native operations, virtualization/reuse,
  sticky headers, async prepared layouts, and transaction size/inset updates.
- Moved UIKit delegate conformance for `AetherListNode` behind a private
  delegate proxy so `UIScrollViewDelegate` / `UIGestureRecognizerDelegate`
  methods are no longer part of the public list-node API.
- Added node-first replacements for overscroll backgrounds and keyboard
  dismissal: `topOverscrollBackgroundNode`,
  `bottomOverscrollBackgroundNode`, and `keyboardDismissBehavior`. The old
  `UIView` / `UIScrollView.KeyboardDismissMode` properties remain only as
  deprecated compatibility escape hatches.
- Added node-native swipe action button rendering under `AetherListNode`.
- Added animated transaction replay for Texture list nodes: survivor frame
  animation, inserted row animation, delete fade/slide/scale, and
  particle-dissolve removal through `AetherDustEffectView`.
- Added `particleDissolveTargetNode` and `particleDissolveOverlayHostNode`;
  `UIView` target/host access remains only as deprecated compatibility.
- Made `AetherListItem` primary callbacks node-first and moved deprecated
  `AetherListView` callbacks behind `AetherLegacyListItem`.
- Marked `AetherListView` as deprecated in favour of `AetherListNode`.
- Updated the chat Example to use `keyboardDismissBehavior` on
  `AetherListNode`.
- Extended node-first controller adapters with navigation item observation,
  tab item tap handling, status-bar updates, and navigation/tab lifecycle
  forwarding.
- Added node-first window/overlay/modal/page/action-sheet/alert/context-menu
  entry points: `contentNode`, node overlay presentation, modal node content,
  `AetherModalNodeNavigationController`, `AetherNodePageController`, and node
  overloads for alert/action-sheet/context-menu/tooltip/toast sources.
- Added node wrappers for remaining reusable surfaces:
  `AetherToolbarNode`, `AetherNavigationBarNode`, `AetherSliderNode`,
  `AetherContentUnavailableNode`, and `AetherSkeletonNode`. Gesture, glass,
  shimmer, and transition-critical code remains UIKit/CoreAnimation internally.

Implementation result, July 8, 2026:

- Migrated `AetherListItemNode` from `UIView` to `ASDisplayNode`.
- Kept only a thin `node.view` boundary for `UIScrollView` hosting, gesture
  recognizers, snapshots, transforms, swipe containers, and particle-dissolve
  targets.
- Removed UIView-like public forwarding wrappers from `AetherListItemNode`; code
  that truly needs UIKit now crosses the boundary explicitly through
  `node.view`.
- Removed the old `AetherListItemView` compatibility alias.
- Renamed the item layout snapshot to `currentLayout` because Texture owns the
  `layout()` lifecycle method.
- Updated `AetherListView` to add visible rows through Texture's `addSubnode`
  while continuing to use the existing transaction/reuse/reorder/swipe engine.
- Migrated `AetherListAccessoryItem` from `makeView/updateView` to
  `makeNode/updateNode`, so accessory content is hosted as Texture subnodes.
- Migrated swipe action option content from `UILabel` / `UIImageView` /
  background `UIView` to `ASTextNode` / `ASImageNode` / `ASDisplayNode`; the
  option container remains a UIKit gesture/hit-test boundary.
- Migrated the swipe reveal row background from `UIView` to `ASDisplayNode`.
- Extended `AetherListDebugInstrumentation` with node performance counters and
  optional signposts for create, update, layout application, prepared-layout
  application, swipe reveal updates, and transaction max duration.
- Replaced the temporary `AetherListNode` bridge with a Texture-native
  `ASScrollNode` engine; `AetherListView` remains only as the legacy parity
  surface while remaining features are moved.
- Converted the chat list demo's section headers, chat rows, and message
  bubbles to `ASDisplayNode` / `ASTextNode` internals. `TextNode` remains the
  message text renderer.
- Added a Texture demo probe for `AetherListNode`.
- Verified the Example build with:
  `xcodebuild -project Example/Example.xcodeproj -scheme Example -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/AetherUITextureBuild -skipMacroValidation build`
- Verified focused list and text tests with:
  `xcodebuild -scheme AetherUI -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/AetherUITextureTests -skipMacroValidation test -only-testing:AetherUITests/AetherListCoreTests -only-testing:AetherUITests/TextNodeTests`

## Phase 5: Evaluate Native ASDK Containers

Goal: decide which Texture container owns Aether's list implementation.

Candidates:

- Evaluate `ASCollectionNode`, `ASTableNode`, `ASScrollNode`, and a custom
  `ASDisplayNode` owning a scroll view.
- Prefer the container that preserves Aether's transaction semantics: chat
  histories, particle deletes, sticky bottom headers, custom reorder, virtual
  content insets, and exact Telegram-like scroll anchoring.

Tasks:

- Keep evolving the canonical `AetherListNode` `ASScrollNode` engine; evaluate
  `ASCollectionNode` only for isolated future surfaces where it fits.
- Compare range tuning, batch update behavior, scroll anchoring, accessibility,
  memory pressure, and animation control.
- Decide the canonical list container for the full migration.

Exit criteria:

- Clear documented recommendation: new code uses `AetherListNode`; old
  `AetherListView` is legacy only.

## Phase 6: Component-by-Component Node-ification

Order components by performance value and integration risk:

1. List row text/image subtrees.
2. Remaining repeated row controls and swipe/action container boundaries.
3. Skeleton placeholders and simple static visual nodes.
4. Toolbar/action sheet/alert internal content where layout is expensive.
5. Navigation/tab/glass surfaces after list/text parity is stable.

Keep these UIKit-hosted as system shells, but migrate their internal content
trees to Texture where feasible:

- `AetherWindow`
- `AetherNavigationController`
- `NavigationBarView`
- `TabBarView`
- `GlassBackgroundView`
- context menu transition hosts
- modal presentation controllers
- Metal-backed dust/lens effects

## Phase 7: Public API Migration Strategy

Release sequence:

- Release N: new Texture line with iOS 15+ floor, Texture as a required core
  dependency, and node hosting / lifecycle infrastructure.
- Release N: `TextNode` becomes `ASDisplayNode`.
- Release N: `AetherListItemNode` becomes `ASDisplayNode`.
- Release N+1: migrate remaining repeated row controls and swipe/action
  container internals to node-native implementations.
- Release N+2: migrate the list container to the chosen Texture container
  strategy.
- Release N+3: migrate repeated controls, content-state views, toolbar/action
  sheet/alert content, and navigation/tab content trees.

Compatibility notes:

- This line is allowed to break source compatibility with UIKit-only call sites.
- Keep migration aliases only when they reduce churn inside the repo; do not add
  long-term dual-backend APIs.
- UIKit consumers that need the old inheritance model should stay on the legacy
  framework line.

## Phase 8: Testing And Verification

Automated coverage:

- Keep all existing planner tests UIKit-free.
- Add backend parity tests for text layout and list row lifecycle.
- Add leak tests for node teardown/reuse.
- Add temporary feature-flag tests while old and new paths coexist.
- Add migration-completion tests that fail when deprecated UIKit row paths are
  still used in Texture-native demos.
- Add example-app UI tests for list interactions.

Manual verification:

- Scroll stress on iPhone SE-size and Pro Max-size simulators.
- Dark/light mode, Dynamic Type, Reduce Motion, RTL, VoiceOver.
- Keyboard interactive dismissal in chat-style lists.
- Reorder rollback and edge auto-scroll.
- Metal particle removal on device.

Performance gates:

- No regression in first render time.
- Lower main-thread layout time for Texture-enabled text/list rows.
- Stable memory under repeated list transactions and reuse.
- No visible node flashing during push/pop, insert/delete, or fast scroll.

## Phase 9: Documentation

Docs to update:

- `README.md`: keep AetherUI positioned as a Texture-first framework hosted at
  UIKit system boundaries.
- `Sources/AetherUI/AetherUI.docc/ListView.md`: document node-native row and
  list container architecture.
- `Sources/AetherUI/AetherUI.docc/QuickStart.md`: show default path, not
  experimental flags.
- `AetherListPortNotes.md`: replace "ASDK out of scope" with the new migration
  status once implementation starts.
- Add a dedicated `TextureIntegration.md` DocC article with dependency setup,
  rollout flags, and UIKit-boundary limitations.

## Risks

- Texture packaging may not fit a SwiftPM-first library yet; a fork or vendored
  target may be required.
- Xcode 26 / iOS 26 SDK compatibility needs active validation.
- Public APIs still expose some `UIView` assumptions around gesture
  recognizers, snapshots, and UIKit transition helpers.
- UIKit glass/backdrop behavior may not be safe or valuable to move into nodes.
- List parity is broad: scroll anchoring, sticky headers, reorder, custom
  indicators, boundary triggers, and particle animations all need regression
  coverage.
- Texture can flash or miss lifecycle hints if nodes are embedded casually into
  arbitrary UIKit hierarchies; node containers/hosting discipline is mandatory.

## Recommended Next Implementation Step

Scope:

- Replace public navigation/tab entry points with node-first equivalents while
  keeping `UIViewController` adapters only at app/system integration
  boundaries.
- Complete `AetherListNode` visual parity: node-native swipe action buttons,
  transaction animations, and particle-dissolve removal through a controlled
  node snapshot path.
- Continue shrinking UIKit boundaries inside repeated content/control trees.
  Keep UIKit for `UIWindow`, responder chain, keyboard, accessibility, and
  presentation-controller integration.

Acceptance criteria:

- Core `AetherUI` builds with iOS 15+ and Texture linked.
- `TextNodeTests` pass with `TextNode: ASDisplayNode`.
- Focused list tests pass with `AetherListItemNode: ASDisplayNode`.
- The demo row tree uses Texture nodes for its renderable content and keeps
  UIKit only at system boundaries.
- List accessories and swipe option content are node-backed.
- Row lifecycle and swipe reveal performance counters are covered by focused
  tests.
- `AetherListNode` exposes the current list through a Texture node API, with
  deprecated UIKit escape hatches isolated and covered by regression tests.
- `AetherListItem` no longer requires `AetherListView` callbacks; old callbacks
  are explicit legacy compatibility only.
- New screens can be composed through `AetherScreenNode`,
  `AetherNavigationNode`, and `AetherTabContainerNode` without exposing
  `UIViewController` as the primary public primitive.
- Remaining app surfaces can be entered through node APIs while legacy
  view/controller APIs stay as compatibility adapters.
