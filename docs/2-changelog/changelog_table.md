# Changelog Table

| Version | Week | Commit Message                  |
| ------- | ---- | ------------------------------- |
| `1.2.1` | 1    | Fix Apply-handler failure verdicts and unknown-exit-code honesty |
| `1.2.0` | 1    | Fix 8 review findings: exit-code worker IPC, CIM measurement, conflict state, consent dialog |
| `1.1.1` | 1    | chore: initialize TRIP workflow |

Versions `1.0.0` and `1.1.0` predate the TRIP workflow — their record is the git tags and GitHub releases only.

# Changelog Summary

- **v1.2.1 (Polish Patch - Week 1, 01-08-2026)**:
  - **Fixes**: The two Minor observations left open at v1.2.0 — Apply-handler failure verdicts (no stale "Problem found" above a failure log) and unknown worker exit codes routed to the honest unknown-outcome path
  - **Verification**: Post-release on-hardware checks recorded — elevated RunAs exit-code transport verified end-to-end, owner live GUI pass OK (`docs/4-unit-tests/w1_v1.2.0_test.md`)
  - **Details**: `docs/2-changelog/w1_v1.2.1.md`
- **v1.2.0 (Review-Fix Release - Week 1, 01-08-2026)**:
  - **Fixes**: All 8 findings from the retroactive code review of v1.1.0 — worker exit-code IPC (result file removed), locale-neutral CIM CPU measurement with honest three-outcome verdicts, conflict state (detect + guide), pre-elevation consent dialog, post-Revert restart state, quoted CLI elevation path, unified spin threshold, SID-based ACL grants
  - **Review**: 3-round adversarial loop (Opus 5, full depth) -> APPROVED with observations; round 1 caught and killed a measurement mechanism that silently fabricated healthy verdicts
  - **Details**: `docs/2-changelog/w1_v1.2.0.md`
- **v1.1.1 (TRIP Initialization - Week 1, 01-08-2026)**:
  - **Setup**: Initialized TRIP workflow with docs structure (1-plans, 2-changelog, 3-code-review, 4-unit-tests, 6-memo)
  - **Documentation**: Generated ARCHI.md (CLI tool + GUI companion architecture) with custom sections: Known Failure Modes, Compatibility Matrix, Docs & UX Copy Map, Release Packaging Runbook
  - **Skills**: Adapted all TRIP skills to the project — syntax-gate/smoke-run verification commands, git-tag versioning (no version file), week anchor 2026-07-27, tutorials disabled, safety-invariant review checklist
  - **Files Added**: docs/ARCHI.md, docs/ARCHI-rules.md, docs/2-changelog/changelog_table.md, docs/4-unit-tests/TESTING.md
