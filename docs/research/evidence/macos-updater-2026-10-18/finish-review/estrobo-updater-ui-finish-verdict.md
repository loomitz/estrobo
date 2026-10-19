## verdict

| Material finding | Score | Visible evidence |
| --- | --- | --- |
| Progress bar must agree with the 35% byte/percentage copy (`UpdateViews.swift:69-75`) | resolved | Revised `en-light-progress.png`, `en-dark-progress.png`, `es-light-progress.png` and `es-dark-progress.png` all show a determinate fill extending approximately 35% across the track, matching their adjacent 35% text. The near-zero dot from the original evidence is gone. |

Evidence reviewed at `/private/tmp/estrobo-macos-updater-ui`, supplied commit `577e1aee2055af0cca985c7d6b912227056aefa7`. No regressions from this fix batch are visible in the four same-state captures.

Capture limit: these are direct renders of the actual hosted native view, not desktop-compositor captures. The revised presentation report attributes the initial mismatch to the insertion animation captured at 100 ms and documents a 750 ms settle plus a separate 30-second hold. I independently inspected the four settled PNGs; I did not repeat the runtime hold or obtain an external Computer Use capture. The evidence supports closing this presentation finding without claiming wider runtime or installation proof.

## remaining

clear. The sole material finding is resolved. Productive app scene/menu/factory wiring remains ticket 16 and outside this verdict.

disposition: ship
