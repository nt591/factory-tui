#!/usr/bin/env python3
"""Opt in to installed Codex through a real TUI and a fixed loopback tool fixture."""

import argparse
import http.server
import json
import os
import shlex
import shutil
import sqlite3
import subprocess
import tempfile
import threading
from pathlib import Path

from fixtures.responses import TEXT
from fixtures.sandbox import ToolGateway
from fixtures.terminal import Terminal


class UiGateway(ToolGateway):
    release = threading.Event()
    received = threading.Event()

    def response_events(self, request):
        type(self).received.set()
        # Hold the response until the test observes the durable Working state.
        if not type(self).release.wait(15):
            raise RuntimeError("The test did not release the loopback response.")
        return super().response_events(request)


def snapshot(database):
    with sqlite3.connect(database, timeout=1) as db:
        row = db.execute("SELECT payload FROM snapshot").fetchone()
        return json.loads(row[0])


def commit(jj, directory, env, revision="@"):
    return subprocess.check_output(
        [
            str(jj),
            "--ignore-working-copy",
            "-R",
            str(directory),
            "log",
            "-r",
            revision,
            "--no-graph",
            "-T",
            "commit_id",
        ],
        env=env,
        text=True,
        timeout=10,
    ).strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--codex", type=Path, required=True, help="Explicit installed agent"
    )
    parser.add_argument("--jj", type=Path, default=shutil.which("jj"))
    parser.add_argument(
        "--preview", type=Path, help="PNG prefix; requires Pillow on macOS"
    )
    args = parser.parse_args()
    for name in ("codex", "jj"):
        value = getattr(args, name)
        if value is None or not value.is_absolute():
            parser.error(f"--{name} must be an absolute executable path")
        value = value.resolve()
        if not value.is_file() or not os.access(value, os.X_OK):
            parser.error(f"--{name} must exist and be executable")
        setattr(args, name, value)
    root = Path(__file__).resolve().parent.parent
    subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    version = subprocess.check_output([str(args.codex), "--version"], text=True).strip()
    with tempfile.TemporaryDirectory(prefix="factory-codex-ui-") as temporary:
        directory = Path(temporary).resolve()
        source = directory / "source"
        parent = directory / "workspaces"
        home = directory / "home"
        codex_home = directory / "codex-home"
        runtime_temp = directory / "runtime-temp"
        for path in (source, parent, home, codex_home, runtime_temp):
            path.mkdir()
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(
            HOME=str(home),
            CODEX_HOME=str(codex_home),
            TMPDIR=str(runtime_temp),
            FACTORY_SMOKE_KEY="dummy-local-key",
        )
        subprocess.run(
            [str(args.jj), "git", "init", "--colocate", str(source)],
            check=True,
            capture_output=True,
            env=env,
        )
        source_commit = commit(args.jj, source, env)
        database = directory / "board.sqlite"
        config = directory / "config.toml"
        config.write_text(
            '[storage]\ndatabase="board.sqlite"\n[workspace]\n'
            f"jj={json.dumps(str(args.jj))}\n"
            'source="source"\nparent="workspaces"\nrevision="@"\nmodel="gpt-4.1"\n'
        )
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), UiGateway)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        gateway = directory / "gateway.toml"
        gateway.write_text(
            f'base_url="http://127.0.0.1:{server.server_port}/v1"\n'
            'key_environment="FACTORY_SMOKE_KEY"\n'
        )
        command = [
            str(root / "_build/default/bin/main.exe"),
            "--live-ui",
            "--workspace-write",
            "--codex-executable",
            str(args.codex),
            "--config",
            str(config),
            "--gateway",
            str(gateway),
        ]
        try:
            with Terminal(command, env) as tui:
                tui.ready()
                tui.check(
                    "empty live startup makes no agent request or workspace",
                    "Your factory starts here" in tui.text()
                    and snapshot(database)["tasks"] == []
                    and not list(parent.iterdir())
                    and UiGateway.requests == 0,
                )
                tui.send(b"n")
                tui.wait("workspace form", lambda: "NEW WORKSPACE TASK" in tui.text())
                tui.send(b"\t" * 4)
                tui.send(b"Create the local smoke sentinel")
                tui.send(b"\x13")
                tui.wait(
                    "workspace creation", lambda: "Workspace task created" in tui.text()
                )
                tui.wait(
                    "queued checkpoint", lambda: len(snapshot(database)["tasks"]) == 1
                )
                task = snapshot(database)["tasks"][0]
                workspace = Path(task["workspace"]["directory"])
                sentinel = workspace / "ui-smoke.txt"
                UiGateway.command = f"printf 'TUI tool wrote this file\\n' > {shlex.quote(str(sentinel))}"
                tui.check(
                    "setup records a real queued task without starting Codex",
                    task["state"] == "queued"
                    and task["runs"] == []
                    and workspace.parent == parent
                    and UiGateway.requests == 0,
                )
                tui.check(
                    "live reply composer does not advertise unsupported harness cycling",
                    "m model / live Codex only" in tui.text()
                    and "H harness" not in tui.text(),
                )
                tui.send(b"?")
                tui.wait(
                    "live help",
                    lambda: "Live execution supports Codex only" in tui.text(),
                )
                tui.check(
                    "live help omits unsupported harness cycling",
                    "H cycles" not in tui.text(),
                )
                tui.send(b"\tG")
                tui.wait(
                    "live settings",
                    lambda: "m edits model / live Codex only" in tui.text(),
                )
                tui.check(
                    "live settings discloses supported selection without starting Codex",
                    "H changes harness" not in tui.text() and UiGateway.requests == 0,
                )
                if args.preview:
                    tui.preview(args.preview.with_stem(args.preview.stem + "-settings"))
                tui.send(b"H")
                tui.check(
                    "live Settings H keeps a runnable Codex task",
                    UiGateway.requests == 0,
                )
                tui.send(b"\x1b")
                tui.send(b"H")
                tui.wait(
                    "live harness boundary", lambda: "supports Codex only" in tui.text()
                )
                tui.send(b"s")
                tui.wait("run confirmation", lambda: "Confirm live run" in tui.text())
                tui.check(
                    "write confirmation discloses temp access and starts nothing",
                    "workspace + temp directories" in tui.text()
                    and "no approvals" in tui.text()
                    and UiGateway.requests == 0,
                )
                disclosure = "".join(
                    row[17:103].strip()
                    for row in tui.screen.display
                    if row[16:17] == "│" and row[103:104] == "│"
                )
                tui.check(
                    "confirmation shows the complete workspace and selected model",
                    str(workspace) in disclosure and "Model: gpt-4.1" in disclosure,
                )
                tui.send(b"y")
                tui.wait(
                    "Working card and checkpoint",
                    lambda: (
                        "/ Working / conversation" in tui.text()
                        and snapshot(database)["tasks"][0]["state"] == "working"
                    ),
                )
                tui.wait("loopback request", UiGateway.received.is_set, timeout=30)
                tui.check("confirmed run automatically moves the card to Working", True)
                tui.send(b"i")
                tui.check(
                    "active live composer explicitly queues replies",
                    "Enter queues" in tui.text(),
                )
                tui.send(b"\x1b")
                UiGateway.release.set()
                tui.wait(
                    "installed Codex completion",
                    lambda: (
                        snapshot(database)["tasks"][0]["state"] == "ready"
                        and "/ Ready / conversation" in tui.text()
                    ),
                    timeout=60,
                )
                task = snapshot(database)["tasks"][0]
                thread_id = task["thread"]
                tui.check(
                    "installed Codex writes the task file and streams its answer",
                    sentinel.read_text() == "TUI tool wrote this file\n"
                    and UiGateway.outputs
                    and any(m["text"] == TEXT for m in task["messages"])
                    and thread_id
                    and not task["runs"][0]["simulated"]
                    and task["runs"][0]["policy"] == "workspace-write",
                )
                tui.check(
                    "completion footer offers review and acceptance, not a stale checkpoint",
                    "Run complete." in tui.text()
                    and "a accepts without merging" in tui.text()
                    and "Waiting for the durable checkpoint" not in tui.text(),
                )
                tui.send(b"e")
                tui.check(
                    "task zoom retains the completed conversation", TEXT in tui.text()
                )
                if args.preview:
                    tui.preview(args.preview.with_stem(args.preview.stem + "-chat"))
                tui.send(b"v")
                tui.send(b"r")
                tui.wait(
                    "real jj review",
                    lambda: (
                        "ui-smoke.txt" in tui.text()
                        and "TUI tool wrote this file" in tui.text()
                    ),
                )
                tui.check("review shows the actual workspace patch", True)
                if args.preview:
                    tui.preview(args.preview.with_stem(args.preview.stem + "-review"))
                tui.send(b"\x1b")
                previous_requests = UiGateway.requests
                tui.send(b"i")
                tui.send(b"Continue this same local conversation")
                tui.send(b"\r")
                tui.send(b"s")
                tui.wait(
                    "resume confirmation", lambda: "Confirm live run" in tui.text()
                )
                tui.check(
                    "queued reply does not automatically resume",
                    UiGateway.requests == previous_requests,
                )
                tui.send(b"y")
                tui.wait(
                    "same-thread completion",
                    lambda: (
                        len(snapshot(database)["tasks"][0]["runs"]) == 2
                        and snapshot(database)["tasks"][0]["state"] == "ready"
                        and "/ Ready / conversation" in tui.text()
                    ),
                    timeout=60,
                )
                task = snapshot(database)["tasks"][0]
                tui.check(
                    "confirmed reply resumes the saved thread and acknowledges the queue",
                    task["thread"] == thread_id
                    and sum(m["text"] == TEXT for m in task["messages"]) == 2
                    and all(not m["queued"] for m in task["messages"])
                    and UiGateway.requests > previous_requests,
                )
                tui.send(b"\x17le")
                tui.wait(
                    "expanded run history",
                    lambda: "RUN HISTORY / newest first" in tui.text(),
                )
                displayed_runs = [
                    row.strip() for row in tui.screen.display if "run live-run-" in row
                ]
                tui.check(
                    "latest installed-agent attempt is first in Activity",
                    len(displayed_runs) == 2
                    and task["runs"][-1]["id"] in displayed_runs[0]
                    and task["runs"][0]["id"] in displayed_runs[1],
                )
                tui.send(b"t")
                tui.wait("expanded tool origin", lambda: "Source run:" in tui.text())
                tui.check(
                    "recorded tool activity identifies its original live attempt",
                    "Source run: "
                    + task["runs"][0]["id"]
                    + " / Codex / gpt-4.1 / live / workspace-write"
                    in tui.text(),
                )
                if args.preview:
                    tui.preview(args.preview.with_stem(args.preview.stem + "-history"))
                tui.send(b"\x1b")
                tui.send(b"a")
                tui.send(b"d")
                tui.wait(
                    "accepted archive", lambda: "/ Done / conversation" in tui.text()
                )
                tui.check(
                    "accepted chat and workspace remain readable",
                    TEXT in tui.text()
                    and sentinel.exists()
                    and "Task accepted. Chat is read-only." in tui.text(),
                )
                if args.preview:
                    tui.preview(args.preview)
                tui.send(b"q")
                tui.wait_exit()
                tui.check("live TUI shuts down cleanly", tui.process.returncode == 0)
            requests = UiGateway.requests
            with Terminal(command, env) as tui:
                tui.ready()
                tui.send(b"d")
                tui.send(b"e")
                tui.check(
                    "restart retains accepted chat without a new run",
                    "/ Done / conversation" in tui.text()
                    and TEXT in tui.text()
                    and UiGateway.requests == requests,
                )
                tui.send(b"q")
                tui.wait_exit()
                tui.check(
                    "reopened TUI shuts down cleanly", tui.process.returncode == 0
                )
            task = snapshot(database)["tasks"][0]
            tui.check(
                "acceptance preserves workspace and does not change source files",
                task["state"] == "done"
                and len(task["runs"]) == 2
                and sentinel.exists()
                and not (source / sentinel.name).exists()
                and commit(args.jj, source, env) == source_commit
                and commit(args.jj, workspace, env, "@-") == task["workspace"]["base"],
            )
            print(
                f"PASS: {version} → confirmed TUI → file + chat → review → resume → archive/restart"
            )
            print(
                "Fixed loopback responses and dummy credentials only; no real provider or security-audit claim."
            )
        finally:
            UiGateway.release.set()
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    main()
