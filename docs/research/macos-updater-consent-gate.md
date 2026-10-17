# macOS updater mechanism gate — 2026-10-17

**Product integration is blocked.** The real Sparkle 2.10.0 experiment proves a public cache-only DMG handoff and preserves consent in the tested lifecycle cases. A separate real feed redirect bypasses the required origin allowlist, and representative interactive cancellation during AppKit's pending termination remains unproven. These results do not satisfy the entire mandatory mechanism gate or authorize weakening spec decisions 2, 15, 17 and 22.

Spec: [`.scratch/macos-auto-update/spec.md`](../../.scratch/macos-auto-update/spec.md). Ticket: [10](../../.scratch/macos-auto-update/issues/10-consent-gate.md). Prototype: [`MacUpdaterConsentSpike`](../../prototype/MacUpdaterConsentSpike/README.md). Base before implementation: `218e9ea69f5aa229c2bf815e64b72bdf34413fe7`, directly on integration `codex/macos-auto-update`. Product app, updater integration, radio session, release tooling, keys, feed and infrastructure were not modified by this experiment.

## Dependency revalidation

The official latest-release API and [release page](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0) were rechecked on 2026-10-17: stable **2.10.0**, published 2026-09-13, source commit `eef1a539a373c1f1a320624b1130fc5de7b2e100`. Its minimum macOS is 12.0, compatible with Estrobo's required 13.0. The official framework contains `x86_64 arm64` slices; execution here was only Apple Silicon macOS 27.0.1.

The [official security advisory index](https://github.com/sparkle-project/Sparkle/security/advisories) was reviewed, including the two high-severity local path/cache issues patched in 2.9.6 ([resolved path](https://github.com/sparkle-project/Sparkle/security/advisories/GHSA-3x7w-j75x-ppq5), [privileged cache cleanup](https://github.com/sparkle-project/Sparkle/security/advisories/GHSA-4v99-qgq9-6pxp)). Pinning 2.10.0 does not waive revalidation before distribution.

Downloaded exact asset: `https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz`; verified SHA-256 `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`, matching GitHub release asset metadata. The prototype links only its public headers and the unmodified framework. No dependency was added to the product build.

## Proven cache handoff

1. Foundation downloads the exact offered DMG to a disk file without asking Sparkle to download or prepare it. Automatic Sparkle checks/downloads remain disabled.
2. Only after explicit confirmation, load those bytes into a sufficiently sized `URLCache`. Verify that a cache entry exists for the exact enclosure URL. Revalidate the fresh **signed** appcast using Sparkle, requiring matching build, URL, length and EdDSA signature through public `SUAppcastItem` data.
3. In public [`updater:willDownloadUpdate:withRequest:`](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SPUUpdaterDelegate.h), set the mutable request's cache policy to [`returnCacheDataDontLoad`](https://developer.apple.com/documentation/foundation/nsurlrequest/cachepolicy/returncachedatadontload). Sparkle's real download task consumes the cached response and creates its own managed archive. On eviction, it errors without an archive network fallback.
4. Sparkle verifies EdDSA **before extraction** (`SUVerifyUpdateBeforeExtraction=YES`), prepares the installer, replaces fixture build 1 with build 2, and actually relaunches build 2. `SURequireSignedFeed=YES`, signed-feed failure expiration `0`, and system profiling disabled were set throughout the final run.

The default cache capacity was insufficient for the fixture: adding a cached response could silently leave no entry. The experiment explicitly sizes capacity, checks lookup, and uses a cache-only request. Treat cache acceptance/eviction failure as a failure to prepare installation, never as permission to redownload silently. Product memory behavior for large archives remains to be designed; the prototype's capacity is not a production policy.

The completed source DMG and disk cache had SHA-256 `1103f3f3b8a0fe3bc0d7afff90b44573d8cbb05abc42e531803ac4da756e3b3b`, length **1,221,247 bytes**. The same EdDSA identity was freshly revalidated and consumed by Sparkle. The successful installation made **zero additional archive requests**; only the fresh feed was requested. Tampering with cached bytes of the same length was rejected by Sparkle. This is evidence that the signed downloaded bytes are usable, not merely a same-version second network download. See [artifact metadata](evidence/macos-updater-2026-10-17/consent/artifact.json), [requests](evidence/macos-updater-2026-10-17/consent/requests.json), [events](evidence/macos-updater-2026-10-17/consent/events.log) and [results](evidence/macos-updater-2026-10-17/consent/results.json).

## Runtime matrix and limits

All 11 scripted runtime cases passed on the recorded fixture. These are mechanical outcomes, not product acceptance or an interactive UX claim.

| Case | Observed outcome |
| --- | --- |
| Completed separate download, normal AppKit quit | Installed build remains 1 |
| Process restart, retained cache, close last window | Installed build remains 1 |
| AppKit veto before preparing installer | App remains open, confirmation invalidated; later ordinary quit leaves build 1 |
| Cancel a real transfer, retry, normal quit | Incomplete cache is absent; retry produces exact bytes; build remains 1 |
| Cancel after real installer preparation via public `.skip` | Attempt dismisses; ordinary quit leaves build 1 |
| New unsafe state after confirmation | Scheduled public action cancels; subsequent ordinary quit leaves build 1 |
| Ordinary quit request during prepared attempt | Public cancellation runs before allowing termination; build remains 1 |
| Fresh signed feed changes the offered build | Consent identity rejected before archive copy; build remains 1 |
| Cache entry evicted after priming | Cache-only error, zero additional archive requests; build remains 1 |
| Same-length cached archive adulterated | Sparkle rejects it; build remains 1 |
| Fresh explicit confirmation of exact cache | Real replacement and relaunch to build 2, zero additional archive requests |

**Interactive cancellation is not proven.** Calling AppKit `terminate:` and returning `.terminateLater` enters a termination mode that suspends the fixture's ordinary input/polling timers. The prepared-cancellation/new-work/quit actions above are scheduled from Sparkle's actual ready callback and exercise real public cancellation and real installed-file outcomes. They do not prove that a visible Cancel button or ordinary menu event remains usable during that phase. A maintainable interactive close/commit strategy must be established before adopting this pattern in Estrobo.

A [negative control](evidence/macos-updater-2026-10-17/negative-control/results.json) verifies the original hazard: letting Sparkle prepare a download and withholding the ready callback still installs build 2 on normal quit without confirmation. A custom user driver or delayed relaunch handler alone is inadequate, matching the public [ready callback contract](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SPUUserDriver.h) and [install-on-quit contract](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SPUUpdaterDelegate.h).

Fixture outer apps are **ad hoc signed, non-sandboxed and not notarized**, installed in a unique user-owned temporary directory. Stderr contains `sandbox_extension_issue_file_to_process ... Operation not permitted` warnings; the recorded replacements/relaunch and version observations succeeded, but these warnings are not sandbox validation. No Intel execution, macOS 13 execution, full OS reboot, Developer ID pair update, system authorization cancellation, production cache/HTTPS redirect behavior, persistent app data migration, radio safety or physical transmitter operation was tested. Those gates remain pending. A clean process restart is not a Mac reboot.

## Independent required network policy fails

Decision 15 requires refusing HTTP, unsafe redirects and unexpected destinations. Archive requests can be cache-only, but Sparkle creates its own default-configured `URLSession` for **feed and release-note data requests**, using `.reloadIgnoringLocalCacheData`. The public updater surface provides neither the session configuration nor a redirect-decision delegate. The relevant pinned implementation is [`SPUDownloadDriver.m`](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SPUDownloadDriver.m) and [`SPUDownloader.m`](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Downloader/SPUDownloader.m).

The real Sparkle diagnostic advertised its approved feed on `127.0.0.1`, then returned a 302 to a separately hosted, explicitly forbidden `localhost` origin. Sparkle **requested that origin and validated its signed feed** before any `shouldProceedWithUpdate` policy rejection could prevent the network request. A public globally registered `URLProtocol` guard was consulted by the application's shared download session but was not consulted for Sparkle's feed. After cancellation, the installed fixture remained build 1. See [network requests](evidence/macos-updater-2026-10-17/feed-redirect/requests.json), [events](evidence/macos-updater-2026-10-17/feed-redirect/events.log) and [diagnostic result](evidence/macos-updater-2026-10-17/feed-redirect/results.json).

This controlled **loopback HTTP origin mismatch** establishes the missing effective destination guard. It does not claim to have tested a real HTTPS downgrade, real estrobo.app/GitHub redirects, or production network exposure. The local HTTP servers model remote fixture origins; no embedded cache relay is proposed or authorized.

Independent [Foundation positive controls](evidence/macos-updater-2026-10-17/foundation-controls.json), with [reproducible source](../../prototype/MacUpdaterConsentSpike/network_policy/run.py), confirm that global `URLProtocol` registration rejects shared-session requests, explicit `protocolClasses` rejects configured-session requests, default configured sessions bypass registration, and cache injection cannot replace requests that explicitly ignore local cache. Apple's [shared session contract](https://developer.apple.com/documentation/foundation/urlsession/shared) and [`protocolClasses` contract](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/protocolclasses) explain the distinction; the [upstream maintainer](https://github.com/sparkle-project/Sparkle/issues/1509#issuecomment-562661151) also describes privately constructed downloader sessions and no injection API.

Pre-fetching/validating a feed and then letting Sparkle fetch it again would leave a second request and redirect race. Rewriting to a file URL is rejected by Sparkle's downloader, which accepts HTTP(S) only. Using a loopback HTTP relay would conflict with the present client-only/HTTPS/precise-entitlement contract. Swizzling, private APIs, a fork or alternate signature validation are not accepted workarounds.

**Decision:** preserve the requirements and stop product integration. The public cache handoff is useful evidence for revisiting the mechanism, not authority to relax the origin policy. Resolve the network seam and the interactive cancellation seam through a supported mechanism or a new explicit specification decision before reopening tickets 12–15. No product updater, release or website behavior was enabled.
