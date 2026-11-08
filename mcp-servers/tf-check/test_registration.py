"""Tests that .mcp.json starts this server the safe way, and that the guard's
allowlist matches the server's real tools (a rename must fail a test, not the guard)."""
import asyncio
import importlib.util
import json
import unittest
from pathlib import Path

from mcp.client import Client

import server

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PREFIX = "${CLAUDE_PROJECT_DIR:-.}/"


def registration():
    with open(REPO / ".mcp.json", encoding="utf-8") as f:
        return json.load(f)["mcpServers"]


def guard_tools():
    spec = importlib.util.spec_from_file_location("pre_tool_guard", REPO / ".claude/hooks/pre_tool_guard.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return set(module.MCP_TOOLS)


async def server_tools():
    async with Client(server.server) as client:
        return {tool.name for tool in (await client.list_tools()).tools}


class Registration(unittest.TestCase):
    def test_only_this_server_is_registered(self):
        self.assertEqual(set(registration()), {"tf-check"})

    def test_started_with_the_venv_python_in_safe_mode(self):
        entry = registration()["tf-check"]
        self.assertEqual(entry["type"], "stdio")
        self.assertEqual(entry["command"], PREFIX + "mcp-servers/tf-check/.venv/bin/python")
        self.assertEqual(entry["args"], ["-I", PREFIX + "mcp-servers/tf-check/server.py"])

    def test_registered_file_exists(self):
        path = registration()["tf-check"]["args"][1].removeprefix(PREFIX)
        self.assertTrue((REPO / path).is_file(), path)

    def test_attack_only_the_agent_token_is_passed(self):
        """No fallback to the owner's gh login: outside `make agent`, the token is invalid text."""
        self.assertEqual(registration()["tf-check"]["env"], {"GH_TOKEN": "${GH_TOKEN}"})

    def test_guard_allowlist_matches_the_real_tools(self):
        expected = {f"mcp__tf-check__{name}" for name in asyncio.run(server_tools())}
        self.assertEqual(guard_tools(), expected)


if __name__ == "__main__":
    unittest.main()
