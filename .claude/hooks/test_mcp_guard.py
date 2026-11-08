"""Attack tests for the MCP part of pre_tool_guard.py and its wiring in settings.json."""
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

from pre_tool_guard import MCP_TOOLS, check

HERE = os.path.dirname(os.path.abspath(__file__))
CHECK = "mcp__tf-check__check"
PLAN = "mcp__tf-check__plan_summary"


def guard(tool, tool_input):
    root = os.path.realpath(tempfile.gettempdir())
    return check({"tool_name": tool, "tool_input": tool_input, "cwd": root}, root)


def settings():
    with open(os.path.join(HERE, "..", "settings.json"), encoding="utf-8") as f:
        return json.load(f)


class Allowed(unittest.TestCase):
    CALLS = [
        (CHECK, {}),
        (PLAN, {"pr": 31}),
        (PLAN, {"pr": 31, "env": "dev"}),
        (PLAN, {"pr": 31, "env": "all"}),
        (PLAN, {"pr": "31"}),
    ]

    def test_normal_calls(self):
        for tool, tool_input in self.CALLS:
            with self.subTest(tool=tool, tool_input=tool_input):
                self.assertIsNone(guard(tool, tool_input))


class Blocked(unittest.TestCase):
    def assert_blocked(self, tool, tool_input):
        self.assertIsNotNone(guard(tool, tool_input), f"should be BLOCKED: {tool} {tool_input}")

    def test_attack_other_mcp_tools(self):
        for tool in ("mcp__tf-check__apply", "mcp__tf-check__check_", "mcp__tf-check__", "mcp__github__merge_pull_request",
                     "mcp__aws__call_aws", "mcp__tf-check__check__x", "mcp__TF-CHECK__check", "mcp__plugin_x_tf-check__check"):
            with self.subTest(tool=tool):
                self.assert_blocked(tool, {})

    def test_attack_check_takes_no_arguments(self):
        for tool_input in ({"target": "up"}, {"argv": ["aws", "s3", "ls"]}, {"": ""}):
            with self.subTest(tool_input=tool_input):
                self.assert_blocked(CHECK, tool_input)

    def test_attack_bad_pr(self):
        for pr in ("31; rm -rf .", "$(id)", "31 ", "031", "1e3", "", "-1", "1000000", 0, -1, 10**9,
                   3.5, True, None, [31], {"n": 31}):
            with self.subTest(pr=pr):
                self.assert_blocked(PLAN, {"pr": pr})

    def test_attack_missing_pr(self):
        self.assert_blocked(PLAN, {})
        self.assert_blocked(PLAN, {"env": "dev"})

    def test_attack_bad_env(self):
        for env in ("staging", "DEV", "dev; rm", "", None, ["dev"]):
            with self.subTest(env=env):
                self.assert_blocked(PLAN, {"pr": 31, "env": env})

    def test_attack_extra_arguments(self):
        self.assert_blocked(PLAN, {"pr": 31, "cmd": "make up"})
        self.assert_blocked(PLAN, {"pr": 31, "env": "dev", "repo": "someone/else"})

    def test_attack_input_that_is_not_an_object(self):
        for tool_input in ([31], "pr=31", 31):
            with self.subTest(tool_input=tool_input):
                self.assert_blocked(PLAN, tool_input)
                self.assert_blocked("Bash", tool_input)

    def test_every_allowed_tool_has_a_rule(self):
        self.assertEqual(set(MCP_TOOLS), {CHECK, PLAN})


class MakeTargets(unittest.TestCase):
    def test_split_targets_and_mcp_tests_are_allowed(self):
        root = os.path.realpath(tempfile.gettempdir())
        for target in ("fmt", "validate", "lint", "mcp-test"):
            with self.subTest(target=target):
                self.assertIsNone(check({"tool_name": "Bash", "tool_input": {"command": f"make {target}"},
                                         "cwd": root}, root))

    def test_attack_mcp_install_is_blocked(self):
        root = os.path.realpath(tempfile.gettempdir())
        self.assertIsNotNone(check({"tool_name": "Bash", "tool_input": {"command": "make mcp-install"},
                                    "cwd": root}, root))


class Wiring(unittest.TestCase):
    """The real script, as Claude Code runs it."""

    def test_unknown_mcp_tool_exits_2(self):
        stdin = json.dumps({"tool_name": "mcp__github__merge_pull_request", "tool_input": {}, "cwd": HERE})
        result = subprocess.run([sys.executable, "-I", os.path.join(HERE, "pre_tool_guard.py")],
                                input=stdin, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("not on the allowed list", result.stderr)


class Settings(unittest.TestCase):
    def entries(self):
        return settings()["hooks"]["PreToolUse"]

    def matches(self, tool):
        """Claude Code: a matcher with only letters, digits, _ - , | and spaces is an exact list;
        anything else is an unanchored regular expression."""
        found = []
        for entry in self.entries():
            matcher = entry.get("matcher", "")
            if re.fullmatch(r"[A-Za-z0-9_|, -]*", matcher):
                hit = tool in [m.strip() for m in matcher.split("|")]
            else:
                hit = re.search(matcher, tool) is not None
            if hit:
                found.extend(entry["hooks"])
        return found

    def test_every_mcp_tool_reaches_the_guard(self):
        for tool in (CHECK, PLAN, "mcp__github__merge_pull_request", "mcp__plugin_x_y__z"):
            with self.subTest(tool=tool):
                commands = [hook["command"] for hook in self.matches(tool)]
                self.assertTrue(any("pre_tool_guard.py" in c for c in commands), tool)

    def test_built_in_tools_still_reach_the_guard(self):
        for tool in ("Bash", "Write", "Edit", "MultiEdit", "NotebookEdit", "Read", "Grep", "Glob"):
            with self.subTest(tool=tool):
                self.assertTrue(self.matches(tool))

    def test_attack_a_hook_that_fails_or_times_out_blocks(self):
        """Without onFailure: block, a crashed or timed-out PreToolUse hook lets the tool run."""
        hooks = [hook for entry in self.entries() for hook in entry["hooks"]]
        self.assertTrue(hooks)
        for hook in hooks:
            with self.subTest(command=hook["command"]):
                self.assertEqual(hook.get("onFailure"), "block")
                self.assertLessEqual(hook.get("timeout", 600), 30)


if __name__ == "__main__":
    unittest.main()
