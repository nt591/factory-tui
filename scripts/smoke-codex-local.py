#!/usr/bin/env python3
"""Verify the installed Codex connector against a loopback Responses fixture."""

import http.server
import json
import os
import sqlite3
import subprocess
import tempfile
import threading
from pathlib import Path

from fixtures.responses import TEXT, Gateway


def main():
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--codex",
        type=Path,
        required=True,
        help="Installed Codex executable; explicit opt-in",
    )
    args = parser.parse_args()
    executable = args.codex.resolve()
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise SystemExit("Codex executable must exist and be executable")
    root = Path(__file__).resolve().parent.parent
    subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = root / "_build/default/bin/main.exe"
    version = subprocess.run(
        [str(executable), "--version"], capture_output=True, text=True, check=True
    ).stdout.strip()
    with tempfile.TemporaryDirectory(prefix="factory-tui-codex-loopback-") as temporary:
        directory = Path(temporary).resolve()
        workspace = directory / "workspace"
        home = directory / "codex-home"
        isolated_home = directory / "home"
        for path in (workspace, home, isolated_home):
            path.mkdir()
        subprocess.run(["git", "init", "-q", str(workspace)], check=True)
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Gateway)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            config = directory / "gateway.toml"
            config.write_text(
                f'base_url = "http://127.0.0.1:{server.server_port}/v1"\nkey_environment = "FACTORY_SMOKE_KEY"\n'
            )
            env = {
                key: os.environ[key]
                for key in ("PATH", "TMPDIR", "LANG")
                if key in os.environ
            }
            env.update(
                HOME=str(isolated_home),
                CODEX_HOME=str(home),
                FACTORY_SMOKE_KEY="dummy-local-key",
            )
            database = directory / "sessions.sqlite"
            command = [
                str(binary),
                "--run-codex",
                "--codex-executable",
                str(executable),
                "--workspace",
                str(workspace),
                "--model",
                "gpt-4.1",
                "--database",
                str(database),
                "--gateway",
                str(config),
            ]
            result = subprocess.run(
                command,
                check=False,
                input="Reply with the smoke result. Do not call tools.",
                text=True,
                capture_output=True,
                env=env,
                timeout=60,
            )
            if result.returncode:
                raise RuntimeError(
                    f"Connector failed ({result.returncode}): {result.stdout}\n{result.stderr}"
                )
            summary = json.loads(result.stdout)
            with sqlite3.connect(database) as db:
                snapshot = json.loads(
                    db.execute("SELECT payload FROM snapshot").fetchone()[0]
                )
            task = snapshot["tasks"][0]
            assert summary["succeeded"] and task["state"] == "ready"
            assert any(message["text"] == TEXT for message in task["messages"])
            assert task["thread"] and not task["runs"][0]["simulated"]
            assert Gateway.requests > 0
            previous_requests = Gateway.requests
            resumed = subprocess.run(
                command + ["--resume", task["thread"]],
                check=False,
                input="Continue the same conversation. Do not call tools.",
                text=True,
                capture_output=True,
                env=env,
                timeout=60,
            )
            if resumed.returncode:
                raise RuntimeError(
                    f"Resume failed ({resumed.returncode}): {resumed.stdout}\n{resumed.stderr}"
                )
            resumed_summary = json.loads(resumed.stdout)
            assert resumed_summary["task_id"] == summary["task_id"]
            assert resumed_summary["thread_id"] == task["thread"]
            with sqlite3.connect(database) as db:
                snapshot = json.loads(
                    db.execute("SELECT payload FROM snapshot").fetchone()[0]
                )
                events = [
                    json.loads(row[0])
                    for row in db.execute(
                        "SELECT payload FROM events ORDER BY sequence"
                    )
                ]
            task = snapshot["tasks"][0]
            assert len(task["runs"]) == 2 and task["state"] == "ready"
            assert sum(m["text"] == TEXT for m in task["messages"]) == 2
            assert all(
                not m["queued"] for m in task["messages"] if m["author"] == "You"
            )
            assert sum(e["type"] == "turn.completed" for e in events) == 2
            assert Gateway.requests > previous_requests
            print(
                f"PASS: {version} → loopback fixture → OCaml reducer → SQLite Ready → same-thread resume"
            )
            print(
                "No real gateway credentials or model calls. Platform command sandboxing is not exercised."
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    main()
