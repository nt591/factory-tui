#!/usr/bin/env python3
"""Verify independent Kanban column scrolling with a temporary fixture board."""

import argparse
import copy
import json
import os
import sqlite3
import subprocess
import tempfile
from pathlib import Path

from fixtures.terminal import Terminal


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", type=Path)
    parser.add_argument("--binary", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-columns-") as temporary:
        database = Path(temporary) / "board.sqlite"
        command = [
            str(binary),
            "--demo",
            "--no-config",
            "--database",
            str(database),
        ]
        with Terminal(command, os.environ) as tui:
            tui.ready()
            tui.send(b"q")
            tui.wait_exit()
        with sqlite3.connect(database) as db:
            snapshot = json.loads(
                db.execute("SELECT payload FROM snapshot").fetchone()[0]
            )
            seed = next(task for task in snapshot["tasks"] if task["state"] == "queued")
            tasks = []
            for state in ("queued", "ready"):
                for index in range(10):
                    task = copy.deepcopy(seed)
                    task.update(
                        id=f"{state}-{index:02}",
                        title=f"{state} task {index:02}",
                        state=state,
                        repository="fixture",
                    )
                    task["messages"][0].update(
                        id=f"{state}-prompt-{index:02}", text=task["title"]
                    )
                    tasks.append(task)
            snapshot.update(tasks=tasks, selected="queued-00", drafts=[])
            db.execute("UPDATE snapshot SET payload=?", (json.dumps(snapshot),))
        with Terminal(command, os.environ) as tui:
            tui.ready()
            tui.check(
                "both columns start with their first two cards",
                "Working 10 / 1-2/10" in tui.text()
                and "Ready 10 / 1-2/10" in tui.text(),
            )
            tui.send(b"\x1b[<65;5;8M")
            tui.wait("queued scroll", lambda: "Working 10 / 2-3/10" in tui.text())
            tui.check(
                "scrolling Queued leaves Ready unchanged",
                "Ready 10 / 1-2/10" in tui.text(),
            )
            tui.send(b"\x1b[<65;95;8M" * 2)
            tui.wait("ready scroll", lambda: "Ready 10 / 3-4/10" in tui.text())
            tui.check(
                "Ready scroll preserves Queued position and chat",
                "Working 10 / 2-3/10" in tui.text()
                and "queued-00 / Not started / conversation" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview)
            tui.send(b"G")
            tui.wait(
                "keyboard follows selected column",
                lambda: "Working 10 / 9-10/10" in tui.text(),
            )
            tui.check(
                "keyboard selection resets only its target column",
                "Ready 10 / 3-4/10" in tui.text()
                and "queued-09 / Not started / conversation" in tui.text(),
            )
            tui.send(b"\x1b[<64;5;8M" * 12)
            tui.wait("manual top", lambda: "Working 10 / 1-2/10" in tui.text())
            tui.check(
                "manual top does not snap back to selected last card",
                "queued-09 / Not started / conversation" in tui.text(),
            )
            tui.send(b"b")
            tui.wait("board scroll reset", lambda: "Ready 10 / 1-2/10" in tui.text())
            tui.send(b"q")
            tui.wait_exit()
            tui.check("column scroll test exits cleanly", tui.process.returncode == 0)
        with sqlite3.connect(database) as db:
            stored = json.loads(
                db.execute("SELECT payload FROM snapshot").fetchone()[0]
            )
            assert stored["tasks"] == tasks
            assert stored["drafts"] == []
            print("PASS: scrolling changes no persisted task content")


if __name__ == "__main__":
    main()
