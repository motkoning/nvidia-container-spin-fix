---
name: TRIP-2-implement
description: Implement a feature following TRIP plan. Enter when the user asks to implement, execute, resume, or continue an approved plan (docs/1-plans/*.plan.md).
argument-hint: "plan file or feature to implement"
---

# Implementation Mode

You are now in **implementation mode** for **nvidia-container-spin-fix**.

## Prerequisites - Read First

Before implementing, you MUST read ALL THE LINES of:

1. @docs/ARCHI.md - Understand current system architecture

## Your Task

Implement: $ARGUMENTS

---

## Step 0: Create a Branch (Pre-Implementation)

**Always** create a dedicated branch before implementing — no need to ask. `TRIP-3-release` merges it back into the main branch with fast-forward, keeping a single clean linear history.

```bash
git checkout -b feat/[short-description]   # or fix/[short-description]
```

Derive the short description from the plan/feature name. If already on a dedicated branch for this work (e.g., resuming a session), continue on it.

---

## Implementation Phase — Delegate to Codex

You do NOT write the implementation yourself — delegate it to Codex via the `codex-implement` skill. (Exception: trivial unplanned changes of a few lines may be done directly.)

Delegation is **batched**: Codex implements a few of the plan's checkboxes per turn, you review and fix each batch, then request the next one with your corrections attached. Same persistent thread throughout — context and conventions compound across turns.

### 1. Read the plan and decide the batches

Read the plan fully and split its to-dos into batches. You are the judge of batch size:

- A batch is the **smallest set of checkboxes that leaves the tree green** (compiles, lints). Never split an interface from its implementation and wiring.
- Target a reviewable diff — roughly ≤300 changed lines per batch. A checkbox that alone exceeds this becomes its own batch.
- Size by risk: novel, architectural, or security-critical work → small batches (down to one checkbox). Mechanical, repetitive work → larger batches.
- Never span phase boundaries.
- **One-shot escape hatch**: a low-risk plan (or phase) of ≤3-4 checkboxes is delegated whole — no batching ceremony.
- **Filter out non-Codex items**: checkboxes needing human input, dashboard/console access, credentials, or ops actions are yours — resolve them with the user before or between batches, never delegate them.

### 2. Delegate batch by batch

**Route each batch before dispatching it.** Reasoning tokens are ~60% of worker output and
they are pure waiting, so deliberation spent on a decision-free batch buys nothing. Default
to Sol; step down only when the batch genuinely has no decisions left in it.

| Batch | Route | When |
|---|---|---|
| **Design-surface / hard** — new logic where the plan describes *what* without pinning *how*, tricky edge-case work, anything security- or data-critical | **Sol @ high** (the default — no env prefix) | Everything not clearly in the rows below |
| **Well-specified standard** — real feature work, but the plan pins the *how*: names, semantics, formats, placement all decided | `CODEX_MODEL=gpt-5.6-luna CODEX_EFFORT=high` | Benchmarked 2026-07-30, 36-cell grid: on this class quality saturated across every model and effort tested — Luna @ high matched Sol @ xhigh's review profile at a fraction of the cost, and xhigh bought Luna no measurable quality over high. Below high is untested for this lane. The escalate-on-failure rule is the safety net that keeps this cheap routing safe |
| **Mechanical** — apply an established pattern to further modules, bulk renames, boilerplate, wiring imports | `CODEX_MODEL=gpt-5.6-luna CODEX_EFFORT=medium` | Only when you can state the batch as "this is just typing" |
| **Trivial** — a couple of lines in one file, no design | **Do it yourself, no dispatch** | A Codex round-trip costs ~1–2 min of fixed overhead; below that the dispatch costs more than the work |

**Escalate on failure, don't patch over it**: if a Luna batch comes back wrong — misapplied
the pattern, missed files, needed conventions re-explained — redo the batch at
Sol @ high rather than hand-fixing it. Misclassification is expected and cheap; quietly
repairing a bad batch hides the signal and costs more than the redo. (This rule is what
makes the Luna lanes safe to use liberally.)

**Two things the step-down does not change**: mixing models inside one thread is fine (the
model is passed on every turn and the cached context carries across), and every batch still
gets the same line-by-line delta review in step 3 — routing changes who types, never who
checks.

**On doing it yourself**: keep this for genuinely trivial work. Batches you implement lose
the cross-vendor property that makes the delta review meaningful (Sol writes, Claude
reviews) — your own code reaches the final gate having been read only by Claude. Anything
with design surface goes to Codex for that reason alone.

**Start** the session with the first batch (state dir is handled by the script):

```bash
bash .claude/skills/codex-implement/scripts/start.sh \
    --prompt-file .claude/skills/codex-implement/prompts/implement.tpl \
    <plan-path> "Implement only: <batch-1 checkboxes>"   # or omit instructions to one-shot a small plan
```

**Each next batch resumes the same thread**, carrying your review corrections as `--notes`:

```bash
export STATE_DIR=".claude/skills/codex-implement/state"
# mechanical batch? prefix: CODEX_MODEL=gpt-5.6-luna CODEX_EFFORT=medium
bash .claude/skills/codex-plan-review/scripts/resume.sh \
    --prompt-file .claude/skills/codex-implement/prompts/continue.tpl \
    --notes "<what you fixed after the last batch and why; conventions to apply from now on>" \
    <plan-path> "Now implement: <next batch checkboxes>"
```

The script echoes the effective `model/effort/tier` — check it matches the route you chose.

**Parse the trailing tag** of each report:
- `IMPLEMENTATION_COMPLETE` → review the batch (below).
- `IMPLEMENTATION_PARTIAL` → read the report; resume with instructions for the remainder, or finish small leftovers yourself during the batch review.

### 3. Review each batch (delta review)

After each Codex report, before requesting the next batch:

1. **Review the delta only**: `git status -s && git diff` — worktree vs index shows just this batch, since previous batches are staged (step 4). Check it against the plan, ARCHI.md patterns, and project conventions (DRY, KISS, comment discipline, error-handling and naming conventions from ARCHI.md).
2. **Fix problems directly yourself** — no back-and-forth with Codex over fixes. What you fixed and why becomes the `--notes` of the next resume.
3. **Micro-gate**: run the lint and typecheck/build commands from the Testing Gate (fast checks only — tests wait for the gate itself). Fix failures now.
4. **Checkpoint**: `git add <this batch's files>` — stage the reviewed batch explicitly so the next delta review starts clean. **Never `git add -A`**: the tree may carry unrelated in-flight work; leave it unstaged, note it once, and read past it in later deltas. No commits — history stays clean for release.
5. Verify the plan checkboxes Codex ticked match what the diff actually contains; cross any it completed but missed.
6. **Govern deviations**: if the diff contains changes the plan didn't sanction, neither revert reflexively nor accept silently. Investigate (who consumes this? what breaks?), then either record it in the plan as an accepted deviation — or instruct reversal in the next `--notes`.

**Adapt as you go**: clean batch → grow the next one; heavy corrections → shrink the next one and spell out the fix pattern in the notes. Grow deliberately, not indefinitely — an oversized batch slows the worker's turn *and* makes your line-by-line review harder, and its output becomes thread history that every later turn re-processes.

**Reset trigger (thread weight)**: a resumed thread re-processes its whole accumulated history each turn, so latency and cost climb batch over batch even at fixed effort. `start.sh`/`resume.sh` print `uncached input` after every call and warn past **350k tokens**. On that warning, reset at the **next batch boundary** (never mid-batch):

```bash
STATE_DIR=".claude/skills/codex-implement/state" \
    bash .claude/skills/codex-plan-review/scripts/reset.sh <plan-path>
```

Then start a fresh thread whose prompt carries: the plan path, which checkboxes are already done, and a short summary of the conventions established so far (the accumulated `--notes`). Cost is one rebuild prompt; the payoff is turns returning to first-batch speed. Also reset — regardless of weight — if Codex starts ignoring notes or repeating corrected mistakes, which is the qualitative signal of the same problem.

### 4. Final pass

After the last batch, read the **full feature diff** once (`git diff HEAD`). Batch reviews catch local issues; this pass catches cross-batch drift — duplicated helpers, divergent naming, dead code left by course corrections. Fix directly.

The testing gate and code review run **once**, after the final pass — never per batch. Proceed to the testing gate once you consider the implementation good for review.

---

## Testing Gate

After implementation, before the Codex review loop. Any failure here blocks the loop from starting.

### 1. Syntax gate (stands in for lint/type-check — no linter installed, PowerShell has no typecheck)

```bash
powershell -NoProfile -Command '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "Fix-NvContainerSpin.ps1"),[ref]$null,[ref]$e); $e; if($e){exit 1}' 2>&1 | tee /tmp/_trip2-lint.txt
powershell -NoProfile -Command '$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "easy-tool/NvidiaFixTool.ps1"),[ref]$null,[ref]$e); $e; if($e){exit 1}' 2>&1 | tee /tmp/_trip2-typecheck.txt
```

Parse both scripts even if only one changed — duplicated helpers mean edits often belong in both. The parser will NOT catch PS7-only syntax (it may parse fine); 5.1 compliance is a read-the-diff check (ARCHI.md §18).

### 2. Read-only smoke runs (stand in for unit tests — no automated suite, ARCHI.md §18)

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File Fix-NvContainerSpin.ps1
powershell -NoProfile -ExecutionPolicy Bypass -STA -File easy-tool/NvidiaFixTool.ps1 -SelfTest
```

Both are safe on any machine: Diagnose is read-only and must print a verdict; `-SelfTest` constructs the GUI off-screen and must print `SelfTest OK`.

### 3. Integration impact check

No integration/E2E tooling exists. Instead:

- If the change touches `-Mode Fix`, `-Mode Revert`, or the GUI worker: those paths cannot be exercised safely here — state in the gate summary that behavioral verification requires affected hardware (one experiment per reboot, ARCHI.md §10), and route the code review to **full depth** (these paths touch AGENTS.md invariants).
- If GUI layout/flow changed: run it once interactively via `easy-tool/START-HERE.bat` when a display is available and eyeball states, buttons, and copy.
- Docs-only changes skip this.

### 4. Equivalence proof (if the plan requires one)

If the plan has an **Equivalence Proof** section, run it now: generate old and new forms from the same source and deep-equal them exhaustively. Any mismatch blocks the loop — the proof is a release gate, not advisory.

### 5. Author missing tests

If the change adds new logic, write its tests **now**, guided by the plan's **Test Impact** section and the project's testing guide (see `TRIP-test`). If no new logic was added, skip this step.

**Hard-to-cover code policy:**

- Test **observable behavior** (inputs → outputs/persisted effects), never internal wiring.
- **Mock-pain tripwire**: if the mock setup grows longer than the test's assertions, stop fighting it — check the project's testing guide for a seam recipe; if none applies, skip the *deep unit* test and add one line to `docs/4-unit-tests/COVERAGE-DEBT.md` (`path | why hard | escape plan`).
- **Critical-path floor**: behavior touching auth, deletion, persistence, cost, or external request shape must keep at least one behavioral test or manual integration check — coverage debt may defer internal-path depth, never safety-critical behavior.
- Never hide untested code (no coverage-ignore comments, no config exclusions, no lowering coverage gates). Legacy modules outside the change scope are not a feature blocker — but record newly encountered risky gaps in the ledger.

### 6. Build the summary

Format: `syntax: clean (both scripts) | diagnose smoke: verdict printed | selftest: OK | hardware-only paths: <none touched / listed for on-hardware verification>`

Fix failures before starting the loop.

---

## Code Review (Opus 5)

Always run the final code review after the testing gate passes — no confirmation needed.

The reviewer is a **fresh-context subagent pinned to `claude-opus-5`** — never the session
model (sessions alternate between Claude models; pin, don't inherit). One knob CANNOT be
pinned: the reviewer's extended-thinking budget is inherited from the dispatching session
(Claude Code provides no per-agent thinking control) — so review depth follows the
session's thinking configuration. Known limitation, documented rather than controlled. This is deliberately
cross-vendor: Sol wrote the code, a Claude reviews it, so author and final reviewer do not
share blind spots. The previous Codex loop (`codex-code-review`, Sol @ xhigh) remains the
**fallback** when Claude-side capacity is unavailable — same state file, same sentinel.

### Depth

Choose the depth from what the change actually touches. State which you chose, and why,
in the CR.

**Full review** — the multi-round loop below. The default, and mandatory whenever the
change touches any of:

- authentication, authorization, or permissions
- deletion, persistence, migrations, or schema
- data correctness — calculations, aggregations, anything a downstream number depends on
- money/cost, or externally observable contracts (API shape, payloads consumers parse)
- an **Equivalence Proof** in the plan
- anything `AGENTS.md` marks owner-gated, invariant, or off-limits
- anything the user flagged as high-stakes

**Light review** — one pass, no loop. Only when the change is confined to presentation,
docs, comments, or formatting **and** touches nothing in the list above.

**No-anchor cap**: artifacts nothing executable can anchor — runbooks, proposals, prose,
configs that cannot be exercised here — get at most ONE review round and its findings are
**advisory**, regardless of how security-critical the topic sounds. Multi-round review
converges on code because tests anchor "done"; on documents it manufactures findings
forever. Ops/infra criticality is enforced by the human approval gates on execution, not
by review rounds on the paper.

**Escalation is mandatory (code only)**: if a light review of CODE returns any Critical or
Major finding, discard the light result and run the full loop from round 1. Misjudging
risk is expected and cheap to recover from; shipping on a light review that found
something serious is not. **When in doubt about code, run full.**

### Round loop

1. **Assemble the packet — scope the diff to the feature.** Working trees routinely carry
   unrelated in-flight work and generated data (conventions 1 and 2), so never hand over a
   raw whole-tree diff:

   ```bash
   git diff HEAD -- <the plan's "Files to Modify/Create" list>
   ```

   An unscoped diff spends reviewer attention on code that isn't shipping and returns
   findings you then have to dismiss. Name any deliberately excluded paths in one line so
   the omission reads as intentional. Scoping bounds what is **under review** — never what
   the reviewer may read: it keeps full read access to the repository and is expected to
   follow callers and read surrounding code.

   Also pass: the plan path, `AGENTS.md`, and
   `.claude/skills/TRIP-review/checklist.md`. For unplanned work (no `F_*.plan.md`),
   describe the change in a sentence instead of a plan path.

2. **Dispatch** a subagent (Agent tool, model `claude-opus-5`) with this framing:

   > You are an adversarial code reviewer with fresh eyes on this repository. GPT-5.6 Sol
   > implemented the change; nobody with your reasoning style has reviewed it. Do not
   > assess whether it looks good — try to prove it is broken: the input that produces
   > wrong output, the edge case the plan missed, silent failures, violated constraints
   > from AGENTS.md. Read the plan at <plan-path>, AGENTS.md, and
   > `.claude/skills/TRIP-review/checklist.md`; judge the diff against the actual code in
   > the repo (read the files — never trust a diff alone). You are read-only: change
   > nothing. Report each finding as `file:line — severity (Critical/Major/Minor/
   > Suggestion) — what breaks and how`. Testing-gate summary: <gate summary>. End with
   > exactly one tag on its own line: APPROVED, REQUEST_CHANGES, or NEEDS_REWORK.

3. **Parse trailing tag**: `APPROVED` → record for release. `NEEDS_REWORK` → surface to
   user. `REQUEST_CHANGES` → continue.

4. **Address findings** — quote each with `file:line`, read the actual code, fix
   legitimate ones, push back on incorrect ones with reasons. Critical/Major block
   approval; Minor/Suggestion are case-by-case. Record a disposition for every finding.

5. **Next round**: re-run the testing gate (lint, typecheck, affected tests), then
   dispatch a **fresh** agent — there is no thread to resume; fresh eyes every round is
   the point. Append to the prompt: the prior rounds' findings with your dispositions
   ("fixed X; pushed back on Y because Z") and the new gate summary. Loop to step 3.

6. **Cap at 3 rounds** (or user-specified). Surface remaining findings.

### Record for release

On convergence, write the consolidated review yourself to the canonical state file —
`TRIP-3-release` Step 3 promotes it from there unchanged:

```bash
STATE_KEY="$(realpath <plan-path> | sed 's|^/||; s|/|__|g')"
# write to: .claude/skills/codex-code-review/state/${STATE_KEY}.review.txt
```

Content: the final round's review, your dispositions for every finding across all rounds,
**the depth chosen and why**, the verdict, `<x.y.z>` version placeholder left unfilled
(resolved during `TRIP-3-release`), then `PROMOTION_READY` on its own line. Same location
and sentinel as the fallback loop, so release promotion and the Step 13 cleanup are
identical either way.

Edge cases:
- **Capped without APPROVED**: still write the file; list the open findings in it.
- **User skipped review**: no file. The CR is written manually during `TRIP-3-release`:
  "Code review skipped — trivial change."

### Fallback: Codex loop (Sol @ xhigh)

If Claude-side capacity is unavailable, run the previous loop via the `codex-code-review`
skill (start/resume/synthesize — see that SKILL.md for the commands). It produces the
same state file and sentinel.

### Operating Notes

Surface reviews verbatim. Keep edits scoped. A fresh reviewer may re-raise something an
earlier round already settled — your recorded disposition answers it; re-read it before
re-fixing. The testing gate (lint, typecheck, affected tests) must pass before APPROVED.

---

## Handoff to Release

After the review converges (or is skipped):

- Cross the corresponding checkboxes in the plan todo list (if any)
- Then **use the `AskUserQuestion` tool** to ask:
  - **Question**: "Is the implementation complete?"
  - **Options**: "Yes, everything is complete" (proceed to release), "No, there are remaining items" (continue working)

**If "Yes"**: proceed directly into the release — read `.claude/skills/TRIP-3-release/SKILL.md` and follow it in this session, passing the same plan path (or feature label). The release skill owns everything from version bump to the fast-forward merge and push.

**If "No"**: continue working, then repeat the sequence: testing gate → Codex review → this question.
