#!/usr/bin/env python3
"""Verify accepted conversation selection survives a real SQLite UI restart."""

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
    with tempfile.TemporaryDirectory(prefix="factory-restart-selection-") as temporary:
        directory = Path(temporary)
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
        saved = read(database)
        active = next(task for task in saved["tasks"] if task["state"] == "queued")
        accepted = next(task for task in saved["tasks"] if task["state"] == "ready")
        accepted["state"] = "done"
        saved.update(
            tasks=[active, accepted],
            selected=accepted["id"],
            drafts=[[accepted["id"], "Retained draft for accepted task"]],
        )
        with sqlite3.connect(database) as db:
            db.execute("UPDATE snapshot SET payload=?", (json.dumps(saved),))
        for attempt in range(2):
            with Terminal(command, env, columns=120 if attempt == 0 else 180) as tui:
                tui.ready()
                tui.wait(
                    "restored accepted chat",
                    lambda: f"{accepted['id']} / Done / conversation" in tui.text(),
                )
                tui.check(
                    "active board and accepted chat remain independent",
                    "Queued 1" in tui.text() and "1 tasks" in tui.screen.display[2],
                )
                tui.check(
                    "retained draft is read-only after restart",
                    "draft retained" in tui.text() and "i to edit" not in tui.text(),
                )
                reveal_column = tui.screen.display[2].index(
                    "[Chat off-board / Show card]"
                )
                tui.send(
                    f"\x1b[<0;{reveal_column + 1};3M\x1b[<0;{reveal_column + 1};3m".encode()
                )
                tui.wait(
                    "Show card reveals accepted task",
                    lambda: "1 tasks accepted" in tui.screen.display[2],
                )
                tui.check(
                    "revealing accepted card keeps chat and retained draft",
                    f"{accepted['id']} / Done / conversation" in tui.text()
                    and "draft retained" in tui.text()
                    and "Show card" not in tui.screen.display[2],
                )
                tui.send(b"b")
                tui.send(b"\x1b")
                tui.check(
                    "Escape preserves accepted chat on active board",
                    f"{accepted['id']} / Done / conversation" in tui.text(),
                )
                tui.send(b"j")
                tui.wait(
                    "explicit navigation selects active task",
                    lambda: f"{active['id']} / Queued / conversation" in tui.text(),
                )
                if attempt == 0:
                    tui.send(b"d")
                else:
                    archive_row = next(
                        row
                        for row, text in enumerate(tui.screen.display)
                        if "Archive" in text
                    )
                    tui.send(
                        f"\x1b[<0;3;{archive_row + 1}M\x1b[<0;3;{archive_row + 1}m".encode()
                    )
                tui.check(
                    "archive switch keeps active conversation open",
                    f"{active['id']} / Queued / conversation" in tui.text()
                    and "1 tasks accepted" in tui.screen.display[2],
                )
                if args.preview and attempt == 1:
                    tui.preview(args.preview.with_stem(args.preview.stem + "-archive"))
                reveal_column = tui.screen.display[2].index(
                    "[Chat off-board / Show card]"
                )
                tui.send(
                    f"\x1b[<0;{reveal_column + 1};3M\x1b[<0;{reveal_column + 1};3m".encode()
                )
                tui.wait(
                    "Show card reveals active task",
                    lambda: (
                        "Queued 1" in tui.text()
                        and "Show card" not in tui.screen.display[2]
                    ),
                )
                tui.check(
                    "revealing active card keeps selected conversation",
                    f"{active['id']} / Queued / conversation" in tui.text(),
                )
                tui.send(b"d")
                tui.send(b"dbd")
                tui.check(
                    "keyboard view switches keep active conversation open",
                    f"{active['id']} / Queued / conversation" in tui.text(),
                )
                tui.send(b"j")
                tui.wait(
                    "archive navigation selects accepted task",
                    lambda: f"{accepted['id']} / Done / conversation" in tui.text(),
                )
                tui.send(b"b")
                tui.check(
                    "session board retains accepted conversation",
                    f"{accepted['id']} / Done / conversation" in tui.text()
                    and "Queued 1" in tui.text(),
                )
                tui.send(b"e")
                tui.wait(
                    "accepted conversation expanded",
                    lambda: "Navigation tests pass" in tui.text(),
                )
                tui.check(
                    "restart does not expose task execution or reply controls",
                    "i reply" not in tui.screen.display[-2]
                    and "s start" not in tui.screen.display[-2],
                )
                if args.preview and attempt == 1:
                    tui.preview(args.preview)
                tui.send(b"q")
                tui.wait_exit()
            current = read(database)
            assert current["selected"] == accepted["id"]
            assert (
                current["tasks"] == saved["tasks"]
                and current["drafts"] == saved["drafts"]
            )
        assert list(home.iterdir()) == []
        print(
            "PASS: repeated restart preserves selected archived conversation and exact task/draft data"
        )
    print("Temporary SQLite/replay only. No model, credentials or workspace access.")


if __name__ == "__main__":
    main()
