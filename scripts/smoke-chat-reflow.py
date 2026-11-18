#!/usr/bin/env python3
"""Verify stable body reading position across actual terminal width changes."""

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


def resize(tui, columns):
    fcntl.ioctl(tui.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 36, columns, 0, 0))
    tui.screen.resize(lines=36, columns=columns)
    os.kill(tui.process.pid, signal.SIGWINCH)


def top_body(tui):
    return tui.screen.display[4].split("│")[1].strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-chat-reflow-") as temporary:
        directory = Path(temporary)
        replay = directory / "events.jsonl"
        body = " ".join(f"word{index:03d}" for index in range(250))
        replay.write_text(
            event("long-body", body) + event("tail", "Tail " * 300 + "TAIL_END")
        )
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        home = directory / "home"
        home.mkdir()
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home), TMPDIR=str(directory))
        command = [str(binary), "--no-config", "--events", str(replay)]
        with Terminal(command, env) as tui:
            tui.ready()
            tui.send(b"e")
            tui.wait("replay loaded", lambda: "TAIL_END" in tui.text())
            tui.send(b"\x1b[H8j")
            tui.wait(
                "body reading position",
                lambda: "word" in top_body(tui) and "reading history" in tui.text(),
            )
            original = top_body(tui)
            original_position = body.index(original[:16])

            def contains_position():
                top = top_body(tui)
                start = body.find(top[:16])
                return start >= 0 and start <= original_position < start + len(top)

            original_rows = tui.screen.display[3:10]
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-original"))
            for columns in (90, 160, 84, 120, 90, 120):
                resize(tui, columns)
                tui.wait("reflow body anchor", contains_position)
                tui.check(
                    f"{columns}-column reflow retains original body position",
                    contains_position() and "reading history" in tui.text(),
                )
                if columns == 120:
                    tui.check(
                        "return to original width restores exact top row",
                        top_body(tui) == original,
                    )
            with replay.open("a") as output:
                output.write(event("tail", "Tail " * 600 + "GROWN_TAIL_END"))
            tui.wait("later output delivered", lambda: "updates: 4" in tui.text())
            tui.check(
                "later stream growth preserves resized reading anchor",
                top_body(tui) == original,
            )
            resize(tui, 90)
            tui.wait("second narrow reflow", contains_position)
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-narrow"))
            resize(tui, 120)
            tui.wait("final exact restoration", lambda: top_body(tui) == original)
            tui.check(
                "returning width preserves original visible body rows",
                tui.screen.display[4:10] == original_rows[1:],
            )
            tui.send(b"\x1b[F")
            tui.wait("explicit follow", lambda: "GROWN_TAIL_END" in tui.text())
            tui.check(
                "End resumes following after repeated width changes",
                "reading history" not in tui.text(),
            )
            tui.send(b"q")
            tui.wait_exit()
            tui.check("reflow fixture exits cleanly", tui.process.returncode == 0)
        assert list(home.iterdir()) == []
    print("Temporary replay only. No storage, agent, credentials or workspace access.")


if __name__ == "__main__":
    main()
