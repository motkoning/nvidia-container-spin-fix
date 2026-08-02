---
name: TRIP-promote
description: Graduate a winning spike from TRIP-explore into the real codebase - lift its diff onto a branch, write the plan retroactively from the working prototype, then run the standard hardening pipeline (tests, review gates, release). Enter when the user picks an exploration winner, says "promote", "keep this one", "make it real", or "harden the prototype".
argument-hint: "<exploration-name> <winning-bet>"
---

# Promotion Mode

You are graduating a spike into production code. The design is now settled — the spike
settled it — so from here the kit's normal quality machinery applies in full. What
promotion adds is the bridge: prototype → branch → retroactive plan → hardening.
Implementation stays terra-high even here; Sol and Opus review (routing 2026-08-02).

Spike: `.trip-spikes/$ARGUMENTS` (name + bet from the arguments; ask if ambiguous).

## Step 1 — Re-verify the tangible

Run the spike's `RUN:` command once more in its dir. If it no longer runs, stop and say
so — never promote a demo you have not just seen work.

## Step 2 — Lift the diff onto a real branch

```bash
ROOT="$(pwd)"; SPIKE="$ROOT/.trip-spikes/<name>/spike-<bet>"
git -C "$SPIKE" add -A
git -C "$SPIKE" diff --cached > "$ROOT/.trip-spikes/<name>/promotion.patch"
git checkout -b feat/<name>
git apply --3way ".trip-spikes/<name>/promotion.patch"
```

`--3way` because main may have moved since the spike was archived from HEAD; resolve
conflicts now, while the spike is fresh. Do NOT commit yet — staging stays explicit and
happens at the hardening checkpoints, never `git add -A` in the real repo (convention
#1; the `add -A` above happens only inside the disposable spike clone).

## Step 3 — The retroactive plan

Write `docs/1-plans/F_<next-version>_<name>.plan.md` FROM the prototype: the brief's
goal/constraints, the design decisions the spike actually settled (the workers' reports
listed them), the TODO corners it consciously cut (grep the spike diff for `TODO`), and
a checklist of what hardening must fix. Mark it clearly: *"retro-plan from spike —
design settled by prototype, plan documents rather than proposes."* Plans are cheap
when the design is known; this one is the map for review, not a proposal for debate —
**no Codex plan review round** (the design was already user-selected from tangibles).

Present it for user approval before proceeding.

## Step 4 — Hardening (the standard pipeline, unchanged)

1. **De-spike**: fix every TODO corner from the plan checklist; un-hardcode; restore
   anything the spike broke. Dispatch to codex-implement (normal `implement.tpl`, not
   the spike template) or do it directly per size.
   **Asset provenance**: every generated image riding the promotion gets an explicit
   user decision — keep as an owner-approved asset (staged explicitly, listed in the
   retro-plan), regenerate at final quality, or replace with licensed art. Binary
   assets never ride a patch silently.
2. **Tests**: write them against the now-stable spec (the plan's checklist is the test
   list). Claude runs the testing gate itself — worker self-runs never replace it
   (convention #3).
3. **Code review**: the standard gate — Opus 5 fresh-context subagent per
   `TRIP-review`; Codex/Sol @ xhigh loop as fallback. Full-loop by default; this is
   exactly the moment the deferred quality enforcement lands.
4. **Release**: `/TRIP-3-release` as ever (version, CR promotion, changelog, ARCHI
   update — the ARCHI likely needs the new design documented).

## Step 5 — Exploration hygiene

After the release (or an abandoned promotion): reset every spike thread
(`reset.sh "$SPIKE"` per spike — usage.ndjson survives), then delete
`.trip-spikes/<name>/` entirely. The brief's content lives on inside the retro-plan;
nothing else in the exploration dir is worth keeping. Stale explorations rot —
if one sits untouched two weeks, ask the user whether to delete it.
