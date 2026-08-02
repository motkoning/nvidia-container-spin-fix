# Code Review: v1.2.1 — Apply-handler failure verdicts and unknown-exit-code honesty

**Review Date**: 2026-08-01
**Version**: 1.2.1
**Files Reviewed**:
- easy-tool/NvidiaFixTool.ps1
- docs/ARCHI.md (§13 wording)
**Plan**: no plan — trivial-lane patch implementing the two open Minor observations from `docs/3-code-review/CR_w1_v1.2.0.md` (remedies specified verbatim by the v1.2.0 round-3 reviewer)

---

## Executive Summary

Closes the two Minors left open at v1.2.0: `Invoke-Worker`'s `default` branch now returns `$null` so out-of-contract exit codes land in the honest unknown-outcome path (matching the message it logs, and matching what ARCHI §14 already claimed), and the Apply handler mirrors the approved Undo failure-verdict pattern instead of leaving a stale "Problem found" verdict above a failure log. **Depth: light review (one pass)** — ~12-line patch mirroring an already-fully-reviewed pattern, no new design surface; the escalation rule applied but was not triggered. Verdict: **APPROVED with observations**.

---

## Findings

### Critical / Major

None.

### Minor

1. **OPEN** — on a declined UAC prompt, both handlers' `$null` branch shows "Could not confirm what happened" although the launch-failure log correctly states nothing was changed — the verdict under-claims where the outcome is known (easy-tool/NvidiaFixTool.ps1 launch-failure catch → handler `$null` branches). Inherited from the approved v1.2.0 Undo pattern, faithfully mirrored here per the specified remedy. Remedy if pursued (own change, touches approved code): distinguishable launch-failure return or inline verdict "Nothing was changed - permission was declined."

### Suggestions

- Fixed in this patch: ARCHI §13 "all three buttons" wording corrected (Apply disables the two visible in its state).
- Skipped (cosmetic, unreachable): the Apply handler's nominal pairing for exit code 3 — reviewer proved code 3 cannot arrive from the Fix action.

Reviewer verifications of note: "The fix was not applied" is literally true for every code reaching that branch (4/5/6 exit pre-mutation; 1 implies the rename did not complete; 3 unreachable); `default`→`$null` breaks no caller (both call sites test ints before `$null`, verified on PS 5.1); new lines are PS 5.1-clean; safety invariants untouched; the patch closes a shipped code-vs-doc divergence (§14 already promised this behavior).

---

## Checklist

- [x] 1. Functional Requirements — passed
- [x] 2. Code Quality — passed
- [x] 3. Architectural Compliance — passed (code now matches §14; §13 corrected)
- [x] 4. Safety Invariants — passed (no mutation-logic, elevation, or service changes)
- [x] 5. PowerShell 5.1 & Deliverable Constraints — passed (parser-verified)
- [ ] 6. UX Copy & Docs Sync — passed with caveat (open Minor above: declined-UAC verdict under-claim)
- [x] 7. Error Handling — passed
- [x] 8. Security — passed (not applicable surface)
- [x] 9. Performance — passed (not applicable surface)

---

## Verdict

**APPROVED with observations**

Light review, one pass, escalation rule not triggered. Gate at approval: syntax clean (both scripts) | CIM non-null discrimination probe OK | Diagnose verdict correct | SelfTest OK | unelevated worker precondition exits 2. Fresh on-hardware context the same day: elevated RunAs exit-code transport verified end-to-end (mutation-free), live owner GUI pass OK (recorded in `docs/4-unit-tests/w1_v1.2.0_test.md`). Open item: the declined-UAC verdict under-claim (Minor, both handlers) — candidate for a future patch as its own change.
