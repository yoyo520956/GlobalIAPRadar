#!/bin/sh
# 5-minute health patrol for GlobalIAPRadar.
#
# Checks, in order:
#   1. latest GitHub Actions run status (cloud side -- the only thing that is
#      genuinely always running)
#   2. local repo integrity: dirty tree, divergence from origin/main
#   3. the archived unsigned IPA still present and readable
# Appends one line per check to /var/minis/shared/GlobalIAPRadar/health.log
#
# Deliberately never mutates anything. Detection only.

set -u

REPO=/var/minis/workspace/GlobalIAPRadar
LOGDIR=/var/minis/shared/GlobalIAPRadar
LOG="$LOGDIR/health.log"
API=https://api.github.com/repos/yoyo520956/GlobalIAPRadar

mkdir -p "$LOGDIR" 2>/dev/null
TS=$(date '+%Y-%m-%d %H:%M:%S')

say() { printf '%s\n' "$1" >> "$LOG" 2>/dev/null; printf '%s\n' "$1"; }

say "=== patrol $TS ==="

if [ -n "${GITHUB_TOKEN:-}" ]; then
    JSON=$(curl -s --max-time 25 -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "$API/actions/runs?per_page=1" 2>/dev/null)
    echo "$JSON" | python3 -c "
import json,sys
raw=sys.stdin.read()
try:
    runs=json.loads(raw).get('workflow_runs') or []
    if not runs:
        print('CI: no runs found (token or network problem)')
    else:
        r=runs[0]
        print(f\"CI: run {r['id']} {r['status']}/{r['conclusion']} sha={r['head_sha'][:8]}\")
except Exception:
    print('CI: unreadable response (network) -- not a code failure')
"
else
    say "CI: GITHUB_TOKEN not set in this shell -- skipped"
fi

if [ -d "$REPO/.git" ]; then
    ( cd "$REPO" || exit 0
      DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
      LOCAL=$(git rev-parse --short HEAD 2>/dev/null)
      REMOTE=$(git rev-parse --short @{u} 2>/dev/null)
      if [ "$DIRTY" -gt 0 ]; then
          say "GIT: $DIRTY uncommitted change(s) in the working tree"
      else
          say "GIT: clean, HEAD=$LOCAL upstream=$REMOTE"
      fi
      if [ "$LOCAL" != "$REMOTE" ]; then
          say "GIT: DIVERGED from upstream ($LOCAL vs $REMOTE)"
      fi
    ) 2>/dev/null
else
    say "GIT: repo missing at $REPO"
fi

IPA="$REPO/GlobalIAPRadar-unsigned.ipa"
if [ -f "$IPA" ]; then
    SIZE=$(wc -c < "$IPA" | tr -d ' ')
    if [ "$SIZE" -gt 400000 ] && [ "$SIZE" -lt 600000 ]; then
        say "IPA: present, $SIZE bytes"
    else
        say "IPA: SUSPICIOUS size $SIZE (expected ~485KB)"
    fi
else
    say "IPA: missing"
fi

# trim the log so it cannot grow without bound on the phone
if [ -f "$LOG" ]; then
    LINES=$(wc -l < "$LOG" | tr -d ' ')
    if [ "$LINES" -gt 400 ]; then
        tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
        say "LOG: trimmed $LINES -> 200 lines"
    fi
fi

say "patrol done"
exit 0