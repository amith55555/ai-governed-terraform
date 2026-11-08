# ADR 0008: Two sub-agents, implementer and read-only reviewer

- Status: Accepted (live results added)
- Date: 2026-11-08
- Tool: Claude Code 2.1.316

## Context

One agent that writes a change and then judges it tends to repeat its own
mistakes. A second agent that starts fresh, like a human reviewer, can catch
them. Sub-agents also cost tokens: each one starts cold and re-reads what it
needs. The benchmark (W3.4) measures whether they pay off.

## Decision

Two sub-agents in `.claude/agents/`, both with `model: inherit`:

| | implementer | reviewer |
|---|---|---|
| Job | make the code change | review the pushed PR |
| Tools | Read, Grep, Glob, Edit, Write, tf-check `check` | Read, Grep, Glob, tf-check `plan_summary` |
| Denied | Bash, Agent, NotebookEdit, `plan_summary` | Bash, Write, Edit, MultiEdit, NotebookEdit, Agent, `check` |
| Turn limit | 30 | 15 |
| Finish rule | SubagentStop hook: `make check` must pass | none (changes nothing) |

- **Read-only by tool list, not by prompt.** The reviewer has no tool that
  writes. `check` is denied too: it writes temporary Terraform folders.
- **Fresh context.** The main agent gives the reviewer only the task, the PR
  number and the changed files, never its reasoning.
- **Hooks still apply.** Per the Claude Code docs, PreToolUse hooks from
  `settings.json` run inside sub-agents, so the guard checks every sub-agent
  tool call. A test checks that every tool either sub-agent has reaches the
  guard.
- **No nesting.** `Agent` is denied, so a sub-agent cannot start another one.
- Tested by `make hook-test` (`test_agents.py`).

## Known limits

- **The reviewer's verdict is advice.** It cannot approve or block a PR;
  CI and the owner do.
- **Tested live (W3.3, agent log 12-14):** the guard blocks inside both
  sub-agents, and the SubagentStop hook stops the implementer from finishing
  with a failing `make check`, including the "same error twice" limit. The
  first tests proved nothing, because the agents refused by their own
  instructions; safety nets must be tested with traps the agent does not
  recognise.
- **Sub-agents run in the background.** The main agent sees only a
  sub-agent's final reply, not its hook messages. The session logs keep them.
- **The stop hook's attempt counter** is kept per session, so the main agent
  and the implementer may share it.
- **Tool lists use `mcp__tf-check__*` and then deny one tool**, because the
  docs only confirm the whole-server form. A new tf-check tool would reach
  both sub-agents; a test (`test_agents.py`) fails until the guard and the
  deny lists are reviewed. Found by the reviewer in its first review.
- **Cost:** every sub-agent call re-reads files the main agent may already
  have read. The benchmark reports whether this paid off.
