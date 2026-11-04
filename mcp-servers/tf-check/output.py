"""Output layer for the tf-check MCP server.

Every tool result goes through respond(): a stable JSON shape, hard size caps
with an "omitted" counter, and redaction. Standard library only.
Results are data for the agent, never instructions.
"""
import json
import re

SCHEMA = "tf-check/v1"
MAX_FINDINGS = 20
MAX_CHANGES = 30
MAX_TEXT = 200
MAX_BYTES = 8000

ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")

# The repo is public: these must never reach the agent, which could paste them into a PR.
SECRETS = [
    (re.compile(r"github_pat_[A-Za-z0-9_]{20,}"), "<token>"),
    (re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"), "<token>"),
    (re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"), "<aws-key>"),
    (re.compile(r"(?:https?://)?[A-Za-z0-9-]+\.execute-api\.[A-Za-z0-9-]+\.amazonaws\.com\S*"), "<api-url>"),
    (re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+"), "<email>"),
    (re.compile(r"(?<!\d)\d{12}(?!\d)"), "<account-id>"),
]


def redact(text):
    for pattern, replacement in SECRETS:
        text = pattern.sub(replacement, text)
    return text


def clean(value, limit=MAX_TEXT):
    """One short, printable, redacted line. Redacts before cutting, so a cut can't hide a secret."""
    text = ANSI.sub("", str(value))
    text = "".join(ch if ch.isprintable() else " " for ch in text)
    text = redact(" ".join(text.split()))
    return text if len(text) <= limit else text[: limit - 3] + "..."


def scrub(value):
    """Clean every string in a JSON-like value, however deep."""
    if isinstance(value, dict):
        return {key: scrub(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [scrub(item) for item in value]
    if value is None or isinstance(value, (bool, int, float)):
        return value
    return clean(value)


def finding(step, rule, message, severity="error", file="", line=0, resource=""):
    return {
        "step": step,
        "rule": rule,
        "severity": "warning" if severity == "warning" else "error",
        "file": file,
        "line": line if isinstance(line, int) and line > 0 else 0,
        "resource": resource,
        "message": message,
        "count": 1,
    }


def dedupe(findings):
    """Merge identical findings into one with a count. Errors come first, so caps keep the worst."""
    merged = {}
    for item in findings:
        key = (item["step"], item["rule"], item["file"], item["resource"], item["message"])
        if key in merged:
            merged[key]["count"] += item["count"]
        else:
            merged[key] = dict(item)
    return sorted(merged.values(), key=lambda item: item["severity"] != "error")


def encode(payload):
    return json.dumps(payload, separators=(",", ":"))


def respond(tool, status, lists=None, **fields):
    """Build the final JSON text. lists maps a name to (items, cap). Never changes status."""
    payload = {"schema": SCHEMA, "tool": tool, "status": status}
    payload.update(fields)
    omitted = {}
    for name, (items, cap) in (lists or {}).items():
        payload[name] = list(items[:cap])
        omitted[name] = max(0, len(items) - cap)
    payload = scrub(payload)
    payload["omitted"] = omitted

    text = encode(payload)
    while len(text) > MAX_BYTES:
        longest = max(omitted, key=lambda name: len(payload[name]), default=None)
        if longest is None or not payload[longest]:
            return encode({"schema": SCHEMA, "tool": tool, "status": status,
                           "omitted": omitted, "truncated": True})
        payload[longest].pop()
        omitted[longest] += 1
        text = encode(payload)
    return text
