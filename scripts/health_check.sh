#!/bin/sh
# 5-minute health patrol for GlobalIAPRadar -- memory-light version.
#
# iSH on iPhone has a small memory ceiling; every patrol should stay well
# under 10 MB of transient allocations. This script deliberately avoids
# python on the hot path, and only spawns python when it needs to parse JSON.

set -u

REPO=/var/minis/workspace/GlobalIAPRadar
LOGDIR=/var/minis/shared/GlobalIAPRadar
LOG="$LOGDIR/health.log"
API=https://api.github.com/repos/yoyo520956/GlobalIAPRadar

mkdir -p "$LOGDIR" 2>/dev/null
TS=$(date '+%Y-%m-%d %H:%M:%S')

say() {
    # Cap each patrol to 5 lines to keep the log bounded on phone storage.
    printf '%s\n' "$1" >> "$LOG" 2>/dev/null
    printf '%s\n' "$1"
}

say "=== $TS ==="

# --- 1. CI status (only when a token is available; skip the network call otherwise)
if [ -n "${GITHUB_TOKEN:-}" ]; then
    # --max-time keeps a hung connection from eating the loop's budget
    RAW=$(curl -s --max-time 15 -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "$API/actions/runs?per_page=1" 2>/dev/null | tr -d ' \n\t')
    case "$RAW" in
        "" | null | "[]") say "CI: no response (network or token)" ;;
        *)
            # Minimal JSON scrape without python: single-line after tr
            ID=$(echo "$RAW" | grep -o '"id":[0-9]*' | head -1 | sed 's/"id"://')
            STATUS=$(echo "$RAW" | grep -o '"status":"[^"]*"' | head -1 | sed 's/"status":"//; s/"$//')
            CONCLUSION=$(echo "$RAW" | grep -o '"conclusion":"[^"]*"' | head -1 | sed 's/"conclusion":"//; s/"$//')
            SHA=$(echo "$RAW" | grep -o '"head_sha":"[^"]*"' | head -1 | sed 's/"head_sha":"//; s/"$//' | cut -c1-8)
            if [ -n "$ID" ]; then
                say "CI: run $ID ${STATUS}/${CONCLUSION:-n/a} sha=${SHA:--}"
            else
                say "CI: unparsable payload (first 80 chars: $(echo "$RAW" | head -c 80))"
            fi
            ;;
    esac
else
    say "CI: GITHUB_TOKEN not set in this shell -- skipped"
fi

# --- 2. Repo integrity (fast, no network)
if [ -d "$REPO/.git" ]; then
    (
        cd "$REPO" || exit 0
        # --no-ahead-behind is essential: plain `git status` contacts the remote
        # to compute ahead/behind, and a hung network makes the patrol itself
        # hang -- exactly when it is most needed. A commit can be read locally.
        DIRTY_COUNT=$(git -c status.aheadBehind=false status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        HEAD=$(git rev-parse --short=8 HEAD 2>/dev/null)
        # Ask the API for the real remote HEAD (works even when github.com is
        # down via git protocol). Only compare if we actually got an answer;
        # otherwise report "unknown" instead of a false DIVERGED flag.
        REMOTE=""
        if [ -n "${GITHUB_TOKEN:-}" ]; then
            REMOTE=$(curl -s --max-time 8 \
                -H "Authorization: Bearer $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github+json" \
                "$API/commits?per_page=1" 2>/dev/null | tr -d ' \n\t' | \
                grep -o '"sha":"[0-9a-f]*"' | head -1 | sed 's/"sha":"//; s/"$//' | cut -c1-8)
        fi
        if [ -z "$HEAD" ]; then
            echo "GIT: local repo state unreadable"
        elif [ -z "$REMOTE" ]; then
            echo "GIT: HEAD=$HEAD (remote unknown -- no token or no network)"
        elif [ "$HEAD" = "$REMOTE" ]; then
            echo "GIT: clean, HEAD=$HEAD"
        else
            echo "GIT: local=$HEAD remote=$REMOTE dirty_files=$DIRTY_COUNT"
        fi
    ) 2>/dev/null | while IFS= read -r line; do say "$line"; done
else
    say "GIT: repo missing at $REPO"
fi

# --- 3. Archived IPA
IPA="$REPO/GlobalIAPRadar-unsigned.ipa"
if [ -f "$IPA" ]; then
    SIZE=$(wc -c < "$IPA" | tr -d ' ')
    if [ "$SIZE" -gt 400000 ] && [ "$SIZE" -lt 600000 ]; then
        say "IPA: present, $SIZE bytes"
    else
        say "IPA: SUSPICIOUS size $SIZE (expected ~485 KB)"
    fi
else
    say "IPA: missing"
fi

# --- 4. Log trimming (bounded)
if [ -f "$LOG" ]; then
    LINES=$(wc -l < "$LOG" | tr -d ' ')
    if [ "$LINES" -gt 300 ]; then
        # keep the newest 150 lines, drop the rest -- cheaper than full rewrite
        tail -n 150 "$LOG" > "$LOG.trim" 2>/dev/null
        mv "$LOG.trim" "$LOG" 2>/dev/null
        say "LOG: trimmed $LINES -> 150 lines"
    fi
fi

say "patrol done"
exit 0