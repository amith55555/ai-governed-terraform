"""Tests for server.py through a real MCP client: the tool list, schemas and argument handling.

Needs the pinned SDK: run with `make mcp-test`, which uses the server's own .venv.
"""
import asyncio
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

from mcp.client import Client
from mcp.client.stdio import StdioServerParameters

import checks
import plan
import server

SERVER = Path(__file__).resolve().parent / "server.py"


def run(coro):
    return asyncio.run(coro)


async def list_tools(target):
    async with Client(target) as client:
        return {tool.name: tool for tool in (await client.list_tools()).tools}


async def call(name, arguments):
    async with Client(server.server) as client:
        return await client.call_tool(name, arguments)


class ToolList(unittest.TestCase):
    def setUp(self):
        self.tools = run(list_tools(server.server))

    def test_exactly_two_tools(self):
        self.assertEqual(set(self.tools), {"check", "plan_summary"})

    def test_check_takes_no_input(self):
        self.assertEqual(self.tools["check"].input_schema.get("properties"), {})

    def test_plan_summary_takes_a_number_and_a_fixed_env(self):
        schema = self.tools["plan_summary"].input_schema
        self.assertEqual(schema["required"], ["pr"])
        self.assertEqual(schema["properties"]["pr"]["type"], "integer")
        self.assertEqual(schema["properties"]["env"]["enum"], ["dev", "prod", "all"])
        self.assertEqual(set(schema["properties"]), {"pr", "env"})

    def test_every_tool_is_marked_read_only(self):
        for name, tool in self.tools.items():
            with self.subTest(name):
                self.assertTrue(tool.annotations.read_only_hint)
                self.assertFalse(tool.annotations.destructive_hint)


class Arguments(unittest.TestCase):
    def test_attack_text_as_pr_is_rejected_before_the_tool_runs(self):
        with mock.patch.object(plan, "summarize") as summarize:
            for value in ("31; rm -rf .", "$(id)", 3.5, None, [31]):
                with self.subTest(value=value):
                    self.assertTrue(run(call("plan_summary", {"pr": value})).is_error)
            summarize.assert_not_called()

    def test_attack_unknown_env_is_rejected(self):
        with mock.patch.object(plan, "summarize") as summarize:
            self.assertTrue(run(call("plan_summary", {"pr": 31, "env": "staging"})).is_error)
            summarize.assert_not_called()

    def test_attack_extra_arguments_never_reach_a_command(self):
        with mock.patch.object(plan, "summarize", return_value="{}") as summarize:
            run(call("plan_summary", {"pr": 31, "cmd": "make up", "env": "dev"}))
        summarize.assert_called_once_with(31, "dev")
        with mock.patch.object(checks, "run_check", return_value="{}") as run_check:
            run(call("check", {"target": "up", "argv": ["aws", "s3", "ls"]}))
        run_check.assert_called_once_with()

    def test_attack_unknown_tool_is_an_error(self):
        self.assertTrue(run(call("apply", {})).is_error)

    def test_result_is_the_tool_json_text(self):
        with mock.patch.object(plan, "summarize", return_value='{"status":"ok"}'):
            result = run(call("plan_summary", {"pr": 31}))
        self.assertFalse(result.is_error)
        self.assertEqual(json.loads(result.content[0].text), {"status": "ok"})


class Stdio(unittest.TestCase):
    def test_server_starts_over_stdio_exactly_as_registered(self):
        params = StdioServerParameters(command=sys.executable, args=["-I", str(SERVER)], cwd=str(SERVER.parent))
        self.assertEqual(set(run(list_tools(params))), {"check", "plan_summary"})


if __name__ == "__main__":
    unittest.main()
