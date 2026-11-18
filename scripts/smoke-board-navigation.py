#!/usr/bin/env python3
"""Verify row-aligned horizontal card navigation in an isolated terminal board."""

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
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-board-navigation-") as temporary:
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
        with sqlite3.connect(database) as db:
            snapshot = json.loads(
                db.execute("SELECT payload FROM snapshot").fetchone()[0]
            )
            seed = next(task for task in snapshot["tasks"] if task["state"] == "queued")
            tasks = []
            for state, count in (("queued", 5), ("needs_you", 5), ("ready", 2)):
                for index in range(count):
                    task = copy.deepcopy(seed)
                    task.update(
                        id=f"{state}-{index}",
                        title=f"{state} instruction {index}",
                        state=state,
                        repository="fixture",
                    )
                    task["messages"] = [
                        {
                            "id": f"{state}-{index}/prompt",
                            "author": "You",
                            "text": task["title"],
                            "queued": True,
                        }
                    ]
                    tasks.append(task)
            snapshot.update(tasks=tasks, selected="queued-0", drafts=[])
            db.execute("UPDATE snapshot SET payload=?", (json.dumps(snapshot),))
        with Terminal(command, env) as tui:
            tui.ready()
            tui.send(b"3j")
            tui.wait(
                "queued fourth card",
                lambda: (
                    "Working 5 / 3-4/5" in tui.text() and "queued-3 ◂" in tui.text()
                ),
            )
            tui.send(b"l")
            tui.wait(
                "aligned next column",
                lambda: (
                    "needs_you-3 ◂" in tui.text()
                    and "Needs you 5 / 3-4/5" in tui.text()
                ),
            )
            tui.check(
                "horizontal movement preserves row and skips empty Working",
                "needs_you instruction 3" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-aligned"))
            tui.send(b"e")
            tui.wait(
                "aligned task chat",
                lambda: "needs_you-3 / Needs you / conversation" in tui.text(),
            )
            tui.check(
                "opening aligned card shows its own instruction",
                "needs_you instruction 3" in tui.text(),
            )
            tui.send(b"\x1b")
            tui.send(b"l")
            tui.wait("shorter target column", lambda: "ready-1 ◂" in tui.text())
            tui.check(
                "shorter column clamps to final card",
                "ready instruction 1" in tui.text(),
            )
            tui.send(b"h")
            tui.wait(
                "left preserves current ordinal", lambda: "needs_you-1 ◂" in tui.text()
            )
            tui.send(b"h")
            tui.wait("left skips empty column", lambda: "queued-1 ◂" in tui.text())
            tui.send(b"gg2l")
            tui.wait("counted horizontal motion", lambda: "ready-0 ◂" in tui.text())
            tui.check(
                "counts apply row-aligned moves", "ready instruction 0" in tui.text()
            )
            tui.send(b"q")
            tui.wait_exit()
        with sqlite3.connect(database) as db:
            final = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        assert final["tasks"] == tasks and final["drafts"] == []
        assert final["selected"] == "ready-0" and list(home.iterdir()) == []
        print(
            "PASS: navigation changes selection without rewriting tasks, runs or drafts"
        )
    print("Temporary board and replay only. No agent, credentials or workspace access.")


if __name__ == "__main__":
    main()
