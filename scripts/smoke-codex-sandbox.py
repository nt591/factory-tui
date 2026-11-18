#!/usr/bin/env python3
"""Exercise installed Codex tool sandboxing against a fixed loopback Responses server."""

import argparse
import http.server
import json
import os
import shlex
import subprocess
import tempfile
import threading
from pathlib import Path

from fixtures.sandbox import ToolGateway


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--codex", required=True, type=Path, help="Explicit installed Codex executable"
    )
    args = parser.parse_args()
    executable = args.codex.resolve()
    if not executable.is_file() or not os.access(executable, os.X_OK):
        parser.error("Executable must exist and be executable")
    root = Path(__file__).resolve().parent.parent
    subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = root / "_build/default/bin/main.exe"
    with tempfile.TemporaryDirectory(prefix="factory-sandbox-") as temporary:
        directory = Path(temporary).resolve()
        workspace = directory / "workspace"
        outside = directory / "outside"
        isolated_home = directory / "home"
        runtime_temp = directory / "runtime-temp"
        for path in (workspace, outside, isolated_home, runtime_temp):
            path.mkdir()
        subprocess.run(["git", "init", "-q", str(workspace)], check=True)
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), ToolGateway)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            config = directory / "gateway.toml"
            config.write_text(
                f'base_url="http://127.0.0.1:{server.server_port}/v1"\nkey_environment="FACTORY_SMOKE_KEY"\n'
            )
            env = {
                key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ
            }
            env.update(
                HOME=str(isolated_home),
                FACTORY_SMOKE_KEY="dummy-local-key",
                TMPDIR=str(runtime_temp),
            )
            inspected = subprocess.run(
                [
                    str(binary),
                    "--dry-run-codex",
                    "--codex-executable",
                    str(executable),
                    "--workspace",
                    str(workspace),
                    "--model",
                    "gpt-4.1",
                    "--gateway",
                    str(config),
                ],
                check=True,
                capture_output=True,
                text=True,
                env=env,
                timeout=10,
            )
            preview = json.loads(inspected.stdout)
            version = subprocess.run(
                [str(executable), "--version"],
                check=True,
                capture_output=True,
                text=True,
                timeout=5,
            ).stdout.strip()
            for policy, escalation in (
                ("read-only", False),
                ("workspace-write", False),
                ("workspace-write", True),
            ):
                case = policy + ("-escalation" if escalation else "")
                home = directory / f"codex-{case}"
                home.mkdir()
                case_env = {**env, "CODEX_HOME": str(home)}
                inside_sentinel = workspace / f"{case}.txt"
                outside_sentinel = outside / f"{case}.txt"
                ToolGateway.command = (
                    f"printf 'inside\\n' > {shlex.quote(str(inside_sentinel))}; "
                    f"printf 'outside\\n' > {shlex.quote(str(outside_sentinel))}"
                )
                temp_sentinel = runtime_temp / f"{case}.txt"
                ToolGateway.command += (
                    f"; printf 'temporary\\n' > {shlex.quote(str(temp_sentinel))}"
                )
                ToolGateway.issued = False
                ToolGateway.outputs = []
                ToolGateway.request_escalation = escalation
                arguments = [
                    f'sandbox_mode="{policy}"'
                    if value == 'sandbox_mode="read-only"'
                    else value
                    for value in preview["arguments"]
                ]
                result = subprocess.run(
                    [str(executable), *arguments],
                    check=False,
                    cwd=workspace,
                    env=case_env,
                    input="Perform the temporary sentinel probe supplied by the fixture.",
                    capture_output=True,
                    text=True,
                    timeout=60,
                )
                if result.returncode:
                    raise RuntimeError(
                        f"Codex run failed ({result.returncode}): {result.stderr[-4000:]}\n{result.stdout[-4000:]}"
                    )
                if not ToolGateway.outputs:
                    raise RuntimeError("Fixture did not observe a shell tool response")
                if escalation and not ToolGateway.escalation_supported:
                    raise RuntimeError(
                        "Installed shell tool lacks escalation arguments; refusal was not exercised."
                    )
                tool_output = "\n".join(
                    str(item.get("output", "")) for item in ToolGateway.outputs
                ).lower()
                if escalation and (
                    "never" not in tool_output or "escalat" not in tool_output
                ):
                    raise RuntimeError(
                        "No explicit never-approval escalation refusal was observed."
                    )
                if not escalation and (
                    "process exited with code" not in tool_output
                    or not any(
                        reason in tool_output
                        for reason in ("operation not permitted", "permission denied")
                    )
                ):
                    raise RuntimeError(
                        "No executed shell probe with a permission-denied result was observed."
                    )
                expected_write = policy == "workspace-write" and not escalation
                if (
                    inside_sentinel.exists() != expected_write
                    or outside_sentinel.exists()
                    or temp_sentinel.exists() != expected_write
                ):
                    raise RuntimeError(
                        f"Sandbox boundary did not hold: {case}: inside={inside_sentinel.exists()}, sibling={outside_sentinel.exists()}, temp={temp_sentinel.exists()}"
                    )
                if expected_write and (
                    inside_sentinel.read_text() != "inside\n"
                    or temp_sentinel.read_text() != "temporary\n"
                ):
                    raise RuntimeError(
                        "Sentinel content did not match the fixed tool command."
                    )
                print(
                    f"PASS: {case}: workspace/temp writes {'allowed' if expected_write else 'denied'}; ordinary sibling write denied ({ToolGateway.tool_name})"
                )
            print(f"Installed executable: {version}")
            print(
                "No real gateway or credentials. Only temporary sentinel writes requested."
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    main()
