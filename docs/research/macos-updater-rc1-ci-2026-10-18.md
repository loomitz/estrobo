# RC1 native confirmation validation

The first public PR checks found a false failure in `UpdatePresentationCheck` on both macOS 15 ARM and Intel. The test located the correct accessible confirmation button, with `AXPress` advertised, but `AXUIElementPerformAction` returned `attributeUnsupported` after invoking its action and dismissing the native alert. A diagnostic followed by the unchanged state assertions observed exactly one installation and the installing stage. Waiting longer did not change the result.

The test now verifies the button role and supported action before dispatch. Only the specific `attributeUnsupported` result can be accepted after the original attached sheet has actually disappeared, with a bounded two-second wait. Other failures still fail the test. The existing assertions still require exactly one installation for the accepted offer, no installation before consent, cancellation requiring new consent, and rejection of a stale dialog for a different downloaded offer.

No product code, confirmation copy, entitlement, release authority or CI protection changed. The reduced diagnostic workflow and temporary instrumentation are excluded from the product branch.

Evidence:

- Before: [original ARM and Intel CI](https://github.com/loomitz/estrobo/actions/runs/39195483495).
- Diagnostic: [action dispatched despite AX error](https://github.com/loomitz/estrobo/actions/runs/39196732562), with `installations=1, stage=installing` after the reported error.
- After: [focused macOS 15 ARM execution](https://github.com/loomitz/estrobo/actions/runs/39196920972) passed the complete presentation flow and capture batch.
- Local macOS 27.0.1, full Xcode beta: `make -C prototype/EstroboMac test-update-presentation` passed using the verified Sparkle 2.10.0 cache. Radio transport and update service are controlled fixtures.

The normal protected PR checks will validate the final commit on both native architectures. These are source/fixture checks, not proof of a notarized production upgrade or physical Bluetooth smoke.

## Selected Xcode portability

The next full ARM run passed presentation, composition and product scenes, then exposed a separate tool configuration bug: `run-update-error-recovery.py` substituted this workstation's `/Applications/Xcode-beta.app/Contents/Developer` when `DEVELOPER_DIR` was absent. GitHub's selected full Xcode is installed elsewhere. The same fallback existed in signature verification and its narrow fixture drivers.

These six tool environments now inherit the caller's environment. Explicit `DEVELOPER_DIR` remains respected, and an unset value allows `xcrun` to use the selected Xcode. No machine-wide Xcode selection is changed. The failing evidence is [full ARM run 39197097070](https://github.com/loomitz/estrobo/actions/runs/39197097070), after the native confirmation fix had passed.
