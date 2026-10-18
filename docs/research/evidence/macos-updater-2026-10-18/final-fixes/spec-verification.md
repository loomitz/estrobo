## Spec — focused verification

Reviewed clean commit `3acb7cc4f4aa5b2eb3e7207066c92f095b8753b7` against `dda8798e34d2ecd8f1a9e3e05996162fdbb10160`, limited to the same two original findings and regressions directly caused by their fixes.

- **Spec #1 — RESOLVED.** `SparkleUpdateService.swift:411–422` now uses named public `SUError` cases: translocation maps to location recovery; file-copy/authentication failures map to installation recovery. The ES/EN messages explain moving the app or checking installation permissions. The new native test observes `showUpdaterError` through `UpdateService.check`, and its retained log records **13/13 PASS**, including cancellation, nested signature and authorization-cancellation precedence. The mapping change preserves the previous classifications of other existing cases.
- **Spec #2 — RESOLVED.** `macos-update-catalog.py:43–49,68,266–267` applies the same 64 MiB archive and 16,384 UTF-8-byte note bounds as the consumer. Prepare validates before approval/signing; approve and site share catalog validation. The public CLI tests and **5/5 PASS** log cover exact accepted limits, archive +1 byte, ASCII/multibyte notes +1 byte, and early prepare/approve rejection.

**Evidence identity verified:** all **13 source hashes** and **23 evidence hashes** match the committed manifest. Both current product binaries, notice hashes, bundle metadata and absence of `SUPublicEDKey` match its product records. The retained current-source check/universal and precise bundle-verification logs support local compilation and development-only artifacts; their embedded base SHA is explicitly distinguished from the fixes identified by source hashes.

The acceptance update correctly retains the real **26-case `fd4cc73` baseline** as historical evidence and identifies the later deterministic mapping delta separately. HTTP, lifecycle and the real-adapter host are unchanged. Synthetic callback results are expressly not proof of real translocation, privileged authorization or production sandbox replacement. Distribution gates remain pending.

**Resolved IDs: Spec #1, Spec #2. Open IDs: none. Directly caused regressions identified: none.** No suites were rerun and no repository files were changed. These two findings can be closed by the same implementer.
