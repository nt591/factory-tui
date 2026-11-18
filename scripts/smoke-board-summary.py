#!/usr/bin/env python3
"""Verify bounded filtered board headers and their actual mouse controls."""

import argparse
import fcntl
import json
import os
import signal
import sqlite3
import struct
import subprocess
import tempfile
import termios
from pathlib import Path

from fixtures.terminal import Terminal


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-board-summary-") as temporary:
        directory = Path(temporary).resolve()
        database = directory / "board.sqlite"
        replay = directory / "empty.jsonl"
        replay.write_text("")
        home = directory / "home"
        home.mkdir()
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
        repository = "/fixture/" + "long-component/" * 20 + "project"
        query = "Filtered instruction " * 8 + "QUERY_END"
        with sqlite3.connect(database) as db:
            saved = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
            task = next(task for task in saved["tasks"] if task["state"] == "queued")
            task.update(repository=repository, title=query)
            task["messages"][0]["text"] = query
            saved.update(tasks=[task], selected=task["id"], drafts=[])
            db.execute("UPDATE snapshot SET payload=?", (json.dumps(saved),))
        with Terminal(command, env, columns=180, rows=50) as tui:
            tui.ready()
            tui.send(b"R")
            tui.wait(
                "long repository filter", lambda: "project" in tui.screen.display[2]
            )
            tui.check(
                "repository summary keeps task count visible",
                "1 tasks" in tui.screen.display[2],
            )
            tui.send(b"/")
            tui.send(b"\x1b[200~" + query.encode() + b"\x1b[201~\r")
            tui.wait(
                "long query",
                lambda: (
                    "1 tasks" in tui.screen.display[2]
                    and "Filtered" in tui.screen.display[2]
                    and "Search:" not in tui.screen.display[-3]
                ),
            )
            fcntl.ioctl(
                tui.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 23, 60, 0, 0)
            )
            tui.screen.resize(lines=23, columns=60)
            os.kill(tui.process.pid, signal.SIGWINCH)
            tui.wait(
                "compact summary",
                lambda: (
                    "project" in tui.screen.display[2]
                    and "1 tasks" in tui.screen.display[2]
                    and "Search:" not in tui.screen.display[-3]
                ),
            )
            tui.check(
                "long query cannot hide compact task count",
                "1 tasks" in tui.screen.display[2] and "/ " in tui.screen.display[2],
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-filtered"))
            search_x = tui.screen.display[2].index("/ ")
            tui.send(f"\x1b[<0;{search_x + 1};3M".encode())
            tui.wait("mouse edits visible search", lambda: "Search:" in tui.text())
            tui.send(b"\x1b[F")
            tui.wait("full query retained", lambda: "QUERY_END" in tui.text())
            tui.check(
                "summary abbreviation does not shorten query", "QUERY_END" in tui.text()
            )
            tui.send(b"\r")
            tui.wait(
                "search editor closes", lambda: "Search:" not in tui.screen.display[-3]
            )
            label_x = tui.screen.display[2].index("project")
            tui.send(f"\x1b[<0;{label_x + 1};3M".encode())
            tui.wait(
                "archive label click",
                lambda: (
                    "Archive" in tui.screen.display[2]
                    and "0 tasks accepted" in tui.screen.display[2]
                ),
            )
            tui.check(
                "archive count stays explicit with long query",
                "0 tasks accepted" in tui.screen.display[2],
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-archive"))
            tui.send(b"q")
            tui.wait_exit()
        with sqlite3.connect(database) as db:
            final = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        assert final["tasks"] == saved["tasks"] and final["drafts"] == []
        assert list(home.iterdir()) == []
        print(
            "PASS: header filtering and clicks leave exact task and run data unchanged"
        )
    print(
        "Temporary replay and storage only. No model, credentials or real workspace access."
    )


if __name__ == "__main__":
    main()
