#!/bin/sh
# Download and summarize GitHub Actions logs for a run id.
set -e
RUN="$1"
OUT="/tmp/ghlogs_$RUN"
rm -rf "$OUT"; mkdir -p "$OUT"
cd "$OUT"
curl -sL -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/yoyo520956/GlobalIAPRadar/actions/runs/$RUN/logs" \
  -o logs.zip
echo "size=$(wc -c < logs.zip)"
unzip -o -q logs.zip || true
find . -name '*.txt' | head -50
