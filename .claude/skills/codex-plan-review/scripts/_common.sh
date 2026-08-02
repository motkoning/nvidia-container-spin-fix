#!/usr/bin/env bash
# Shared paths, key derivation, and prompt-loading helpers for the
# codex-plan-review and codex-code-review skills. Source-only.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# STATE_DIR can be overridden by the caller (e.g., codex-code-review
# exports its own state path before invoking the shared scripts).
# Default falls back to the script's own skill directory.
: "${STATE_DIR:=$SKILL_DIR/state}"
export STATE_DIR
mkdir -p "$STATE_DIR"

# Model/effort per flow (single source of truth for all codex skills).
# Routing rebalanced 2026-08-02 on benchmark evidence (bench/reports/,
# T5 + July grid): implementation quality is saturated across models AND
# effort levels, and terra-high was fastest in every measurement — so
# TERRA implements, SOL reviews. Sol @ xhigh for hardening reviews
# (thoroughness over latency), Sol @ high for codex-ask (advisory speed).
# Override per run via CODEX_MODEL / CODEX_EFFORT as ever.
case "$STATE_DIR" in
    *codex-implement*)
        CODEX_MODEL="${CODEX_MODEL:-gpt-5.6-terra}"
        CODEX_EFFORT="${CODEX_EFFORT:-high}"
        ;;
    *codex-ask*)
        CODEX_MODEL="${CODEX_MODEL:-gpt-5.6-sol}"
        CODEX_EFFORT="${CODEX_EFFORT:-high}"
        ;;
    *)
        CODEX_MODEL="${CODEX_MODEL:-gpt-5.6-sol}"
        CODEX_EFFORT="${CODEX_EFFORT:-xhigh}"
        ;;
esac
# Service tier (inference speed): pinned to "fast" (the 2026-07-30 rename of
# "priority") so the desktop app's speed toggle can't silently retune workers
# via the shared ~/.codex/config.toml. Fast is ~1.5x speed at 2.5x credit burn
# on ChatGPT plans — use CODEX_SERVICE_TIER=standard for bulk/benchmark runs.
CODEX_SERVICE_TIER="${CODEX_SERVICE_TIER:-fast}"
# Lean worker profile (~/.codex/worker.config.toml overlay): strips the desktop
# plugin catalog from worker context (the "2% skills budget" tax). Applies on
# session START only — `codex exec resume` rejects -p (verified 2026-08-02).
CODEX_PROFILE="${CODEX_PROFILE:-worker}"
export CODEX_MODEL CODEX_EFFORT CODEX_SERVICE_TIER CODEX_PROFILE

# Append this run's token usage (the turn.completed events in $1) to
# $STATE_DIR/usage.ndjson, tagged with timestamp, model, effort, and
# target. The events file is overwritten on every turn, so usage.ndjson
# is the only durable usage record; usage.sh sums it. Must never fail
# the calling script.
log_usage() {
    local events="$1"
    [ -f "$events" ] || return 0
    # JSON-escape the target in bash (awk -v would mangle backslashes).
    local tgt="${TARGET-}"
    tgt="${tgt//\\/\\\\}"
    tgt="${tgt//\"/\\\"}"
    TGT_JSON="$tgt" awk -v ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        -v model="$CODEX_MODEL" -v effort="$CODEX_EFFORT" -v tier="$CODEX_SERVICE_TIER" '
        /"type":"turn\.completed"/ && match($0, /"usage":\{[^}]*\}/) {
            printf "{\"ts\":\"%s\",\"model\":\"%s\",\"effort\":\"%s\",\"tier\":\"%s\",\"target\":\"%s\",%s}\n",
                ts, model, effort, tier, ENVIRON["TGT_JSON"], substr($0, RSTART, RLENGTH)
        }
    ' "$events" >> "$STATE_DIR/usage.ndjson" || true
}

# Uncached input tokens of the most recent logged call = this thread's
# working weight. Resume turns re-process accumulated history, so this
# climbs every batch; past ~350k a reset buys back most of the latency
# (see TRIP-2-implement's reset trigger). Prints nothing if unknown.
last_uncached_input() {
    [ -f "$STATE_DIR/usage.ndjson" ] || return 0
    tail -1 "$STATE_DIR/usage.ndjson" | awk '
        match($0, /"input_tokens":[0-9]+/)        { i = substr($0, RSTART + 15, RLENGTH - 15) }
        match($0, /"cached_input_tokens":[0-9]+/) { c = substr($0, RSTART + 22, RLENGTH - 22) }
        END { if (i != "") print i - c }
    '
}

# Echo the effective settings plus thread weight, warning once the
# thread is heavy enough that a reset is worth considering.
echo_run_footer() {
    echo "  model/effort/tier: $CODEX_MODEL / $CODEX_EFFORT / $CODEX_SERVICE_TIER"
    local uncached
    uncached="$(last_uncached_input)"
    if [ -n "$uncached" ]; then
        echo "  uncached input: $uncached tokens"
        if [ "$uncached" -gt 350000 ] 2>/dev/null; then
            echo "  NOTE: heavy thread (>350k uncached input) — every further turn re-processes it."
            case "$STATE_DIR" in
                *codex-implement*)
                    echo "        Reset at the NEXT BATCH BOUNDARY (never mid-batch); rebuild with the"
                    echo "        plan path, done checkboxes, and accumulated conventions. See TRIP-2." ;;
                *)
                    echo "        Normal as review rounds accumulate — do NOT reset mid-convergence"
                    echo "        (the reviewer would forget what it already accepted). Finish the"
                    echo "        loop; state is cleared for you at release (TRIP-3 Step 13)." ;;
            esac
        fi
    fi
}

# Derive a per-target key from a path-like string. For real paths we
# resolve to absolute; for non-path targets (branch names, commit
# ranges) we sanitize in place. Replace '/' with '__'; force any other
# non-portable characters to '_'.
target_key() {
    local target="$1"
    if [ -e "$target" ]; then
        local abs
        abs="$(realpath -- "$target" 2>/dev/null || readlink -f -- "$target")"
        if [ -z "$abs" ]; then
            echo "error: cannot resolve target path: $target" >&2
            return 1
        fi
        printf '%s' "$abs" | sed 's|^/||; s|/|__|g'
    else
        printf '%s' "$target" | sed 's|^/||; s|/|__|g; s|[^A-Za-z0-9._-]|_|g'
    fi
}

# Backwards-compatible alias used by older script call sites.
plan_key() { target_key "$@"; }

thread_file() {
    printf '%s/%s.thread' "$STATE_DIR" "$(target_key "$1")"
}

review_file() {
    printf '%s/%s.review.txt' "$STATE_DIR" "$(target_key "$1")"
}

events_file() {
    printf '%s/%s.events.ndjson' "$STATE_DIR" "$(target_key "$1")"
}

verdict_file() {
    printf '%s/%s.verdict' "$STATE_DIR" "$(target_key "$1")"
}

# When a structured output schema was used (--output-schema), the -o file
# holds JSON: {verdict, report}. Split it — machine-readable verdict to a
# sidecar, prose back into the report file WITH the verdict re-appended as
# the familiar trailing tag, so every existing tag parser, show.sh replay,
# and CR promotion keeps working unchanged; the schema just makes the tag
# guaranteed instead of prompt-disciplined. Python, not jq: the kit's floor
# is jq-free Git Bash + Python (SETUP §0). No-op when no schema was passed
# or the file isn't JSON (model fallback) — never fails the calling script.
extract_structured() {
    local file="$1" sidecar="$2"
    [ "${#SCHEMA_ARGS[@]}" -gt 0 ] 2>/dev/null || return 0
    python - "$file" "$sidecar" <<'PYEOF' || true
import json, sys
path, sidecar = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(path, encoding="utf-8"))
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
verdict = str(d.get("verdict", "") or "")
report = str(d.get("report", "") or "")
if report or verdict:
    body = report.rstrip()
    if verdict and not body.endswith(verdict):
        body = (body + "\n\n" if body else "") + verdict
    open(path, "w", encoding="utf-8").write(body + "\n")
if verdict:
    open(sidecar, "w", encoding="utf-8").write(verdict + "\n")
    print("  verdict: " + verdict)
PYEOF
}

# Load a prompt template from $1 and substitute {{TARGET}} and
# {{EXTRA_PROMPT}} placeholders with the values of the $TARGET and
# $EXTRA_PROMPT environment variables. Other text passes through
# verbatim — no surprise expansion of unrelated $VAR sequences.
# Values are spliced literally via index/substr and ENVIRON: gsub()
# replacement would mangle '&' and '\' (awk -v also eats backslashes),
# and notes/extra routinely carry both. Writes the prompt to stdout.
load_prompt() {
    local tpl="$1"
    if [ ! -f "$tpl" ]; then
        echo "error: prompt template not found: $tpl" >&2
        return 1
    fi
    TPL_TARGET="${TARGET-}" TPL_EXTRA="${EXTRA_PROMPT-}" TPL_NOTES="${IMPLEMENTER_NOTES-}" awk '
        function replace_all(s, key, val,    out, i) {
            out = ""
            while ((i = index(s, key)) > 0) {
                out = out substr(s, 1, i - 1) val
                s = substr(s, i + length(key))
            }
            return out s
        }
        {
            line = $0
            line = replace_all(line, "{{TARGET}}", ENVIRON["TPL_TARGET"])
            line = replace_all(line, "{{EXTRA_PROMPT}}", ENVIRON["TPL_EXTRA"])
            line = replace_all(line, "{{IMPLEMENTER_NOTES}}", ENVIRON["TPL_NOTES"])
            print line
        }
    ' "$tpl"
}
