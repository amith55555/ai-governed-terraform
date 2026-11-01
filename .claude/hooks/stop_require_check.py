#!/usr/bin/env python3
"""Stop hook for Claude Code: the agent may only finish when `make check` passes.

Claude Code runs this when the agent says it is done.
  exit 0 = the agent may stop.
  exit 2 = the agent must keep working; stderr (the end of the make check output) is shown to it.
Loop limits, so a stuck agent cannot burn tokens forever:
  - at most MAX_ATTEMPTS failed checks per session, then it may stop (with a warning to the human);
  - the same failure twice in a row also stops it early.
CI reruns every check anyway, so stopping with a warning is safe. See docs/adr/0005-agent-hooks.md.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

MAX_ATTEMPTS = 3
TAIL_LINES = 40
CHECK_CMD = ["make", "check"]
STATE_DIR = os.path.join(tempfile.gettempdir(), "aigt-stop-hook")


def has_changes(root):
    """True if there is anything to check: uncommitted files or commits not on origin/main."""
    status = subprocess.run(["git", "status", "--porcelain"], cwd=root, capture_output=True, text=True)
    if status.returncode != 0 or status.stdout.strip():
        return True
    ahead = subprocess.run(["git", "rev-list", "--count", "origin/main..HEAD"], cwd=root, capture_output=True, text=True)
    if ahead.returncode != 0:
        return True  # cannot tell: check to be safe
    return ahead.stdout.strip() != "0"


def tail(text, lines=TAIL_LINES):
    return "\n".join(text.strip().splitlines()[-lines:])


def decide(state, passed, output):
    """Pure decision logic. Returns (allow_stop, new_state, message)."""
    if passed:
        return True, {"attempts": 0, "last_hash": None}, None
    attempts = state.get("attempts", 0) + 1
    digest = hashlib.sha256(tail(output).encode()).hexdigest()
    if digest == state.get("last_hash"):
        return True, {"attempts": 0, "last_hash": None}, (
            "make check failed with the same error twice in a row: stopping. A human needs to look."
        )
    if attempts >= MAX_ATTEMPTS:
        return True, {"attempts": 0, "last_hash": None}, (
            f"make check still failing after {attempts} attempts: stopping. A human needs to look."
        )
    return False, {"attempts": attempts, "last_hash": digest}, (
        f"make check failed (attempt {attempts} of {MAX_ATTEMPTS}). Fix the cause; do not weaken a check.\n"
        f"Last {TAIL_LINES} lines:\n{tail(output)}"
    )


def state_path(session_id):
    safe = re.sub(r"[^A-Za-z0-9_-]", "_", session_id or "unknown")
    return os.path.join(STATE_DIR, f"{safe}.json")


def load_state(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(path, state):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(state, f)


def run(payload, root, check_cmd=CHECK_CMD):
    """Returns (exit_code, stderr_text, stdout_text)."""
    if not has_changes(root):
        return 0, "", ""
    result = subprocess.run(check_cmd, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    path = state_path(payload.get("session_id"))
    allow, new_state, message = decide(load_state(path), result.returncode == 0, result.stdout)
    save_state(path, new_state)
    if allow:
        stdout = json.dumps({"systemMessage": message}) if message else ""
        return 0, "", stdout
    return 2, message, ""


def main():
    try:
        payload = json.load(sys.stdin)
        root = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd())
        code, err, out = run(payload, root)
    except Exception as exc:
        # Fail visibly, not closed: blocking here could loop forever, and CI rechecks everything.
        code, err = 0, ""
        out = json.dumps({"systemMessage": f"completion hook error ({exc.__class__.__name__}): make check was NOT verified"})
    if out:
        print(out)
    if err:
        print(err, file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
