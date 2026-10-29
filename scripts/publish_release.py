#!/usr/bin/env python3
"""Publish (or repair) a GitHub Release for a tag with direct-download assets.

Runs on the CI runner. Talks only to api.github.com / uploads.github.com with
plain HTTPS; on ANY error it posts the full traceback + context as a commit
comment (fetchable via the API) before exiting non-zero, so failures are
never invisible.

Usage:  publish_release.py <tag> <asset-path> [<asset-path> ...]
Env:    GITHUB_REPOSITORY, GITHUB_SHA, GITHUB_TOKEN, GITHUB_STEP_SUMMARY,
        RELEASE_NOTES_FILE (optional).
"""
import json
import mimetypes
import os
import sys
import traceback
import urllib.error
import urllib.request

API = "https://api.github.com"
UPLOADS = "https://uploads.github.com"


def _req(method, url, body=None, headers=None, data=None):
    h = {
        "Authorization": "token " + os.environ["GITHUB_TOKEN"],
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if headers:
        h.update(headers)
    return urllib.request.Request(url, data=data, headers=h, method=method) \
        if body is None else urllib.request.Request(
            url, data=json.dumps(body).encode(),
            headers={**h, "Content-Type": "application/json"}, method=method)


def _call(method, url, body=None):
    with urllib.request.urlopen(_req(method, url, body)) as r:
        raw = r.read()
        return json.loads(raw) if raw and r.status != 204 else {}


def _safe_note(lines):
    """Persist diagnostics to step summary + commit comment, never raising."""
    txt = "\n".join(lines)
    try:
        summ = os.environ.get("GITHUB_STEP_SUMMARY")
        if summ:
            with open(summ, "a", encoding="utf-8") as f:
                f.write("```\n" + txt + "\n```\n")
    except Exception:
        pass
    try:
        sha = os.environ.get("GITHUB_SHA", "")
        repo = os.environ.get("GITHUB_REPOSITORY", "")
        if sha and repo:
            _call("POST", f"{API}/repos/{repo}/commits/{sha}/comments",
                  {"body": "## publish_release.py\n\n```\n" + txt[:58000] + "\n```"})
    except Exception:
        pass


def main():
    tag = sys.argv[1]
    assets = sys.argv[2:]
    repo = os.environ["GITHUB_REPOSITORY"]
    notes_file = os.environ.get("RELEASE_NOTES_FILE", "")
    notes = open(notes_file, encoding="utf-8").read() if notes_file else tag
    log = [f"tag={tag} repo={repo} assets={assets}"]
    try:
        rel = None
        try:
            rel = _call("GET", f"{API}/repos/{repo}/releases/tags/{tag}")
            log.append(f"release exists id={rel['id']}")
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
            rel = _call("POST", f"{API}/repos/{repo}/releases", {
                "tag_name": tag, "name": f"Schematic 3D {tag}",
                "body": notes, "draft": False})
            log.append(f"release created id={rel['id']}")
        rel_id = rel["id"]
        existing = {a["name"]: a["id"]
                    for a in _call("GET", f"{API}/repos/{repo}/releases/{rel_id}/assets")}
        for path in assets:
            name = os.path.basename(path)
            if name in existing:
                _call("DELETE", f"{API}/repos/{repo}/releases/assets/{existing[name]}")
                log.append(f"replaced old asset {name}")
            blob = open(path, "rb").read()
            ctype = ("application/vnd.android.package-archive"
                     if name.endswith(".apk")
                     else mimetypes.guess_type(name)[0] or "application/zip")
            url = (f"{UPLOADS}/repos/{repo}/releases/{rel_id}/assets"
                   f"?name={name}")
            with urllib.request.urlopen(_req(
                    "POST", url, data=blob,
                    headers={"Content-Type": ctype})) as r:
                info = json.loads(r.read() or b"{}")
            log.append(f"uploaded {name} {len(blob)}B -> {info.get('browser_download_url')}")
        print("\n".join(log))
        _safe_note(log + ["RESULT: OK"])
        return 0
    except Exception:
        log.append("FATAL:\n" + traceback.format_exc())
        _safe_note(log)
        print("\n".join(log), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
