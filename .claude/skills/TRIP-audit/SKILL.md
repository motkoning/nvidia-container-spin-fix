---
name: TRIP-audit
description: Attribution audit — verify recent commits trace to Codex worker dispatches and catch orchestrator drift (a compacted session silently implementing solo). Use when the user asks "did this go through codex", after any context compaction, when work feels off-protocol, or as part of the TRIP-3 release gate.
---

# TRIP-audit — who actually did the work?

Drift is invisible from inside a session: a compacted orchestrator keeps committing,
self-reviewing, and looking healthy while quietly implementing everything itself
(observed 2026-08-02: five solo commits including a 10-major Electron jump). Quality
signals cannot catch it — attribution can. Every real dispatch leaves telemetry in the
skill `state/` dirs; this audit correlates `git log` against it.

## Run

```bash
bash .claude/skills/codex-plan-review/scripts/audit.sh                  # last 14 days
bash .claude/skills/codex-plan-review/scripts/audit.sh --since v3.2.0   # a release range
```

Read-only. Exit 0 = clean, 2 = DRIFT? lines present.

## Reading the report

- **DISPATCHED** — backed by implement-flow telemetry since the previous commit, or by a
  `TRIP-Dispatch:` commit trailer (declarative evidence; release Step 9 adds it).
- **solo-docs** / **solo-trivial** — legitimate direct work under the routing triage
  rules (docs/kit/imagery paths, or ≤30 changed lines).
- **DRIFT?** — substantial commit with no dispatch evidence. Investigate.
- **reviewed / no-review** — whether a code-review-flow call preceded the commit (8h
  window).

## Before accusing — the false-positive classes

1. **Multi-commit integrations from ONE worker thread** (promote patch-lifts, a batch
   split across commits): only the first commit sees the dispatch. Verify via the
   thread's events file in the flow's `state/` dir; prevent it by adding the
   `TRIP-Dispatch: <state-key or thread-id>` trailer at commit time.
2. **Work predating the kit install** in this repo.
3. Killed or stalled calls log no usage — but they also produced no work.

## Recovery — when the drift is real

1. **Freeze** new feature work.
2. Per DRIFT? commit: **retroactive code review** — codex-code-review flow, target
   `retro-<sha>`, extra prompt carries the SHA (the worker reviews `git show <sha>`)
   plus the intent docs (plan / opportunity menu / critique).
3. Findings → **fixes via codex-implement dispatch** (`fix-<sha>-<slug>` targets),
   re-review to APPROVED.
4. Re-read the `## TRIP routing` block in CLAUDE.md (the anti-drift invariant), then
   resume the normal workflow.
5. **Never delete skill `state/` dirs** — they are the flight recorder this audit reads.
