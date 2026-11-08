"""Tests for usage.py: counts each API response once (sub-agents included), splits cache
writes by lifetime, ignores everything else, and never loses history."""
import csv
import json
import os
import tempfile
import unittest

import usage


def assistant(msg_id, request_id, inp, out, cache_write=0, cache_read=0, stamp="2026-11-02T10:00:00Z",
              write_1h=None, sidechain=None):
    message_usage = {
        "input_tokens": inp,
        "output_tokens": out,
        "cache_creation_input_tokens": cache_write,
        "cache_read_input_tokens": cache_read,
    }
    if write_1h is not None:
        message_usage["cache_creation"] = {"ephemeral_5m_input_tokens": cache_write - write_1h,
                                           "ephemeral_1h_input_tokens": write_1h}
    record = {"type": "assistant", "requestId": request_id, "timestamp": stamp,
              "message": {"id": msg_id, "model": "claude-opus-5-5", "usage": message_usage}}
    if sidechain is not None:
        record["isSidechain"] = sidechain
    return json.dumps(record)


def main_only(lines):
    return [(lines, False)]


class Summarize(unittest.TestCase):
    def test_counts_each_response_once(self):
        lines = [
            assistant("m1", "r1", 10, 5, 100, 1000, "2026-11-02T10:00:00Z"),
            assistant("m1", "r1", 10, 5, 100, 1000, "2026-11-02T10:00:01Z"),  # same response, 2nd content block
            assistant("m2", "r2", 20, 7, 0, 2000, "2026-11-02T10:05:00Z"),
        ]
        row = usage.summarize("s1", main_only(lines))
        self.assertEqual(row["api_calls"], 2)
        self.assertEqual(row["input_tokens"], 30)
        self.assertEqual(row["output_tokens"], 12)
        self.assertEqual(row["cache_write_5m_tokens"], 100)
        self.assertEqual(row["cache_read_tokens"], 3000)
        self.assertEqual(row["total_tokens"], 30 + 12 + 100 + 3000)
        self.assertEqual(row["started"], "2026-11-02T10:00:00Z")
        self.assertEqual(row["ended"], "2026-11-02T10:05:00Z")
        self.assertEqual(row["models"], "claude-opus-5-5")

    def test_cache_writes_are_split_by_lifetime(self):
        row = usage.summarize("s1", main_only([assistant("m1", "r1", 1, 1, 1000, 0, write_1h=600)]))
        self.assertEqual((row["cache_write_5m_tokens"], row["cache_write_1h_tokens"]), (400, 600))

    def test_bad_split_never_exceeds_the_total(self):
        row = usage.summarize("s1", main_only([assistant("m1", "r1", 1, 1, 100, 0, write_1h=500)]))
        self.assertEqual((row["cache_write_5m_tokens"], row["cache_write_1h_tokens"]), (0, 100))

    def test_ignores_other_lines(self):
        lines = [
            json.dumps({"type": "user", "message": {"content": "hi"}}),
            json.dumps({"type": "assistant", "message": {"content": "no usage"}}),
            "not json at all",
            json.dumps(["a", "list"]),
        ]
        row = usage.summarize("s1", main_only(lines))
        self.assertEqual(row["api_calls"], 0)
        self.assertEqual(row["total_tokens"], 0)

    def test_missing_ids_are_not_merged_together(self):
        lines = [
            json.dumps({"type": "assistant", "message": {"usage": {"input_tokens": 1, "output_tokens": 1}}}),
            json.dumps({"type": "assistant", "message": {"usage": {"input_tokens": 1, "output_tokens": 1}}}),
        ]
        self.assertEqual(usage.summarize("s1", main_only(lines))["api_calls"], 2)


class SubAgents(unittest.TestCase):
    def test_subagent_logs_are_added_to_the_session(self):
        main = [assistant("m1", "r1", 10, 5)]
        sub = [assistant("m2", "r2", 20, 7), assistant("m3", "r3", 1, 1)]
        row = usage.summarize("s1", [(main, False), (sub, True)])
        self.assertEqual((row["api_calls"], row["subagent_calls"]), (3, 2))
        self.assertEqual(row["input_tokens"], 31)

    def test_a_response_in_both_logs_counts_once(self):
        line = assistant("m2", "r2", 20, 7)
        row = usage.summarize("s1", [([assistant("m1", "r1", 1, 1), line], False), ([line], True)])
        self.assertEqual(row["api_calls"], 2)

    def test_sidechain_lines_in_the_main_log_count_as_subagent(self):
        row = usage.summarize("s1", main_only([assistant("m1", "r1", 1, 1, sidechain=True)]))
        self.assertEqual(row["subagent_calls"], 1)

    def test_read_sessions_finds_the_subagent_folder(self):
        directory = tempfile.mkdtemp()
        with open(os.path.join(directory, "abc.jsonl"), "w", encoding="utf-8") as f:
            f.write(assistant("m1", "r1", 1, 1) + "\n")
        os.makedirs(os.path.join(directory, "abc", "subagents"))
        with open(os.path.join(directory, "abc", "subagents", "agent-1.jsonl"), "w", encoding="utf-8") as f:
            f.write(assistant("m2", "r2", 2, 2) + "\n")
        rows = usage.read_sessions(directory)
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0]["api_calls"], rows[0]["subagent_calls"]), (2, 1))


class Merge(unittest.TestCase):
    def test_rows_are_kept_after_logs_are_deleted(self):
        path = os.path.join(tempfile.mkdtemp(), "results", "usage.csv")
        old = usage.summarize("old", main_only([assistant("m1", "r1", 1, 1, stamp="2026-11-01T00:00:00Z")]))
        usage.merge(path, [old])
        new = usage.summarize("new", main_only([assistant("m2", "r2", 2, 2, stamp="2026-11-02T00:00:00Z")]))
        usage.merge(path, [new])  # "old" is no longer in the logs
        with open(path, newline="", encoding="utf-8") as f:
            ids = [r["session_id"] for r in csv.DictReader(f)]
        self.assertEqual(ids, ["old", "new"])

    def test_a_session_is_updated_not_duplicated(self):
        path = os.path.join(tempfile.mkdtemp(), "usage.csv")
        usage.merge(path, [usage.summarize("s", main_only([assistant("m1", "r1", 1, 1)]))])
        usage.merge(path, [usage.summarize("s", main_only([assistant("m1", "r1", 1, 1), assistant("m2", "r2", 5, 5)]))])
        with open(path, newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["api_calls"], "2")

    def test_old_format_rows_keep_their_cache_writes(self):
        path = os.path.join(tempfile.mkdtemp(), "usage.csv")
        with open(path, "w", newline="", encoding="utf-8") as f:
            f.write("session_id,started,ended,models,api_calls,input_tokens,output_tokens,cache_write_tokens,"
                    "cache_read_tokens,total_tokens\nold,2026-11-01T00:00:00Z,x,m,3,1,2,300,400,703\n")
        usage.merge(path, [])
        with open(path, newline="", encoding="utf-8") as f:
            row = next(csv.DictReader(f))
        self.assertEqual((row["cache_write_5m_tokens"], row["cache_write_1h_tokens"]), ("300", ""))
        self.assertEqual(row["total_tokens"], "703")


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
