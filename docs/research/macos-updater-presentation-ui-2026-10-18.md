# macOS update presentation — native verification

Date: 2026-10-18. Ticket 13. Apple Silicon, macOS 27.0.1, Xcode 27 beta SDK; deployment target remains macOS 13. This is the presentation boundary, with the real `UpdateCoordinator` and a controlled `UpdateService`, `MockRadioRuntime` simulated transport and in-memory preferences. It neither installs Sparkle packages nor operates a physical transmitter.

`UpdateViews.swift` provides the Updates surface, Settings section, app command, nonmodal invitation and availability indicator. The incumbent Settings popover now contains the Updates section, separate from automatic delivery of radio changes. Every component receives the app-owned coordinator; views have no Sparkle types and create no session. Product composition, AppKit lifecycle and actual command/scene routing remain ticket 16.

## Checks

Run from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer make -C prototype/EstroboMac test-update-presentation
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer make -C prototype/EstroboMac test-localization
```

The native fixture runs `NSApplication.run`, hosts real SwiftUI views in AppKit windows and invokes their public accessibility Press actions. An async entry point without the AppKit event loop exited prematurely, so a success requires reaching the final `Update presentation verified` marker. The batch output writes `results.json` only after all cases pass; the target invalidates an older result before running.

Behavior verified:

- Manual checking preserves opt-out. Independent toggles share the same coordinator with Settings; disabling checks also disables background download.
- Download explicitly starts, exposes byte progress, cancels and can retry. Cached bytes alone do not start an installation.
- Opening confirmation has no installation effect. Accepting starts one installation; cancelling preparation waits for the service acknowledgement and returns to the downloaded state.
- A dialog for build 5 cannot approve newly offered and downloaded build 6: the captured identity is rejected without another installation.
- A network failure exposes localized recovery and never becomes “up to date.” Configuration and signature failures have distinct EN/ES explanations.
- The second-launch invitation is inline, offers both enable and decline, and preserves the existing workspace field editor and key window as an offer appears. Enabling explicitly sets both background preferences; declining leaves both off.
- Spanish/English notes follow the selected app language and render as passive verbatim text. Merely rendering does not invoke `openURL`.
- Posted native Escape key events dismiss installation confirmation without authorizing installation.
- A real simulated scan blocks installation and explains the existing connection controls to use. The fixture explicitly cancels that scan; the updater performs no radio action.
- Requested manual download opens the exact offered archive URL. With no offer it opens `/guia/` or `/en/guide/`; support uses the existing GitHub issue route. An injected SwiftUI `openURL` handler records these URLs without browsing or downloading.

The first failing tests preceded each major capability (manual action, independent preferences, transfer/cancellation, confirmation, Settings, error recovery and invitation). A native accessibility finding was corrected: placing an identifier on the invitation `VStack` propagated it to the child buttons. The identifier now belongs to its title, retaining distinct Enable/Not now actions.

## Visual evidence

[Batch results](evidence/macos-updater-2026-10-18/presentation-ui/results.json) contains 40 captures: EN/ES × light/dark × invitation, available, progress, downloaded, confirmation, blocked, successful no-update, missing configuration and signature error, plus the native confirmation sheet. Each capture has an accessibility tree next to its PNG.

Representative views:

- [English downloaded update](evidence/macos-updater-2026-10-18/presentation-ui/en-light-downloaded.png)
- [Spanish nonmodal invitation](evidence/macos-updater-2026-10-18/presentation-ui/es-light-invitation.png)
- [Spanish blocked installation](evidence/macos-updater-2026-10-18/presentation-ui/es-dark-blocked.png)
- [Native confirmation identifying build 5](evidence/macos-updater-2026-10-18/presentation-ui/en-light-confirmation-panel-0.png)

Two batched visual rounds found and removed duplicate privacy copy during the invitation. The native `NSAlert` draws in the enclosing theme frame; capturing only its content view produced a black bitmap. The fixture captures the actual theme frame for sheets, preserving title, message and native actions.

A focused contrast measurement found that the incumbent calibrated RGB secondary color resolves to a lighter sRGB value than its nominal hex. Updates uses explicit sRGB for secondary text, retaining the existing hue and global palette while meeting 4.5:1 for small text (approximately 4.70:1 light and 8.01:1 dark against the resolved incumbent background). Native disabled controls retain platform treatment. No display fonts, imagery, animations or new identity were introduced.

## Limits

These checks establish presentation behavior through the agreed coordinator/UI seams. The reusable app command compiles, but its productive scene/menu route and the shared app-owned factory are verified in ticket 16. Signed/notarized replacement, sandboxed distribution, Intel/minimum-macOS execution and physical Bluetooth permission continuity require their separate evidence; this controlled UI fixture does not establish them.
