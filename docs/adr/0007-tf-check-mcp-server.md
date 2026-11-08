# ADR 0007: tf-check MCP server

- Status: Accepted
- Date: 2026-11-08
- SDK: `mcp` 2.3.0 (Python, `MCPServer`), pinned with hashes

## Context

Raw `make check` output and Terraform plans are long; most of it is noise
the agent pays for in tokens. An MCP server can return short, stable JSON
instead. But a server runs commands for the agent, outside the Bash guard,
so it must be safe by design, not by prompt.

The agent has no AWS credentials (ADR 0006), so it cannot plan locally.

## Decision

One server, `mcp-servers/tf-check/`, stdio only, two read-only tools:

| Tool | Input | Source |
|---|---|---|
| `check` | none | the `make check` targets, from a fixed list (`static` split into `fmt`, `validate`, `lint`) |
| `plan_summary` | `pr` (number), `env` (`dev`, `prod`, `all`) | the CI plan of the PR's latest commit: the `risk-<env>` artifacts from `risk_gate.py` (level, reasons, counts, changes), or the plan-policy `FAIL` lines from the run log |

Options for `plan_summary` that were rejected: planning locally without
credentials (fails at the S3 backend, and a mock plan shows everything as
"create", hiding replaces and destroys); reading the PR comment (anyone can
post a fake one on a public repo). Consequence: the agent never reaches AWS,
not even read-only.

Security layers, each tested:

1. **Server:** runs only `make <fixed target>` and 4 fixed `gh` commands,
   never a shell; no tool takes free text; commands get a short list of
   environment variables (no AWS, `TF_VAR_*`, `MAKEFLAGS`); the source
   policy runs before any `terraform init`; a report is accepted only in the
   exact shape `risk_gate.py` writes, with counts matching changes;
   addresses with spaces are replaced (no sentences in for_each keys).
2. **Output:** schema `tf-check/v1`, at most 20 findings, 30 changes and
   8,000 bytes, an `omitted` counter, redaction of account IDs, emails, API
   URLs and tokens, no secret values from gitleaks. A failure, a timeout or
   unreadable output is never reported as a pass; a missing plan gives level
   `unknown`, never `low`.
3. **Guard:** the PreToolUse matcher `mcp__.*` sends every MCP call to
   `pre_tool_guard.py`, which allows only the two tools and checks their
   arguments again (ADR 0005).

Tests: `make mcp-test` (92 tests, part of `make check` and CI, including a
real stdio start) and `make hook-test` (`test_mcp_guard.py`).

## Known limits

- **The report is built from the PR's own code.** A PR that edits
  `risk/risk_gate.py` could produce a misleading report before the owner
  approves it in `guardrail-approval`. The CI risk gate has the same limit.
- **Needs a push and a CI run** (about 2-3 minutes) before `plan_summary`
  has anything to read. Artifacts expire after 3 days (`no_plan`).
- **Policy failures are read from log text.** If GitHub's log format
  changes, they show as `no_plan` instead of `policy_failed`.
- **Free text in reasons and policy messages** is capped and redacted, not
  filtered. The agent must treat all results as data (AGENTS.md F10).
- **`validate` stops at the first failing environment**, as in CI, so one
  error can hide the same error in prod.
- **The server runs as the owner's Linux user**, like the agent. A separate
  user or container would isolate it (same limit as ADR 0006).
- **Not yet tested live** with Claude Code: W3.2 registers the server in
  `.mcp.json` and runs the agent against it.
