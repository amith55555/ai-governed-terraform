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
                     "benchmarks/v2/results/v2.csv", "benchmarks/v2/results/manual-review.csv",
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


V2_HEADER = ["run_id", "task", "config", "agent", "date", "session_ids", "pr", "status", "success", "ci_pushes",
             "first_pass_ci", "minutes", "cost_estimate_usd", "turns", "tool_calls", "guard_blocks", "tools",
             "fixed_reply", "planted", "failed_checks", "notes"]
PRICES = {"m1": {"input": "4", "output": "20", "cache_write_5m": "5", "cache_write_1h": "8", "cache_read": "0.2"}}


def v2_run(run_id, task, config, success, session, minutes="2"):
    row = dict.fromkeys(V2_HEADER, "")
    row.update(run_id=run_id, task=task, config=config, session_ids=session, success=success,
               first_pass_ci="yes", minutes=minutes, tool_calls="20", guard_blocks="0")
    return row


def usage(*sessions, output=1_000_000):
    return {s: {"session_id": s, "models": "m1", "output_tokens": str(output)} for s in sessions}


class V2(unittest.TestCase):
    def runs(self, h_success=("yes", "yes", "yes"), b_success=("yes", "yes", "yes")):
        rows = []
        for i, task in enumerate(readme.V2_TASKS):
            rows.append(v2_run(f"{task}-b1", task, "baseline", b_success[i], f"b{i}"))
            rows.append(v2_run(f"{task}-h1", task, "harness", h_success[i], f"h{i}"))
        return rows

    def text(self, runs, review=None, out=1_000_000):
        sessions = [r["session_ids"] for r in runs]
        return "\n".join(readme.v2_section(runs, review or {}, usage(*sessions, output=out), PRICES))

    def test_cost_is_price_weighted_from_tokens(self):
        text = self.text(self.runs())
        self.assertIn("| baseline | 3 | 3/3 | 3/3 | 3/3 |", text)
        self.assertIn("$20.00", text)  # 1M output tokens x $20 per million

    def test_manual_review_changes_only_the_reviewed_column(self):
        runs = self.runs(h_success=("no", "yes", "yes"))
        text = self.text(runs, review={"C1-h1": {"reviewed_success": "yes"}})
        self.assertIn("| harness | 3 | 2/3 | 3/3 |", text)

    def test_rule_uses_judge_verdicts(self):
        self.assertIn("did not help", self.text(self.runs()))  # equal success, equal cost
        helped = self.runs(h_success=("yes", "yes", "yes"), b_success=("no", "no", "yes"))
        self.assertIn("the harness **helped**", self.text(helped))
        one_more = self.runs(h_success=("yes", "yes", "yes"), b_success=("no", "yes", "yes"))
        self.assertIn("did not help", self.text(one_more))

    def test_missing_usage_stops_the_report(self):
        runs = self.runs()
        with self.assertRaises(report.BadData):
            readme.v2_section(runs, {}, usage("b0"), PRICES)

    def test_bad_values_stop_the_report(self):
        runs = self.runs()
        runs[0]["success"] = "maybe"
        with self.assertRaises(report.BadData):
            self.text(runs)


if __name__ == "__main__":
    unittest.main()
