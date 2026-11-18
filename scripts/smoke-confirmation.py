#!/usr/bin/env python3
"""Verify long run disclosures in a real terminal with a temporary fake harness."""

import argparse
import fcntl
import json
import os
import signal
import sqlite3
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", type=Path)
    parser.add_argument("--binary", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = args.binary or root / "_build/default/bin/main.exe"
    with tempfile.TemporaryDirectory(prefix="factory-confirmation-") as temporary:
        directory = Path(temporary).resolve()
        database = directory / "board.sqlite"
        home = directory / "home"
        home.mkdir()
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(HOME=str(home), TMPDIR=str(directory))
        command = [str(binary), "--no-config", "--database", str(database)]
        with Terminal(command, env) as tui:
            tui.ready()
            tui.send(b"q")
            tui.wait_exit()
        workspace = directory / "workspace"
        workspace.mkdir()
        # The fake harness needs only the recorded checkout marker, not jj commands.
        (workspace / ".jj").mkdir()
        marker = workspace / "started"
        thread = "t" * 190 + "THREAD_END"
        with sqlite3.connect(database) as db:
            snapshot = json.loads(
                db.execute("SELECT payload FROM snapshot").fetchone()[0]
            )
            task = next(task for task in snapshot["tasks"] if task["state"] == "queued")
            task.update(
                repository=str(directory / "source"),
                title="Long task disclosure " * 100 + "TITLE_END",
                model="m" * 190 + "MODEL_END",
                thread=thread,
                workspace={
                    "source": str(directory / "source"),
                    "directory": str(workspace),
                    "base": "a" * 40,
                    "name": "fixture",
                },
            )
            task["messages"][0].update(text="OLD_SENT_INSTRUCTION", queued=False)
            task["messages"] += [
                {
                    "id": "queued-first",
                    "author": "You",
                    "text": "Actual next-run instruction\n"
                    + "Requested work " * 70
                    + "QUEUED_END",
                    "queued": True,
                },
                {
                    "id": "queued-second",
                    "author": "You",
                    "text": "Second queued reply é 👩🏽‍💻",
                    "queued": True,
                },
            ]
            expected_prompt = "\n\n".join(
                message["text"] for message in task["messages"] if message["queued"]
            )
            snapshot.update(tasks=[task], selected=task["id"], drafts=[])
            db.execute("UPDATE snapshot SET payload=?", (json.dumps(snapshot),))
        executable = directory / "fake-codex"
        events = [
            {"type": "thread.started", "thread_id": thread},
            {"type": "turn.started"},
            {
                "type": "item.completed",
                "item": {
                    "type": "agent_message",
                    "id": "reply",
                    "text": "Confirmed fixture answer",
                },
            },
            {"type": "turn.completed"},
        ]
        executable.write_text(
            "#!/bin/sh\ncat > prompt.txt\ntouch started\n"
            + "".join(
                "printf '%s\\n' '" + json.dumps(event) + "'\n" for event in events
            )
        )
        executable.chmod(0o700)
        command += ["--live-ui", "--codex-executable", str(executable)]
        with Terminal(command, env, columns=88, rows=20) as tui:
            tui.ready()
            tui.send(b"s")
            tui.wait("long disclosure", lambda: "[Review all details]" in tui.text())
            tui.check(
                "usage and auth appear before scrolling",
                "may incur model usage" in tui.text()
                and "existing Codex auth" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-locked"))
            tui.send(b"y")
            tui.check(
                "unseen details cannot start a process",
                not marker.exists() and "Confirm live run" in tui.text(),
            )
            tui.send(b"G")
            end_seen = tui.text()
            tui.check(
                "End exposes the complete thread tail but leaves gaps locked",
                "THREAD_END" in tui.text()
                and "[Review all details]" in tui.text()
                and not marker.exists(),
            )
            tui.send(b"\x1b[200~y\r\x1b[201~")
            tui.check("paste cannot confirm from the last page", not marker.exists())
            tui.send(b"g")
            tui.send(b"\x1b[<65;4;5M")
            tui.check("wheel scrolls the disclosure body", "1-16/" not in tui.text())
            before = tui.text()
            tui.send(b"\x1b[<65;4;19M")
            tui.check(
                "wheel over buttons does not scroll details", tui.text() == before
            )
            tui.send(b"g")
            seen = end_seen + "\n" + tui.text()
            for _ in range(20):
                tui.send(b"\x06")
                seen += "\n" + tui.text()
                if "[Run / Enter or y]" in tui.text():
                    break
            tui.wait("all rows disclosed", lambda: "[Run / Enter or y]" in tui.text())
            tui.check(
                "intermediate page exposes title and model tails",
                "TITLE_END" in seen and "MODEL_END" in seen,
            )
            tui.check(
                "confirmation shows actual queued replies instead of only old task title",
                "Actual next-run instruction" in seen
                and "QUEUED_END" in seen
                and "Second queued reply" in seen
                and "OLD_SENT_INSTRUCTION" not in seen,
            )
            tui.send(b"G")
            tui.check(
                "paging reveals all identity suffixes without starting",
                "THREAD_END" in tui.text() and not marker.exists(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-reviewed"))
            resize(tui, 80, 20)
            tui.wait(
                "resize resets review", lambda: "[Review all details]" in tui.text()
            )
            tui.send(b"y")
            tui.check(
                "resizing cannot reuse review at another width", not marker.exists()
            )
            resize(tui, 88, 20)
            tui.wait("restored dialog", lambda: "1-16/" in tui.text())
            for _ in range(20):
                tui.send(b"\x06")
                if "[Run / Enter or y]" in tui.text():
                    break
            tui.send(b"\x1b[<0;25;19M")
            tui.wait("mouse cancel", lambda: "Confirm live run" not in tui.text())
            tui.check("Cancel remains clickable after paging", not marker.exists())
            tui.send(b"s")
            tui.wait("new review", lambda: "[Review all details]" in tui.text())
            tui.check(
                "reopening does not reuse earlier authorization",
                "[Run / Enter or y]" not in tui.text(),
            )
            for _ in range(20):
                tui.send(b"\x06")
                if "[Run / Enter or y]" in tui.text():
                    break
            tui.send(b"\x1b[<0;3;19M")
            tui.wait(
                "confirmed fake run",
                lambda: marker.exists() and "Ready 1" in tui.text(),
            )
            tui.send(b"e")
            tui.wait("confirmed chat", lambda: "Confirmed fixture answer" in tui.text())
            tui.check(
                "Run click queues the fixed harness after full disclosure",
                "Confirmed fixture answer" in tui.text(),
            )
            tui.send(b"q")
            tui.wait_exit()
            tui.check("terminal exits cleanly", tui.process.returncode == 0)
        with sqlite3.connect(database) as db:
            saved = json.loads(
                db.execute("SELECT payload FROM snapshot").fetchone()[0]
            )["tasks"][0]
        assert saved["state"] == "ready" and len(saved["runs"]) == 1
        assert saved["title"] == task["title"] and saved["model"] == task["model"]
        assert saved["thread"] == thread
        assert (workspace / "prompt.txt").read_text() == expected_prompt
        print("PASS: exact task, model, thread and prompt survive disclosure scrolling")
    print("Temporary fake harness only. No model, credentials or real checkout access.")


if __name__ == "__main__":
    main()
