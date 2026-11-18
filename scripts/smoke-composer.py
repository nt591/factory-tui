#!/usr/bin/env python3
"""Verify cursor-following draft overflow and exact persistence in a local terminal."""

import argparse
import json
import os
import sqlite3
import subprocess
import tempfile
from pathlib import Path

from fixtures.terminal import Terminal


def saved(database):
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
    with tempfile.TemporaryDirectory(prefix="factory-composer-") as temporary:
        directory = Path(temporary).resolve()
        replay = directory / "empty.jsonl"
        replay.write_text("")
        database = directory / "board.sqlite"
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
        draft = "\n".join(f"Draft line {index:02d} — é 👩🏽‍💻" for index in range(18))
        with Terminal(command, env) as tui:
            tui.ready()
            tui.send(b"ei")
            tui.send(b"\x1b[200~" + draft.encode() + b"\x1b[201~")
            tui.wait(
                "bottom draft window",
                lambda: (
                    "draft rows 14-18/18" in tui.text()
                    and "Draft line 17" in tui.text()
                    and "Reply (queued):" in tui.text()
                    and "Enter queues" in tui.text()
                ),
            )
            tui.check(
                "long pasted draft stays editable and unsubmitted",
                "Reply (queued):" in tui.text() and "Enter queues" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-bottom"))
            tui.send(b"\x1b[A" * 18 + b"\x1b[H")
            tui.wait(
                "top draft window",
                lambda: (
                    "draft rows 1-5/18" in tui.text()
                    and "> ▏Draft line 00" in tui.text()
                ),
            )
            tui.check(
                "top draft exposes below direction",
                "↓" in next(row for row in tui.screen.display if "draft rows" in row),
            )
            tui.send(b"\x1b[200~EDIT-\x1b[201~")
            expected = "EDIT-" + draft
            tui.wait("top edit", lambda: "EDIT-▏Draft line 00" in tui.text())
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-top"))
            tui.send(b"\x1b[B" * 8)
            tui.wait("middle draft window", lambda: "draft rows 5-9/18" in tui.text())
            cue = next(row for row in tui.screen.display if "draft rows" in row)
            tui.check(
                "middle draft shows both hidden directions", "↑" in cue and "↓" in cue
            )
            tui.send(b"\x1b")
            tui.wait(
                "saved draft preview",
                lambda: (
                    "Draft saved" in tui.text() and "draft rows 14-18/18" in tui.text()
                ),
            )
            tui.send(b"q")
            tui.wait_exit()
        first = saved(database)
        task_id = first["selected"]
        assert dict(first["drafts"])[task_id] == expected
        task = next(task for task in first["tasks"] if task["id"] == task_id)
        runs = task["runs"]
        assert not any(message["text"] == expected for message in task["messages"])
        print(
            "PASS: full multiline Unicode draft persists without submission or new run"
        )
        with Terminal(command, env) as tui:
            tui.ready()
            reopened = next(
                task for task in saved(database)["tasks"] if task["id"] == task_id
            )
            reopened_runs = reopened["runs"]
            assert [run["id"] for run in reopened_runs] == [run["id"] for run in runs]
            tui.send(b"ei")
            tui.wait(
                "restored editor",
                lambda: (
                    "draft rows 14-18/18" in tui.text()
                    and "Draft line 17" in tui.text()
                ),
            )
            tui.send(b"\x1b[A" * 18 + b"\x1b[H")
            tui.wait("restored top edit", lambda: "> ▏EDIT-Draft line 00" in tui.text())
            tui.check(
                "restart preserves original top edit", "draft rows 1-5/18" in tui.text()
            )
            tui.send(b"\r")
            tui.wait(
                "queued long instruction",
                lambda: (
                    "Reply queued" in tui.text() or "queued for the next" in tui.text()
                ),
            )
            tui.send(b"q")
            tui.wait_exit()
        final = saved(database)
        task = next(task for task in final["tasks"] if task["id"] == task_id)
        assert any(
            message["text"] == expected and message["queued"]
            for message in task["messages"]
        )
        assert task["runs"] == reopened_runs and not dict(final["drafts"]).get(task_id)
        print("PASS: Enter queues exact retained text without starting another run")
        assert list(home.iterdir()) == []
    print("Temporary replay and SQLite only. No agent, credential or workspace access.")


if __name__ == "__main__":
    main()
