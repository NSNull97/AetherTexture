# Legacy / iOS 18 Figma parity audit

Reference: Figma Community file `NI0odsWChGlBsv3NCEHc2J`, page
`Examples` (`0:3329`). This document tracks the classic `.legacy` renderer
only. Liquid Glass V1/V2 keep their own geometry and renderer contracts.

Status legend:

- **Match** — implementation and regression coverage agree with the reference.
- **Fixed** — a confirmed mismatch was corrected in the current working tree.
- **Gap** — confirmed mismatch still needs implementation.
- **Missing** — the reference has a component with no production AetherUI peer.
- **Needs context** — only frame metadata / visual inspection was available;
  exact-token work should wait for node-level design context.

## Component matrix

| Area | Figma evidence | Status | Current result / remaining work |
| --- | --- | --- | --- |
| Navigation bar | `754:64215`, `770:21903` | Fixed | 44 pt compact row and Chrome material already matched. Batch 1 corrects the bottom hairline to one physical pixel with dynamic bar-border at 0.3 opacity, and restores classic blue controls. Large-title/prompt variants remain under visual regression review. |
| Search field | `754:64215`, `2517:14505` | Fixed | Legacy uses tertiary fill instead of a blur renderer; target geometry is 36 pt high, radius 10, 8 pt horizontal and 7 pt vertical content padding, 17/22 text. |
| Text-field rows | `2517:14505` | Gap | Reference uses 16 pt horizontal inset, 11 pt vertical padding, 100 pt title column, radius 10 grouped container, and a 0.333 pt non-opaque separator. AetherUI has search/input primitives but no complete reusable Settings-style text-field row matching every reference state. |
| Tab bar | `2517:14488` | Fixed | Chrome blur, 49/83 total height, 40 pt items at y=7, top-pinned icon, bottom-pinned 10 pt Medium title, and minimizer-off Legacy behavior match. Batch 1 corrects unselected icon/title tint from `.label` to Figma `#999999`. Separator intentionally retains the previously requested Liquid Glass V2 strength. |
| Slider | `754:64635` | Fixed | Batch 1 adds style-aware classic metrics: 44 pt row, 4 pt track, 28 pt circular thumb and 24 pt endpoint-image boxes; Liquid Glass keeps its 50/32/44×38 defaults. Explicit custom geometry survives live style changes and the Texture wrapper forwards the same contract. |
| Segmented control | visual component inventory | Gap | Batch 1 fixes local style seeding before allocation, live renderer replacement, selected/disabled accessibility, and Texture routing. Legacy now avoids a Liquid mask/deformation pipeline, but exact classic track/selected-segment fill geometry still awaits node-level context. |
| Buttons / control groups | embedded nav/toolbar controls | Gap | Batch 1 fixes pre-allocation Legacy seeding for `GlassButtonView` and Texture button wrappers. Exact button geometry is variant-specific and still needs node-level context. |
| Badge | embedded tab/nav controls | Fixed | UIKit and Texture wrappers now share the compact 18 pt pill metrics instead of rendering the Texture badge as bare text. |
| Switch | embedded action-sheet rows | Gap | Native `UISwitch` is the correct primitive; accessibility value/traits need to update after toggles. |
| Stepper | `754:64669`, `2517:14511` | Missing | No production AetherUI/`UIStepper` wrapper exists. Do not emulate this with segmented or glass controls. |
| Context menu | `754:62668` | Fixed | Batch 1 targets 250 pt width, 12 pt radius, 44 pt rows, 16 pt content inset, 17 pt labels, 20 pt symbols, 0.5 pt row separators, 15 pt dim blur, and classic pre-allocation renderer gating. |
| Standalone menu / submenu | `770:21901`, `754:64157` | Missing | Context menu exists, but there is no standalone public Menu/Popover component covering edit menus and submenus. |
| Action sheet | `754:62559`, `754:62590` | Needs context | Classic surface exists. Local appearance pinning and exact row/group geometry remain gaps; only frame metadata was available in this pass. |
| Alert | `770:21495`, `770:21750` | Needs context | Classic material hard gate exists, but geometry is still centered around Liquid presets and lacks a local appearance pin. Exact keyboard/non-keyboard variants need node context. |
| Toolbar / floating toolbar | `2517:14528` | Needs context | Surfaces follow global appearance through nested renderers, but public local appearance pinning is missing. Text/symbol variants need node context. |
| Modal / sheets | `770:21908`, `770:21909` | Gap | Legacy transition hard gate is present. Public detents cover fewer reference variants than the five named iPhone and two iPad examples. |
| Toast / notification | `770:21905`, `770:21906` | Needs context | Public component exists but lacks local appearance pinning and exact expanded/collapsed reference metrics. |
| Tooltip / popover | `754:64525` | Gap | Tooltip surface exists but has no local appearance pin; there is no standalone reference-parity popover component. |
| List rows | `781:15374`, `754:63935`, `2567:16580` | Gap | `AetherListNode` is layout infrastructure, not a canonical inset/full-width row kit. Standard row, section-header, grouped-spacing, and separator tokens are not centralized. |

## Verified reference tokens

- Chrome bars: `UIBlurEffect.systemChromeMaterial`; the Figma blur/fill layers
  are an approximation, not a reason to recreate a private backdrop pipeline.
- Bar hairline: one physical pixel (`0.333 pt` at 3×); light bar-border is
  `rgba(0, 0, 0, 0.3)` and must remain dynamic in dark appearance.
- Search: tertiary fill `rgba(120, 120, 128, 0.12)`, radius 10, body 17/22.
- Tab title: 10 pt Medium; unselected tint `#999999`; selected tint system blue.
- Context-menu row: 44 pt, body 17/22, 16 pt horizontal inset,
  0.5 pt separator `rgba(128,128,128,0.55)`.

## Evidence limitations

The Figma Starter connector reached its tool-call limit during this pass.
Exact node design context was available for Navigation Bar, Tab Bar, Text
Fields, and Context Menu; Slider/Stepper and the remaining examples were
checked with saved page metadata and live canvas inspection. Items marked
**Needs context** are deliberately not assigned guessed pixel constants.
