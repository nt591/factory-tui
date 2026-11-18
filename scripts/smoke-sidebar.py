#!/usr/bin/env python3
"""Check repository overflow with a temporary board and no agent calls."""

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
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    with tempfile.TemporaryDirectory(prefix="factory-sidebar-") as temporary:
        database = Path(temporary) / "board.sqlite"
        command = [
            str(root / "_build/default/bin/main.exe"),
            "--no-config",
            "--database",
            str(database),
        ]
        with Terminal(command, os.environ, columns=180, rows=20) as tui:
            tui.ready()
            tui.send(b"q")
            tui.wait_exit()
        with sqlite3.connect(database) as db:
            snapshot = json.loads(
                db.execute("SELECT payload FROM snapshot").fetchone()[0]
            )
            seed = next(task for task in snapshot["tasks"] if task["state"] == "queued")
            tasks = []
            for index in range(40):
                task = copy.deepcopy(seed)
                task.update(
                    id=f"T-{index:02}",
                    title=f"Repository task {index:02}",
                    repository=f"repo-{index:02}",
                )
                task["messages"][0].update(id=f"prompt-{index:02}", text=task["title"])
                tasks.append(task)
            snapshot.update(tasks=tasks, selected="T-00", drafts=[])
            db.execute("UPDATE snapshot SET payload=?", (json.dumps(snapshot),))
        with Terminal(command, os.environ, columns=180, rows=20) as tui:
            tui.ready()
            tui.check(
                "repository overflow starts at the top",
                "1-4/41" in tui.text() and "All repositories" in tui.text(),
            )
            tui.send(b"\x1b[<65;3;12M")
            tui.wait("sidebar scroll frame", lambda: "4-7/41" in tui.text())
            tui.check(
                "sidebar wheel exposes more repositories", "repo-05" in tui.text()
            )
            tui.send(b"\x1b[<0;3;15M\x1b[<0;3;15m")
            tui.wait("repository selection", lambda: " repo-05  |" in tui.text())
            tui.check(
                "repository click filters board",
                "T-05" in tui.text() and "task 05" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview)
            tui.send(b"b")
            tui.wait(
                "all repository reset",
                lambda: "1-4/41" in tui.text() and "All repositories" in tui.text(),
            )
            tui.check(
                "return to board resets sidebar scroll", "Session board" in tui.text()
            )
            tui.send(b"q")
            tui.wait_exit()
            tui.check("overflow sidebar exits cleanly", tui.process.returncode == 0)


if __name__ == "__main__":
    main()
