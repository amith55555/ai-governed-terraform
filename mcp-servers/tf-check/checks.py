"""The `check` tool: run the same make targets as `make check`, return short findings.

Security: the only program is `make`, the only targets are CHECK_TARGETS, there is
no shell, and the tool takes no input. test_checks.py keeps the list equal to the Makefile.
"""
import os
import re
import signal
import subprocess
import threading
import time
from pathlib import Path

from output import ANSI, MAX_FINDINGS, dedupe, finding, respond

REPO = Path(__file__).resolve().parents[2]
STEP_TIMEOUT = 300
MAX_OUTPUT = 2_000_000

# Same targets and order as `make check`, with `static` split into fmt, validate, lint.
CHECK_TARGETS = (
    "policy", "risk-test", "hook-test", "usage-test", "mcp-test", "fmt", "validate", "lint",
    "test", "secrets", "scan", "agents-md",
)
# These run `terraform init`, which must never run if the source policy failed.
NEEDS_POLICY = {"validate", "test"}

# Commands get only these variables. Everything else is dropped, such as AWS_*,
# TF_VAR_*, TF_CLI_ARGS*, GH_TOKEN, MAKEFLAGS, MAKEFILES, BASH_ENV, PYTHONPATH, LD_PRELOAD.
ENV_ALLOWED = (
    "PATH", "HOME", "LANG", "LC_ALL", "TMPDIR", "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY",
    "SSL_CERT_FILE", "TF_PLUGIN_CACHE_DIR",
)
ENV_FIXED = {
    "NO_COLOR": "1",
    "TF_IN_AUTOMATION": "1",
    "TF_INPUT": "0",
    "PYTHONDONTWRITEBYTECODE": "1",
}

LOCK = threading.Lock()


def safe_env(source=None):
    source = os.environ if source is None else source
    env = {name: source[name] for name in ENV_ALLOWED if name in source}
    env.update(ENV_FIXED)
    return env


def run_command(argv, env, timeout=STEP_TIMEOUT):
    """Run one command without a shell. Returns (exit_code, text); exit_code None means it never finished."""
    try:
        process = subprocess.Popen(
            argv, cwd=REPO, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, errors="replace", start_new_session=True,
        )
    except OSError as exc:
        return None, f"could not start {argv[0]}: {exc.__class__.__name__}"
    try:
        text, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)  # the whole group: make and everything it started
        process.communicate()
        return None, f"timed out after {timeout} seconds"
    return process.returncode, text[-MAX_OUTPUT:]


def run_make(target):
    if target not in CHECK_TARGETS:
        raise ValueError("target is not on the fixed list")
    return run_command(["make", "--no-print-directory", target], safe_env())


# ---------- parsers: tool text -> findings ----------

def plain_lines(text):
    return [line.rstrip() for line in ANSI.sub("", text).splitlines()]


def parse_conftest(step, text):
    found = []
    for line in plain_lines(text):
        match = re.match(r"^(FAIL|WARN) - (.+?) - (.+?)(?: - (.+))?$", line)
        if match:
            level, file, rule, message = match.groups()
            found.append(finding(step, rule, message or rule, file=file,
                                 severity="warning" if level == "WARN" else "error"))
    return found


def parse_guards(step, text):
    """The "FAIL: reason" and "MISSING path" lines our own scripts print."""
    found = []
    for line in plain_lines(text):
        match = re.match(r"^(?:FAIL: |MISSING\s+)(.+)$", line)
        if match:
            found.append(finding(step, "guard", match.group(1)))
    return found


def parse_fmt(step, text):
    found = []
    for line in plain_lines(text):
        if re.match(r"^terraform/\S+\.(tf|hcl)$", line):
            found.append(finding(step, "terraform_fmt", "not formatted: run terraform fmt on this file", file=line))
    return found


def parse_tflint(step, text):
    found = []
    for line in plain_lines(text):
        match = re.match(r"^(\S+?):(\d+):\d+: (Error|Warning|Notice) - (.+) \((\w+)\)$", line)
        if match:
            file, number, level, message, rule = match.groups()
            found.append(finding(step, rule, message, file=file, line=int(number),
                                 severity="error" if level == "Error" else "warning"))
    return found


def parse_terraform(step, text):
    """Terraform diagnostics, with or without the box characters it may draw around them."""
    found, block, folder = [], None, ""

    def close():
        if block is None:
            return
        last = block["lines"][-1] if block["lines"] else ""
        is_detail = last and not last.startswith(("on ", "with ")) and not re.match(r"^\d+:|^[├│]", last)
        message = f"{block['summary']}: {last}" if is_detail else block["summary"]
        found.append(finding(step, "terraform", message, file=block["file"], line=block["line"],
                             severity="warning" if block["level"] == "Warning" else "error"))

    for raw in plain_lines(text):
        line = re.sub(r"^[╷╵]\s*$", "", raw)
        line = re.sub(r"^│ ?", "", line).strip()
        heading = re.match(r"^== (?:validate|terraform test:) (\S+)$", line)
        start = re.match(r"^(Error|Warning): (.+)$", line)
        if heading:
            folder = heading.group(1)
        elif start:
            close()
            block = {"level": start.group(1), "summary": start.group(2), "file": "", "line": 0, "lines": []}
        elif block is not None and line:
            where = re.match(r"^on (\S+) line (\d+)", line)
            if where and not block["file"]:
                block["file"] = os.path.normpath(f"{folder}/{where.group(1)}" if folder else where.group(1))
                block["line"] = int(where.group(2))
            elif line.startswith("make: ***"):
                continue
            else:
                block["lines"].append(line)
    close()
    return found


def parse_scan(step, text):
    found, lines = [], plain_lines(text)
    for index, line in enumerate(lines):
        match = re.match(r"^\s+(CKV2?_[A-Z0-9_]+)\s+(\S+?):(\d+)\s+(\S+)", line)
        if match:
            rule, file, number, resource = match.groups()
            name = lines[index + 1].strip() if index + 1 < len(lines) else rule
            found.append(finding(step, rule, name, file=file, line=int(number), resource=resource))
    return found + parse_guards(step, text)


def parse_unittest(step, text):
    found = []
    for line in plain_lines(text):
        match = re.match(r"^(?:FAIL|ERROR): (test\w*) \((.+?)\)", line)
        if match:
            found.append(finding(step, match.group(1), f"unit test failed: {match.group(2)}"))
    return found


def parse_secrets(step, text):
    """Reads only RuleID, File and Line. The Finding and Secret lines are never touched."""
    found, rule, file = [], None, ""
    for line in plain_lines(text):
        match = re.match(r"^(RuleID|File|Line):\s+(.+)$", line)
        if not match:
            continue
        key, value = match.groups()
        if key == "RuleID":
            rule = value
        elif key == "File":
            file = value
        elif rule is not None:
            found.append(finding(step, rule, "possible secret in a commit", file=file,
                                 line=int(value) if value.isdigit() else 0))
            rule, file = None, ""
    return found


PARSERS = {
    "policy": lambda step, text: parse_conftest(step, text) + parse_guards(step, text),
    "fmt": parse_fmt,
    "validate": parse_terraform,
    "lint": parse_tflint,
    "test": parse_terraform,
    "secrets": parse_secrets,
    "scan": parse_scan,
    "agents-md": parse_guards,
    "risk-test": parse_unittest,
    "hook-test": parse_unittest,
    "usage-test": parse_unittest,
    "mcp-test": lambda step, text: parse_unittest(step, text) + parse_guards(step, text),
}


def findings_for(step, text):
    found = PARSERS[step](step, text)
    if found:
        return found
    # A failed step must always say something. Raw text never comes from the secret scan.
    if step == "secrets":
        return [finding(step, "unparsed", "secret scan failed: run make secrets")]
    lines = [line for line in plain_lines(text) if line.strip() and not line.startswith("make: ***")]
    return [finding(step, "unparsed", " | ".join(lines[-3:]) or "step failed with no output")]


# ---------- the tool ----------

def run_check(runner=run_make):
    if not LOCK.acquire(blocking=False):
        return respond("check", "error", reason="another check is already running")
    try:
        started = time.monotonic()
        passed, failed, skipped, errors, found = 0, [], [], [], []
        for step in CHECK_TARGETS:
            if step in NEEDS_POLICY and "policy" in failed + errors:
                skipped.append(step)
                continue
            code, text = runner(step)
            if code == 0:
                passed += 1
            elif code is None:
                errors.append(step)
                found.append(finding(step, "not-finished", text))
            else:
                failed.append(step)
                found.extend(findings_for(step, text))
        status = "error" if errors else "fail" if failed or skipped else "pass"
        return respond("check", status, lists={"findings": (dedupe(found), MAX_FINDINGS)},
                       passed=passed, failed=failed, skipped=skipped, errors=errors,
                       seconds=round(time.monotonic() - started))
    finally:
        LOCK.release()
