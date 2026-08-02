#!/usr/bin/env bash
# Turn 1: start a fresh Codex review session for <target>, capture
# the thread_id from the JSON event stream, and write the final review
# to the per-target review file.
#
# Usage: start.sh --prompt-file <tpl> <target> [extra prompt text...]
# Exits 0 on success, 1 on Codex / thread_id capture failure,
# 2 on an existing thread (use reset.sh first).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

PROMPT_FILE=""
IMAGE_ARGS=()
SCHEMA_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --prompt-file)
            PROMPT_FILE="$2"; shift 2 ;;
        --prompt-file=*)
            PROMPT_FILE="${1#*=}"; shift ;;
        --image)
            IMAGE_ARGS+=("-i" "$2"); shift 2 ;;
        --image=*)
            IMAGE_ARGS+=("-i" "${1#*=}"); shift ;;
        --output-schema)
            SCHEMA_ARGS+=("--output-schema" "$2"); shift 2 ;;
        --output-schema=*)
            SCHEMA_ARGS+=("--output-schema" "${1#*=}"); shift ;;
        --) shift; break ;;
        -*)
            echo "error: unknown flag: $1" >&2; exit 64 ;;
        *) break ;;
    esac
done

if [ -z "$PROMPT_FILE" ] || [ $# -lt 1 ]; then
    echo "usage: start.sh --prompt-file <tpl> [--image <file>]... <target> [extra prompt text...]" >&2
    exit 64
fi

TARGET="$1"; shift
EXTRA_PROMPT="${*:-}"
export TARGET EXTRA_PROMPT

THREAD_FILE="$(thread_file "$TARGET")"
REVIEW_FILE="$(review_file "$TARGET")"
EVENTS_FILE="$(events_file "$TARGET")"

if [ -f "$THREAD_FILE" ]; then
    echo "error: review session already exists for $TARGET" >&2
    echo "       thread id: $(cat "$THREAD_FILE")" >&2
    echo "       run resume.sh to continue, or reset.sh to start fresh." >&2
    exit 2
fi

PROMPT="$(load_prompt "$PROMPT_FILE")"

# Run Codex non-interactively: JSONL events to stdout, last message to file.
# stdin closed to skip the "reading from stdin" detour.
# read-only sandbox: Codex only inspects files, never modifies them.
codex exec \
    --json \
    -p "$CODEX_PROFILE" \
    "${SCHEMA_ARGS[@]}" \
    "${IMAGE_ARGS[@]}" \
    --skip-git-repo-check \
    --sandbox read-only \
    --color never \
    -c model="$CODEX_MODEL" \
    -c model_reasoning_effort="$CODEX_EFFORT" \
    -c service_tier="$CODEX_SERVICE_TIER" \
    -o "$REVIEW_FILE" \
    "$PROMPT" \
    </dev/null \
    >"$EVENTS_FILE" \
    2> "$EVENTS_FILE.stderr" || {
        rc=$?
        echo "error: codex exec failed (rc=$rc)" >&2
        echo "stderr tail:" >&2
        tail -20 "$EVENTS_FILE.stderr" >&2
        exit 1
    }

log_usage "$EVENTS_FILE"
extract_structured "$REVIEW_FILE" "$(verdict_file "$TARGET")"

# Capture thread_id from the first thread.started event.
# (Windows: jq-free — Git Bash on Windows has no jq. Split on '"' and take
# the field two positions after the "thread_id" key.)
THREAD_ID="$(awk -F'"' '/thread\.started/ { for (i = 1; i < NF; i++) if ($i == "thread_id") { print $(i+2); exit } }' "$EVENTS_FILE" 2>/dev/null)"

if [ -z "$THREAD_ID" ] || [ "$THREAD_ID" = "null" ]; then
    echo "error: no thread.started event found in $EVENTS_FILE" >&2
    echo "first 20 events:" >&2
    head -20 "$EVENTS_FILE" >&2
    exit 1
fi

printf '%s\n' "$THREAD_ID" > "$THREAD_FILE"
echo "started review session for $TARGET"
echo "  thread id:   $THREAD_ID"
echo_run_footer
echo "  review file: $REVIEW_FILE"
echo "---"
cat "$REVIEW_FILE"
