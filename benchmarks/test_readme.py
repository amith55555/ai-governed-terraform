"""Tests for readme.py: the README results are generated from the data, never typed by hand."""
import contextlib
import io
import os
import shutil
import tempfile
import unittest

import readme
import report

REPO = readme.REPO
EVAL_HEADER = "eval_id,config,date,session_id,pr,agent_introduced_violation,first_layer,other_layers," \
              "mergeable_without_approval,passed,notes\n"


def evals(*rows):
    return [dict(zip(EVAL_HEADER.strip().split(","), row.split(","))) for row in rows]


class UpToDate(unittest.TestCase):
    def test_readme_results_match_the_data(self):
        with open(os.path.join(REPO, "README.md"), encoding="utf-8") as f:
            current = f.read()
        self.assertEqual(readme.replace_block(current, readme.block()), current,
                         "README results are out of date: run make readme")


class Block(unittest.TestCase):
    def test_only_the_text_between_the_markers_changes(self):
        text = f"top\n{readme.START}\nold numbers\n{readme.END}\nbottom\n"
        self.assertEqual(readme.replace_block(text, "NEW"), "top\nNEW\nbottom\n")

    def test_missing_or_doubled_markers_fail(self):
        for text in ("no markers", f"{readme.START}\n", f"{readme.END}\n{readme.START}\n",
                     f"{readme.START}{readme.START}{readme.END}"):
            with self.subTest(text=text), self.assertRaises(report.BadData):
                readme.replace_block(text, "x")


class Evals(unittest.TestCase):
    def test_repeated_runs_are_numbered_and_counted(self):
        lines = readme.eval_section(evals(
            "E1,harness,d,s,62,no,agent,o,CLEAN,yes,n",
            "E2,harness,d,s,none,no,agent,o,n/a,yes,n",
            "E2,harness,d,s,66,no,agent,o,CLEAN,yes,n"))
        text = "\n".join(lines)
        self.assertIn("| E1 | harness | #62 |", text)
        self.assertIn("| E2 run 1 | harness | none |", text)
        self.assertIn("| E2 run 2 | harness | #66 |", text)
        self.assertIn("3 of 3 runs passed: no violation", text)

    def test_a_failed_run_is_not_hidden(self):
        text = "\n".join(readme.eval_section(evals("E1,harness,d,s,62,yes,none,o,CLEAN,no,n",
                                                   "E2,harness,d,s,63,no,agent,o,CLEAN,yes,n")))
        self.assertIn("1 of 2 runs passed.", text)
        self.assertNotIn("no violation became mergeable", text)

    def test_bad_values_stop_the_report(self):
        for row in ("E1,harness,d,s,62,no,agent,o,CLEAN,maybe,n", "E1,harness,d,s,62,perhaps,agent,o,CLEAN,yes,n",
                    "E1,staging,d,s,62,no,agent,o,CLEAN,yes,n"):
            with self.subTest(row=row), self.assertRaises(report.BadData):
                readme.eval_section(evals(row))

    def test_no_runs_stop_the_report(self):
        with self.assertRaises(report.BadData):
            readme.eval_section([])


class CheckMode(unittest.TestCase):
    def setUp(self):
        self.repo = tempfile.mkdtemp()
        for path in ("benchmarks/prices.csv", "benchmarks/results/runs.csv", "benchmarks/results/usage.csv",
                     "evals/results.csv", "README.md"):
            os.makedirs(os.path.dirname(os.path.join(self.repo, path)), exist_ok=True)
            shutil.copy(os.path.join(REPO, path), os.path.join(self.repo, path))

    def run_main(self, *args):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return readme.main(["--repo", self.repo, *args])

    def test_check_fails_after_the_data_changes_and_passes_after_make_readme(self):
        path = os.path.join(self.repo, "evals", "results.csv")
        with open(path, encoding="utf-8") as f:
            text = f.read()
        with open(path, "w", encoding="utf-8") as f:
            f.write(text.replace(",62,", ",99,", 1))
        self.assertEqual(self.run_main("--check"), 1)
        self.assertEqual(self.run_main(), 0)
        self.assertEqual(self.run_main("--check"), 0)
        with open(os.path.join(self.repo, "README.md"), encoding="utf-8") as f:
            self.assertIn("| #99 |", f.read())

    def test_check_never_writes(self):
        readme_path = os.path.join(self.repo, "README.md")
        with open(readme_path, "a", encoding="utf-8") as f:
            f.write("")
        before = os.path.getmtime(readme_path)
        with open(os.path.join(self.repo, "evals", "results.csv"), "a", encoding="utf-8") as f:
            f.write("E1,harness,d,s,70,no,agent,o,CLEAN,yes,n\n")
        self.assertEqual(self.run_main("--check"), 1)
        self.assertEqual(os.path.getmtime(readme_path), before)


if __name__ == "__main__":
    unittest.main()
