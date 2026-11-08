"""Tests for report.py: cost is price-weighted, every number comes from the CSV files,
and bad or missing data stops the report instead of producing a number."""
import contextlib
import io
import os
import tempfile
import unittest

import report

PRICES = "model,input,output,cache_write_5m,cache_write_1h,cache_read,unit,checked,source\n" \
         "m1,4,20,5,8,0.2,USD per million tokens,2026-11-08,https://example.com\n"
USAGE_HEADER = "session_id,started,ended,models,api_calls,subagent_calls,input_tokens,output_tokens," \
               "cache_write_5m_tokens,cache_write_1h_tokens,cache_read_tokens,total_tokens\n"
RUNS_HEADER = "run_id,task,config,run,session_id,pr,date,success,first_pass_ci,ci_pushes,stop_hook_blocks," \
              "human_interventions,notes\n"


def folder(runs, usage):
    path = tempfile.mkdtemp()
    os.makedirs(os.path.join(path, "results"))
    for name, text in (("prices.csv", PRICES), ("results/runs.csv", RUNS_HEADER + runs),
                       ("results/usage.csv", USAGE_HEADER + usage)):
        with open(os.path.join(path, name), "w", encoding="utf-8") as f:
            f.write(text)
    return path


def run_report(path):
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        return report.main(["--results", os.path.join(path, "results"),
                            "--prices", os.path.join(path, "prices.csv")])


def output(path):
    with open(os.path.join(path, "results", "report.md"), encoding="utf-8") as f:
        return f.read()


GOOD_USAGE = ("s1,a,b,m1,10,0,1000000,0,0,0,0,1000000\n"
              "s2,a,b,m1,5,2,0,0,0,0,1000000,1000000\n"
              "s3,a,b,m1,1,0,0,1000000,0,0,0,1000000\n")


class Cost(unittest.TestCase):
    def test_cost_is_weighted_by_price_not_summed(self):
        path = folder("b1,T1,baseline,1,s1,40,2026-11-09,yes,yes,1,0,0,\n"
                      "h1,T1,harness,1,s2,40,2026-11-09,yes,no,2,1,0,\n", GOOD_USAGE)
        self.assertEqual(run_report(path), 0)
        text = output(path)
        self.assertIn("| baseline | 1 | 1/1 | 1/1 |", text)
        self.assertIn("$4.00", text)   # 1M input tokens
        self.assertIn("$0.20", text)   # 1M cache-read tokens: same token count, 20x cheaper
        self.assertIn("-95%", text)

    def test_a_run_with_several_sessions_adds_them(self):
        path = folder("b1,T1,baseline,1,s1 s3,40,2026-11-09,yes,yes,1,0,0,\n", GOOD_USAGE)
        self.assertEqual(run_report(path), 0)
        self.assertIn("$24.00", output(path))


class BadData(unittest.TestCase):
    def assert_fails(self, runs, usage=GOOD_USAGE):
        self.assertEqual(run_report(folder(runs, usage)), 1)

    def test_no_runs(self):
        self.assert_fails("")

    def test_unknown_session(self):
        self.assert_fails("b1,T1,baseline,1,nope,40,2026-11-09,yes,yes,1,0,0,\n")

    def test_unpriced_model(self):
        self.assert_fails("b1,T1,baseline,1,s1,40,2026-11-09,yes,yes,1,0,0,\n", "s1,a,b,other,1,0,1,1,0,0,0,2\n")

    def test_two_models_in_one_session(self):
        self.assert_fails("b1,T1,baseline,1,s1,40,2026-11-09,yes,yes,1,0,0,\n", "s1,a,b,m1 m2,1,0,1,1,0,0,0,2\n")

    def test_bad_yes_no(self):
        self.assert_fails("b1,T1,baseline,1,s1,40,2026-11-09,maybe,yes,1,0,0,\n")

    def test_duplicate_run(self):
        self.assert_fails("b1,T1,baseline,1,s1,40,2026-11-09,yes,yes,1,0,0,\n"
                          "b1,T1,baseline,2,s3,40,2026-11-09,yes,yes,1,0,0,\n")

    def test_unknown_config(self):
        self.assert_fails("b1,T1,fancy,1,s1,40,2026-11-09,yes,yes,1,0,0,\n")


class RealFiles(unittest.TestCase):
    def test_prices_file_has_every_column_and_a_source(self):
        rows = report.read_csv(os.path.join(report.HERE, "prices.csv"))
        self.assertTrue(rows)
        for row in rows:
            for key in list(report.TOKEN_PRICES.values()) + ["checked", "source"]:
                with self.subTest(model=row["model"], key=key):
                    self.assertTrue(row[key].strip())
            self.assertTrue(row["source"].startswith("https://"))


if __name__ == "__main__":
    unittest.main()
