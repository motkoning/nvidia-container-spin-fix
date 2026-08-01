---
name: TRIP-test
description: Write/run tests following project standards (deep test authoring)
disable-model-invocation: true
argument-hint: "component or feature to test"
---

# Testing Mode

You are now in **testing mode** for **nvidia-container-spin-fix**.

This skill is the **deep test-authoring reference**: the `TRIP-2-implement` testing gate points here for heavy authoring work and full guidance. Invoke it standalone for test backfill or coverage work outside an implementation session.

## Prerequisites - Read First

Before testing, you MUST read:

1. @docs/ARCHI.md - Understand system architecture
2. @docs/4-unit-tests/TESTING.md - Testing guidelines

## Your Task

Test: $ARGUMENTS

---

## Testing Guidelines

### Scope

- Only run tests for relevant files that changed (not the whole project)
- Focus on the new feature/fix/refactor

### Commands

There is **no automated test framework** (ARCHI.md §18). Verification = parser syntax checks + read-only smoke runs; run all four from the repo root:

```bash
# Syntax-check both scripts with the Windows PowerShell 5.1 parser
powershell -NoProfile -Command '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "Fix-NvContainerSpin.ps1"),[ref]$null,[ref]$e); $e; if($e){exit 1}'
powershell -NoProfile -Command '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "easy-tool/NvidiaFixTool.ps1"),[ref]$null,[ref]$e); $e; if($e){exit 1}'

# Read-only diagnosis smoke run (safe on any machine — prints a verdict)
powershell -NoProfile -ExecutionPolicy Bypass -File Fix-NvContainerSpin.ps1

# GUI smoke check (constructs the form off-screen, prints plugin state, exits without showing a window)
powershell -NoProfile -ExecutionPolicy Bypass -STA -File easy-tool/NvidiaFixTool.ps1 -SelfTest
```

### Test Structure

No test files exist. Verification results are recorded as markdown summaries in `docs/4-unit-tests/wa_vx.y.z_test.md` (see Post-Testing Summary below); deferred on-hardware verification of Fix/Revert/worker paths is recorded there explicitly. If automated tests are ever introduced, that is a deliberate architecture decision (Pester 5 is the natural choice) — the shipped scripts must stay dependency-free either way.

### Testing Priorities

**Smoke checks (every change)**:

- Both scripts parse under Windows PowerShell 5.1
- `Fix-NvContainerSpin.ps1` (Diagnose, read-only) completes and prints a verdict
- `NvidiaFixTool.ps1 -SelfTest` prints `SelfTest OK` with a plugin state

**Manual verification (when the change warrants it)**:

- GUI interaction pass via START-HERE.bat on a machine with a display: verdict states, button visibility/morphing, copy
- Fix/Revert behavior — only on affected hardware, **one experiment per reboot** (ARCHI.md §10); record as performed or explicitly deferred

**What to verify by reading (no runner catches these)**:

- PowerShell 5.1-only syntax (parser accepts PS7-isms)
- Read-only invariant on all Diagnose paths
- Both copies of intentionally duplicated helpers updated together
- Failure messages honest on every error path ("nothing was changed" only when true)

**What to Test** (for any logic change):

- The (spin × pluginState) verdict matrix: every reachable combination maps to the intended verdict/buttons
- Edge cases: no driver, plugin missing, container not running, counter failure, declined UAC, missing/stale worker result file

---

## Hard-to-Test Code

Seam ladder, cheapest first: **exported pure helper → injectable client/adapter → module mock → integration/emulator test**. Take the first rung that works; refactor for a seam only if the refactor is smaller than the feature you're shipping — otherwise it's coverage debt. Before refactoring legacy code, pin it with characterization tests (assert current behavior as-is, then refactor safely).

Uncovered risky paths: one line each in `docs/4-unit-tests/COVERAGE-DEBT.md` (`path | why hard | escape plan`). Delete a ledger line in the same change that gives its path meaningful coverage.

---

## Post-Testing Summary

After completing tests, create a summary file:

**File**: `docs/4-unit-tests/wa_vx.y.z_test.md`
(a = project week, x.y.z = version)

**Content**:

```markdown
# Test Summary - Week a, V. x.y.z

## What Was Tested

[List of tested components/functions]

## Test Results

- Total tests: X
- Passed: X
- Failed: X
- Coverage: X%

## Key Findings

[Any issues discovered, edge cases found, etc.]

## Notes

[Additional context or recommendations]
```
