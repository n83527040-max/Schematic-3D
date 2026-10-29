#!/usr/bin/env bash
# Collect /tmp/*.log diagnostics and post them as a commit comment so the
# dev sandbox (where Actions log/artifact endpoints are flaky) can fetch the
# results via api.github.com. Best-effort: never fails the job itself.
set -u

OUT=/tmp/combined.md
{
  echo "## pub get (tail)";            tail -n 40 /tmp/pubget.log 2>/dev/null
  echo "## gen-l10n (tail)";            tail -n 40 /tmp/genl10n.log 2>/dev/null
  echo "## flutter analyze (tail)";     tail -n 150 /tmp/analyze.log 2>/dev/null
  echo "## flutter test (tail)";        tail -n 1500 /tmp/flutter-test.log 2>/dev/null
  echo "## flutter build apk (tail)";   tail -n 220 /tmp/apk.log 2>/dev/null
} > "$OUT"

python3 - "$OUT" <<'PYEOF'
import json, os, subprocess, sys

body = open(sys.argv[1]).read()[-58000:]
payload = json.dumps({"body": body})
sha = os.environ["GITHUB_SHA"]
repo = os.environ["GITHUB_REPOSITORY"]
tok = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN", "")
r = subprocess.run(
    [
        "curl", "-sS", "-X", "POST",
        f"https://api.github.com/repos/{repo}/commits/{sha}/comments",
        "-H", f"Authorization: Bearer {tok}",
        "-H", "Accept: application/vnd.github+json",
        "--data", payload,
    ],
    capture_output=True, text=True,
)
print("comment response:", r.stdout[-300:], r.stderr[-200:])

# Fallback channel: push the log onto a dedicated branch (contents:write).
if "created_at" not in r.stdout:
    import tempfile, shutil
    work = tempfile.mkdtemp()
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    cmds = [
        ["git", "clone", "--depth", "1",
         f"https://x-access-token:{tok}@github.com/{repo}.git", work],
        ["git", "-C", work, "checkout", "-B", "ci-logs"],
        ["git", "-C", work, "rm", "-rf", "--ignore-unmatch", "logs"],
    ]
    dst = os.path.join(work, "logs")
    os.makedirs(dst, exist_ok=True)
    for f in ("pubget.log", "genl10n.log", "analyze.log", "flutter-test.log", "apk.log"):
        src = f"/tmp/{f}"
        if os.path.exists(src):
            shutil.copy(src, os.path.join(dst, f))
    shutil.copy(sys.argv[1], os.path.join(dst, "combined.md"))
    cmds += [
        ["git", "-C", work, "add", "-A"],
        ["git", "-C", work, "-c", "user.email=ci@arena", "-c",
         "user.name=arena-ci", "commit", "-q", "-m", f"ci logs {sha[:8]}"],
        ["git", "-C", work, "push", "-f", "origin", "ci-logs"],
    ]
    for c in cmds:
        rr = subprocess.run(c, capture_output=True, text=True, env=env)
        if rr.returncode != 0:
            print("fallback cmd failed:", c[1:3], rr.stdout[-200:], rr.stderr[-300:])
PYEOF
echo "post_logs_comment done"
