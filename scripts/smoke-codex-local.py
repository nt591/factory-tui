#!/usr/bin/env python3
"""Verify the installed Codex connector against a loopback Responses fixture."""
import http.server
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import threading

TEXT = "Factory TUI loopback smoke passed."


class Gateway(http.server.BaseHTTPRequestHandler):
    requests = 0

    def log_message(self, *_):
        pass

    def do_POST(self):
        if self.path != "/v1/responses":
            self.send_error(404)
            return
        if self.headers.get("Authorization") != "Bearer dummy-local-key":
            self.send_error(401)
            return
        length = int(self.headers.get("Content-Length", "0"))
        if length < 1 or length > 1048576:
            self.send_error(413)
            return
        body = self.rfile.read(length)
        json.loads(body)
        type(self).requests += 1
        item = {"id": "msg_smoke", "type": "message", "status": "completed",
                "role": "assistant", "content": [{"type": "output_text", "text": TEXT, "annotations": []}]}
        response = {"id": "resp_smoke", "object": "response", "created_at": 0,
                    "status": "completed", "model": "gpt-4.1", "output": [item],
                    "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15,
                              "input_tokens_details": {"cached_tokens": 0},
                              "output_tokens_details": {"reasoning_tokens": 0}}}
        events = [
            {"type": "response.created", "response": {**response, "status": "in_progress", "output": []}},
            {"type": "response.output_item.added", "output_index": 0,
             "item": {**item, "status": "in_progress", "content": []}},
            {"type": "response.content_part.added", "item_id": item["id"], "output_index": 0,
             "content_index": 0, "part": {"type": "output_text", "text": "", "annotations": []}},
            {"type": "response.output_text.delta", "item_id": item["id"], "output_index": 0,
             "content_index": 0, "delta": TEXT},
            {"type": "response.output_item.done", "output_index": 0, "item": item},
            {"type": "response.completed", "response": response},
        ]
        data = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n" for event in events).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--codex", type=Path, required=True, help="Installed Codex executable; explicit opt-in")
    args = parser.parse_args()
    executable = args.codex.resolve()
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise SystemExit("Codex executable must exist and be executable")
    root = Path(__file__).resolve().parent.parent
    subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = root / "_build/default/bin/main.exe"
    version = subprocess.run([str(executable), "--version"], capture_output=True, text=True, check=True).stdout.strip()
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
            config.write_text(f'base_url = "http://127.0.0.1:{server.server_port}/v1"\nkey_environment = "FACTORY_SMOKE_KEY"\n')
            env = {key: os.environ[key] for key in ("PATH", "TMPDIR", "LANG") if key in os.environ}
            env.update(HOME=str(isolated_home), CODEX_HOME=str(home), FACTORY_SMOKE_KEY="dummy-local-key")
            database = directory / "sessions.sqlite"
            command = [str(binary), "--run-codex", "--codex-executable", str(executable),
                       "--workspace", str(workspace), "--model", "gpt-4.1",
                       "--database", str(database), "--gateway", str(config)]
            result = subprocess.run(command, input="Reply with the smoke result. Do not call tools.",
                                    text=True, capture_output=True, env=env, timeout=60)
            if result.returncode:
                raise RuntimeError(f"Connector failed ({result.returncode}): {result.stdout}\n{result.stderr}")
            summary = json.loads(result.stdout)
            with sqlite3.connect(database) as db:
                snapshot = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
            task = snapshot["tasks"][0]
            assert summary["succeeded"] and task["state"] == "ready"
            assert any(message["text"] == TEXT for message in task["messages"])
            assert task["thread"] and not task["runs"][0]["simulated"]
            assert Gateway.requests > 0
            previous_requests = Gateway.requests
            resumed = subprocess.run(command + ["--resume", task["thread"]],
                input="Continue the same conversation. Do not call tools.", text=True,
                capture_output=True, env=env, timeout=60)
            if resumed.returncode:
                raise RuntimeError(f"Resume failed ({resumed.returncode}): {resumed.stdout}\n{resumed.stderr}")
            resumed_summary = json.loads(resumed.stdout)
            assert resumed_summary["task_id"] == summary["task_id"]
            assert resumed_summary["thread_id"] == task["thread"]
            with sqlite3.connect(database) as db:
                snapshot = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
                events = [json.loads(row[0]) for row in db.execute("SELECT payload FROM events ORDER BY sequence")]
            task = snapshot["tasks"][0]
            assert len(task["runs"]) == 2 and task["state"] == "ready"
            assert sum(m["text"] == TEXT for m in task["messages"]) == 2
            assert all(not m["queued"] for m in task["messages"] if m["author"] == "You")
            assert sum(e["type"] == "turn.completed" for e in events) == 2
            assert Gateway.requests > previous_requests
            print(f"PASS: {version} → loopback fixture → OCaml reducer → SQLite Ready → same-thread resume")
            print("No real gateway credentials or model calls. Platform command sandboxing is not exercised.")
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    main()
