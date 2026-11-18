#!/usr/bin/env python3
"""Verify visible rejected reply edits and exact saved text at the byte limit."""

import argparse
import json
import os
import sqlite3
import subprocess
import tempfile
from pathlib import Path

from fixtures.terminal import Terminal


def snapshot(database):
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
    with tempfile.TemporaryDirectory(prefix="factory-input-limit-") as temporary:
        directory = Path(temporary).resolve()
        database = directory / "board.sqlite"
        home = directory / "home"
        home.mkdir()
        replay = directory / "empty.jsonl"
        replay.write_text("")
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home), TMPDIR=str(directory))
        command = [
            str(binary),
            "--no-config",
            "--database",
            str(database),
            "--events",
            str(replay),
        ]
        with Terminal(command, env) as tui:
            tui.ready()
            tui.send(b"q")
            tui.wait_exit()
        saved = snapshot(database)
        task = next(task for task in saved["tasks"] if task["state"] == "queued")
        task_id = task["id"]
        full = "a" * (65536 - len("LIMIT_END")) + "LIMIT_END"
        saved.update(tasks=[task], selected=task_id, drafts=[[task_id, full]])
        with sqlite3.connect(database) as db:
            db.execute("UPDATE snapshot SET payload=?", (json.dumps(saved),))
        with Terminal(command, env) as tui:
            tui.ready()
            tui.send(b"ei")
            tui.wait("full retained draft", lambda: "LIMIT_END▏" in tui.text())
            tui.send(b"\x1b[200~REJECTED\x1b[201~")
            tui.wait(
                "visible limit rejection",
                lambda: "Edit not applied / limit 64 KiB" in tui.text(),
            )
            tui.check(
                "rejected paste leaves cursor and draft tail intact",
                "LIMIT_END▏" in tui.text() and "REJECTED" not in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview)
            tui.send(b"\x1b[D")
            tui.check(
                "cursor movement retains rejection warning",
                "Edit not applied / limit 64 KiB" in tui.text(),
            )
            tui.send(b"\x1b[F\x7f")
            tui.wait(
                "delete creates room",
                lambda: (
                    "LIMIT_EN▏" in tui.text() and "Edit not applied" not in tui.text()
                ),
            )
            tui.send(b"\x1b[200~Z\x1b[201~")
            tui.wait("valid edit accepted", lambda: "LIMIT_ENZ▏" in tui.text())
            tui.send(b"\x1b")
            tui.send(b"q")
            tui.wait_exit()
        final = snapshot(database)
        assert dict(final["drafts"])[task_id] == full[:-1] + "Z"
        assert final["tasks"] == [task]
        assert list(home.iterdir()) == []
        print(
            "PASS: rejected paste and recovery preserve exact full draft without submission"
        )
    print("Temporary SQLite/replay only. No model, credentials or workspace access.")


if __name__ == "__main__":
    main()
