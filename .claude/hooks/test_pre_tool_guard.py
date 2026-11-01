"""Attack tests for pre_tool_guard.py: every forbidden action must be blocked,
and normal work must still be allowed."""
import json
import os
import subprocess
import sys
import tempfile
import unittest

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
        for path in ["terraform/modules/s3_bucket/main.tf", "app/handler.py", "docs/agent-log.md"]:
            with self.subTest(path=path):
                self.assert_allowed("Write", file_path=path)

    def test_secret_reads_blocked(self):
        self.assert_blocked("Read", file_path="~/.aws/config")
        self.assert_blocked("Read", file_path="terraform/envs/dev/terraform.tfvars")
        self.assert_blocked("Grep", pattern="token", path="~/.config/gh")
        self.assert_blocked("Glob", pattern="**/*.tfvars")

    def test_normal_reads_allowed(self):
        self.assert_allowed("Read", file_path="policies/terraform/tags.rego")
        self.assert_allowed("Grep", pattern="bucket", path="terraform")
        self.assert_allowed("Glob", pattern="terraform/**/*.tf")

    def test_missing_path_blocked(self):
        self.assert_blocked("Write")


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


if __name__ == "__main__":
    unittest.main()
