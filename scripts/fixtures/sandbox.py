import json
from typing import ClassVar

from .responses import Gateway


class ToolGateway(Gateway):
    command = ""
    issued = False
    outputs: ClassVar[list[dict]] = []
    tool_specs: ClassVar[list[dict]] = []
    tool_name = None
    request_escalation = False
    escalation_supported = False

    def response_events(self, request):
        cls = type(self)
        cls.tool_specs = request.get("tools", [])
        for item in request.get("input", []):
            if isinstance(item, dict) and item.get("type") == "function_call_output":
                cls.outputs.append(item)
        if cls.issued:
            return super().response_events(request)
        cls.issued = True
        # Fixture commands use only temporary sentinel paths supplied by this script.
        functions = [tool for tool in cls.tool_specs if tool.get("type") == "function"]
        tool = next(
            (
                tool
                for tool in functions
                if tool.get("name") in ("exec_command", "shell_command", "shell")
            ),
            None,
        )
        if tool is None:
            raise RuntimeError("Installed Codex did not offer a supported shell tool.")
        name = tool["name"]
        cls.tool_name = name
        properties = tool.get("parameters", {}).get("properties", {})
        if name == "exec_command":
            arguments = {
                "cmd": cls.command,
                "yield_time_ms": 1000,
                "max_output_tokens": 1000,
            }
        elif name == "shell_command":
            arguments = {"command": cls.command, "timeout_ms": 10000}
        else:
            arguments = {"command": ["/bin/sh", "-c", cls.command], "timeout_ms": 10000}
        cls.escalation_supported = "sandbox_permissions" in properties
        if cls.request_escalation:
            arguments["sandbox_permissions"] = "require_escalated"
            arguments["justification"] = (
                "Temporary sentinel probe; never-approval policy must refuse escalation."
            )
        arguments = {
            key: value for key, value in arguments.items() if key in properties
        }
        item = {
            "id": "fc_sandbox",
            "type": "function_call",
            "name": name,
            "call_id": "call_sandbox",
            "arguments": json.dumps(arguments),
            "status": "completed",
        }
        response = {
            "id": "resp_sandbox",
            "object": "response",
            "created_at": 0,
            "status": "completed",
            "model": "gpt-4.1",
            "output": [item],
            "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15},
        }
        return [
            {
                "type": "response.created",
                "response": {**response, "status": "in_progress", "output": []},
            },
            {
                "type": "response.output_item.added",
                "output_index": 0,
                "item": {**item, "status": "in_progress", "arguments": ""},
            },
            {
                "type": "response.function_call_arguments.delta",
                "item_id": item["id"],
                "output_index": 0,
                "delta": item["arguments"],
            },
            {
                "type": "response.function_call_arguments.done",
                "item_id": item["id"],
                "output_index": 0,
                "arguments": item["arguments"],
            },
            {"type": "response.output_item.done", "output_index": 0, "item": item},
            {"type": "response.completed", "response": response},
        ]
