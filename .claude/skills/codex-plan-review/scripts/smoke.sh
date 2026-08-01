#!/usr/bin/env bash
# End-to-end lifecycle self-test for the codex skills. Copies the
# installed scripts+prompts into a throwaway project, then exercises:
# start -> duplicate-start guard -> resume with hostile notes (&&,
# backslashes, quotes, $VAR must survive verbatim) -> implement-start
# -> show -> reset (usage.ndjson must survive) -> usage tally.
# Three Codex calls at Luna/low (~90s, negligible quota). Run after any
# script change or fresh install, before trusting the pipeline.
#
# Usage: smoke.sh
# Env overrides: SMOKE_MODEL (default gpt-5.6-luna), SMOKE_EFFORT (low).
# Exits 0 if all checks pass, 1 otherwise.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

export CODEX_MODEL="${SMOKE_MODEL:-gpt-5.6-luna}"
export CODEX_EFFORT="${SMOKE_EFFORT:-low}"

# Stable scratch location inside the (gitignored) state dir: a random
# mktemp dir would leave a new codex trust entry in ~/.codex/config.toml
# on every run.
WORK="$SCRIPT_DIR/../state/smoke-proj"
rm -rf "$WORK"
trap 'rm -rf "$WORK"' EXIT

FAILED=0
pass() { echo "  ok:   $*"; }
fail() { echo "  FAIL: $*" >&2; FAILED=1; }

mkdir -p "$WORK/.claude/skills/codex-plan-review" "$WORK/.claude/skills/codex-implement" "$WORK/docs/1-plans"
cp -r "$SKILLS_ROOT/codex-plan-review/scripts" "$SKILLS_ROOT/codex-plan-review/prompts" "$WORK/.claude/skills/codex-plan-review/"
cp -r "$SKILLS_ROOT/codex-implement/scripts" "$SKILLS_ROOT/codex-implement/prompts" "$WORK/.claude/skills/codex-implement/"
cd "$WORK"
git init -q .
PLAN="docs/1-plans/smoke.plan.md"
printf '# Smoke Plan\n\nAdd a hello() function returning "hi".\n\n## To-dos\n- [ ] add hello()\n' > "$PLAN"
PR_STATE=".claude/skills/codex-plan-review/state"
IM_STATE=".claude/skills/codex-implement/state"
NOTES='fixed A && B; used path C:\Users\x and "quotes" and $VAR'

echo "[1/7] start.sh (fresh thread, $CODEX_MODEL/$CODEX_EFFORT)"
if bash .claude/skills/codex-plan-review/scripts/start.sh \
        --prompt-file .claude/skills/codex-plan-review/prompts/start.tpl "$PLAN" \
        "PIPELINE SMOKE TEST: do not actually review. Reply with one short sentence ending in the tag APPROVED." >/dev/null 2>&1; then
    pass "start.sh exited 0"
else
    fail "start.sh failed"
fi
[ -n "$(ls "$PR_STATE"/*.thread 2>/dev/null)" ] && pass "thread file written" || fail "no thread file"
[ -s "$PR_STATE/usage.ndjson" ] && pass "usage line logged" || fail "usage.ndjson missing/empty"

echo "[2/7] duplicate start.sh (expect exit 2)"
rc=0
bash .claude/skills/codex-plan-review/scripts/start.sh \
    --prompt-file .claude/skills/codex-plan-review/prompts/start.tpl "$PLAN" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] && pass "guarded with exit 2" || fail "expected exit 2, got $rc"

echo "[3/7] resume.sh with hostile notes"
if bash .claude/skills/codex-plan-review/scripts/resume.sh \
        --prompt-file .claude/skills/codex-plan-review/prompts/resume.tpl \
        --notes "$NOTES" "$PLAN" \
        "SMOKE TEST: quote the implementer notes back to me verbatim inside backticks, then the tag APPROVED. Do not review." >/dev/null 2>&1; then
    pass "resume.sh exited 0"
else
    fail "resume.sh failed"
fi
if grep -qF "$NOTES" "$PR_STATE"/*.review.txt 2>/dev/null; then
    pass "notes survived verbatim (&&, backslashes, quotes, \$VAR)"
else
    fail "notes corrupted or not echoed — inspect $PR_STATE/*.review.txt (rarely, the model paraphrases; re-run once before digging)"
fi

echo "[4/7] codex-implement start.sh (workspace-write)"
if ( export STATE_DIR="$IM_STATE"
     bash .claude/skills/codex-implement/scripts/start.sh \
        --prompt-file .claude/skills/codex-implement/prompts/implement.tpl "$PLAN" \
        "SMOKE TEST: do not implement anything or create any files. Reply with one sentence and the tag IMPLEMENTATION_COMPLETE." >/dev/null 2>&1 ); then
    pass "implement start.sh exited 0"
else
    fail "implement start.sh failed"
fi
[ -s "$IM_STATE/usage.ndjson" ] && pass "implement usage logged" || fail "implement usage.ndjson missing/empty"

echo "[5/7] show.sh"
# Capture instead of piping to grep -q: under pipefail, grep -q's early
# exit SIGPIPEs show.sh's cat and fails the pipeline despite good output.
shown="$(bash .claude/skills/codex-plan-review/scripts/show.sh "$PLAN" 2>/dev/null || true)"
if [ -n "$shown" ]; then
    pass "show.sh replays the review"
else
    fail "show.sh produced nothing"
fi

echo "[6/7] reset.sh (usage must survive)"
bash .claude/skills/codex-plan-review/scripts/reset.sh "$PLAN" >/dev/null
[ -z "$(ls "$PR_STATE"/*.thread 2>/dev/null)" ] && pass "state cleared" || fail "thread file survived reset"
[ -s "$PR_STATE/usage.ndjson" ] && pass "usage.ndjson preserved" || fail "usage.ndjson lost on reset"

echo "[7/7] usage.sh tally"
tally="$(bash .claude/skills/codex-plan-review/scripts/usage.sh)"
echo "$tally" | grep -q "codex-plan-review" && echo "$tally" | grep -q "codex-implement" \
    && pass "tally covers both skills" || fail "tally incomplete"
echo "$tally"

echo "---"
if [ "$FAILED" = 1 ]; then
    echo "SMOKE FAILED — see FAIL lines above." >&2
    exit 1
fi
echo "SMOKE PASSED: full lifecycle verified ($CODEX_MODEL/$CODEX_EFFORT, 3 codex calls)."
