# ADR 0005: Agent hooks enforce the rules locally

- Status: Accepted (updated in W3.1: MCP tools, onFailure; W3.6: scratchpad, live results)
- Date: 2026-11-01, updated 2026-11-08 and 2026-11-10
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
  - Writes are allowed inside the repo (except protected paths, ADR 0004)
    and, since W3.6, inside the session's own Claude Code scratchpad:
    `/tmp/claude-<uid>/<repo path>/<session id>/scratchpad/`, built from the
    hook input's session ID (a plain UUID only). Nothing written there can
    be run, because interpreters and scripts stay blocked.
  - Paths are resolved for real (`~`, `../`, symlinks, `cd`) before the
    protected-path, scratchpad and secret-file checks.
  - Fails closed: an error inside the guard blocks (exception handler); a
    guard that cannot start blocks (`|| exit 2`); a guard that crashes or
    times out blocks (`"onFailure": "block"`, Claude Code 2.1.295 or later).
- **Completion hook** (`stop_require_check.py`), when the agent says it is
  done (Stop) and when the `implementer` sub-agent finishes (SubagentStop):
  runs `make check` if anything changed; on failure the agent must continue
  and sees the last 40 lines. At most 3 attempts per session, and the same
  error twice stops early, with a warning to the owner. It fails visibly,
  not closed: a blocking error here could loop forever, and CI rechecks
  everything.

Tested by `make hook-test`: attack commands that must be blocked, normal
commands that must work, file-tool cases, MCP calls, scratchpad escapes
(another session, another repo, another user, `..`, symlinks), loop limits,
and a test that the protected-path lists in the hook, `guard.yml` and
CODEOWNERS agree.

Config files that tools load automatically (`GNUmakefile`, mise files,
`.gitleaks.toml`, `.gitleaksignore`, `conftest.toml`) are protected paths,
in CI too.

## Tested live

- W2.6: with working hooks, the guard blocked a secret-file read and the
  completion hook blocked a failing finish (agent-log entries 2, 3).
- W3.2: malformed MCP calls were blocked by the guard, not by Claude Code
  (entry 10).
- W3.3: both hooks also run inside sub-agents (entry 14).
- W3.4-W3.5: 16 benchmark and 6 eval sessions. The guard blocked no dangerous
  action in the evals, because the agent never tried one; its blocks were
  `$`, here-documents, `sed` and scratchpad writes (entries 19-24).

## Known limits

- **The completion hook cannot tell whose changes it checks.** Any
  uncommitted change makes it run, so a read-only task can be blocked by the
  owner's own work in progress (seen in the W2.7 live test). Possible fix:
  record the git state at session start and only check what changed since.
- **Fixed after the W2.7 live test:** "same error twice" never fired, because
  gitleaks prints timestamps and durations. The failure fingerprint now
  ignores numbers, and a test covers it.
- **A hook that cannot start fails open** unless it says otherwise. Claude Code
  treats any exit code other than 2 as a non-blocking error. Found live: the
  Windows build had no `python3`, every hook failed, and the agent read a
  (fake) secret file. Fixed with `|| exit 2` and `onFailure: block`, both tested.
- **Claude Code must run inside WSL/Linux**, where the hooks' `python3`
  exists. `make agent` refuses the Windows build.
- **Identity:** the agent pushes and opens PRs with its own limited token
  (ADR 0006), but on GitHub it still shows as the owner's account.
- **Owner's AWS session:** the guard blocks AWS commands, and `make agent`
  refuses to start while an AWS session exists, as a second layer.
- **Local only:** a session started without these project settings has no
  hooks. CI is the final authority and rechecks everything.
- **Sub-agent hook messages** are not shown to the main agent, only the
  sub-agent's final reply (entry 14).
- **False positives:** `$` is blocked even inside commit messages, a message
  ending in `.tfvars` is blocked, and `sed` is not allowed. The agent rewrites
  the command. Until W3.6, scratchpad writes were blocked too (entries 8, 19-23).
- **Cost:** the completion hook runs `make check` (about 1-2 minutes) each
  time the agent finishes with changes.
