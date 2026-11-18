#!/usr/bin/env python3
"""Verify deliberate archive shortcut and restore across temporary SQLite restart."""

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
        subprocess.run([str(root / "scripts/build.sh")], check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-archive-") as temporary:
        directory = Path(temporary).resolve()
        home = directory / "home"
        home.mkdir()
        events = directory / "empty.jsonl"
        events.write_text("")
        database = directory / "board.sqlite"
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home), TMPDIR=str(directory))
        command = [
            str(binary),
            "--no-config",
            "--events",
            str(events),
            "--database",
            str(database),
        ]
        with Terminal(command, env) as tui:
            tui.ready()
            tui.send(b"q")
            tui.wait_exit()
        saved = read(database)
        task = next(task for task in saved["tasks"] if task["state"] == "ready")
        task["messages"].append(
            {
                "id": "pending-followup",
                "author": "You",
                "text": "Preserve queued work",
                "queued": True,
            }
        )
        saved.update(
            tasks=[task],
            selected=task["id"],
            drafts=[[task["id"], "Preserve unsent draft"]],
        )
        with sqlite3.connect(database) as db:
            db.execute("UPDATE snapshot SET payload=?", (json.dumps(saved),))
        with Terminal(command, env, columns=180, rows=50) as tui:
            tui.ready()
            tui.send(b"a")
            tui.check(
                "plain a leaves task on active board",
                f"{task['id']} / Ready / conversation" in tui.text(),
            )
            tui.send(b"\x01")
            tui.wait(
                "Ctrl-A archives",
                lambda: f"{task['id']} / Done / conversation" in tui.text(),
            )
            tui.send(b"d")
            tui.wait(
                "archive navigation",
                lambda: "1 tasks accepted" in tui.screen.display[2],
            )
            tui.check(
                "archive has visible board return and restore controls",
                "b session board" in tui.screen.display[-2]
                and "u restore" in tui.screen.display[-2],
            )
            if args.preview:
                tui.preview(args.preview)
            tui.send(b"q")
            tui.wait_exit()
        archived = read(database)
        assert archived["tasks"][0]["state"] == "done"
        with Terminal(command, env, columns=180, rows=50) as tui:
            tui.ready()
            tui.send(b"d")
            tui.send(b"u")
            tui.wait(
                "restore reveals active task",
                lambda: (
                    f"{task['id']} / Ready / conversation" in tui.text()
                    and "1 tasks accepted" not in tui.screen.display[2]
                ),
            )
            tui.check(
                "restore retains reply and draft without starting a run",
                "i reply" in tui.screen.display[-2]
                and "Task restored to Ready" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-restored"))
            tui.send(b"q")
            tui.wait_exit()
        current = read(database)
        expected = {**task, "revision": task["revision"] + 2}
        assert current["tasks"] == [expected]
        assert (
            current["drafts"] == saved["drafts"] and current["selected"] == task["id"]
        )
        assert list(home.iterdir()) == []
    print(
        "PASS: Ctrl-A archive and u restore persist exact history/queued replies/draft. Temporary SQLite/replay only."
    )


if __name__ == "__main__":
    main()
