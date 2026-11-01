"""The protected-path list exists in three places. This test fails if they drift apart:
  .claude/hooks/pre_tool_guard.py   (local hook)
  .github/workflows/guard.yml       (CI approval)
  .github/CODEOWNERS                (documentation)
"""
import os
import re
import unittest

from pre_tool_guard import PROTECTED

REPO = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# Paths that must NOT be protected (the agent's normal work area).
EDITABLE = [
    "terraform/modules/s3_bucket/main.tf",
    "terraform/envs/dev/main.tf",
    "app/handler.py",
    "docs/agent-log.md",
    "README.md",
    "Makefile.bak/x",
    "scripts.md",
]


def read(relative):
    with open(os.path.join(REPO, relative), encoding="utf-8") as f:
        return f.read()


def ci_regex():
    match = re.search(r"PROTECTED: '(.+)'", read(".github/workflows/guard.yml"))
    return re.compile(match.group(1))


def codeowners_paths():
    """Each CODEOWNERS entry as a sample path: '/policies/' -> 'policies/x', '/Makefile' -> 'Makefile'."""
    samples = []
    for line in read(".github/CODEOWNERS").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        path = line.split()[0].lstrip("/")
        samples.append(path + "x" if path.endswith("/") else path)
    return samples


class ProtectedListsAgree(unittest.TestCase):
    def test_every_codeowners_entry_is_protected_locally_and_in_ci(self):
        ci = ci_regex()
        samples = codeowners_paths()
        self.assertGreater(len(samples), 10)
        for path in samples:
            with self.subTest(path=path):
                self.assertTrue(PROTECTED.search(path), "missing in pre_tool_guard.py")
                self.assertTrue(ci.search(path), "missing in guard.yml")

    def test_ci_and_hook_agree(self):
        ci = ci_regex()
        for path in codeowners_paths() + EDITABLE:
            with self.subTest(path=path):
                self.assertEqual(bool(ci.search(path)), bool(PROTECTED.search(path)))

    def test_normal_work_area_is_not_protected(self):
        ci = ci_regex()
        for path in EDITABLE:
            with self.subTest(path=path):
                self.assertFalse(PROTECTED.search(path))
                self.assertFalse(ci.search(path))


if __name__ == "__main__":
    unittest.main()
