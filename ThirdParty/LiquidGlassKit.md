# LiquidGlassKit source attribution

The experimental Metal renderer, shader, capture buffer and frame leases were
adapted from the local optimized LiquidGlassKit prototype, based on
https://github.com/DnV1eX/LiquidGlassKit at
2eb41c5d0115d23179d7a3eb133cb07bac7bb7d8.

Original source headers credit Alexey Demin; the upstream README states
Copyright © 2025 DnV1eX. No LICENSE file was present in that checkout.
Original shader headers are retained. Aether modifications include pooled
resources, asynchronous blur/render submission, bounded local refraction,
analytic rounded-rectangle normals, Direct capture and framework adapters.


Integration validation (2026-09-14):

- AetherUI Release arm64 generic iOS build succeeded (deployment target 15).
- iOS 18.4: 63 targeted tests, 3 native-only tests skipped, no failures.
- iOS 27 / APPSTORE_SAFE: all 63 targeted tests passed.
- Tests cover direct pixel capture during movement/scrolling, foreground
  exclusion/restoration, weak source inheritance, GPU readback after resize,
  live material/geometry changes and native/classic/lens renderer selection.
- Integrated AetherUI performance on physical iPhone 7 has not been measured;
  the preceding standalone Direct prototype was accepted there by the user.


PushApp performance follow-up:

- Share automatic captures across NavigationBarView, TabBarView and
  GlassControlGroup boundaries; capture panel foreground-free UIKit pixels once
  per shared display-link callback and crop them for each surface.
- Share explicit-source snapshots across consumers; invalidate on frame/source
  geometry changes. Reuse snapshot contexts and bound the weak-key cache.
- Regression test: twenty panel surfaces require one tree render, with correct
  top/bottom pixel orientation; next-frame invalidation requires a new render.
- PushApp Release previously forced -Onone; changed that target to -O.
- Device frame rate still needs measurement after installation.

Second PushApp follow-up after device feedback (notifications/detail worst,
send-push also affected):

- Replace independent MTKView timers with one common-mode CADisplayLink and
  explicitly invalidate the shared snapshot epoch once before drawing surfaces.
- Skip surfaces outside the window or clipped ancestor bounds. Partial modal
  presentation still renders exposed underlying surfaces.
- Size shared capture bitmaps to the maximum sampling scale requested by their
  consumers; final Metal drawable and per-surface capture sizes are unchanged.
- ChatBackgroundNode's static gradient/image-mask overlay now stores a composed
  image, invalidated by gradient, mask, layout size or content-mode changes.
  This avoids recompositing the full-screen mask during each glass capture.
- 14 iOS 18.4 tests passed, including actual scheduled MTKView capture sharing,
  offscreen suppression, and masked gradient pixels/theme/resize invalidation.
- User reported that the previous build was still slow; these tests establish
  correctness, not a measured iPhone 7 FPS improvement.

Device profiling follow-up:

- Opt-in `AETHER_GLASS_PROFILE` build condition logs callback cadence, main-thread
  glass work, capture time, drawable acquisition, surface/tree counts and skipped
  resource leases. Callback cadence is not measured GPU presentation FPS.
- PushApp build 4 on iPhone 7: four active surfaces/four tree renders per callback;
  typical capture cost 60–86 ms and drawable acquisition about 0.06 ms. This
  identifies CPU capture as the dominant measured cost, rather than drawable waits.
- Next optimization restricts shared snapshots to the union of required source
  regions and prunes off-region layer branches before CALayer.render. Overflowing
  children are retained; unknown out-of-bounds effects remain conservative.
- 15 targeted iOS 18.4 tests pass, including capture pruning, overflow preservation
  and restoration of temporary layer visibility changes.

Modal/menu follow-up (build 6):

- Build 5 user feedback: notification scrolling improved substantially, detail
  modal and context-menu invocation remain slow. Device samples show up to 75 ms
  for a 375x637 surface capture and 43 ms for a 260x420 surface capture.
- Reuse unchanged model-layer snapshots across frames; fingerprint captured
  layer geometry, contents, colors, masks, text, shape and gradient properties.
  CA animations, filters and procedural emitter/replicator output bypass reuse.
- Large surfaces use a stable window-sized source extent during movement;
  source sampling density remains independent of the foreground transform.
- Prune lower siblings fully covered by opaque source content. Translucent
  covers retain the lower layers; temporary visibility changes are restored.
- 17 targeted tests passed, including opaque/translucent cover pixels, static
  snapshot reuse, source changes, and animation invalidation. Device recheck pending.
