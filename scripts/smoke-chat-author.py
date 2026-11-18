#!/usr/bin/env python3
"""Verify long stored author labels, delivery state, and search in an isolated TUI."""

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
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-chat-author-") as temporary:
        directory = Path(temporary).resolve()
        home = directory / "home"
        home.mkdir()
        database = directory / "board.sqlite"
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
        snapshot = read(database)
        task = next(task for task in snapshot["tasks"] if task["state"] == "queued")
        author = "Stored fixture author " + "a" * 190 + "AUTHOR_END"
        task["messages"] = [
            {
                "id": "author-queued",
                "author": author,
                "text": "Queued body is complete",
                "queued": True,
            },
            {
                "id": "author-unicode",
                "author": "Unicode author é " + "b" * 130 + "UNICODE_END",
                "text": "Second body is complete",
                "queued": False,
            },
        ]
        snapshot.update(tasks=[task], selected=task["id"], drafts=[])
        with sqlite3.connect(database) as db:
            db.execute("UPDATE snapshot SET payload=?", (json.dumps(snapshot),))
        with Terminal(command, env) as tui:
            tui.ready()
            tui.send(b"e")
            tui.wait(
                "complete author labels",
                lambda: "AUTHOR_END" in tui.text() and "UNICODE_END" in tui.text(),
            )
            tui.check(
                "queued delivery suffix survives author wrapping",
                "/ queued" in tui.text() and "Queued body is complete" in tui.text(),
            )
            tui.check(
                "other body follows its complete author",
                "Second body is complete" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview)
            tui.send(b"S")
            tui.send(b"\x1b[200~AUTHOR_END\x1b[201~\r")
            tui.wait("author search", lambda: "1/1 messages" in tui.text())
            tui.check("full stored author is searchable", "AUTHOR_END" in tui.text())
            tui.send(b"n")
            tui.check(
                "match navigation leaves wrapped identity visible",
                "AUTHOR_END" in tui.text(),
            )
            tui.send(b"\x1b")
            tui.send(b"q")
            tui.wait_exit()
        final = read(database)
        assert final["tasks"][0]["messages"] == task["messages"]
        assert final["tasks"][0]["runs"] == task["runs"]
        assert final["drafts"] == [] and list(home.iterdir()) == []
        print(
            "PASS: wrapped authors, delivery labels and search preserve stored messages/runs"
        )
    print("Temporary stored messages only. No model, credentials or workspace access.")


if __name__ == "__main__":
    main()
