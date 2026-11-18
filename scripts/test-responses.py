#!/usr/bin/env python3
"""Test local Responses fixtures without a server, subprocess, credentials, or files."""

import json
import unittest

from fixtures.responses import TEXT, Gateway
from fixtures.sandbox import ToolGateway


class FixtureTests(unittest.TestCase):
    def setUp(self):
        ToolGateway.command = "printf fixture"
        ToolGateway.issued = False
        ToolGateway.outputs = []
        ToolGateway.request_escalation = False
        ToolGateway.escalation_supported = False
        self.handler = object.__new__(ToolGateway)

    def request(self, name="exec_command", properties=None):
        if properties is None:
            properties = {"cmd": {}, "yield_time_ms": {}, "max_output_tokens": {}}
        return {
            "tools": [
                {
                    "type": "function",
                    "name": name,
                    "parameters": {"properties": properties},
                }
            ],
            "input": [],
        }

    def final_item(self, events):
        self.assertEqual(events[-1]["type"], "response.completed")
        return events[-1]["response"]["output"][0]

    def test_fixed_answer(self):
        events = object.__new__(Gateway).response_events({})
        item = self.final_item(events)
        self.assertEqual(item["content"][0]["text"], TEXT)
        self.assertFalse(
            any(event["type"].startswith("response.function_call") for event in events)
        )

    def test_exec_arguments_come_from_fixed_command(self):
        events = self.handler.response_events(self.request())
        item = self.final_item(events)
        self.assertEqual(item["name"], "exec_command")
        self.assertEqual(
            json.loads(item["arguments"]),
            {"cmd": "printf fixture", "yield_time_ms": 1000, "max_output_tokens": 1000},
        )
        deltas = [
            event["delta"]
            for event in events
            if event["type"] == "response.function_call_arguments.delta"
        ]
        self.assertEqual("".join(deltas), item["arguments"])

    def test_second_request_collects_result_not_another_tool(self):
        self.handler.response_events(self.request())
        request = self.request()
        request["input"] = [
            {
                "type": "function_call_output",
                "call_id": "call_sandbox",
                "output": "done",
            }
        ]
        item = self.final_item(self.handler.response_events(request))
        self.assertEqual(item["type"], "message")
        self.assertEqual(ToolGateway.outputs, request["input"])

    def test_escalation_sent_only_when_advertised(self):
        ToolGateway.request_escalation = True
        item = self.final_item(
            self.handler.response_events(
                self.request(
                    properties={
                        "cmd": {},
                        "sandbox_permissions": {},
                        "justification": {},
                    }
                )
            )
        )
        arguments = json.loads(item["arguments"])
        self.assertTrue(ToolGateway.escalation_supported)
        self.assertEqual(arguments["sandbox_permissions"], "require_escalated")
        self.assertNotIn("yield_time_ms", arguments)

    def test_unsupported_escalation_cannot_be_claimed_exercised(self):
        ToolGateway.request_escalation = True
        item = self.final_item(self.handler.response_events(self.request()))
        self.assertFalse(ToolGateway.escalation_supported)
        self.assertNotIn("sandbox_permissions", json.loads(item["arguments"]))

    def test_unsupported_shell_tool_fails(self):
        with self.assertRaisesRegex(RuntimeError, "supported shell tool"):
            self.handler.response_events(self.request(name="unsupported"))

    def test_shell_command_shape(self):
        item = self.final_item(
            self.handler.response_events(
                self.request(
                    name="shell_command", properties={"command": {}, "timeout_ms": {}}
                )
            )
        )
        self.assertEqual(
            json.loads(item["arguments"]),
            {"command": "printf fixture", "timeout_ms": 10000},
        )

    def test_shell_array_shape(self):
        item = self.final_item(
            self.handler.response_events(
                self.request(name="shell", properties={"command": {}})
            )
        )
        self.assertEqual(
            json.loads(item["arguments"]),
            {"command": ["/bin/sh", "-c", "printf fixture"]},
        )


if __name__ == "__main__":
    unittest.main()
