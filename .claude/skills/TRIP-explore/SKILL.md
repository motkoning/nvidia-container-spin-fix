---
name: TRIP-explore
description: Fast exploration lane - turn an uncertain idea into 2-3 running prototypes to react to, or scan an existing codebase for opportunities. Enter when the user has an idea but is unsure how to implement or design it, wants prototypes/spikes/concepts to compare, says "not sure how", "try a few approaches", "something tangible to look at" - or asks what could be done differently/better in this codebase (scan). NOT for settled designs (TRIP-1-plan) or production changes.
argument-hint: "<idea to explore> | scan [focus area]"
---

# Explore Mode

You are in **exploration mode**: the deliverable is *learning per hour*, not correct
code. The design is discovered by building tangibles and reacting to them; quality
enforcement is deferred to `/TRIP-promote`, where the settled design meets the full
hardening pipeline. Design rationale: `docs/PLAN-explore-lane.md` (this kit's repo).

Routing here is fixed (2026-08-02): spikes → terra-high, adversarial critic →
sol-high — both are the `_common.sh` defaults, so never override models in this lane.

## Entry A — explore an idea: `$ARGUMENTS`

### 1. Dialectic (with the user, no ceremony)

Duke it out conversationally until the space is understood. Then write the CONCEPT
BRIEF — a living scratch doc, never versioned, never reviewed:

```bash
grep -qxF '.trip-spikes/' .gitignore 2>/dev/null || echo '.trip-spikes/' >> .gitignore
mkdir -p .trip-spikes/<name>
```

`.trip-spikes/<name>/BRIEF.md`: **Goal** (2-3 sentences) · **Constraints** (hard ones
only) · **Bets** (2, max 3 — each: the design idea in a paragraph + the cheapest spike
that proves or kills it; bets must be structurally different, not variants) ·
**Open questions**. Do not manufacture a third bet for symmetry.

### 2. Dispatch spikes + critic IN PARALLEL (order matters: bets first, critique second)

For each bet (2 by default), build a self-contained scratch workspace — the bench-cell
pattern, sandbox-proven; never git branches/worktrees (their shared plumbing sits
outside the worker sandbox fence):

```bash
ROOT="$(pwd)"; SPIKE="$ROOT/.trip-spikes/<name>/spike-<bet>"
mkdir -p "$SPIKE" && git archive HEAD | tar -x -C "$SPIKE"
git -C "$SPIKE" init -q && git -C "$SPIKE" add -A && git -C "$SPIKE" commit -qm baseline
```

(Note: `git archive HEAD` carries committed state only — tell the user if relevant
uncommitted work exists.) Then dispatch each spike as a BACKGROUND task, all
concurrently:

```bash
cd "$SPIKE" && bash "$ROOT/.claude/skills/codex-implement/scripts/start.sh" \
    --prompt-file "$ROOT/.claude/skills/codex-implement/prompts/spike.tpl" \
    "$SPIKE" "<the bet, verbatim from the brief, plus what tangible to produce>"
```

And fire the adversarial critic in parallel with them (ONE round, advisory, opt-in —
skip for small explorations):

```bash
export STATE_DIR=".claude/skills/codex-ask/state"
bash .claude/skills/codex-plan-review/scripts/start.sh \
    --prompt-file .claude/skills/codex-ask/prompts/adversarial.tpl \
    ".trip-spikes/<name>/BRIEF.md" "explore: <name> — attack the brief"
```

The critique arrives mid-flight; use it to redirect or add spike 3 (the one case a
third spike is justified: the critic proposed a bet neither of us had), or to feed the
reaction round. It never blocks a dispatch and never gets a rebuttal round.

### 3. Demo gate (per spike, replaces all other gates)

When a spike reports, extract its `RUN:` line, execute it inside the spike dir, and
confirm it actually runs. Then hand the user the run command and one paragraph on the
design decisions the worker reported. That is the entire gate: no tests, no review.

**Imagery in spikes** (verified 2026-08-02: built-in `image_gen` tool, ChatGPT-plan
auth, no API key): visual bets get REAL generated assets — hero shots, logos, photos,
empty-states — because reaction fidelity is the lane's currency and gray boxes cap it at
"layout only". The spike template already mandates this; expect visual spikes to take
minutes longer (each image is a 2–6 min server-side call; known flake: complex prompts
can die with a network error — have the worker retry once with a simpler prompt).
Standalone asset exploration (e.g. 4 logo directions to react to) is just a spike whose
demo is a folder of images.

### 4. Reaction rounds

The user reacts to running tangibles — and reactions can be VISUAL: screenshot the demo,
annotate it, and pass it with `--image <file>` (repeatable; works on start and resume).
A red circle on the wrong element beats two paragraphs. Iterate survivors on the same
thread:

```bash
cd "$SPIKE" && bash "$ROOT/.claude/skills/codex-plan-review/scripts/resume.sh" \
    --prompt-file "$ROOT/.claude/skills/codex-implement/prompts/spike-iterate.tpl" \
    --notes "<the user's reaction, verbatim where possible>" "$SPIKE"
```

Kill losers without eulogy: `bash .claude/skills/codex-plan-review/scripts/reset.sh
"$SPIKE"` then delete the spike dir. Thread-weight rules still apply (reset past 350k).

### 5. Exit

A winner → `/TRIP-promote <name> <winning-bet>`. Or the exploration ends with learning
and no code — say so plainly; that is a successful outcome, not a failure.

## Entry B — scan an existing project: `scan [focus]`

The same lane pointed at the codebase — a sharp new senior engineer's first week,
compressed. Requires `docs/ARCHI.md` (run `/TRIP-init` first if absent).

1. **Ground**: build `.trip-spikes/scan-<date>/OBSERVATIONS.md` — each observation tied
   to evidence you actually measured in the repo (dead code found by grep, dependency
   doing nothing, N-line module doing an M-line job, hot path never profiled). No
   vibes, no claims sourced from docs alone — measure (SETUP convention #8).
2. **Adversarial pass**: same critic call as Entry A step 2, target =
   `.trip-spikes/scan-<date>/OBSERVATIONS.md`, extra = "scan mode: <focus>". One round.
3. **Output — the OPPORTUNITY MENU** at `docs/6-memo/opportunity-menu-<date>.md`:
   ranked 3-liners — *what / evidence / expected payoff / cheapest spike to validate*.
   Flag anything touching AGENTS.md owner-gated territory as such. **Menu rule**: no
   item without a measurable payoff claim AND a ≤1-spike validation path — churn-shaped
   refactor lists are the failure mode.
4. **The menu is parked by default.** Present it; take NO further action. A picked item
   enters Entry A's spike flow (steps 2-5), never TRIP-1 directly.

## Guardrails (non-negotiable)

- Advisory passes: ONE round, parallel, skippable. No versioned artifacts in this lane.
- The ceremony circuit breaker patrols here too: two consecutive turns of
  brief-polishing or menu-grooming with no new tangible → stop and spike something.
- **Spike code never merges directly** — `/TRIP-promote` is the only door to main.
- Explore-phase Codex calls log usage like everything else (telemetry is not ceremony).
