# Code Review: v1.2.2 — Declined-UAC verdict shows the known no-change outcome

**Review Date**: 2026-08-01
**Version**: 1.2.2
**Files Reviewed**:
- easy-tool/NvidiaFixTool.ps1
- docs/ARCHI.md (§12 clause, §16 diagram node)
**Plan**: no plan — trivial-lane patch closing the one open Minor from `docs/3-code-review/CR_w1_v1.2.1.md` (remedy sketched by that CR's reviewer)

---

## Executive Summary

The launch-failure catch in `Invoke-Worker` (UAC declined / helper could not start — the worker provably never ran) now returns a `'declined'` sentinel instead of `$null`, and both handlers show a DarkOrange "Nothing was changed - see details below." verdict for it — the verdict no longer under-claims an outcome the code knows. Readout failures keep `$null` → "Could not confirm what happened". **Depth: light review (one pass)**, escalation rule not triggered. Verdict: **APPROVED with observations**.

---

## Findings

### Critical / Major

None.

### Minor

1. `Invoke-Worker`'s return contract became `Int32 | 'declined' | $null` with no code-site documentation. **Fixed pre-release** — contract comment added above the function ("compare with -eq only").

### Suggestions (recorded, discretionary — none acted on except the diagram)

- Sentinel name `'declined'` is narrower than the branch (also fires when the helper cannot start); log, verdict, and ARCHI §12 are all accurate for either cause — naming observation only.
- §16 Fix-flow diagram node for launch failure described only the log — **fixed pre-release** (now names the orange verdict).
- Theoretical window where the catch could fire after a successful launch (process lookup racing an instant worker exit) — unreachable in practice; the underlying log line is pre-existing v1.2.0 behavior blessed by the 3-round review.
- The new verdict/log pair names no explicit next action (§15 tone rule); mitigated — the action buttons remain visible and re-enabled, and the replaced verdict named no action either.

Reviewer verifications of note: independent re-run of the full 9-value dispatch table through both handlers' exact branch chains on PS 5.1.26100 (correct routing, no throws — with the correction that `-eq` never throws on failed coercion in either operand order, making the string-first ordering defensive rather than load-bearing); "Nothing was changed" verified literally true on every path returning the sentinel (the catch wraps only `Start-Process`; the GUI process contains zero mutation code paths); exactly two consumers of the return value, both `-eq`-only; return purity confirmed; safety invariants untouched (worker block byte-identical).

---

## Checklist

- [x] 1. Functional Requirements — passed
- [x] 2. Code Quality — passed (contract comment added)
- [x] 3. Architectural Compliance — passed (§12/§16 in sync with code)
- [x] 4. Safety Invariants — passed (no mutation/elevation/service changes; worker untouched)
- [x] 5. PowerShell 5.1 & Deliverable Constraints — passed (parser-verified; pure ASCII; CRLF preserved)
- [x] 6. UX Copy & Docs Sync — passed (the under-claim this patch exists to fix is closed; no open copy items remain)
- [x] 7. Error Handling — passed (launch vs readout failure now distinguished end-to-end)
- [x] 8. Security — passed (not applicable surface)
- [x] 9. Performance — passed (not applicable surface)

---

## Verdict

**APPROVED with observations**

Light review, one pass. Gate at approval: syntax clean | `-SelfTest` OK | unelevated worker precondition exits 2 | 9-value sentinel dispatch probe correct on both handlers (independently re-verified by the reviewer). No open Minors remain across the v1.2.x series; the recorded suggestions above are discretionary future polish.
