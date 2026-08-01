#!/usr/bin/env bash
# Token-usage tally across all codex skills' state dirs, summed from the
# usage.ndjson lines that log_usage appends after every codex exec.
# "uncached-in" (input minus cached input) plus output is the
# quota-relevant spend on the ChatGPT plan.
#
# Usage: usage.sh   (no arguments; scans sibling skills of this script's skill)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

files=()
for f in "$SKILLS_ROOT"/*/state/usage.ndjson; do
    [ -f "$f" ] && files+=("$f")
done
if [ ${#files[@]} -eq 0 ]; then
    echo "no usage recorded yet (no state/usage.ndjson under $SKILLS_ROOT)"
    exit 0
fi

awk '
function num(key,    m) {
    if (match($0, "\"" key "\":[0-9]+")) {
        m = substr($0, RSTART, RLENGTH); sub(/.*:/, "", m); return m + 0
    }
    return 0
}
function str(key,    m) {
    if (match($0, "\"" key "\":\"[^\"]*\"")) {
        m = substr($0, RSTART, RLENGTH); sub(/^[^:]*:"/, "", m); sub(/"$/, "", m)
        return m
    }
    return "?"
}
{
    n = split(FILENAME, parts, "/")
    skill = parts[n - 2]
    k = skill "|" str("model") "|" str("effort") "|" str("tier")
    calls[k]++
    in_t[k] += num("input_tokens")
    cach[k] += num("cached_input_tokens")
    out_t[k] += num("output_tokens")
    reas[k] += num("reasoning_output_tokens")
}
END {
    fmt = "%-18s %-16s %-7s %-9s %6s %14s %14s %12s %12s\n"
    printf fmt, "skill", "model", "effort", "tier", "calls", "input", "uncached-in", "output", "reasoning"
    for (k in calls) {
        split(k, p, "|")
        printf fmt, p[1], p[2], p[3], p[4], calls[k], in_t[k], in_t[k] - cach[k], out_t[k], reas[k]
        tc += calls[k]; ti += in_t[k]; tu += in_t[k] - cach[k]; to += out_t[k]; tr += reas[k]
    }
    printf fmt, "TOTAL", "", "", "", tc, ti, tu, to, tr
}
' "${files[@]}"
