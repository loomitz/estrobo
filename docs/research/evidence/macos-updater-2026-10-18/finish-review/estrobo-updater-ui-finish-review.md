disposition: fix

Scope/evidence limits: ordinary native macOS Settings extension at `e94590ec461bf4c46873ac27e6ffb8716a01cb8e`; new-world comp, QUALITY BAR card and concept seed are intentionally inapplicable. Reviewed ten PNGs, representative AX data, primary presentation sources, EN/ES resources and the supplied evidence report; the other thirty PNGs were not opened. Actual app scene/menu/factory wiring remains ticket 16, and signed replacement/physical radio behavior is outside this presentation review.

## persistence

pass. `PRODUCT.md` and `DESIGN.md` exist. Both explicitly describe the iOS product; the supplied contract correctly keeps this macOS extension anchored to incumbent `SettingsRow`, `PrototypePalette` and native SwiftUI/AppKit controls. The Updates row at `prototype/EstroboMac/Sources/PrototypeViews.swift:3083` follows the existing row/divider pattern. No new visual world or documentation rewrite is warranted. The supplied detector result is `[]`; no second detector was run.

## fidelity

| Element / promise | Classification | Evidence |
| --- | --- | --- |
| THESIS: quiet update task inside the existing macOS product | match | Installed version, update state and actions lead the reading order in `en-light-downloaded.png`; no marketing structure appears. |
| OWN-WORLD: native settings vocabulary | match | Standard buttons, switches, separators and a native `_NSAlertPanel`; `UpdateViews.swift:77`, `:169`, `:187`, `:137`. |
| STORY: installed build → offered build/notes → explicit action | match | `en-light-downloaded.png` distinguishes builds 4 and 5 and leaves installation to the user. |
| FIRST VIEWPORT: current state and appropriate recovery findable | match | `es-dark-blocked.png` names the blocker, offers the workspace action and visibly disables installation; configuration and signature captures name distinct recoveries. |
| FORM: incumbent spacing and restrained surfaces | match | Left alignment, tighter local groups, section rules and 24-point inset; `UpdateViews.swift:17`, `:20`, `:34`, `:131`. No new hero, illustration or motion. |
| TYPE | match | SwiftUI system typography with clear title/headline/callout/caption steps; EN/ES labels and confirmation copy fit in the inspected captures. System typography is explicitly earned by this native Operate surface. |
| MATERIAL | match | Real SwiftUI/AppKit controls and native surfaces; no imitation texture, bevel, physical material or placeholder imagery. |
| Independent background preferences | match | Separate switches and an explicit dependency explanation; `es-light-invitation.png`, `UpdateViews.swift:169-184`. Downloads can be disabled independently while checks remain enabled. |
| Nonmodal discovery / invitation | match | Inline enable/decline choice in `es-light-invitation.png`; it does not replace the state or require a dialog. |
| Exact-version protected installation | match | `en-light-confirmation-panel-0.png` and `es-dark-confirmation-panel-0.png` identify version 0.1.0, build 5, and offer cancel; `UpdateViews.swift:137-158` captures the offer. |
| Download progress | contradicted | `es-light-progress.png` and `en-dark-progress.png` show an effectively empty track with a dot at its origin while adjacent text reports 35%. `UpdateViews.swift:69-75` binds both to the same progress value. These files alone do not establish whether the discrepancy is live UI behavior or the capture path. |
| Localized copy, local notes and recovery links | match | Selected-language copy and passive notes in the inspected EN/ES captures; verbatim notes at `UpdateViews.swift:62`; support/manual actions expose `AXLink` in `es-light-progress.json`. Source routes open only on a button action. |
| Contrast / floor | match | Explicit sRGB secondary source and sampled light/dark PNG glyph colors remain above 4.5:1 against their backgrounds. Native disabled treatment remains distinguishable. No kicker, decorative card scaffold, glyph substitute, gradient text or unnecessary modal appears. |
| Demonstration truth | adaptation | The supplied report and `results.json` explicitly label a controlled service, simulated session and in-memory preferences. Fixture builds/notes are presentation evidence, not a claim of signed installation or physical hardware validation. |

## ceiling

reached for this native Settings extension, apart from the progress discrepancy below. Native controls, system typography, restrained spacing and a protected native confirmation are the appropriate finish. Additional ornament, authored motion, display lettering or new imagery would contradict the inherited contract.

## material_fixes

1. Progress truth / state clarity — at `prototype/EstroboMac/Sources/UpdateViews.swift:69-75`, verify the settled actual native view at 35% and make its determinate bar visibly agree with the byte/percentage text; then replace the EN/ES light/dark progress captures with faithful settled captures. If the live view is correct and `NSView.cacheDisplay` alone loses the fill, repair the evidence capture path and document that distinction; do not alter the bitmap or redesign the control. Current evidence: `es-light-progress.png` and `en-dark-progress.png`, track near y=587, text near y=642.

## keep

Keep the incumbent native control vocabulary, inline discovery, independent preference choices, exact-build confirmation, passive localized notes and explicit blocker recovery; fix only the progress truth/evidence mismatch.
