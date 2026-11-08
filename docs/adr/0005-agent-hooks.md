# ADR 0005: Agent hooks enforce the rules locally

- Status: Accepted (updated in W3.1: MCP tools, onFailure)
- Date: 2026-11-01, updated 2026-11-08
- Tool: Claude Code 2.1.316

## Context

AGENTS.md asks; it cannot enforce. An agent can ignore, misread or be
tricked out of any written rule. Claude Code runs hooks itself, so the agent
cannot skip them.

## Decision

Two hooks, configured in `.claude/settings.json`, written in plain Python
(stdlib only) and run with `python3 -I`:

- **Pre-tool guard** (`pre_tool_guard.py`), before Bash, Write, Edit,
  MultiEdit, NotebookEdit, Read, Grep, Glob, and every MCP tool
  (matcher `mcp__.*`):
  - Commands are an **allowlist**: safe `make` targets, safe `git`
    subcommands, read-only `gh` plus `gh pr create`, `terraform fmt`,
    read-only tools. Everything else is blocked.
  - MCP tools are an allowlist too: only the two `tf-check` tools, with
    their arguments checked (ADR 0007). Any other MCP tool is blocked.
  - No agent-written code runs locally: no `python3`, `bash`, `./script`,
    `env`, `xargs`, `make` options or `make` outside the repo root, no `$`,
    backticks, subshells or here-documents.
  - Paths are resolved for real (`~`, `../`, symlinks, `cd`) before the
    protected-path and secret-file checks.
  - Fails closed: an error inside the guard blocks (exception handler); a
    guard that cannot start blocks (`|| exit 2`); a guard that crashes or
    times out blocks (`"onFailure": "block"`, Claude Code 2.1.295 or later).
- **Completion hook** (`stop_require_check.py`), when the agent says it is
  done: runs `make check` if anything changed; on failure the agent must
  continue and sees the last 40 lines. At most 3 attempts per session, and
  the same error twice stops early, with a warning to the
