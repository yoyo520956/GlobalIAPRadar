#!/bin/sh
# Creates the GitHub repository (if missing) and pushes the project.
# The token is read from the environment and never written to disk or echoed.
set -eu
cd /var/minis/workspace/GlobalIAPRadar

USER_JSON=$(curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/user)
LOGIN=$(printf '%s' "$USER_JSON" | jq -r .login)
ID=$(printf '%s' "$USER_JSON" | jq -r .id)
echo "github user: $LOGIN (id $ID)"

git init -q 2>/dev/null || true
git config user.name "$LOGIN"
git config user.email "$ID+$LOGIN@users.noreply.github.com"
git checkout -B main 2>/dev/null || true
git add -A
git commit -q -m "Global IAP Radar: native SwiftUI radar for App Store IAP prices across 175 storefronts" \
  || echo "(no changes to commit)"

REPO_NAME=GlobalIAPRadar
CODE=$(curl -sS -o /tmp/repo.json -w '%{http_code}' -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/$LOGIN/$REPO_NAME")
if [ "$CODE" != "200" ]; then
  echo "creating repository $REPO_NAME ..."
  curl -sS -X POST -H "Authorization: Bearer $GITHUB_TOKEN" -H 'Content-Type: application/json' \
    https://api.github.com/user/repos \
    -d "{\"name\":\"$REPO_NAME\",\"description\":\"Global App Store in-app purchase price radar across 175 storefronts (SwiftUI native)\",\"private\":false,\"license_template\":\"mit\",\"has_issues\":true}" \
    | jq -r '.html_url // .message'
  sleep 2
fi

git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$LOGIN/$REPO_NAME.git"
AUTH=$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')
git -c http.extraheader="AUTHORIZATION: basic $AUTH" push -u origin main
echo "PUSH_OK https://github.com/$LOGIN/$REPO_NAME"
