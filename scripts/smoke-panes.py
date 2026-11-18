#!/usr/bin/env python3
"""Verify adjustable splits and reading position in a temporary replay terminal."""

import argparse
import fcntl
import json
import os
import signal
import struct
import subprocess
import tempfile
import termios
from pathlib import Path

from fixtures.terminal import Terminal


def resize(tui, columns, rows):
    fcntl.ioctl(tui.slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
    tui.screen.resize(lines=rows, columns=columns)
    os.kill(tui.process.pid, signal.SIGWINCH)


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


def conversation_row(tui):
    return next(
        index
        for index, row in enumerate(tui.screen.display)
        if "T-102 / Working / conversation" in row
    )


def conversation_column(tui):
    row = next(
        row for row in tui.screen.display if "T-102 / Working / conversation" in row
    )
    return row.index("T-102 / Working / conversation")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", type=Path)
    parser.add_argument("--binary", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = args.binary or root / "_build/default/bin/main.exe"
    with tempfile.TemporaryDirectory(prefix="factory-pane-replay-") as temporary:
        replay = Path(temporary) / "events.jsonl"
        replay.write_text(
            "".join(
                event(str(index), f"Replay history {index:02}") for index in range(40)
            )
        )
        with Terminal(
            [str(binary), "--no-config", "--events", str(replay)], os.environ
        ) as tui:
            tui.ready()
            tui.wait("history loaded", lambda: "Replay history 39" in tui.text())

            def focused_title(label):
                row = next(row for row in tui.screen.display if label in row)
                return row[row.index(label) - 3] == "┏"

            tui.check("whole board has strong initial focus", focused_title("Board /"))
            original_top = conversation_row(tui)
            for section in ("conversation", "activity", "Board /"):
                tui.send(b"\t")
                label = (
                    "T-102 / Working / conversation"
                    if section == "conversation"
                    else ("T-102 / activity" if section == "activity" else section)
                )
                tui.check(
                    "Tab makes " + section + " focus visible", focused_title(label)
                )
                tui.check(
                    "Tab keeps layout stable", conversation_row(tui) == original_top
                )
                if args.preview:
                    tui.preview(
                        args.preview.with_stem(
                            args.preview.stem + "-focus-" + section.replace(" /", "")
                        )
                    )
            tui.send(b"d")
            tui.check(
                "plain d cannot open Archive",
                "tasks accepted" not in tui.screen.display[2],
            )
            original_top = conversation_row(tui)
            tui.send(b"3\x17+")
            tui.wait(
                "counted board growth",
                lambda: conversation_row(tui) == original_top + 3,
            )
            tui.check(
                "counted split adjustment moves actual pane borders",
                conversation_row(tui) == original_top + 3,
            )
            tui.send(b"\x17=")
            tui.wait(
                "default split restored", lambda: conversation_row(tui) == original_top
            )
            tui.send(b"\x17l\x1b[H")
            tui.wait(
                "history anchor",
                lambda: (
                    "reading history" in tui.text()
                    and "Build the event reducer" in tui.text()
                ),
            )
            tui.send(b"\x17+")
            tui.wait("chat grows", lambda: conversation_row(tui) == original_top - 1)
            tui.check(
                "growing focused chat preserves paused instruction",
                "Build the event reducer" in tui.text()
                and "reading history" in tui.text(),
            )
            with replay.open("a") as output:
                output.write(
                    event("after-resize", "Output arrives after changing pane sizes")
                )
            tui.wait("replay delivered", lambda: "updates: 42" in tui.text())
            tui.check(
                "resized history does not jump to incoming output",
                "Build the event reducer" in tui.text()
                and "Output arrives after" not in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-stacked"))
            tui.send(b"\x1b[200~+\x1b[201~")
            tui.check(
                "paste cannot resize panes", conversation_row(tui) == original_top - 1
            )
            tui.send(b"?")
            tui.wait("resize help", lambda: "Ctrl-W +/-" in tui.text())
            tui.send(b"\x17+")
            tui.send(b"\x1b")
            tui.wait("modal closes", lambda: "HELP" not in tui.text())
            tui.check(
                "menu does not resize background panes",
                conversation_row(tui) == original_top - 1,
            )
            tui.send(b"i")
            tui.send(b"\x1b[200~+ draft resize fixture\x1b[201~")
            tui.send(b"\t\x1b[Z")
            tui.wait("draft retained", lambda: "+ draft resize fixture" in tui.text())
            tui.send(b"\x17-")
            tui.wait("chat shrinks", lambda: conversation_row(tui) == original_top)
            tui.check(
                "draft stays visible after changing split",
                "+ draft resize fixture" in tui.text(),
            )
            tui.send(b"e")
            tui.wait("zoom opens", lambda: conversation_row(tui) == 3)
            tui.send(b"\x17+")
            tui.wait("zoom resize guidance", lambda: "Return from zoom" in tui.text())
            tui.send(b"\x1b")
            tui.wait(
                "zoom returns to stored split",
                lambda: conversation_row(tui) == original_top,
            )
            resize(tui, 240, 50)
            tui.wait(
                "wide split",
                lambda: conversation_row(tui) == 3 and conversation_column(tui) > 100,
            )
            original_column = conversation_column(tui)
            tui.send(b"\x17l")
            tui.send(b"5\x17+")
            tui.wait(
                "wide chat growth",
                lambda: conversation_column(tui) == original_column - 5,
            )
            adjusted_column = conversation_column(tui)
            draft_y = next(
                index
                for index, row in enumerate(tui.screen.display)
                if "+ draft resize fixture" in row
            )
            draft_x = tui.screen.display[draft_y].index("+ draft resize fixture")
            tui.send(f"\x1b[<0;{draft_x + 1};{draft_y + 1}M".encode())
            tui.send(b"\x1b[200~ mouse-edited\x1b[201~")
            tui.send(b"\x1b")
            tui.check(
                "resized composer remains clickable", "mouse-edited" in tui.text()
            )
            tui.check(
                "wide split keeps chat and draft visible",
                "+ draft resize fixture" in tui.text() and "activity" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-wide"))
            resize(tui, 60, 14)
            tui.wait("compact focused chat", lambda: "conversation" in tui.text())
            tui.send(b"\x17+")
            tui.wait(
                "compact resize guidance", lambda: "No board/chat split" in tui.text()
            )
            resize(tui, 240, 50)
            tui.wait(
                "wide preference restored",
                lambda: conversation_column(tui) == adjusted_column,
            )
            tui.check(
                "compact resize does not erase wide preference",
                "+ draft resize fixture" in tui.text(),
            )
            tui.send(b"\x17=")
            tui.wait("wide reset", lambda: conversation_column(tui) == original_column)
            resize(tui, 120, 36)
            tui.wait("stacked reset", lambda: conversation_row(tui) == original_top)
            tui.send(b"\x17l")
            tui.send(b"\x1b[F")
            tui.wait(
                "follow resumes",
                lambda: "Output arrives after changing pane sizes" in tui.text(),
            )
            tui.check(
                "End resumes follow after layout changes",
                "reading history" not in tui.text(),
            )
            tui.send(b"q")
            tui.wait_exit()
            tui.check("pane replay exits cleanly", tui.process.returncode == 0)
    print("Temporary replay only. No agent, credential, or workspace operations.")


if __name__ == "__main__":
    main()
