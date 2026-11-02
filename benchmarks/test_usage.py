"""Tests for usage.py: counts each API response once, ignores everything else,
and never loses history."""
import csv
import json
import os
import tempfile
import unittest

import usage


def assistant(msg_id, request_id, inp, out, cache_write=0, cache_read=0, stamp="2026-11-02T10:00:00Z"):
    return json.dumps({
        "type": "assistant",
        "requestId": request_id,
        "timestamp": stamp,
        "message": {
            "id": msg_id,
            "model": "claude-opus-5-5",
            "usage": {
                "input_tokens": inp,
                "output_tokens": out,
                "cache_creation_input_tokens": cache_write,
                "cache_read_input_tokens": cache_read,
            },
        },
    })


class Summarize(unittest.TestCase):
    def test_counts_each_response_once(self):
        lines = [
            assistant("m1", "r1", 10, 5, 100, 1000, "2026-11-02T10:00:00Z"),
            assistant("m1", "r1", 10, 5, 100, 1000, "2026-11-02T10:00:01Z"),  # same response, 2nd content block
            assistant("m2", "r2", 20, 7, 0, 2000, "2026-11-02T10:05:00Z"),
        ]
        row = usage.summarize("s1", lines)
        self.assertEqual(row["api_calls"], 2)
        self.assertEqual(row["input_tokens"], 30)
        self.assertEqual(row["output_tokens"], 12)
        self.assertEqual(row["cache_write_tokens"], 100)
        self.assertEqual(row["cache_read_tokens"], 3000)
        self.assertEqual(row["total_tokens"], 30 + 12 + 100 + 3000)
        self.assertEqual(row["started"], "2026-11-02T10:00:00Z")
        self.assertEqual(row["ended"], "2026-11-02T10:05:00Z")
        self.assertEqual(row["models"], "claude-opus-5-5")

    def test_ignores_other_lines(self):
        lines = [
            json.dumps({"type": "user", "message": {"content": "hi"}}),
            json.dumps({"type": "assistant", "message": {"content": "no usage"}}),
            "not json at all",
            json.dumps(["a", "list"]),
        ]
        row = usage.summarize("s1", lines)
        self.assertEqual(row["api_calls"], 0)
        self.assertEqual(row["total_tokens"], 0)

    def test_missing_ids_are_not_merged_together(self):
        lines = [
            json.dumps({"type": "assistant", "message": {"usage": {"input_tokens": 1, "output_tokens": 1}}}),
            json.dumps({"type": "assistant", "message": {"usage": {"input_tokens": 1, "output_tokens": 1}}}),
        ]
        self.assertEqual(usage.summarize("s1", lines)["api_calls"], 2)


class Merge(unittest.TestCase):
    def test_rows_are_kept_after_logs_are_deleted(self):
        path = os.path.join(tempfile.mkdtemp(), "results", "usage.csv")
        old = usage.summarize("old", [assistant("m1", "r1", 1, 1, stamp="2026-11-01T00:00:00Z")])
        usage.merge(path, [old])
        new = usage.summarize("new", [assistant("m2", "r2", 2, 2, stamp="2026-11-02T00:00:00Z")])
        usage.merge(path, [new])  # "old" is no longer in the logs
        with open(path, newline="", encoding="utf-8") as f:
            ids = [r["session_id"] for r in csv.DictReader(f)]
        self.assertEqual(ids, ["old", "new"])

    def test_a_session_is_updated_not_duplicated(self):
        path = os.path.join(tempfile.mkdtemp(), "usage.csv")
        usage.merge(path, [usage.summarize("s", [assistant("m1", "r1", 1, 1)])])
        usage.merge(path, [usage.summarize("s", [assistant("m1", "r1", 1, 1), assistant("m2", "r2", 5, 5)])])
        with open(path, newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["api_calls"], "2")


class LogDir(unittest.TestCase):
    def test_finds_claude_code_folder_for_the_repo(self):
        home = tempfile.mkdtemp()
        expected = os.path.join(home, ".claude", "projects", "-home-amit-code-ai-governed-terraform")
        os.makedirs(expected)
        self.assertEqual(usage.log_dir("/home/amit/code/ai-governed-terraform", home), expected)

    def test_none_when_missing(self):
        self.assertIsNone(usage.log_dir("/nowhere/repo", tempfile.mkdtemp()))


if __name__ == "__main__":
    unittest.main()
