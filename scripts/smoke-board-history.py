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
    parser.add_argument("--binary", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-board-history-") as temporary:
        replay = Path(temporary) / "events.jsonl"
        replay.write_text(
            "".join(
                event(str(index), f"History item {index:02d}") for index in range(40)
            )
        )
        command = [
            str(binary),
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
            tui.send(b"\x1b[<65;5;4M")
            tui.check(
                "wheel on column title leaves its card range unchanged",
                "Queued 3 / 1-2/3" in tui.text(),
            )
            tui.send(b"\x1b[<65;10;20M")
            tui.check("wheel on chat title preserves history", chat_rows() == old_chat)
            tui.send(b"\x1b[<65;90;20M")
            tui.check(
                "wheel on Activity title preserves its range",
                "rows 1-12/14" in tui.text(),
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
            tui.send(b"b")
            tui.send(b"\x1b[<0;5;8M")
            tui.wait(
                "other task selected",
                lambda: "T-101 / Queued / conversation" in tui.text(),
            )
            with replay.open("a") as output:
                output.write(event("background", "Background chunk"))
                output.write(event("background", "Background final reply"))
            tui.wait("background badge", lambda: "1 new update" in tui.text())
            tui.check(
                "background streaming counts one item rather than chunks",
                "2 new updates" not in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-background"))
            with replay.open("a") as output:
                output.write(
                    json.dumps(
                        {
                            "task_id": "T-102",
                            "run_id": "demo-102",
                            "type": "turn.completed",
                        }
                    )
                    + "\n"
                )
                output.write(
                    json.dumps(
                        {
                            "task_id": "T-102",
                            "run_id": "demo-102",
                            "type": "process.exited",
                            "code": 0,
                        }
                    )
                    + "\n"
                )
            tui.wait(
                "moved task retains badge",
                lambda: "2 new updates" in tui.text() and "Ready 2" in tui.text(),
            )
            tui.check(
                "background completion keeps selected conversation unchanged",
                "T-101 / Queued / conversation" in tui.text(),
            )
            tui.send(b"\x1b[<0;95;8M")
            tui.wait(
                "updated task inspected",
                lambda: (
                    "T-102 / Ready / conversation" in tui.text()
                    and "new updates" not in tui.text()
                ),
            )
            tui.check(
                "inspecting moved task clears badge without starting a run",
                "Background final reply" in tui.text(),
            )
            tui.send(b"\x1b[<0;10;22M\x1b[<0;10;22m\x1b[H")
            tui.wait("paused before reply", lambda: "reading history" in tui.text())
            tui.send(b"i")
            tui.send(b"\x1b[200~Reply queued from old history\x1b[201~\r")
            tui.wait(
                "submitted reply visible",
                lambda: (
                    "Reply queued from old history" in tui.text()
                    and "reading history" not in tui.text()
                ),
            )
            tui.check(
                "submitting from history returns to the queued reply without starting a run",
                "T-102 / Ready / conversation" in tui.text()
                and "Reply / next turn · 2 queued" in tui.text(),
            )
            if args.preview:
                tui.preview(
                    args.preview.with_stem(args.preview.stem + "-submitted-reply")
                )
            tui.send(b"i")
            tui.send(b"\x1b[200~Retained unsent draft\x1b[201~")
            tui.send(b"\x1b")
            tui.send(b"a")
            tui.wait(
                "accepted pending work disclosure",
                lambda: (
                    "Accepted / read-only" in tui.text()
                    and "2 queued retained" in tui.text()
                    and "draft retained" in tui.text()
                ),
            )
            tui.check(
                "acceptance preserves queued chat without making pending work executable",
                "Reply queued from old history" in tui.text()
                and "i reply" not in tui.screen.display[-2]
                and "s start" not in tui.screen.display[-2],
            )
            if args.preview:
                tui.preview(
                    args.preview.with_stem(args.preview.stem + "-accepted-pending")
                )
            tui.send(b"q")
            tui.wait_exit()
            tui.check(
                "board history fixture exits cleanly", tui.process.returncode == 0
            )


if __name__ == "__main__":
    main()
