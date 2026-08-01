# AGENTS.md — Instructions for AI coding agents in this repo

**Read first:** README.md (user-facing contract: what the fix does, Download section),
evidence.md (the investigation record — CPU-spin and shutdown-deadlock evidence this fix
rests on). When `docs/ARCHI.md` exists it is the maintained architecture snapshot.

## Hard rules

- **Never modify generated artifacts or business data**: this repo has no generated
  paths — everything is hand-written source. Code changes belong in `Fix-NvContainerSpin.ps1`
  (the core tool) and `easy-tool/` (the non-technical-user wrapper).
- **Never commit, tag, or push.** The orchestrating agent owns all git ceremony.
- **Fix semantics are owned by Richard Wilken** (human domain owner): what gets disabled on
  end users' machines, risk/reversibility messaging, and anything that changes what
  `-Mode Fix` or `-Mode Revert` actually touches. Implement only what the plan explicitly
  specifies; when something needs a judgment call about end-user safety, flag it in your
  report instead of deciding.
- Project-specific invariants:
  - Scripts run on **stock Windows PowerShell 5.1** on end users' machines — no PS7-only
    syntax, no modules, no external dependencies, no internet access assumed.
  - `-Mode Diagnose` is strictly **read-only**, always.
  - `-Mode Fix` must remain fully reversible by `-Mode Revert` (rename, never delete).
  - Never start/stop/restart the NVIDIA container service programmatically — the shutdown
    deadlock makes leftover processes unkillable (see evidence.md); the contract is
    "change file, tell user to reboot".
  - `easy-tool/` must stay double-click usable by non-technical users (START-HERE.bat is
    the entry point; no terminal knowledge assumed).
- Runtime + test facts: PowerShell 5.1+ / Windows only. **No automated test suite.**
  Verification = run `-Mode Diagnose` locally (safe, read-only) plus manual review;
  `-Mode Fix`/`-Mode Revert` behavior can only be truly verified on affected hardware,
  so those paths get extra review scrutiny instead of test runs.
