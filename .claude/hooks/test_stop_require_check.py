"""Tests for stop_require_check.py: the agent cannot finish with failing checks,
and a stuck agent cannot loop forever."""
import json
import os
import subprocess
import tempfile
import unittest

import stop_require_check as hook


class Decide(unittest.TestCase):
    def test_pass_allows_stop(self):
        allow, state, message = hook.decide({"attempts": 2, "last_hash": "x"}, True, "ok")
        self.assertTrue(allow)
        self.assertEqual(state["attempts"], 0)
        self.assertIsNone(message)

    def test_first_failure_blocks_and_shows_the_error(self):
        allow, state, message = hook.decide({}, False, "line1\nFAIL: something broke")
        self.assertFalse(allow)
        self.assertEqual(state["attempts"], 1)
        self.assertIn("FAIL: something broke", message)

    def test_only_the_last_lines_are_shown(self):
        output = "\n".join(f"line {i}" for i in range(200))
        _, _, message = hook.decide({}, False, output)
        self.assertIn("line 199", message)
        self.assertNotIn("line 100\n", message)

    def test_same_failure_twice_stops_early(self):
        _, state, _ = hook.decide({}, False, "FAIL: A")
        allow, state, message = hook.decide(state, False, "FAIL: A")
        self.assertTrue(allow)
        self.assertIn("same error twice", message)
        self.assertEqual(state["attempts"], 0)

    def test_attempt_cap_stops(self):
        state = {}
        for i in range(hook.MAX_ATTEMPTS - 1):
            allow, state, _ = hook.decide(state, False, f"FAIL: {i}")
            self.assertFalse(allow)
        allow, state, message = hook.decide(state, False, "FAIL: last")
        self.assertTrue(allow)
        self.assertIn(f"after {hook.MAX_ATTEMPTS} attempts", message)


class Run(unittest.TestCase):
    """Runs the hook against a real temporary git repo."""

    def setUp(self):
        self.root = os.path.realpath(tempfile.mkdtemp())
        self.git("init", "-q", "-b", "main")
        with open(os.path.join(self.root, "a.txt"), "w") as f:
            f.write("a\n")
        self.git("add", "a.txt")
        self.git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "init")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.payload = {"session_id": f"test-{os.getpid()}-{id(self)}"}

    def tearDown(self):
        try:
            os.remove(hook.state_path(self.payload["session_id"]))
        except OSError:
            pass

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def change_something(self):
        with open(os.path.join(self.root, "b.txt"), "w") as f:
            f.write("b\n")

    def test_no_changes_skips_the_check(self):
        code, _, _ = hook.run(self.payload, self.root, check_cmd=["false"])
        self.assertEqual(code, 0)

    def test_changes_and_failing_check_block(self):
        self.change_something()
        code, err, _ = hook.run(self.payload, self.root, check_cmd=["false"])
        self.assertEqual(code, 2)
        self.assertIn("make check failed", err)

    def test_changes_and_passing_check_allow(self):
        self.change_something()
        code, _, _ = hook.run(self.payload, self.root, check_cmd=["true"])
        self.assertEqual(code, 0)

    def test_commit_not_on_main_is_checked(self):
        self.change_something()
        self.git("add", "b.txt")
        self.git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "b")
        code, _, _ = hook.run(self.payload, self.root, check_cmd=["false"])
        self.assertEqual(code, 2)

    def test_give_up_message_reaches_the_human(self):
        self.change_something()
        hook.run(self.payload, self.root, check_cmd=["false"])
        code, _, out = hook.run(self.payload, self.root, check_cmd=["false"])
        self.assertEqual(code, 0)
        self.assertIn("same error twice", json.loads(out)["systemMessage"])


if __name__ == "__main__":
    unittest.main()
