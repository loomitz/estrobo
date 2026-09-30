# Estrobo iOS App Store Wayfinder

Status: Bootstrapped on 2026-08-31; source consolidation resumed on 2026-09-29

Frontier: #1 only

End state: a reproducible signed candidate, an internal TestFlight pilot, an optional external beta, App Store acceptance, and only then an optional history-preserving open-source repository extraction.

This file is the canonical decision map. Load it in full at the start of every Wayfinder session, resolve only one frontier ticket per session, and update dependencies when an answer changes the map. Downstream tickets intentionally describe gates and evidence, not predetermined implementations.

## Evidence model

Keep these gates separate:

1. **Source candidate:** reviewed commits, known upstream, and fresh-clone reproducibility.
2. **Automation:** shared Swift, unit, UI, metadata, Release, and unsigned archive evidence from stable Xcode, including the declared iOS 18 family.
3. **Signed candidate:** final App ID, Team, version, Apple Distribution signing, archive, validation, and export.
4. **Physical evidence:** permission, selection, connection, `Psub`/`PWOK`/Sync, GATT, `FEC8`, optical result, disconnect, recovery, and Forget/Keychain evidence recorded independently.
5. **Internal pilot:** one exact processed build, What to Test, public feedback route, testers, diagnostics policy, and exit criteria.
6. **Store package:** privacy, public support, metadata, screenshots, rating, compliance, and hardware-dependent review notes.
7. **Submission:** explicit human authorization, exact build selection or upload, and submission to App Review.
8. **Acceptance:** Apple observations resolved and the public state independently verified.

An unsigned archive is not a signed candidate. Installation is not connection. Connection is not GATT delivery. GATT is not `FEC8`. `FEC8` is not an optical result. Repository extraction substitutes for none of these gates.

## Consolidation snapshot — 2026-09-29

- The user requested completion and local consolidation of pending macOS and iOS work into one branch before assessing production readiness. The integration branch is `codex/integration-20260929`; the iOS WIP was preserved as local commit `b4c6e6f` before integration. This request does not authorize an Apple upload, distribution or physical radio operation.
- The integration preserves the native macOS shell under `prototype/EstroboMac` and the shared `Sources/EstroboCore`, `Sources/EstroboBluetooth` and `Sources/EstroboPersistence` modules. iOS visual-identity imports now use the renamed macOS path.
- Privacy and security wording now distinguishes the published macOS Beta 4 plaintext opt-in storage from the candidate's device-only Keychain vault. Bluetooth documentation distinguishes the historical 2026-08-30 installation from the new candidate, which requires its own installation and physical results.
- Settings now links to the candidate's privacy/support documents on `codex/integration-20260929`, so a published source branch can expose the matching contract. Before distribution, pin those links to the reviewed release tag or commit and verify them from the exact binary. A qualifying public support contact remains a release gate; local documentation edits do not satisfy publication.
- The available toolchain remains Xcode 27 beta with iOS 26/27 runtimes. Development verification with that toolchain must be recorded separately from the required stable-Xcode and iOS 18 gates. No signed candidate, TestFlight upload, App Store submission or new physical validation occurred in this consolidation.

The bootstrap observations below describe 2026-08-31 and are retained as history. They are not the current branch status or evidence for the consolidated candidate. Frontier #1 remains open until the final committed source and its new result artifacts are reconciled.

## Bootstrap snapshot — 2026-08-31

### Git history

- After `git fetch --prune origin`, `codex/ios-app` is at `0bbc4a485f92ed066f61a7717a71c33348752202`, zero commits behind and five ahead of `origin/main` at `c1e67ce58d2c7218e5c7448a7e299ffa0e5402cb`.
- The branch has no upstream, is absent from the remote heads, and has no current or historical pull request. Local `main` is stale and is not an authority for this map.

### Unpublished local WIP

- Before this map was created, the worktree contained 50 modified, 4 deleted, and 27 untracked files, with no staged paths. The tracked working-tree diff covered 54 files and was not altered by the bootstrap.
- The map path did not previously exist and did not overlap existing WIP. The local iOS workflow, RC0 checklist, Bluetooth evidence, and several application/support changes are not yet versioned or published.

### Local evidence

- Source currently declares `mx.loo.estrobo.dev`, `0.1.0 (1)`, iOS 18.0, iPhone/iPad, an empty `DEVELOPMENT_TEAM`, and two direct source imports from the macOS prototype tree.
- The existing Release archive is arm64, contains its privacy manifest, assets, and matching dSYM, and is deliberately unsigned. There is no export configuration or IPA. The current credential-free archive lane must remain separate from a future signed/export lane.
- The available local toolchain is Xcode 27 beta with iOS 26/27 runtimes, not the stable Xcode 26.6 and iOS 18.5 tools described by the local workflow.
- Historical local reports are not one coherent candidate ledger: the bootstrap brief cites 62/62 shared tests, 31/31 unit tests per idiom, 3/3 smoke tests per idiom, and 26 iPhone UI passes, while the mandatory physical matrix records an older 60/60, 30/30, and 23/24 plus a focused rerun. No suite was rerun during bootstrap; #1 must tie every claim to an exact source state and result artifact.
- A development build was installed on an iPhone, but the current application has no attributable complete physical power-control result. Three attempts stopped before GATT, `FEC8`, and optical effect could be established; Test and Multi were not executed.

### GitHub evidence

- GitHub has no `codex/ios-app` branch, PR, or run. The latest general repository runs belong to other refs and are not iOS candidate evidence.
- `.github/workflows/ios-ci.yml` exists only as untracked local WIP, so its stable-Xcode, iOS 18.5, UI, Release, and unsigned-archive lanes are a design, not executed GitHub evidence.

### Work not yet performed

- No final Apple Developer Team, App ID, bundle identifier, version/build policy, Apple Distribution export, TestFlight upload, App Store submission, public support contact, feedback email, open-source license, or iOS repository extraction has been completed.
- The local privacy/support/security/notices set is not yet a coherent public iOS contract: Settings points to `main`, while relevant local revisions are unpublished; support has no public email; Keychain wording conflicts with `SECURITY.md`; and the Bluetooth evidence contains superseded installation wording.

## Map rules

- Preserve all unrelated WIP. Never use broad staging, stash, reset, checkout restoration, clean, switch, or rebase as part of a ticket.
- Ask exactly one short human question per turn. Stop for every Team, bundle ID, public contact, license, compatibility claim, Test/Multi, data-use, repository, Git publication, Apple-account, signing, physical-operation, TestFlight, tester-invitation, or submission decision.
- Apple Research tickets must use official Apple sources and record the consultation date. Never store Apple IDs, private email addresses, certificates, profiles, keys, Radio Codes, tokens, or other secrets in this map.
- Test and Multi remain excluded from pilot claims until their own authorized optical evidence exists.
- If an optional path is declined, resolve or remove its dependent nodes rather than pretending the work occurred.

## #1: Establish the candidate and evidence ledger

Blocked by: None
Type: Research

### Question

Which exact committed paths, uncommitted paths, generated artifacts, historical test results, installed builds, physical observations, and GitHub artifacts belong to one proposed iOS source candidate, and which are stale, contradictory, unrelated, or excluded? Output evidence: a dated, secret-free ledger keyed by commit/diff and artifact identifiers, including the iOS 26.1 diagnostic spike decision and reconciled Bluetooth-installation provenance, without staging or modifying production files.

### Answer

Pending

## #2: Approve the source boundary and review plan

Blocked by: #1
Type: Discuss

### Question

What exact candidate path list, exclusions, and small commit sequence should become RC0, and is that scoped commit, branch, push, and pull-request plan explicitly authorized? Output evidence: one approved boundary and review plan that preserves every unrelated WIP path and forbids broad staging.

### Answer

Pending

## #3: Prove a reviewable and reproducible source candidate

Blocked by: #2
Type: Prototype

### Question

Can the approved candidate be represented by reviewed, path-scoped commits on a known upstream and reproduced from a fresh clone with XcodeGen 2.46.0, both localizations, public-link tests, and no undeclared local source? Output evidence: commit/path manifest, remote/PR identifiers, clean-clone commands and results, and before/after proof that unrelated WIP stayed untouched.

### Answer

Pending

## #4: Validate stable automation for the exact candidate

Blocked by: #3
Type: Prototype

### Question

Does the exact reviewed candidate pass shared Swift, metadata, iPhone/iPad unit tests, focused and full UI tests, generic Release, and credential-free archive gates with stable Xcode, including the declared iOS 18 family and an explicit disposition of the iOS 26.1 spike? Output evidence: tool/runtime versions, commands, result bundles, archive checks, and GitHub run URLs tied to the candidate SHA.

### Answer

Pending

## #5: Establish Apple program and Team prerequisites

Blocked by: #1
Type: Research

### Question

Which eligible Apple Developer organizations or teams can own Estrobo iOS, and which membership, legal, tax, banking, and agreement states must be active for TestFlight and App Store distribution? Output evidence: an option matrix based only on official Apple documentation with consultation date, recording no Apple IDs, private contacts, credentials, or secrets.

### Answer

Pending

## #6: Select the owning Apple Developer Team

Blocked by: #5
Type: Discuss

### Question

Which eligible Apple Developer Team should own Estrobo iOS through pilot and App Store acceptance? Output evidence: one explicit human decision and its non-secret ownership rationale; no Apple-account change is authorized merely by recording the answer.

### Answer

Pending

## #7: Select the final bundle identifier and App ID boundary

Blocked by: #6
Type: Discuss

### Question

What final explicit bundle identifier and App ID capability boundary should replace `mx.loo.estrobo.dev`, including the consequences for containers, Keychain identity, development builds, tests, and the foreground-only Bluetooth contract? Output evidence: one explicit human decision with migration and retest requirements, without changing Apple Developer or source state.

### Answer

Pending

## #8: Define marketing-version and build-number policy

Blocked by: #7
Type: Discuss

### Question

What marketing version should identify the first pilot and App Store release, and what monotonic build-number policy should cover local, TestFlight, rejected, and resubmitted builds? Output evidence: one explicit versioning policy with examples and the next authorized version/build pair.

### Answer

Pending

## #9: Produce and verify the signed candidate

Blocked by: #4, #6, #7, #8
Type: Prototype

### Question

After separate explicit authorization for Apple-account changes and real signing, can a dedicated lane register or use the final App ID, create an Apple Distribution archive, validate it, and export the App Store artifact without weakening the unsigned archive gate? Output evidence: official-Apple-source consultation date, exact source SHA/version/build, non-secret signing and entitlement verification, archive/export logs, artifact digest, and proof that the new bundle identity receives fresh physical validation.

### Answer

Pending

## #10: Decide pilot diagnostics and data policy

Blocked by: #1
Type: Discuss

### Question

Should the iOS candidate preserve the current no-network, no-analytics, no-telemetry, and no-remote-crash-reporting contract, and what strictly tester-initiated redacted diagnostics may be requested during pilots? Output evidence: one explicit policy covering collection, retention, deletion, consent, and prohibited Radio Code, authentication, UUID, and personal data.

### Answer

Pending

## #11: Select public support and feedback contacts

Blocked by: #1
Type: Discuss

### Question

What public contact set will Estrobo use for the Support URL and TestFlight feedback, and what non-secret role will handle App Review communication? Output evidence: explicitly approved public-facing contact values and ownership, while private email addresses and Apple-account details remain outside this map.

### Answer

Pending

## #12: Reconcile privacy, encryption, and App Privacy

Blocked by: #9, #10
Type: Research

### Question

For the exact signed binary and approved data policy, are the privacy manifest, Keychain statements, App Privacy answers, tracking/collection declarations, required-reason APIs, and export-compliance/encryption answers accurate and mutually consistent? Output evidence: binary/source audit, contradiction list, proposed answers, and links to official Apple documentation with consultation date.

### Answer

Pending

## #13: Publish and verify the public support contract

Blocked by: #3, #11, #12
Type: Prototype

### Question

After explicit authorization for each commit, push, PR, merge, and documentation publication, can the English/Spanish privacy, support, security, third-party notices, and in-app URLs be made mutually consistent and verified from the exact build against public `main` URLs? Output evidence: reviewed diffs, publication identifiers, anonymous HTTP checks, in-app link checks, and proof that no private contact or secret was published.

### Answer

Pending

## #14: Define localized App Store metadata

Blocked by: #7, #10, #11, #12
Type: Research

### Question

What category, age rating, name/subtitle, description, keywords, promotional text, localization set, privacy URL, support URL, and compliance metadata accurately describe the bounded hardware-dependent app without unsupported compatibility claims? Output evidence: a length-checked English/Spanish metadata draft based on official Apple documentation with consultation date.

### Answer

Pending

## #15: Produce final iPhone and iPad screenshots

Blocked by: #9, #14
Type: Prototype

### Question

Can the exact candidate produce truthful, localized, current-size iPhone and iPad screenshots without secrets, debug state, unsupported hardware claims, or stale UI? Output evidence: device/OS and build identifiers, deterministic capture steps, required-size inventory, visual review, and final asset hashes.

### Answer

Pending

## #16: Verify the App Review Demo Mode path

Blocked by: #9, #10
Type: Prototype

### Question

Can a reviewer launch a clean install, enter Demo Mode without hardware or private credentials, exercise the material iPhone/iPad flows, leave Demo Mode without touching live Keychain or recovery state, and understand which features require hardware? Output evidence: clean-container scripted and visual walkthroughs tied to the exact build, with failures and exclusions recorded.

### Answer

Pending

## #17: Authorize the bounded physical smoke

Blocked by: #9
Type: Discuss

### Question

Is the exact signed candidate authorized for the minimum physical matrix on named iPhone/iPad, OS, transmitter, flash, firmware, safe power, and radio-exclusivity conditions, excluding Test and Multi? Output evidence: one explicit human authorization, operator responsibilities, stop conditions, and a secret-free run sheet.

### Answer

Pending

## #18: Execute the minimum physical evidence gate

Blocked by: #17
Type: Prototype

### Question

Does the exact signed candidate pass fresh permission and denial, selection, connection, `Psub`/`PWOK`/Sync, A0-before-A1, one final-value power change, GATT, `FEC8`, optical result, disconnect, foreground recovery, uncertain-write behavior, Forget/Keychain, and required iPhone/iPad/iOS 18 coverage? Output evidence: a sanitized matrix that records installation, connection, GATT, `FEC8`, and optical result separately and stops on any unreliable control.

### Answer

Pending

## #19: Approve public compatibility claims and Test/Multi scope

Blocked by: #18
Type: Discuss

### Question

Which exact transmitter, flash, firmware, platform, and operating-system claims are supported by the physical evidence, and should Test or Multi be included in any pilot claim? Output evidence: one explicit human decision with an allowed/forbidden claims matrix and a separate go/no-go for Test and Multi.

### Answer

Pending

## #20: Validate any authorized Test and Multi claims

Blocked by: #19
Type: Prototype

### Question

If #19 authorizes inclusion, do Test and Multi pass their own safe, minimum-power optical protocol on the exact candidate without queueing, retry, intermediate writes, or ambiguous outcomes? Output evidence: separate authorization, GATT, `FEC8`, optical, recovery, and stop records; otherwise record that the features remain excluded and perform no flash operation.

### Answer

Pending

## #21: Prepare hardware-dependent App Review notes

Blocked by: #11, #14, #16, #19, #20
Type: Research

### Question

What concise App Review notes explain Demo Mode, optional hardware, tested compatibility boundaries, Bluetooth permission, foreground-only behavior, safe review steps, support route, and excluded Test/Multi claims without exposing credentials? Output evidence: an English draft checked against official Apple review guidance with consultation date and the exact candidate behavior.

### Answer

Pending

## #22: Define the internal TestFlight pilot

Blocked by: #9, #12, #13, #19, #20, #21
Type: Research

### Question

What exact build, internal tester cohort, What to Test text, public feedback route, redacted diagnostic procedure, duration, stop rules, and measurable exit criteria define a bounded internal pilot? Output evidence: a pilot runbook based on official Apple TestFlight documentation with consultation date, containing no private tester data.

### Answer

Pending

## #23: Distribute the exact internal pilot build

Blocked by: #22
Type: Prototype

### Question

After one-at-a-time explicit authorization for the TestFlight upload and tester invitations, can the exact signed artifact be uploaded, processed, selected, configured with approved What to Test and feedback data, and distributed only to the approved internal cohort? Output evidence: source SHA, artifact digest, App Store Connect build identity, processing result, sanitized tester count, timestamps, and rollback/stop state.

### Answer

Pending

## #24: Decide whether the internal pilot passed

Blocked by: #23
Type: Research

### Question

Did the exact distributed build satisfy every pilot exit criterion, and what redacted tester-initiated feedback, reproducible defects, physical evidence, and privacy observations remain? Output evidence: a build-specific go/no-go report that does not infer analytics and creates new remediation tickets for unresolved failures.

### Answer

Pending

## #25: Decide whether to run an external beta

Blocked by: #24
Type: Discuss

### Question

Does the internal-pilot evidence justify an external TestFlight beta, and if so what bounded audience, compatibility claims, duration, risk controls, and exit criteria are acceptable? Output evidence: one explicit human go/no-go decision; a no-go keeps the App Store path open without pretending an external beta occurred.

### Answer

Pending

## #26: Run the optional external TestFlight review and beta

Blocked by: #14, #15, #16, #21, #25
Type: Prototype

### Question

If #25 is go, and after explicit authorization for App Store Connect changes, TestFlight App Review, upload, and invitations, can the external-beta package pass Apple's beta review and meet its approved exit criteria? Output evidence: official Apple documentation and consultation date, submitted metadata/build identity, review outcome, sanitized cohort evidence, and go/no-go report; otherwise record the path as not selected and perform no external action.

### Answer

Pending

## #27: Audit the final Store package

Blocked by: #13, #14, #15, #16, #21, #24, #26
Type: Research

### Question

Is one exact candidate fully represented by the public privacy/support contract, App Privacy and export answers, localized metadata, age rating, screenshots, Demo Mode, review notes, pilot evidence, compatibility claims, and processed build? Output evidence: a zero-ambiguity checklist against official Apple documentation with consultation date, immutable identifiers, and every gap marked unresolved rather than waived.

### Answer

Pending

## #28: Authorize final App Store submission

Blocked by: #27
Type: Discuss

### Question

Is the exact audited build and Store package authorized for final upload or selection and submission to App Review? Output evidence: one explicit human decision naming immutable build/package identifiers, release mode, stop conditions, and any timing constraint, without recording private Apple-account data.

### Answer

Pending

## #29: Submit the authorized build to App Review

Blocked by: #28
Type: Prototype

### Question

Can the exact authorized build be uploaded if necessary, selected, validated with its final metadata, and sent to App Review without substituting artifacts or changing claims? Output evidence: App Store Connect build/version identity, artifact digest, validation result, submission timestamp/state, and a record of every external change.

### Answer

Pending

## #30: Resolve Apple observations and verify acceptance

Blocked by: #29
Type: Research

### Question

What did Apple return for the submitted build, what new tickets are required for any issue without bypassing earlier gates, and when accepted is the approved version publicly available in the intended storefronts? Output evidence: official review-state history, resolution links, public listing checks, version/build identity, and acceptance date.

### Answer

Pending

## #31: Observe the published release

Blocked by: #30
Type: Research

### Question

During the bounded post-publication window, do public links, installation, launch, Demo Mode, support intake, privacy claims, and approved hardware behavior remain consistent for the accepted build without adding analytics? Output evidence: dated storefront and smoke checks, redacted support findings, rollback criteria, and follow-up tickets.

### Answer

Pending

## #32: Select an open-source license

Blocked by: #30
Type: Discuss

### Question

Should Estrobo iOS be released as open source, and if so which license and contribution boundary cover application code, shared modules, assets, trademarks, protocol research, and third-party notices? Output evidence: one explicit human decision informed by qualified legal review where needed; no repository publication is authorized merely by choosing a license.

### Answer

Pending

## #33: Decouple iOS from macOS-owned source paths

Blocked by: #30
Type: Prototype

### Question

Can the two iOS source imports under the macOS prototype tree and any remaining repository-relative assumptions be moved behind an owned shared-module boundary without changing behavior or breaking either platform? Output evidence: reviewed dependency graph, focused cross-platform tests, source-path audit, and fresh-clone builds; this work must not retroactively block the completed internal pilot.

### Answer

Pending

## #34: Decide whether to extract an iOS repository

Blocked by: #32, #33
Type: Discuss

### Question

Should `estrobo-ios` become a separate repository now, and what history, issues, releases, shared-code ownership, security policy, public links, and ongoing macOS synchronization contract must be preserved? Output evidence: one explicit human go/no-go and repository-creation/publication authorization with a migration and rollback plan.

### Answer

Pending

## #35: Execute and verify the history-preserving extraction

Blocked by: #34
Type: Prototype

### Question

If #34 is go, can the authorized extraction preserve the approved history and license, reproduce the accepted iOS build, run CI, keep public/support/security links valid, and leave the original repository in a documented non-ambiguous state? Output evidence: old/new commit mapping, remote and default-branch identifiers, fresh-clone gates, CI URLs, link checks, and rollback evidence; otherwise perform no repository action.

### Answer

Pending
