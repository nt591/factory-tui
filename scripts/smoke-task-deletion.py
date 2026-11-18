#!/usr/bin/env python3
"""Verify task deletion and conversation entry using temporary SQLite fixtures."""

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
    with tempfile.TemporaryDirectory(prefix="factory-delete-ui-") as temporary:
        directory = Path(temporary).resolve()
        home = directory / "home"
        home.mkdir()
        replay = directory / "empty.jsonl"
        replay.write_text("")
        database = directory / "board.sqlite"
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home), TMPDIR=str(directory))
        command = [
            str(binary),
            "--no-config",
            "--events",
            str(replay),
            "--database",
            str(database),
        ]
        with Terminal(command, env) as tui:
            tui.ready()
            tui.send(b"q")
            tui.wait_exit()
        saved = read(database)
        task = next(task for task in saved["tasks"] if task["state"] == "ready")
        other = next(task for task in saved["tasks"] if task["state"] == "queued")
        workspace = directory / "workspace"
        workspace.mkdir()
        sentinel = workspace / "keep.txt"
        sentinel.write_text("Keep workspace files")
        task.update(session_root=str(workspace), repository=str(workspace))
        saved.update(
            tasks=[task, other],
            selected=task["id"],
            drafts=[[task["id"], "Retained reply"], [other["id"], "Other reply"]],
        )
        with sqlite3.connect(database) as db:
            db.execute("UPDATE snapshot SET payload=?", (json.dumps(saved),))
            for entry in (task, other):
                db.execute(
                    "INSERT INTO events(payload) VALUES(?)",
                    (
                        json.dumps(
                            {
                                "task_id": entry["id"],
                                "run_id": "fixture",
                                "type": "message",
                                "item_id": "fixture",
                                "text": "Retained fixture event",
                            }
                        ),
                    ),
                )
        with Terminal(command, env, columns=180, rows=50) as tui:
            tui.ready()
            tui.send(b"\r")
            tui.wait(
                "task opens with editor",
                lambda: "INSERT / Enter sends" in tui.screen.display[-1],
            )
            tui.check(
                "board Enter defaults to conversation insert",
                "Retained reply" in tui.text() and "Queued 1" not in tui.text(),
            )
            tui.send(b"\x1b")
            tui.send(b"ee")
            tui.check(
                "e cannot collapse the conversation",
                "Queued 1" not in tui.text() and "INSERT" not in tui.screen.display[-1],
            )
            tui.send(b"\r")
            tui.check(
                "conversation Enter edits instead of toggling view",
                "INSERT / Enter sends" in tui.screen.display[-1]
                and "Queued 1" not in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-insert"))
            tui.send(b"\x1b")
            tui.send(b"\x1b")
            tui.check(
                "second Escape returns board with board navigation",
                "Queued 1" in tui.text()
                and "hjkl/arrows: cards" in tui.screen.display[-1],
            )
            tui.send(b"\x18")
            tui.wait("confirmation", lambda: "Delete task / permanent" in tui.text())
            tui.send(b"\r")
            tui.check(
                "empty Enter cannot confirm", "Delete task / permanent" in tui.text()
            )
            tui.send(b"\x1b[200~delete\r\x1b[201~")
            tui.check(
                "paste cannot confirm",
                "Delete task / permanent" in tui.text()
                and read(database)["tasks"] == saved["tasks"],
            )
            tui.send(b"\x1b")
            tui.check(
                "Escape cancels deletion without data loss",
                read(database)["tasks"] == saved["tasks"],
            )
            tui.send(b"\x18")
            if args.preview:
                tui.preview(args.preview)
            tui.send(b"delete\r")
            tui.wait(
                "deleted task gone",
                lambda: (
                    "Task deleted." in tui.text()
                    and f"{task['id']} / Ready / conversation" not in tui.text()
                ),
            )
            tui.check(
                "surviving task remains selectable",
                f"{other['id']} / Queued / conversation" in tui.text(),
            )
            tui.send(b"q")
            tui.wait_exit()
        deleted = read(database)
        assert deleted["tasks"] == [other]
        assert deleted["drafts"] == [[other["id"], "Other reply"]]
        with sqlite3.connect(database) as db:
            assert (
                db.execute(
                    "SELECT count(*) FROM runs WHERE task_id=?", (task["id"],)
                ).fetchone()[0]
                == 0
            )
            history = [
                json.loads(row[0]) for row in db.execute("SELECT payload FROM events")
            ]
            assert [event["task_id"] for event in history] == [other["id"]]
        assert sentinel.read_text() == "Keep workspace files"
        with Terminal(command, env) as tui:
            tui.ready()
            tui.check(
                "restart does not restore deleted task", task["title"] not in tui.text()
            )
            tui.send(b"\x18delete\r")
            tui.wait(
                "empty board",
                lambda: (
                    "Task deleted." in tui.text() and "0 tasks" in tui.screen.display[2]
                ),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-empty"))
            tui.send(b"q")
            tui.wait_exit()
        assert read(database)["tasks"] == []
        assert list(home.iterdir()) == []
    print(
        "PASS: confirmed task-only deletion persists; workspace sentinel stays intact. No agents, credentials or network."
    )


if __name__ == "__main__":
    main()
