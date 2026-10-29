#!/usr/bin/env python3
"""Post a text file as a commit comment (used by release.yml to surface
publish diagnostics — the raw runner log host is not always fetchable).

Usage: post_commit_comment.py <sha> <body-file>
Reads GITHUB_REPOSITORY + GITHUB_TOKEN (or GH_TOKEN) from the environment.
"""
import json
import os
import sys
import urllib.request


def main() -> int:
    sha, path = sys.argv[1], sys.argv[2]
    body = open(path, encoding="utf-8").read()[:60000]
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""
    req = urllib.request.Request(
        "https://api.github.com/repos/%s/commits/%s/comments"
        % (os.environ["GITHUB_REPOSITORY"], sha),
        data=json.dumps({"body": body}).encode(),
        headers={
            "Authorization": "token " + token,
            "Accept": "application/vnd.github+json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as r:
            print("comment posted:", r.status)
        return 0
    except Exception as e:  # diagnostics must never fail the build themselves
        print("comment failed:", e)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
