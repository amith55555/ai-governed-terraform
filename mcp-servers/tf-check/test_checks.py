"""Tests for checks.py. Samples come from real tool output. Attack cases are marked."""
import json
import re
import threading
import time
import unittest
from pathlib import Path

import checks
import output
from checks import CHECK_TARGETS, findings_for, run_check, run_command, run_make, safe_env

SERVER_DIR = Path(__file__).resolve().parent


def fake_runner(results):
    """Every step passes unless results says otherwise. Records what ran."""
    calls = []

    def runner(step):
        calls.append(step)
        return results.get(step, (0, ""))

    runner.calls = calls
    return runner


class FixedCommands(unittest.TestCase):
    def test_attack_target_outside_the_list_is_refused(self):
        for target in ("up", "down", "plan", "agent", "check; rm -rf .", "-f evil.mk", "--eval=x", ""):
            with self.subTest(target), self.assertRaises(ValueError):
                run_make(target)

    def test_attack_no_shell_anywhere_in_the_server(self):
        for path in SERVER_DIR.glob("*.py"):
            if path.name.startswith("test_"):
                continue
            source = path.read_text(encoding="utf-8")
            with self.subTest(path.name):
                self.assertNotIn("shell=True", source)
                self.assertNotIn("os.system", source)
                self.assertNotIn("os.popen", source)
                self.assertNotIn("eval(", source)
                self.assertNotIn("exec(", source)

    def test_run_check_takes_no_input_from_the_caller(self):
        import inspect
        self.assertEqual(list(inspect.signature(run_check).parameters), ["runner"])


class MakefileParity(unittest.TestCase):
    def prerequisites(self, text, target):
        match = re.search(rf"^{target}:([^#\n]*)", text, re.M)
        return match.group(1).split()

    def test_targets_equal_make_check(self):
        text = (checks.REPO / "Makefile").read_text(encoding="utf-8")
        static = [t for t in self.prerequisites(text, "static") if t != "policy"]
        expected = []
        for target in self.prerequisites(text, "check"):
            expected.extend(static if target == "static" else [target])
        self.assertEqual(list(CHECK_TARGETS), expected)

    def test_terraform_init_targets_still_depend_on_policy(self):
        text = (checks.REPO / "Makefile").read_text(encoding="utf-8")
        for target in sorted(checks.NEEDS_POLICY):
            with self.subTest(target):
                self.assertIn("policy", self.prerequisites(text, target))

    def test_every_target_has_a_parser(self):
        self.assertEqual(set(CHECK_TARGETS), set(checks.PARSERS))


class Environment(unittest.TestCase):
    def test_attack_dangerous_variables_are_dropped(self):
        source = {name: "x" for name in (
            "AWS_PROFILE", "AWS_ACCESS_KEY_ID", "AWS_SESSION_TOKEN", "AWS_CONFIG_FILE",
            "TF_VAR_aws_account_id", "TF_CLI_ARGS", "TF_CLI_ARGS_plan", "TF_CLI_CONFIG_FILE",
            "GH_TOKEN", "GITHUB_TOKEN", "MAKEFLAGS", "MAKEFILES", "BASH_ENV", "ENV",
            "PYTHONPATH", "PYTHONSTARTUP", "LD_PRELOAD", "GIT_CONFIG_COUNT", "GIT_DIR", "CHECKOV_CONFIG",
        )}
        env = safe_env(source)
        self.assertEqual(set(env), set(checks.ENV_FIXED))

    def test_needed_variables_are_kept(self):
        env = safe_env({"PATH": "/bin", "HOME": "/home/x"})
        self.assertEqual((env["PATH"], env["HOME"]), ("/bin", "/home/x"))

    def test_fixed_values_cannot_be_overridden(self):
        self.assertEqual(safe_env({"TF_INPUT": "1"})["TF_INPUT"], "0")


class RunCommand(unittest.TestCase):
    ENV = {"PATH": "/usr/bin:/bin"}

    def test_output_and_code(self):
        self.assertEqual(run_command(["sh", "-c", "echo hi; exit 3"], self.ENV), (3, "hi\n"))

    def test_missing_program_is_not_a_pass(self):
        code, text = run_command(["no-such-program-xyz"], self.ENV)
        self.assertIsNone(code)
        self.assertIn("could not start", text)

    def test_timeout_kills_the_children_too(self):
        marker = f"/tmp/tf-check-test-{time.time_ns()}"
        started = time.monotonic()
        code, text = run_command(["sh", "-c", f"(sleep 1; touch {marker}) & wait"], self.ENV, timeout=0.2)
        self.assertIsNone(code)
        self.assertLess(time.monotonic() - started, 0.9)
        time.sleep(1.1)
        self.assertFalse(Path(marker).exists())


class Parsers(unittest.TestCase):
    def one(self, step, text):
        result = findings_for(step, text)
        self.assertEqual(len(result), 1)
        return result[0]

    def test_conftest(self):
        item = self.one("policy", "\x1b[31mFAIL\x1b[0m - terraform/modules/alarms/main.tf - hcl.escape_hatches"
                                  " - provisioner blocks are not allowed\n\n2 tests, 1 passed\nmake: *** [x] Error 1\n")
        self.assertEqual((item["rule"], item["file"]), ("hcl.escape_hatches", "terraform/modules/alarms/main.tf"))
        self.assertEqual(item["message"], "provisioner blocks are not allowed")

    def test_script_guard(self):
        item = self.one("policy", "FAIL: *.tf.json files are not allowed.\n")
        self.assertEqual((item["rule"], item["message"]), ("guard", "*.tf.json files are not allowed."))

    def test_missing_path_from_agents_md_check(self):
        result = findings_for("agents-md", "MISSING  docs/x.md (in AGENTS.md)\nFAIL: some instructions point to files that do not exist.\n")
        self.assertEqual(len(result), 2)
        self.assertEqual(result[0]["message"], "docs/x.md (in AGENTS.md)")

    def test_fmt_ignores_the_diff(self):
        text = "terraform/envs/dev/main.tf\n--- old/terraform/envs/dev/main.tf\n+++ new\n@@ -1 +1 @@\n-a\n+b\n"
        self.assertEqual(self.one("fmt", text)["file"], "terraform/envs/dev/main.tf")

    def test_tflint(self):
        text = ("1 issue(s) found:\n\nterraform/modules/alarms/main.tf:67:1: Warning - variable \"x\" is declared "
                "but not used (terraform_unused_declarations)\n")
        item = self.one("lint", text)
        self.assertEqual((item["rule"], item["line"], item["severity"]),
                         ("terraform_unused_declarations", 67, "warning"))

    def test_terraform_plain(self):
        text = ('== validate terraform/envs/dev\n\nError: Reference to undeclared input variable\n\n'
                '  on main.tf line 12, in module "x":\n  12:   name = var.nope\n\n'
                'An input variable with the name "nope" has not been declared.\n')
        item = self.one("validate", text)
        self.assertEqual((item["file"], item["line"]), ("terraform/envs/dev/main.tf", 12))
        self.assertIn("has not been declared", item["message"])

    def test_terraform_path_through_a_module_is_shortened(self):
        text = "== validate terraform/envs/prod\nError: x\n  on ../../modules/alarms/main.tf line 70:\n"
        self.assertEqual(self.one("validate", text)["file"], "terraform/modules/alarms/main.tf")

    def test_terraform_box(self):
        text = ('== terraform test: terraform/modules/s3_bucket\n╷\n│ Error: Test assertion failed\n│ \n'
                '│   on tests/x.tftest.hcl line 9, in run "y":\n│    9:     condition = false\n│ \n'
                '│ bucket must be private\n╵\nmake: *** [test] Error 1\n')
        item = self.one("test", text)
        self.assertEqual(item["file"], "terraform/modules/s3_bucket/tests/x.tftest.hcl")
        self.assertEqual(item["message"], "Test assertion failed: bucket must be private")

    def test_terraform_two_errors(self):
        self.assertEqual(len(findings_for("validate", "Error: one\n\nError: two\n")), 2)

    def test_checkov_lines_from_scan_sh(self):
        text = ("passed=5 failed=1 parsing_errors=0\n  CKV_AWS_18  /envs/dev/main.tf:12  aws_s3_bucket.x\n"
                "      Ensure logging\nFAIL: Checkov found problems (exit code 1).\nSCAN FAILED\n")
        result = findings_for("scan", text)
        self.assertEqual((result[0]["rule"], result[0]["line"], result[0]["resource"]),
                         ("CKV_AWS_18", 12, "aws_s3_bucket.x"))
        self.assertEqual(result[0]["message"], "Ensure logging")
        self.assertEqual(result[1]["rule"], "guard")

    def test_unittest_failure(self):
        item = self.one("risk-test", "FAIL: test_a (test_zz.T.test_a)\n---\nRan 1 test\n")
        self.assertEqual(item["rule"], "test_a")

    def test_secrets(self):
        text = ('Finding:     aws_key = "REDACTED\nSecret:      REDACTED\nRuleID:      aws-access-token\n'
                'Entropy:     3.5\nFile:        app/x.txt\nLine:        1\nCommit:      abc\nAuthor:      x\n'
                'Email:       a@b.c\n')
        item = self.one("secrets", text)
        self.assertEqual((item["rule"], item["file"], item["line"]), ("aws-access-token", "app/x.txt", 1))

    def test_attack_secret_value_never_appears(self):
        text = ('Finding:     token = "ghp_real-looking-value\nSecret:      hunter2-value\nRuleID:      github-pat\n'
                'File:        app/x.txt\nLine:        2\n')
        result = json.dumps(findings_for("secrets", text))
        self.assertNotIn("real-looking", result)
        self.assertNotIn("hunter2", result)

    def test_attack_unparsed_secret_scan_never_returns_raw_text(self):
        item = self.one("secrets", "something new: hunter2-value\n")
        self.assertEqual(item["rule"], "unparsed")
        self.assertNotIn("hunter2", item["message"])

    def test_unknown_failure_still_reports_something(self):
        item = self.one("validate", "weird line\nlast line\nmake: *** [x] Error 1\n")
        self.assertEqual(item["rule"], "unparsed")
        self.assertIn("last line", item["message"])

    def test_empty_failure_still_reports_something(self):
        self.assertEqual(self.one("lint", "")["message"], "step failed with no output")


class Status(unittest.TestCase):
    def test_all_pass(self):
        result = json.loads(run_check(fake_runner({})))
        self.assertEqual(result["status"], "pass")
        self.assertEqual(result["passed"], len(CHECK_TARGETS))
        self.assertEqual(result["findings"], [])

    def test_all_steps_run_in_order(self):
        runner = fake_runner({})
        run_check(runner)
        self.assertEqual(runner.calls, list(CHECK_TARGETS))

    def test_one_failure_does_not_hide_later_steps(self):
        runner = fake_runner({"fmt": (3, "terraform/a.tf\n")})
        result = json.loads(run_check(runner))
        self.assertEqual(result["status"], "fail")
        self.assertEqual(runner.calls, list(CHECK_TARGETS))

    def test_attack_failure_with_unreadable_output_is_never_a_pass(self):
        self.assertEqual(json.loads(run_check(fake_runner({"scan": (1, "???")})))["status"], "fail")

    def test_attack_tool_that_never_finished_is_never_a_pass(self):
        result = json.loads(run_check(fake_runner({"scan": (None, "timed out after 300 seconds")})))
        self.assertEqual(result["status"], "error")
        self.assertEqual(result["errors"], ["scan"])

    def test_attack_failed_policy_stops_terraform_init(self):
        runner = fake_runner({"policy": (2, "FAIL: no\n")})
        result = json.loads(run_check(runner))
        self.assertEqual(result["skipped"], ["validate", "test"])
        self.assertNotIn("validate", runner.calls)
        self.assertNotIn("test", runner.calls)
        self.assertEqual(result["status"], "fail")

    def test_attack_flood_of_findings_stays_capped_and_failed(self):
        flood = "".join(f"a.tf:{n}:1: Warning - m{n} (rule{n})\n" for n in range(1, 5000))
        text = run_check(fake_runner({"lint": (2, flood)}))
        result = json.loads(text)
        self.assertLessEqual(len(text), output.MAX_BYTES)
        self.assertEqual(result["status"], "fail")
        self.assertEqual(len(result["findings"]) + result["omitted"]["findings"], 4999)

    def test_attack_output_is_redacted(self):
        text = run_check(fake_runner({"validate": (1, "Error: bad arn:aws:iam::123456789012:role/x\n")}))
        self.assertNotIn("123456789012", text)

    def test_second_call_while_running_is_refused(self):
        entered, release = threading.Event(), threading.Event()

        def slow(step):
            entered.set()
            release.wait(5)
            return 0, ""

        thread = threading.Thread(target=run_check, args=(slow,))
        thread.start()
        entered.wait(5)
        result = json.loads(run_check(fake_runner({})))
        release.set()
        thread.join()
        self.assertEqual(result["status"], "error")
        self.assertFalse(checks.LOCK.locked())


if __name__ == "__main__":
    unittest.main()
