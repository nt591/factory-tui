#!/usr/bin/env python3
"""Verify paused chat history while the board owns mouse focus."""

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path

from fixtures.terminal import Terminal


def event(item, text):
    return (
        json.dumps(
            {
                "task_id": "T-102",
                "run_id": "demo-102",
                "type": "message",
                "item_id": item,
                "text": text,
            }
        )
        + "\n"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    with tempfile.TemporaryDirectory(prefix="factory-board-history-") as temporary:
        replay = Path(temporary) / "events.jsonl"
        replay.write_text(
            "".join(
                event(str(index), f"History item {index:02d}") for index in range(40)
            )
        )
        command = [
            str(root / "_build/default/bin/main.exe"),
            "--no-config",
            "--events",
            str(replay),
        ]
        with Terminal(command, os.environ) as tui:
            tui.ready()
            tui.wait("history loaded", lambda: "History item 39" in tui.text())
            tui.send(b"\x1b[<0;10;22M\x1b[<0;10;22m\x1b[H")
            tui.wait("paused history", lambda: "reading history" in tui.text())

            def chat_rows():
                return [row[:80] for row in tui.screen.display[20:28]]

            old_chat = chat_rows()
            tui.check(
                "Home reveals original task instruction",
                any("Build the event reducer" in row for row in old_chat),
            )
            tui.send(b"\x1b[<65;5;8M")
            tui.wait("board scroll frame", lambda: "Queued 3 / 2-3/3" in tui.text())
            tui.check(
                "board wheel leaves visible chat history unchanged",
                chat_rows() == old_chat and "reading history" in tui.text(),
            )
            with replay.open("a") as output:
                output.write(event("arrival", "New output while scrolling board"))
            tui.wait("stream arrival", lambda: "updates: 42" in tui.text())
            tui.check(
                "streaming with board focus preserves chat anchor",
                chat_rows() == old_chat,
            )
            tui.send(b"\x1b[<0;10;22M\x1b[<0;10;22m")
            tui.check(
                "returning to chat keeps paused position",
                chat_rows() == old_chat,
            )
            if args.preview:
                tui.preview(args.preview)
            button_y = next(
                index
                for index, row in enumerate(tui.screen.display)
                if "[Latest / End]" in row
            )
            button_x = tui.screen.display[button_y].index("[Latest / End]")
            tui.check(
                "paused border reports transcript rows",
                "rows 1-" in tui.screen.display[button_y],
            )
            tui.send(f"\x1b[<65;{button_x + 1};{button_y + 1}M".encode())
            tui.check(
                "wheel on Latest border cannot move history", chat_rows() == old_chat
            )
            tui.send(f"\x1b[<0;{button_x + 1};{button_y + 1}M".encode())
            tui.wait(
                "follow resumed",
                lambda: (
                    "New output while scrolling board" in tui.text()
                    and "reading history" not in tui.text()
                ),
            )
            tui.check(
                "Latest click resumes following after board scrolling",
                "[Latest / End]" not in tui.text(),
            )
            with replay.open("a") as output:
                output.write(
                    event("after-follow", "Following continues after Latest click")
                )
            tui.wait(
                "followed append",
                lambda: "Following continues after Latest click" in tui.text(),
            )
            tui.check(
                "Latest stays followed on later output",
                "[Latest / End]" not in tui.text(),
            )
            tui.send(b"q")
            tui.wait_exit()
            tui.check(
                "board history fixture exits cleanly", tui.process.returncode == 0
            )


if __name__ == "__main__":
    main()
