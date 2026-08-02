---
name: TRIP-1-plan
description: Plan a new feature following project standards. Enter whenever the user asks to add, build, change, or extend functionality — any non-trivial change (multi-file, new behavior, new module, schema or algorithm change) — even if they never say "plan". Trivial work (docs/config-only, roughly under 30 lines) is handled directly instead; when unsure, enter — Step 0 triages.
argument-hint: "describe the feature you want to build"
---

# Planning Mode

You are now in **planning mode** for **nvidia-container-spin-fix**.

## Prerequisites - Read First

Before creating any plan, you MUST read ALL THE LINES of:

1. @docs/ARCHI.md - Understand current system architecture

## Your Task

Plan the following feature: $ARGUMENTS

---

## Step 0: Size, Shape, and Maturity Triage

Before any ceremony, judge the request on three axes — and say what you concluded.

**Size**: doc-only, config-only, or roughly under ~30 changed lines with no architectural
impact → propose the lightweight path (implement directly or one-shot via codex-implement,
skip the Codex plan review; `codex-ask` for a quick second opinion if wanted).

**Shape — does TRIP even apply?** The full pipeline exists for changes that workers can
implement and executable checks can anchor. If the deliverable is **operations,
configuration, investigation, or documents** — human-gated infra actions, audits,
runbooks, proposals — say so plainly and propose the lightweight mode instead: work
directly with the user, keep an evidence memo, at most ONE advisory review round, no plan
document unless the user wants one, no versions/CRs/release ceremony for prose. Multi-round
review needs an executable anchor to converge; on documents it manufactures findings
forever (measured: one ops project spent two days and 6,500 lines of proposals in review
rounds, then shipped the entire build in six hours from a 168-line checklist).

**Maturity — is the design settled?** A request can be big AND worker-implementable AND
still not ready for this pipeline: if the user is exploring — unsure how they want it to
work, wants options to compare, "something tangible to look at" — a plan would be a guess
and every review round would polish that guess. Propose `/TRIP-explore` instead: 2-3
fast parallel prototypes to react to, promotion to the full pipeline only after a winner
settles the design. Planning resumes at `/TRIP-promote` with the design already decided.

The user decides; full ceremony remains the default only for real, worker-implementable
work whose design is settled.

---

## Step 1: Discovery & Clarification (Interactive)

**Do NOT start writing a plan immediately.** First, engage in a discovery conversation to fully understand the user's intent.

### 1.1 Initial Understanding

After reading the feature request, summarize your understanding in 2-3 sentences, then **use the `AskUserQuestion` tool** to present clarifying questions with structured options.

Frame questions around:

- **Scope**: What's included vs excluded?
- **Behavior**: How should it work from the user's perspective?
- **Constraints**: Any technical limitations, deadlines, or dependencies?
- **Priority**: What's most important if trade-offs are needed?

For each question, provide 2-4 concrete options based on your analysis of the codebase and the feature request. Always let the user provide custom input via the built-in "Other" option.

After the user answers, run the measurement pass (1.2), then proceed **directly to writing the plan** (Step 2) — no approach-confirmation question. Ask a follow-up round with `AskUserQuestion` only if a blocking ambiguity remains (**maximum 3 rounds total**; if still unclear, summarize what you know and proceed with noted assumptions).

### 1.2 Measure Before Writing

Probe the live system before drafting: actual sizes, field variance, real consumers of whatever the feature touches. Project docs — ARCHI.md included — drift and can misdirect scope; in one real run the repo's own architecture notes blamed the wrong data feed, and measuring first roughly doubled the win. Ground every plan option in numbers and let the plan cite them.

---

## Step 2: Plan Document Creation

Once understanding is confirmed, create the plan document.

### File Naming

Depending on the feature (major, minor, patch), propose a new version using SemVer (x.y.z) and create:
`docs/1-plans/F_[version]_[feature-name].plan.md`

### Required Sections

```markdown
# [Feature Name] Implementation Plan

## Overview

[2-4 sentences describing the feature and its purpose]

## Problem Statement (if applicable)

[Current limitations/issues this feature addresses]

## Solution Architecture

[High-level design approach]

## Implementation Details

### 1. [Component/Module/File Name]

**File**: `path/to/file`

[Detailed description of changes needed]

**Current state** (if modifying existing):
[Describe what currently exists]

**Modifications**:

- Specific change 1 (around line X)
- Specific change 2 (around line Y)

### 2. [Next Component/Module/File]

[Continue with same pattern]

## Technical Considerations

- **Pattern Usage**: Which existing patterns to follow (from ARCHI.md — verdict/state model §9, elevation split §12, worker result-file protocol, color vocabulary §13)
- **Safety Invariants (ARCHI.md §5)**: Diagnose stays strictly read-only; Fix stays a reversible rename; never start/stop/restart the NVIDIA service. Anything altering what Fix/Revert touches on end users' machines is owner-gated (Richard Wilken) — the plan must flag it explicitly, never decide it
- **PowerShell 5.1 Compatibility**: no PS7-only syntax (ternary, `??`, `?.`, `&&`/`||` chains), no modules, no external dependencies, no internet — shipped scripts run stock as downloaded
- **Dual-Surface Sync**: shared helpers are intentionally duplicated between `Fix-NvContainerSpin.ps1` and `easy-tool/NvidiaFixTool.ps1` — behavior changes must land in both; user-facing facts echo across five doc surfaces (§15) and change together in one commit
- **Non-Technical UX**: easy-tool must stay double-click usable; GUI strings follow the plain-English tone rules (§15); keep diagnosis within the ~10-second expectation (§19)
- **Field Constraints (§10)**: no live plugin experiments, one experiment per reboot, driver updates revert the fix — plan verification steps within these limits
- **Edge Cases**: no NVIDIA driver, plugin missing (unusual layout), container not running, "fixed but reboot pending", declined UAC, missing/stale worker result file

## Files to Modify/Create

[Comprehensive numbered list with purposes]

1. `path/to/file1` (modify) - Purpose description
2. `path/to/file2` (new) - Purpose description

## Type Definitions (if applicable)

[New types, interfaces, structs, or modifications to existing ones]

## Performance & Cost Impact (if applicable)

[Expected performance implications]

## Backward Compatibility (if applicable)

[Migration strategy if needed]

## Equivalence Proof (required if the change must not alter behavior/output)

[How old and new forms will be generated from the same source and deep-equal-compared exhaustively — every row, every period. This proof runs in the TRIP-2 testing gate and gates the release. For cross-runtime transform/inverse pairs: validate the merge/restore semantics with a throwaway reference implementation in one runtime first, then hand the validated semantics to the implementer verbatim in the dispatch notes.]

## Test Impact

[2-5 bullets: which existing tests the change affects, what new logic will need tests, whether an integration/E2E check applies. No test code — the TRIP-2 testing gate consumes this section.]

## To-dos

### Phase 1: [Phase Name] (if multiple phases are needed) or simply skip title if only one phase is needed

- [ ] Task description
- [ ] Another task

### Phase 2: [Phase Name] (if applicable)

- [ ] Task description
- [ ] Another task

**Note**: For simple plans, a single phase is sufficient. Split into multiple phases only for complex features requiring sequential implementation.

**Parallel groups (rare, opt-in)**: when two batches are BOTH chunky (≥5 min of worker
build each) AND touch provably disjoint file sets (list them — include leak-prone shared
touchpoints: exports/`__init__`, config, changelog) AND come after the pattern-setting
early batches, you MAY mark them `Parallel group: <batch A> + <batch B> — file sets: …`
so TRIP-2 can dispatch them concurrently (its §2b re-verifies all three preconditions
before honoring the mark). Do not mark groups on small-batch plans — at terra-high
speeds sequential is already near the floor, and unmarked plans are always sequential.

**Note**: Do NOT write test code during planning — the Test Impact section above only names what the TRIP-2 testing gate will run and author.
```

## Quality Standards

- **Zero Ambiguity**: Every step must be clear and actionable
- **File-Level Specificity**: List exact files and functions to modify
- **Architecture Alignment**: Must conform to existing patterns in ARCHI.md
- **Risk Assessment**: Highlight potential failure points

---

## Step 3: Codex Second-Opinion Review

Before the user sees the plan, run the Codex plan review loop.

### Confirm

`AskUserQuestion`: "I'll run Codex as a second-opinion reviewer and iterate until clean. Proceed?"
Options: "Yes, run Codex review" (recommended) / "Skip Codex, go to user review" / "Cap iterations at N"

Skip for trivial plans (single-file, low-risk). Run for non-trivial (new module, schema/algorithm change).

### Loop

1. **Start**: `bash .claude/skills/codex-plan-review/scripts/start.sh --prompt-file .claude/skills/codex-plan-review/prompts/start.tpl <plan-path>`
2. **Parse trailing tag**: `APPROVED` -> Step 4. `NEEDS_REWORK` -> surface to user. `REQUEST_CHANGES` -> continue.
3. **Address findings critically** — quote each P1/P2, push back on incorrect ones, fix legitimate ones by editing the plan in place.
4. **Write implementer notes** (1-3 sentences): which findings you fixed, which you pushed back on and why, any user decisions that override existing docs or environment limitations that can't be resolved in the plan.
5. **Resume** with notes:
   ```bash
   bash .claude/skills/codex-plan-review/scripts/resume.sh \
       --prompt-file .claude/skills/codex-plan-review/prompts/resume.tpl \
       --notes "Fixed X. Pushed back on Y because Z. User decided W." \
       <plan-path>
   ```
   -> back to step 2.
6. **Cap at 5 rounds** (or user-specified). Surface remaining findings and let user decide.

Surface Codex reviews verbatim. Keep edits scoped to findings. Reset thread (`reset.sh <plan-path>`) only if context is genuinely confused.

---

## Step 4: User Review & Validation

After Codex review converges (or is skipped), present a summary to the user including:

- **Feature**: [name]
- **Approach**: [1-2 sentences]
- **Files affected**: [count] files ([list key ones])
- **Estimated complexity**: [simple/moderate/complex]
- **Codex status**: [APPROVED / skipped / capped at N rounds with open findings]

Then **use the `AskUserQuestion` tool** to collect feedback:

- **Question**: "Please review the plan at `docs/1-plans/F_x.y.z_feature-name.plan.md`. How would you like to proceed?"
- **Options**: "Approved" (ready for implementation), "Request changes" (I have modifications), "Needs rework" (significant issues to address)

Handle feedback:

- **If "Request changes"**: Update the plan and re-present. Run another Codex pass if changes are substantive.
- **If "Needs rework"**: Discuss issues, rework the plan, and re-present.
- **If "Other" (custom input)**: Handle accordingly.
- **If "Approved"**: **Use the `AskUserQuestion` tool** to ask:
  - **Question**: "Plan approved. Would you like to start implementation now?"
  - **Options**: "Yes, implement now" (proceed with `TRIP-2-implement` using this plan), "Not yet" (I'll implement later)

---

## IMPORTANT: No Code Implementation

**DO NOT write code snippets or implement anything during planning.**

This is a high-level planning phase only. Your plan should describe:

- WHAT needs to be done (features, changes, structures)
- WHERE changes will happen (files, modules, functions)
- WHY certain approaches are chosen (trade-offs, rationale)

But NOT:

- Actual code implementations
- Detailed algorithm code

Keep it architectural and descriptive. Code comes in the `TRIP-2-implement` phase.

## For Changes to Diagnosis Logic

Required analysis:

- Which surface(s): CLI Diagnose, GUI `Invoke-Diagnosis`, or both (usually both — helpers are duplicated by design)
- New states in the (spin × pluginState) verdict matrix and their verdict text, color, and button visibility on each surface
- Read-only invariant preserved (ARCHI.md §5.1) — no writes, no elevation, no state changes
- Time budget: stays within the GUI's ~10-second expectation, or the label text changes with it
- PowerShell 5.1-compatible constructs only

## For Changes to Fix/Revert Semantics

Required analysis:

- **Owner gate**: exactly what changes on end users' machines — flagged for Richard Wilken's decision, never decided in-plan
- Reversibility proof: how Revert exactly undoes the new behavior
- Elevation path affected: CLI self-elevation, GUI hidden worker, or both; any change to the `OK|`/`ERR|` result-file protocol
- Ownership/ACL implications (takeown/icacls scope — parent folder AND file)
- Reboot contract preserved: nothing starts/stops/restarts the NVIDIA service (ARCHI.md §5.3, §10)

## For GUI / easy-tool Changes

Required analysis:

- Which (spin × pluginState) states show the new/changed control; button-morphing implications ("Apply the fix" → "Restart PC now")
- Copy follows the plain-English tone rules (ARCHI.md §15); failure messages only claim "nothing was changed" when true
- Fixed-size layout: which widget positions/sizes must shift
- Still double-click usable via START-HERE.bat; `-SelfTest` still passes

## For Documentation Changes

Required analysis:

- Which surface owns the fact (ARCHI.md §15 copy map); which echoes must change in the same commit
- evidence.md is append-only in spirit — new evidence gets new sections, existing sections are not reworded
- Release-asset names and README download links are a stable contract (ARCHI.md §6, §22)
