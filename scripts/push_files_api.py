#!/usr/bin/env python3
"""Push several files via the GitHub Contents API (one commit per file).

Fallback for when `git push` cannot reach github.com but api.github.com works.

Usage: push_files_api.py <repo> <local:remote> ...
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

TOKEN = os.environ.get("GITHUB_TOKEN")
if not TOKEN:
    sys.exit("GITHUB_TOKEN not set")


def api(method, url, payload=None):
    req = urllib.request.Request(
        url,
        method=method,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
        data=json.dumps(payload).encode() if payload is not None else None,
    )
    try:
        with urllib.request.urlopen(req, timeout=40) as resp:
            return resp.status, json.load(resp)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return 404, None
        raise


def push(repo, local, remote, message):
    base = f"https://api.github.com/repos/{repo}/contents/{remote}"
    status, existing = api("GET", base)
    payload = {
        "message": message,
        "content": base64.b64encode(open(local, "rb").read()).decode(),
        "branch": "main",
    }
    if existing:
        payload["sha"] = existing["sha"]
    status, result = api("PUT", base, payload)
    return result["commit"]["sha"]


def main():
    repo = sys.argv[1]
    message = sys.argv[2]
    for pair in sys.argv[3:]:
        local, remote = pair.split(":", 1)
        sha = push(repo, local, remote, message)
        print(f"{remote} -> {sha}")


if __name__ == "__main__":
    main()