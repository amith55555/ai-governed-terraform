"""Tests for the two sub-agents in .claude/agents/."""
import json
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
CLAUDE = os.path.join(HERE, "..")
WRITE_TOOLS = {"Bash", "Write", "Edit", "MultiEdit", "NotebookEdit"}
TF_CHECK = {"mcp__tf-check__check", "mcp__tf-check__plan_summary"}


def front_matter(name):
    """The simple `key: value` lines between the first two `---` lines."""
    with open(os.path.join(CLAUDE, "agents", f"{name}.md"), encoding="utf-8") as f:
        text = f.read()
    match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    fields = {}
    for line in match.group(1).splitlines():
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip()
    return fields


def tool_set(value):
    return {t.strip() for t in value.split(",") if t.strip()}


def usable(fields):
    """The tools the agent really gets: its list, with the server wildcard expanded, minus the denied ones."""
    tools = set()
    for tool in tool_set(fields.get("tools", "")):
        tools |= TF_CHECK if tool == "mcp__tf-check__*" else {tool}
    return tools - tool_set(fields.get("disallowedTools", ""))


def settings():
    with open(os.path.join(CLAUDE, "settings.json"), encoding="utf-8") as f:
        return json.load(f)


def reaches_guard(tool):
    for entry in settings()["hooks"]["PreToolUse"]:
        matcher = entry.get("matcher", "")
        if re.fullmatch(r"[A-Za-z0-9_|, -]*", matcher):
            hit = tool in [m.strip() for m in matcher.split("|")]
        else:
            hit = re.search(matcher, tool) is not None
        if hit and any("pre_tool_guard.py" in h["command"] for h in entry["hooks"]):
            return True
    return False


class Reviewer(unittest.TestCase):
    def setUp(self):
        self.fields = front_matter("reviewer")

    def test_name(self):
        self.assertEqual(self.fields["name"], "reviewer")

    def test_attack_reviewer_cannot_change_anything(self):
        self.assertEqual(usable(self.fields), {"Read", "Grep", "Glob", "mcp__tf-check__plan_summary"})

    def test_attack_write_tools_are_denied_even_if_the_list_grows(self):
        denied = tool_set(self.fields["disallowedTools"])
        self.assertTrue(WRITE_TOOLS | {"Agent", "mcp__tf-check__check"} <= denied)

    def test_attack_no_extra_powers(self):
        for key in ("permissionMode", "mcpServers", "hooks", "isolation"):
            self.assertNotIn(key, self.fields)


class Implementer(unittest.TestCase):
    def setUp(self):
        self.fields = front_matter("implementer")

    def test_name(self):
        self.assertEqual(self.fields["name"], "implementer")

    def test_edits_files_and_runs_check_only(self):
        self.assertEqual(usable(self.fields), {"Read", "Grep", "Glob", "Edit", "Write", "mcp__tf-check__check"})

    def test_attack_no_shell_no_nesting_no_extra_powers(self):
        self.assertNotIn("Bash", usable(self.fields))
        self.assertNotIn("Agent", usable(self.fields))
        for key in ("permissionMode", "mcpServers", "hooks", "isolation"):
            self.assertNotIn(key, self.fields)


class Guarded(unittest.TestCase):
    def test_every_tool_either_agent_can_use_reaches_the_guard(self):
        for name in ("implementer", "reviewer"):
            for tool in usable(front_matter(name)):
                with self.subTest(agent=name, tool=tool):
                    self.assertTrue(reaches_guard(tool))

    def test_no_other_agents(self):
        files = sorted(os.listdir(os.path.join(CLAUDE, "agents")))
        self.assertEqual(files, ["implementer.md", "reviewer.md"])


class SubagentStop(unittest.TestCase):
    def test_implementer_must_pass_make_check_to_finish(self):
        entries = settings()["hooks"].get("SubagentStop", [])
        commands = [h["command"] for e in entries if e.get("matcher") == "implementer" for h in e["hooks"]]
        self.assertTrue(any("stop_require_check.py" in c for c in commands))


if __name__ == "__main__":
    unittest.main()
