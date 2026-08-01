# Code Review: v1.2.0 review-fix release (8 findings from the retroactive review)

**Review Date**: 2026-08-01
**Version**: 1.2.0
**Files Reviewed**:
- Fix-NvContainerSpin.ps1
- easy-tool/NvidiaFixTool.ps1
- README.md
- easy-tool/ReadMe.txt
**Plan**: docs/1-plans/F_1.2.0_review-fixes.plan.md

---

## Executive Summary

Implements all 8 findings of the retroactive Codex review of v1.1.0: exit-code worker IPC (replacing cross-account-fragile file IPC), locale-neutral CIM CPU measurement with honest three-outcome verdicts, conflict state (detect + guide), pre-elevation consent dialog, dedicated post-Revert state, quoted CLI self-elevation, unified spin threshold, and SID-based ACL grants. Reviewed at **full depth** (mandatory: the change touches Fix/Revert/worker paths, AGENTS.md invariants, and owner-gated messaging) over **three fresh-context adversarial rounds** (Claude Opus reviewer; Sol authored — cross-vendor preserved). Verdict: **APPROVED with observations**.

---

## Changes Overview

Both delivery surfaces changed in lockstep plus documentation echoes. The worker now reports through an exhaustive (state × action) exit-code matrix read from the process object — no writable-file IPC remains. CPU measurement uses CIM Win32_Process Kernel+User time deltas (English-invariant, unelevated-readable) after round 1 proved the planned Get-Process mechanism silently fabricated 0% for SYSTEM processes; a null guard maps unreadable samples to a Failed outcome, never zero. The GUI gained a consent dialog (owner-pinned facts), a persistent post-Revert restart state, honest failure verdicts on Undo, and full-duration button disabling against DoEvents reentrancy (empirically proven effective in round 3).

---

## Findings

### Critical Issues

1. **Fabricated 0% measurement** (round 1) — Get-Process TotalProcessorTime silently reads $null for the SYSTEM-owned container processes unelevated; $null−$null=0 flowed through the guard as "Measured: 0%", silently disabling spin detection and falsifying the smoke gate. **Disposition: fixed** — plan amended; both helpers rewritten to CIM Win32_Process time deltas with an explicit null→Failed fabrication guard; a discriminating non-null gate check was added and passes; round 2 independently re-proved the mechanism against SYSTEM and protected processes. None remaining.

### Major Issues

1. **README verification snippet shared the Critical's defect** (round 1) — confirmed success unconditionally. **Disposition: fixed** — CIM-based guarded snippet, elapsed measured between snapshots, no-process branch added (round 3 polish).

### Minor Issues

1. Undo logged "Restored" on exit code 3 (round 1). **Fixed** — Invoke-Worker returns the exit code; post-Revert state only on 0, re-diagnosis on 3.
2. Undo double-click reentry via DoEvents (round 1). **Fixed** — handler disables buttons for its duration.
3. CLI rounded vs GUI unrounded threshold (round 1/2). **Fixed** — $oneCoreExact everywhere; rounding display-only.
4. ReadMe.txt stale step count (round 2). **Fixed** — step 3 describes the consent window.
5. Check-again button not disabled during Apply/Undo (round 2). **Fixed** — disabled for full handler duration incl. all exit paths; round-3 probe confirms no reentrancy.
6. Undo failures left stale reassuring verdict (round 2). **Fixed** — dedicated DarkOrange failure verdicts ($null vs non-null distinguished honestly).
7. **OPEN** — Apply-handler failure outcomes (codes 1/4/5/6/$null) leave the prior "Problem found" verdict standing; self-healing on next action, log lines are honest (easy-tool/NvidiaFixTool.ps1:466-477, round 3). Candidate for next patch: mirror the Undo failure-verdict pattern.
8. **OPEN** — for out-of-contract exit codes the default branch logs "couldn't confirm" but the Undo verdict claims "was not performed" (easy-tool/NvidiaFixTool.ps1:421-424 vs :500-502, round 3). Reachable only on abnormal elevated-host termination. Candidate one-line fix: default returns $null.

### Suggestions

- Fixed during the loop: CLI conflict abort hoisted pre-elevation; Fix/Revert no-op checks hoisted pre-elevation; scope-1 catch message covers helper-launch failure; README no-process branch.
- Open (accepted as-is or deferred): WaitForExit timeout bound (deferred design work; no regression vs v1.1.0); "Check again"/Form-Shown diagnosis reentrancy (pre-existing in v1.1.0, end-state stays consistent; one-line guard candidate); disable/re-enable pairs not exception-safe (try/finally candidate); `missing` state prompts UAC before failing; README snippet silent if all PIDs vanish mid-window; locale decimal separators (intentional — correct for viewer's locale).

---

## Checklist

- [x] 1. Functional Requirements — passed (all 8 planned findings implemented; round-1 Critical fixed and re-verified)
- [x] 2. Code Quality — passed (intentional dual-surface duplication maintained in lockstep)
- [x] 3. Architectural Compliance — passed (ARCHI.md §3/§7/§12/§13/§14/§16/§17 updates assigned to release Step 7 per plan)
- [x] 4. Safety Invariants — passed (Diagnose/-SelfTest provably write-free; single reversible rename; no service manipulation; elevation confined to Fix/Revert; grep-verified each round)
- [x] 5. PowerShell 5.1 & Deliverable Constraints — passed (no PS7 syntax any round; in-box CIM; single-file; pure ASCII; SelfTest green)
- [ ] 6. UX Copy & Docs Sync — passed with caveats (open Minors 7-8: Apply-side failure verdict + default-branch wording; all shipped copy honest and cross-surface facts synchronized)
- [x] 7. Error Handling — passed (three-outcome measurement, honest unknown-outcome handling, scope-separated catches)
- [x] 8. Security — passed (exit-code IPC removes writable-file surface; ValidateSet on inputs; no network/telemetry)
- [x] 9. Performance — passed (bounded sampling; GUI within its stated ~10 s budget)

---

## Verdict

**APPROVED with observations**

Three-round fresh-context adversarial loop (cap reached), full depth. Gate at convergence: syntax clean (both scripts, PS 5.1 parser) | CIM non-null discrimination probe OK | Diagnose smoke: real samples, correct verdict | SelfTest OK | unelevated worker precondition exits 2 per matrix. Open items: Minors 7-8 above (non-blocking, self-healing or rare-path; candidates for next patch) and the deferred on-hardware verifications recorded in the plan's Test Impact (real Fix/Revert renames, RunAs exit-code transport E2E, cross-account UAC, conflict state, live GUI dialog pass, localized-Windows run). ARCHI.md §12/§14 still describe the removed result file — assigned to release Step 7; must not slip.

