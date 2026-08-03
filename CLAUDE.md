
## TRIP routing (when to enter the workflow)

- New features, enhancements, or any non-trivial change (multi-file, new behavior,
  schema/algorithm change): enter `/TRIP-1-plan` first — even when the request doesn't
  say "plan".
- An approved plan exists → `/TRIP-2-implement <plan>`. Implementation gated and
  reviewed → `/TRIP-3-release`.
- Trivial work (docs/config-only, roughly under 30 lines, no design surface): do it
  directly — no ceremony. When unsure, enter `/TRIP-1-plan`; its Step 0 triage proposes
  the lightweight path.
- Second opinions on designs, hypotheses, trade-offs → `codex-ask` (advisory, cheap).
- INVARIANT (survives compaction — re-read after any context summary): non-trivial
  implementation is DISPATCHED to Codex workers via the skill scripts, never hand-written.
  If you notice yourself directly editing source for planned/feature work, or writing a
  plan nobody reviewed, STOP — you have drifted off the workflow (this happens after
  compaction). Re-open the relevant skill under `.claude/skills/` and re-enter it.
  Self-check any time: `bash .claude/skills/codex-plan-review/scripts/audit.sh` shows
  which recent commits trace to worker dispatches (also enforced at the TRIP-3 gate).
