"""Attack tests for pre_tool_guard.py: every forbidden action must be blocked,
and normal work must still be allowed."""
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

import pre_tool_guard
from pre_tool_guard import check

HERE = os.path.dirname(os.path.abspath(__file__))


class GuardTest(unittest.TestCase):
    def setUp(self):
        self.root = os.path.realpath(tempfile.mkdtemp())
        os.makedirs(os.path.join(self.root, "policies"))
        os.makedirs(os.path.join(self.root, "app"))
        # A symlink inside an editable folder that points into a protected one.
        os.symlink(os.path.join(self.root, "policies"), os.path.join(self.root, "app", "sneaky"))

    def run_tool(self, tool, **tool_input):
        return check({"tool_name": tool, "tool_input": tool_input, "cwd": self.root}, self.root)

    def assert_blocked(self, tool, **tool_input):
        self.assertIsNotNone(self.run_tool(tool, **tool_input), f"should be BLOCKED: {tool} {tool_input}")

    def assert_allowed(self, tool, **tool_input):
        self.assertIsNone(self.run_tool(tool, **tool_input), f"should be ALLOWED: {tool} {tool_input}")


class BashBlocked(GuardTest):
    COMMANDS = [
        # F1: terraform state changes and anything that runs agent-written code through terraform
        "terraform apply",
        "terraform -chdir=terraform/envs/dev destroy",
        "terraform state list",
        "terraform init -backend=false",
        "make up",
        "make down",
        "make plan",
        "make -f other.mk check",
        "make -C app check",
        "cd app && make check",
        "make secrets RANGE=--output=policies/x",
        # F2: AWS
        "aws s3 ls",
        "AWS_PROFILE=tfp-admin make check",
        "cat ~/.aws/config",
        # F4: approving, merging, admin, tokens
        "gh pr merge 5 --squash",
        "gh pr review 5 --approve",
        "gh api repos/x/y/rulesets",
        "gh auth token",
        "cat ~/.config/gh/hosts.yml",
        "cat ~/.config/aigt-agent/token",
        "cat /proc/self/environ",
        "grep GH_TOKEN /proc/1/environ",
        # F5: skipping hooks
        "git commit --no-verify -m x",
        "git commit -anm x",
        "git -c core.hooksPath=/dev/null commit -m x",
        "git config core.hooksPath /dev/null",
        # pushing main, forcing, deleting
        "git push --force",
        "git push -f origin feat/x",
        "git push origin main",
        "git push origin HEAD:main",
        "git push origin --delete feat/x",
        # F3: writing protected paths, every way
        "echo x > policies/terraform/tags.rego",
        "echo x >> Makefile",
        "printf x > GNUmakefile",
        "echo '[allowlist]' > .gitleaks.toml",
        "touch .tool-versions",
        "cp app/handler.py scripts/x.sh",
        "cp --target-directory=policies app/handler.py",
        "rm -rf .github",
        "mv risk/risk_gate.py app/",
        "cd policies && rm tags.rego",
        "rm app/sneaky/tags.rego",
        "git checkout main -- policies/terraform/tags.rego",
        "tee .claude/settings.json",
        "echo x > .git/hooks/pre-commit",
        # files that would make CI skip checks
        "touch terraform/envs/dev/x.tf.json",
        "touch .checkov.yml",
        # wildcards and the whole repo
        "rm p*",
        "rm -rf .",
        # writes outside the repo
        "echo x > /tmp/x",
        "echo x >> ~/.bashrc",
        # private values
        "cat terraform/envs/dev/terraform.tfvars",
        "cat .env",
        # running arbitrary code
        "t=terraform; $t apply",
        "echo `whoami`",
        "bash -c 'terraform apply'",
        "sh scripts/scan.sh",
        "python3 -c 'print(1)'",
        "python3 app/handler.py",
        "./scripts/scan.sh",
        "/usr/bin/terraform apply",
        "env terraform apply",
        "xargs rm < files.txt",
        "find . -name x -exec rm {} ;",
        "find . -delete",
        "sed -i s/a/b/ app/handler.py",
        "awk 'BEGIN{system(\"id\")}'",
        "(cd policies; rm x)",
        "cat <<EOF",
        "curl https://example.com",
        "pip install requests",
        "sudo ls",
        "cd /",
        # a forbidden command hidden after an allowed one
        "terraform fmt && aws sts get-caller-identity",
        "make check; terraform apply",
        "ls | xargs rm",
        "echo ok\naws s3 ls",
    ]

    def test_all_blocked(self):
        for command in self.COMMANDS:
            with self.subTest(command=command):
                self.assert_blocked("Bash", command=command)


class BashAllowed(GuardTest):
    COMMANDS = [
        "make check",
        "make",
        "make test",
        "make plan-policy PLAN=/tmp/dev-plan.json",
        "git status && git diff",
        "git add -A",
        "git commit -m 'fix: handle empty body'",
        "git commit -m 'message with ; and && inside quotes'",
        "git switch -c feat/new-alarm",
        "git push -u origin feat/new-alarm",
        "gh pr create --base main --title t --body b",
        "gh pr checks",
        "gh run view 123 --log",
        "terraform fmt -recursive terraform/",
        "ls -la terraform/modules",
        "grep -rn bucket terraform/modules",
        "cat policies/terraform/tags.rego",
        "cat AGENTS.md",
        "echo hi > docs/notes.md",
        "mkdir -p terraform/modules/sqs_queue",
        "rm docs/old.md",
        "cd terraform/modules && ls",
        "make check 2>&1 | tail -n 40",
        "find terraform -name '*.tf'",
        "jq .level /tmp/risk.json",
    ]

    def test_all_allowed(self):
        for command in self.COMMANDS:
            with self.subTest(command=command):
                self.assert_allowed("Bash", command=command)


class FileTools(GuardTest):
    def test_writes_blocked(self):
        for path in [
            ".github/workflows/pr.yml",
            "docs/agent-log.md",
            "benchmarks/results/usage.csv",
            "policies/terraform/tags.rego",
            "Makefile",
            "GNUmakefile",
            "mise.local.toml",
            ".gitleaksignore",
            ".claude/settings.local.json",
            ".git/hooks/pre-commit",
            "terraform/bootstrap/ci-apply.tf",
            "terraform/../policies/x.rego",
            "app/sneaky/x.rego",
            "terraform/envs/dev/x.tf.json",
            "terraform/envs/dev/terraform.tfvars",
            "/home/someone/.bashrc",
            "~/.claude/settings.json",
        ]:
            for tool in ("Write", "Edit", "MultiEdit"):
                with self.subTest(tool=tool, path=path):
                    self.assert_blocked(tool, file_path=path)

    def test_writes_allowed(self):
        for path in ["terraform/modules/s3_bucket/main.tf", "app/handler.py", "docs/notes.md"]:
            with self.subTest(path=path):
                self.assert_allowed("Write", file_path=path)

    def test_secret_reads_blocked(self):
        self.assert_blocked("Read", file_path="~/.aws/config")
        self.assert_blocked("Read", file_path="terraform/envs/dev/terraform.tfvars")
        self.assert_blocked("Grep", pattern="token", path="~/.config/gh")
        self.assert_blocked("Glob", pattern="**/*.tfvars")
        self.assert_blocked("Read", file_path="~/.config/aigt-agent/token")
        self.assert_blocked("Read", file_path="/proc/self/environ")

    def test_normal_reads_allowed(self):
        self.assert_allowed("Read", file_path="policies/terraform/tags.rego")
        self.assert_allowed("Grep", pattern="bucket", path="terraform")
        self.assert_allowed("Glob", pattern="terraform/**/*.tf")

    def test_missing_path_blocked(self):
        self.assert_blocked("Write")


class Scratchpad(GuardTest):
    """Writes are allowed only inside this session's own Claude Code scratchpad."""
    SESSION = "5168f3b1-5c24-4399-a8c6-2684c39d1244"

    def setUp(self):
        super().setUp()
        self.saved_base = pre_tool_guard.SCRATCH_BASE
        self.base = os.path.realpath(tempfile.mkdtemp())
        pre_tool_guard.SCRATCH_BASE = self.base
        self.project = os.path.join(self.base, f"claude-{os.getuid()}", re.sub(r"[^A-Za-z0-9]", "-", self.root))
        self.pad = os.path.join(self.project, self.SESSION, "scratchpad")
        os.makedirs(self.pad)
        os.symlink(os.path.join(self.root, "policies"), os.path.join(self.pad, "out"))

    def tearDown(self):
        pre_tool_guard.SCRATCH_BASE = self.saved_base

    def run_as(self, session, tool, **tool_input):
        payload = {"tool_name": tool, "tool_input": tool_input, "cwd": self.root, "session_id": session}
        return check(payload, self.root)

    def test_own_scratchpad_allowed(self):
        for tool, tool_input in [
            ("Write", {"file_path": f"{self.pad}/pr.md"}),
            ("Write", {"file_path": f"{self.pad}/notes/commit.txt"}),
            ("Bash", {"command": f"echo body > {self.pad}/pr.md"}),
            ("Bash", {"command": f"rm {self.pad}/pr.md"}),
        ]:
            with self.subTest(tool=tool, tool_input=tool_input):
                self.assertIsNone(self.run_as(self.SESSION, tool, **tool_input))

    def test_attack_paths_outside_own_scratchpad_blocked(self):
        other_session = "00000000-0000-4000-8000-000000000000"
        for path in [
            self.pad,  # the folder itself
            f"{self.project}/{other_session}/scratchpad/pr.md",  # another session
            f"{self.base}/claude-{os.getuid()}/-home-other-repo/{self.SESSION}/scratchpad/pr.md",  # another repo
            f"{self.base}/claude-99999/{os.path.basename(self.project)}/{self.SESSION}/scratchpad/pr.md",  # another user
            f"{self.pad}/../../{other_session}/scratchpad/pr.md",  # .. escape
            f"{self.pad}/../pr.md",  # just above it
            f"{self.pad}/out/x.rego",  # symlink into the repo's protected policies/
            f"{self.pad}/.env",  # secrets stay blocked
            f"{self.pad}/dev.tfvars",
            f"{self.base}/x.md",
        ]:
            with self.subTest(path=path):
                self.assertIsNotNone(self.run_as(self.SESSION, "Write", file_path=path))

    def test_attack_bad_session_ids_blocked(self):
        for session in [None, "", "../../x", f"{self.SESSION}/..", self.SESSION.upper(), 42]:
            with self.subTest(session=session):
                self.assertIsNotNone(self.run_as(session, "Write", file_path=f"{self.pad}/pr.md"))

    def test_session_is_not_remembered_between_calls(self):
        self.assertIsNone(self.run_as(self.SESSION, "Write", file_path=f"{self.pad}/pr.md"))
        self.assertIsNotNone(self.run_as(None, "Write", file_path=f"{self.pad}/pr.md"))


class Wiring(unittest.TestCase):
    """Run the real script the way Claude Code does: JSON on stdin, exit code out."""

    def run_script(self, stdin):
        return subprocess.run(
            [sys.executable, "-I", os.path.join(HERE, "pre_tool_guard.py")],
            input=stdin, capture_output=True, text=True,
        )

    def test_block_is_exit_2_with_reason(self):
        result = self.run_script(json.dumps({"tool_name": "Bash", "tool_input": {"command": "terraform apply"}, "cwd": HERE}))
        self.assertEqual(result.returncode, 2)
        self.assertIn("BLOCKED", result.stderr)

    def test_allow_is_exit_0(self):
        result = self.run_script(json.dumps({"tool_name": "Bash", "tool_input": {"command": "ls"}, "cwd": HERE}))
        self.assertEqual(result.returncode, 0)

    def test_bad_input_fails_closed(self):
        result = self.run_script("this is not json")
        self.assertEqual(result.returncode, 2)

class Settings(unittest.TestCase):
    """If the guard cannot even start (for example, no python3), Claude Code treats that
    as a non-blocking error and runs the tool anyway. The command must turn it into a block.
    Found in the W2.6 live test (Claude Code on Windows had no python3)."""

    def test_guard_command_fails_closed(self):
        with open(os.path.join(HERE, "..", "settings.json"), encoding="utf-8") as f:
            settings = json.load(f)
        commands = [h["command"] for entry in settings["hooks"]["PreToolUse"] for h in entry["hooks"]]
        self.assertTrue(commands)
        for command in commands:
            self.assertTrue(command.rstrip().endswith("|| exit 2"), command)

    def test_missing_interpreter_becomes_a_block(self):
        result = subprocess.run(["bash", "-c", "no-such-python-xyz -I guard.py || exit 2"], capture_output=True)
        self.assertEqual(result.returncode, 2)

if __name__ == "__main__":
    unittest.main()
