#!/usr/bin/env python3
"""Verify explicit background TUI model discovery with a loopback dummy gateway."""

import argparse
import http.server
import json
import os
import sqlite3
import subprocess
import tempfile
import threading
from pathlib import Path
from typing import ClassVar

from fixtures.terminal import Terminal


class Gateway(http.server.BaseHTTPRequestHandler):
    calls: ClassVar[list] = []
    release: ClassVar[threading.Event] = threading.Event()
    received: ClassVar[threading.Event] = threading.Event()
    status = 200

    def log_message(self, *_):
        pass

    def do_GET(self):
        type(self).calls.append((self.path, self.headers.get("Authorization")))
        type(self).received.set()
        if not type(self).release.wait(10):
            self.send_error(504)
            return
        payload = json.dumps(
            {"data": [{"id": f"fixture-model-{index:02}"} for index in range(40)]}
        ).encode()
        self.send_response(type(self).status)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def read(database):
    with sqlite3.connect(database) as db:
        return json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-picker-") as temporary:
        directory = Path(temporary).resolve()
        home = directory / "home"
        home.mkdir()
        events = directory / "empty.jsonl"
        events.write_text("")
        database = directory / "board.sqlite"
        env = {
            name: os.environ[name] for name in ("PATH", "LANG") if name in os.environ
        }
        env.update(
            HOME=str(home),
            XDG_CONFIG_HOME=str(home),
            TMPDIR=str(directory),
            LITELLM_API_KEY="dummy-picker-key",
        )
        command = [
            str(binary),
            "--no-config",
            "--database",
            str(database),
            "--events",
            str(events),
        ]
        with Terminal(command, env) as tui:
            tui.ready()
            tui.send(b"q")
            tui.wait_exit()
        saved = read(database)
        task = next(task for task in saved["tasks"] if task["state"] == "queued")
        saved.update(
            tasks=[task], selected=task["id"], drafts=[[task["id"], "Retained draft"]]
        )
        with sqlite3.connect(database) as db:
            db.execute("UPDATE snapshot SET payload=?", (json.dumps(saved),))
        marker = directory / "must-not-launch"
        executable = directory / "fake-codex"
        executable.write_text(f"#!/bin/sh\ntouch '{marker}'\nexit 2\n")
        executable.chmod(0o700)
        config = directory / "gateway.toml"
        config.write_text(
            'base_url_environment="LITELLM_BASE_URL"\nkey_environment="LITELLM_API_KEY"\n'
        )
        startup = directory / "startup.toml"
        startup.write_text((root / "test/configs/model-picker.toml").read_text())
        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Gateway) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            env["LITELLM_BASE_URL"] = f"http://127.0.0.1:{server.server_port}/v1"
            command = [str(binary), "--live-ui", "--config", str(startup)]
            try:
                with Terminal(command, env) as tui:
                    tui.ready()
                    tui.check(
                        "startup does not fetch models or start an agent",
                        Gateway.calls == [] and not marker.exists(),
                    )
                    tui.send(b"M")
                    tui.wait(
                        "background request",
                        lambda: (
                            Gateway.received.is_set() and "Loading..." in tui.text()
                        ),
                    )
                    tui.send(b"\x1b")
                    tui.wait(
                        "escape stays responsive during network request",
                        lambda: "Gateway models / next run" not in tui.text(),
                    )
                    tui.send(b"M")
                    tui.wait(
                        "pending request reused on reopen",
                        lambda: "Loading..." in tui.text(),
                    )
                    tui.check(
                        "reopen during load does not start duplicate request",
                        len(Gateway.calls) == 1,
                    )
                    Gateway.release.set()
                    tui.wait(
                        "catalogue loaded", lambda: "fixture-model-00" in tui.text()
                    )
                    tui.check(
                        "one background request uses dummy auth",
                        Gateway.calls == [("/v1/models", "Bearer dummy-picker-key")],
                    )
                    tui.send(b"\x1b[200~model-39\x1b[201~")
                    tui.wait(
                        "filter finds exact model",
                        lambda: "> fixture-model-39" in tui.text(),
                    )
                    tui.check("filter leaves task unchanged", not marker.exists())
                    if args.preview:
                        tui.preview(args.preview)
                    tui.send(b"\r")
                    tui.wait(
                        "model selection closes modal",
                        lambda: (
                            "Gateway models / next run" not in tui.text()
                            and "fixture-model-39" in tui.text()
                        ),
                    )
                    tui.check("choice starts no agent", not marker.exists())
                    tui.send(b"M")
                    tui.wait(
                        "cached models on reopen",
                        lambda: "fixture-model-00" in tui.text(),
                    )
                    tui.check(
                        "reopening does not refresh automatically",
                        len(Gateway.calls) == 1,
                    )
                    Gateway.status = 401
                    tui.send(b"\x12")
                    tui.wait(
                        "auth diagnostic",
                        lambda: "Gateway authentication failed" in tui.text(),
                    )
                    tui.check(
                        "auth error never prints dummy key",
                        "dummy-picker-key" not in tui.text(),
                    )
                    tui.send(b"\x1b")
                    tui.send(b"M")
                    tui.check(
                        "error reopen does not retry in a loop", len(Gateway.calls) == 2
                    )
                    Gateway.status = 200
                    tui.send(b"\x12")
                    tui.wait("retry recovers", lambda: "fixture-model-00" in tui.text())
                    tui.send(b"\x1b")
                    tui.send(b"W")
                    tui.wait(
                        "workspace form", lambda: "Source repository" in tui.text()
                    )
                    row = next(
                        i
                        for i, text in enumerate(tui.screen.display)
                        if "[Models / Ctrl-G]" in text
                    )
                    column = tui.screen.display[row].index("[Models / Ctrl-G]")
                    tui.send(
                        f"\x1b[<0;{column + 1};{row + 1}M\x1b[<0;{column + 1};{row + 1}m".encode()
                    )
                    tui.wait(
                        "form catalogue",
                        lambda: "Gateway models / workspace form" in tui.text(),
                    )
                    tui.send(b"\x1b[200~model-07\x1b[201~\r")
                    tui.wait(
                        "model returned to form",
                        lambda: (
                            "Model selected for this form" in tui.text()
                            and "fixture-model-07" in tui.text()
                        ),
                    )
                    tui.check(
                        "form selection starts no task or agent", not marker.exists()
                    )
                    if args.preview:
                        tui.preview(args.preview.with_stem(args.preview.stem + "-form"))
                    tui.send(b"\x1b")
                    tui.send(b"q")
                    tui.wait_exit()
                previous_calls = len(Gateway.calls)
                with Terminal(command, env) as tui:
                    tui.ready()
                    tui.send(b"W")
                    tui.wait(
                        "new launch workspace form",
                        lambda: "Source repository" in tui.text(),
                    )
                    tui.send(b"\x07")
                    tui.wait(
                        "first form picker fetch",
                        lambda: "fixture-model-00" in tui.text(),
                    )
                    tui.check(
                        "first form opening fetches once without creation",
                        len(Gateway.calls) == previous_calls + 1
                        and not marker.exists(),
                    )
                    tui.send(b"\x1b")
                    tui.send(b"\x1b")
                    tui.send(b"q")
                    tui.wait_exit()
                current = read(database)
                assert current["drafts"] == saved["drafts"]
                assert current["tasks"][0]["messages"] == saved["tasks"][0]["messages"]
                assert current["tasks"][0]["runs"] == saved["tasks"][0]["runs"]
                assert current["tasks"][0]["model"] == "fixture-model-39"
                assert not marker.exists()
                print(
                    "PASS: model picker changes only next-run selection; draft/history and startup inactivity retained"
                )
            finally:
                Gateway.release.set()
                server.shutdown()
                thread.join()
    print(
        "Loopback/dummy API key and fake executable only; no real gateway/model/credentials."
    )


if __name__ == "__main__":
    main()
