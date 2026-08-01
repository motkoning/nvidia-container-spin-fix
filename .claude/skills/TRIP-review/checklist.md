# Code Review Checklist

This file is the **single source of truth** for code-review criteria. Both human-driven reviews via `.claude/skills/TRIP-review` and Codex-driven reviews via `.claude/skills/codex-code-review` apply the criteria below — referenced, not copied — so the two review surfaces cannot drift.

## Systematic Review Checklist

### 1. Functional Requirements

- [ ] Implementation logic matches requirements correctly
- [ ] Interface/API matches documented specifications
- [ ] Error scenarios handled with proper feedback
- [ ] Edge cases and boundary conditions validated

### 2. Code Quality

- [ ] Proper typing (no unjustified dynamic types)
- [ ] DRY principle - no code duplication
- [ ] KISS principle - not unnecessarily complex
- [ ] Consistent, descriptive naming conventions
- [ ] Complex logic has explanatory comments
- [ ] Files/modules not excessively large
- [ ] Imports/includes organized, unused ones removed

### 3. Architectural Compliance

- [ ] Code follows established patterns from ARCHI.md
- [ ] Proper separation of concerns
- [ ] Appropriate abstractions used
- [ ] Consistent with existing codebase style

### 4. Safety Invariants (ARCHI.md §5 — any violation is Critical)

- [ ] Diagnose paths (CLI Diagnose, GUI diagnosis, `-SelfTest`) remain strictly read-only — no writes, renames, elevation, or state changes
- [ ] Fix remains a rename to `.off` — nothing deleted, nothing else modified — and Revert exactly undoes it
- [ ] No code starts, stops, or restarts the NVIDIA container service or kills its processes; the "change file, tell user to reboot" contract is intact
- [ ] Any change to what Fix/Revert touches on end users' machines was explicitly sanctioned by the plan (owner: Richard Wilken) — not introduced by the implementer
- [ ] Elevation scope unchanged: only Fix/Revert elevate; the GUI process itself never elevates; Diagnose never elevates

### 5. PowerShell 5.1 & Deliverable Constraints

- [ ] No PS7-only syntax (ternary, `??`, `?.`, `&&`/`||` pipeline chains) — the parser gate does not catch these; verify by reading the diff
- [ ] No modules, no external dependencies, no internet access, no extra files required at runtime
- [ ] Each shipped script remains self-contained single-file; intentionally duplicated helpers updated in BOTH copies where the behavior change applies
- [ ] easy-tool still double-click launchable via START-HERE.bat; `-SelfTest` still passes

### 6. UX Copy & Docs Sync (ARCHI.md §15)

- [ ] User-facing strings follow the plain-English tone rules; failure messages only claim "nothing was changed" when literally true
- [ ] Facts that echo across surfaces (what you lose, driver-update reversion, reboot contract, rename-not-delete) updated everywhere in this change
- [ ] Release-asset names and README download links untouched (or transitioned per ARCHI.md §22)

### 7. Error Handling

- [ ] Errors are properly caught and handled
- [ ] Error messages are clear and actionable
- [ ] Failure modes are graceful
- [ ] Logging is appropriate (not too verbose, not silent)

### 8. Security (if applicable)

- [ ] Input validation implemented
- [ ] No sensitive data exposed
- [ ] Authentication/authorization respected
- [ ] No obvious vulnerabilities

### 9. Performance

- [ ] No obvious performance issues
- [ ] Resource cleanup implemented (no leaks)
- [ ] Appropriate data structures used
- [ ] No unnecessary operations in hot paths

---

## Issue Severity Classification

**Critical (Block Deployment)**:

- Security vulnerabilities
- Data corruption risks
- Breaking API/interface changes
- Authentication bypasses

**Major (Require Immediate Fix)**:

- Incorrect business logic
- Significant performance degradation
- Missing error handling
- Compilation/build errors

**Minor (Should Fix)**:

- Code style inconsistencies
- Missing documentation
- Code duplication
- Missing edge case handling

**Suggestions (Nice to Have)**:

- Performance optimizations
- Readability improvements
- Additional test coverage

---

## Review Completion Criteria (Approval Gate)

Minimum for approval:

- [ ] All functional requirements implemented
- [ ] No critical or major issues remaining
- [ ] Both scripts pass the PowerShell 5.1 parser syntax gate
- [ ] Read-only smoke runs pass: `Fix-NvContainerSpin.ps1` (Diagnose) prints a verdict; `NvidiaFixTool.ps1 -SelfTest` prints `SelfTest OK` (per the TRIP-2 testing gate)
- [ ] Changes touching Fix/Revert/worker paths are either verified on affected hardware or explicitly recorded as deferred on-hardware verification (no automated suite exists — ARCHI.md §18)
- [ ] Documentation updated per project standards (including the §15 cross-surface echoes)
