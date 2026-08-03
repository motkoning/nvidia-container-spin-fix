#!/usr/bin/env bash
# Attribution audit — the drift detector. Answers mechanically: which commits
# trace to Codex dispatches, and which were implemented solo?
#
# A compacted orchestrator session can silently stop dispatching and implement
# by hand while still committing and self-reviewing (observed 2026-08-02).
# Quality signals cannot catch that; attribution can: every real dispatch
# leaves a usage.ndjson line in a skill state dir. This script correlates
# git commits against that telemetry.
#
# Usage: audit.sh [--since <git-ref | approxidate>]   (default: "14 days ago")
#   audit.sh --since v3.2.0        # release range
#   audit.sh --since "2 days ago"
# Read-only. Exit 0 = clean; 2 = substantial commits with no dispatch
# evidence (investigate via /TRIP-audit); 1 = error.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "error: not inside a git repository" >&2; exit 1; }
SINCE="${2:-14 days ago}"
if [ "${1-}" != "" ] && [ "${1-}" != "--since" ]; then
    echo "usage: audit.sh [--since <git-ref | approxidate>]" >&2; exit 1
fi
cd "$ROOT"
python - "$SINCE" <<'PYEOF'
import glob, json, os, subprocess, sys, time, calendar

since = sys.argv[1]

def git(*args):
    return subprocess.run(["git"] + list(args), capture_output=True,
                          text=True, encoding="utf-8", errors="replace").stdout

# --since accepts a ref (range mode) or an approxidate (time mode).
is_ref = subprocess.run(["git", "rev-parse", "--verify", "--quiet", since + "^{commit}"],
                        capture_output=True).returncode == 0
log_args = [since + "..HEAD"] if is_ref else ["--since=" + since]
raw = git("log", *log_args, "--no-merges", "--format=%H\t%ct\t%s")
commits = []
# Paths whose changes are legitimate solo work under the triage rules:
# docs, generated imagery, and the kit's own files.
import re
DOCS_RE = re.compile(
    r"^(docs/|\.claude/|\.gitattributes$|\.gitignore$|CLAUDE\.md$|AGENTS\.md$"
    r"|CHANGELOG|README)|\.(md|png|jpe?g|gif|svg|ico)$", re.IGNORECASE)

for line in raw.splitlines():
    sha, ct, subj = line.split("\t", 2)
    stat = git("show", "--numstat", "--format=", sha)
    lines_changed, binary, docs_only = 0, False, True
    for s in stat.splitlines():
        parts = s.split("\t")
        if len(parts) == 3:
            if parts[0] == "-":
                binary = True
            else:
                lines_changed += int(parts[0]) + int(parts[1])
            if not DOCS_RE.search(parts[2]):
                docs_only = False
    # A TRIP-Dispatch: trailer is declarative evidence — integration commits
    # (promote patch-lifts, multi-commit batches) name their worker thread.
    trailer = "trip-dispatch:" in git("show", "-s", "--format=%B", sha).lower()
    commits.append({"sha": sha, "t": int(ct), "subj": subj, "lines": lines_changed,
                    "binary": binary, "docs_only": docs_only, "trailer": trailer})
commits.sort(key=lambda c: c["t"])
if len(commits) > 200:
    print(f"note: {len(commits)} commits in range, auditing the most recent 200")
    commits = commits[-200:]

calls = []
for path in glob.glob(".claude/skills/*/state/usage.ndjson"):
    flow = os.path.basename(os.path.dirname(os.path.dirname(path)))
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
            t = calendar.timegm(time.strptime(d["ts"], "%Y-%m-%dT%H:%M:%SZ"))
            calls.append({"t": t, "flow": flow, "target": str(d.get("target", ""))})
        except (ValueError, KeyError):
            continue
calls.sort(key=lambda c: c["t"])

def fmt(t):
    return time.strftime("%m-%d %H:%M", time.localtime(t))

TRIVIAL_LINES = 30   # matches the routing-block triage threshold
WINDOW = 8 * 3600    # lookback for the first commit / review evidence
flags = 0
print(f"attribution audit — {len(commits)} commits, {len(calls)} logged Codex calls "
      f"({'range ' + since + '..HEAD' if is_ref else 'since ' + since})")
print()
for i, c in enumerate(commits):
    prev_t = commits[i - 1]["t"] if i else c["t"] - WINDOW
    impl = [x for x in calls if x["flow"] == "codex-implement" and prev_t < x["t"] <= c["t"]]
    rev  = [x for x in calls if x["flow"] == "codex-code-review" and c["t"] - WINDOW < x["t"] <= c["t"]]
    size = f"{c['lines']}L" + ("+bin" if c["binary"] else "")
    if c["trailer"]:
        tag, ev = "DISPATCHED", "TRIP-Dispatch commit trailer (declared worker thread)"
    elif impl:
        tag, ev = "DISPATCHED", f"{len(impl)} impl call(s), last: {impl[-1]['target'][:40]}"
    elif c["docs_only"]:
        tag, ev = "solo-docs", "docs/kit/imagery paths only — legitimate solo class"
    elif c["lines"] <= TRIVIAL_LINES and not c["binary"]:
        tag, ev = "solo-trivial", "no dispatch since prev commit (within triage threshold)"
    else:
        tag, ev = "DRIFT?", "no implement dispatch since previous commit"
        flags += 1
    rtag = "reviewed" if rev else "no-review"
    print(f"  {c['sha'][:8]}  {fmt(c['t'])}  {tag:12} {rtag:10} {size:>9}  {c['subj'][:52]}")
    print(f"           {ev}")
print()
if flags:
    print(f"{flags} substantial commit(s) lack dispatch evidence. Before accusing, check")
    print("the false-positive cases: multi-commit integrations from ONE spike/promote or")
    print("implement thread (verify via the thread's events file), and work done before")
    print("this kit was installed. Real drift => run the /TRIP-audit recovery procedure.")
    sys.exit(2)
print("clean: every substantial commit has dispatch evidence.")
PYEOF
