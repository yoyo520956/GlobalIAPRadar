#!/usr/bin/env python3
"""Push a single file change via the GitHub Contents API.

Fallback for when `git push` cannot reach github.com but api.github.com works.
Usage: push_file_api.py <repo> <path-in-repo> <local-file> <commit-message>
"""
import base64
import json
import os
import sys
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
    with urllib.request.urlopen(req, timeout=40) as resp:
        return json.load(resp)


def main():
    repo, path, local, message = sys.argv[1:5]
    base = f"https://api.github.com/repos/{repo}/contents/{path}"

    existing = api("GET", base)
    content = base64.b64encode(open(local, "rb").read()).decode()
    result = api("PUT", base, {
        "message": message,
        "content": content,
        "sha": existing["sha"],
        "branch": "main",
    })
    print("committed:", result["commit"]["sha"])


if __name__ == "__main__":
    main()
