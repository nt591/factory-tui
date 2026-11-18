#!/usr/bin/env python3
"""Exercise folder-rooted multi-repo work with a fake runner and temporary data."""

import argparse
import json
import os
import sqlite3
import subprocess
import tempfile
from pathlib import Path

from fixtures.terminal import Terminal


def read(database):
    with sqlite3.connect(database) as db:
        return json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(repo / "scripts/build.sh")], check=True)
    binary = (args.binary or repo / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-folder-root-") as temporary:
        directory = Path(temporary).resolve()
        root = directory / "session"
        root.mkdir()
        for service in ("api", "worker"):
            (root / service).mkdir()
            (root / service / "README.md").write_text(f"Fixture {service}\n")
        home = directory / "home"
        home.mkdir()
        marker = directory / "invocations.jsonl"
        executable = directory / "fake-codex"
        executable.write_text(
            "#!/usr/bin/env python3\n"
            + f"""
import pathlib, json, sys
cwd = pathlib.Path.cwd()
prompt = sys.stdin.read()
with pathlib.Path({str(marker)!r}).open('a') as output:
    output.write(json.dumps({{'cwd': str(cwd), 'prompt': prompt, 'arguments': sys.argv[1:]}}) + '\\n')
(cwd / 'api' / 'change.txt').write_text('API fixture change\\n')
(cwd / 'worker' / 'change.txt').write_text('Worker fixture change\\n')
(cwd / 'new-service').mkdir(exist_ok=True)
(cwd / 'new-service' / 'README.md').write_text('Greenfield fixture\\n')
for event in [
    {{'type': 'thread.started', 'thread_id': 'folder-thread'}},
    {{'type': 'turn.started'}},
    {{'type': 'item.completed', 'item': {{'type': 'agent_message', 'id': 'answer', 'text': 'Updated both services and created a new service in the session root'}}}},
    {{'type': 'turn.completed'}},
]:
    print(json.dumps(event), flush=True)
"""
        )
        executable.chmod(0o700)
        config = directory / "config.toml"
        config.write_text(
            '[storage]\ndatabase="board.sqlite"\n[codex]\nexecutable="fake-codex"\n[workspace]\nsource='
            + json.dumps(str(root))
            + '\nmodel="fixture-model"\nmode="folder"\n'
        )
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home), TMPDIR=str(directory))
        command = [
            str(binary),
            "--live-ui",
            "--workspace-write",
            "--config",
            str(config),
        ]
        with Terminal(command, env, columns=180, rows=50) as tui:
            tui.ready()
            tui.send(b"n")
            tui.wait("folder root mode", lambda: "FOLDER ROOT" in tui.text())
            tui.send(b"\t" * 4 + b"Work across these services and create a new one\x13")
            tui.wait("session created", lambda: "Workspace task created" in tui.text())
            tui.check(
                "session root needs no jj initialization",
                not (root / ".jj").exists() and not marker.exists(),
            )
            tui.send(b"s")
            tui.wait(
                "root disclosure",
                lambda: (
                    "Session root:" in tui.text()
                    and "no isolated checkout" in tui.text()
                ),
            )
            tui.send(b"\x1b[6~" * 20 + b"y")
            tui.wait(
                "folder run completes", lambda: "/ Ready / conversation" in tui.text()
            )
            tui.send(b"e")
            tui.wait(
                "multi-service answer", lambda: "Updated both services" in tui.text()
            )
            calls = [json.loads(line) for line in marker.read_text().splitlines()]
            tui.check(
                "runner receives root and exact goal",
                len(calls) == 1
                and calls[0]["cwd"] == str(root)
                and calls[0]["prompt"]
                == "Work across these services and create a new one",
            )
            tui.check(
                "runner can organize multiple folders under root",
                (root / "api/change.txt").exists()
                and (root / "worker/change.txt").exists()
                and (root / "new-service/README.md").exists(),
            )
            tui.send(b"v")
            tui.check(
                "root does not claim single-repo diff support",
                "Folder-rooted session:" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview)
            tui.send(b"q")
            tui.wait_exit()
        saved = read(directory / "board.sqlite")
        task = saved["tasks"][0]
        assert task["session_root"] == str(root) and task["workspace"] is None
        assert task["state"] == "ready" and task["runs"][0]["simulated"] is False
        with Terminal(command, env, columns=180, rows=50) as tui:
            tui.ready()
            tui.check(
                "restart keeps root without executing",
                len(marker.read_text().splitlines()) == 1,
            )
            tui.send(b"q")
            tui.wait_exit()
        assert read(directory / "board.sqlite") == saved
        assert not (root / ".git").exists() and not (root / ".jj").exists()
    print(
        "PASS: folder session persists and runs fake multi-folder/greenfield work; no real repositories or models."
    )


if __name__ == "__main__":
    main()
