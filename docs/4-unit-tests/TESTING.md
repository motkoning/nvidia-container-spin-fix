# Testing Guidelines

## Test Framework

None. The project has no automated test suite (ARCHI.md §18): the highest-stakes paths (`-Mode Fix` / `-Mode Revert` / the GUI worker on an affected machine) can only be truly verified on affected hardware, and everything else is covered by parser syntax gates, read-only smoke runs, and review scrutiny.

## Running Verification

From the repo root (all four are safe on any machine):

```powershell
# Syntax-check both scripts with the Windows PowerShell 5.1 parser
powershell -NoProfile -Command '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "Fix-NvContainerSpin.ps1"),[ref]$null,[ref]$e); $e; if($e){exit 1}'
powershell -NoProfile -Command '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "easy-tool/NvidiaFixTool.ps1"),[ref]$null,[ref]$e); $e; if($e){exit 1}'

# Read-only diagnosis smoke run — must print a verdict
powershell -NoProfile -ExecutionPolicy Bypass -File Fix-NvContainerSpin.ps1

# GUI smoke check — constructs the form off-screen, must print "SelfTest OK"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File easy-tool/NvidiaFixTool.ps1 -SelfTest
```

Caveat: the parse check uses whichever PowerShell engine runs it and accepts PS7-only syntax that would break on end users' stock 5.1 — **5.1 compliance is a review check, not a gate** (ARCHI.md §18).

## Test Organization

No test files. Verification results are recorded as markdown summaries in `docs/4-unit-tests/wa_vx.y.z_test.md` per release (format in `.claude/skills/TRIP-test/SKILL.md`). Any Fix/Revert/worker change must be recorded there as **verified on affected hardware** or **explicitly deferred** — never silently assumed.

## Writing Tests

If logic ever grows enough to warrant automated tests (e.g. extracting the verdict matrix into a testable helper), Pester 5 is the natural framework — but adding dev-tooling is a deliberate architecture decision, and the shipped scripts must stay single-file and dependency-free regardless (ARCHI.md §5.4 applies to deliverables; dev tooling stays out of the shipped files).

## Coverage Requirements

Not defined — no coverage tooling. The critical-path floor is manual: changes touching Fix/Revert/worker behavior require on-hardware verification or an explicit deferral note in the test summary, plus full-depth code review (they touch AGENTS.md invariants).
