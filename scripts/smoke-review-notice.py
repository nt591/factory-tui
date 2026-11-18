#!/usr/bin/env python3
"""Verify readable review failures and explicit retry with a temporary jj fixture."""

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


def click(tui, label):
    y = next(index for index, row in enumerate(tui.screen.display) if label in row)
    x = tui.screen.display[y].index(label)
    tui.send(f"\x1b[<0;{x + 1};{y + 1}M".encode())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-review-notice-") as temporary:
        directory = Path(temporary).resolve()
        home = directory / "home"
        workspace = directory / "workspace"
        home.mkdir()
        workspace.mkdir()
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
        with sqlite3.connect(database) as db:
            saved = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
            task = next(task for task in saved["tasks"] if task["state"] == "queued")
            task.update(
                repository=str(directory / "source"),
                workspace={
                    "source": str(directory / "source"),
                    "directory": str(workspace),
                    "base": "a" * 40,
                    "name": "fixture",
                },
            )
            saved.update(tasks=[task], selected=task["id"], drafts=[])
            db.execute("UPDATE snapshot SET payload=?", (json.dumps(saved),))
        executable = directory / "fake-jj"
        count = workspace / "calls"
        executable.write_text(
            "#!/bin/sh\nprintf 'call\\n' >> calls\nprintf 'PRIVATE_FIXTURE_OUTPUT\\n'\nexit 1\n"
        )
        executable.chmod(0o700)
        with Terminal(command, env, columns=60, rows=20) as tui:
            tui.ready()
            tui.send(b"v")
            tui.wait(
                "review path editor",
                lambda: "CHANGES /" in tui.text() and "jj:" in tui.text(),
            )
            tui.check("opening review starts no command", not count.exists())
            tui.send(b"\x1b[200~" + str(executable).encode() + b"\x1b[201~")
            tui.check("pasted executable path starts no command", not count.exists())
            click(tui, "[Close / Esc]")
            tui.wait("mouse closes path editor", lambda: "CHANGES /" not in tui.text())
            tui.check("path editor Close starts no command", not count.exists())
            tui.send(b"v")
            tui.wait("review reopened", lambda: "[Refresh / r]" in tui.text())
            tui.send(b"\r")
            tui.wait(
                "review error", lambda: "Changes error: jj command failed" in tui.text()
            )
            tui.check(
                "complete failure guidance wraps into body",
                "inspection." in tui.text() and "explicitly." in tui.text(),
            )
            tui.check(
                "command output stays private",
                "PRIVATE_FIXTURE_OUTPUT" not in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-error"))
            resize(tui, 30, 10)
            tui.wait(
                "narrow review",
                lambda: "CHANGES /" in tui.text() and "Changes error:" in tui.text(),
            )
            tui.send(b"G")
            tui.wait("error last page", lambda: "explicitly." in tui.text())
            tui.check(
                "End pages wrapped notice without retry",
                count.read_text().count("call") == 1,
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-tail"))
            tui.send(b"g\x06")
            tui.wait("notice page down", lambda: "inspection." in tui.text())
            tui.check(
                "Ctrl-F pages notices without command side effects",
                count.read_text().count("call") == 1,
            )
            resize(tui, 60, 20)
            tui.send(b"g")
            tui.wait(
                "review error restored",
                lambda: "Changes error: jj command failed" in tui.text(),
            )
            executable.write_text(
                "#!/bin/sh\nprintf 'call\\n' >> calls\nprintf '%s\\n' 'diff --git a/fixture.txt b/fixture.txt' '--- a/fixture.txt' '+++ b/fixture.txt' '@@ -0,0 +1 @@' '+Fixture patch line'\n"
            )
            tui.check(
                "changing fixture does not automatically retry",
                count.read_text().count("call") == 1,
            )
            resize(tui, 30, 10)
            tui.wait(
                "compact complete controls",
                lambda: "[Refresh]  [jj]  [Close]" in tui.text(),
            )
            click(tui, "[Refresh]")
            tui.wait(
                "fixture patch loaded", lambda: "diff --git a/fixture" in tui.text()
            )
            tui.send(b"G")
            tui.wait(
                "explicit retry returns patch",
                lambda: "+Fixture patch line" in tui.text(),
            )
            tui.check(
                "retry replaces notices with unwrapped patch lines",
                count.read_text().count("call") == 2
                and "Changes error:" not in tui.text(),
            )
            click(tui, "[jj]")
            tui.wait(
                "compact editor close control", lambda: "[Close / Esc]" in tui.text()
            )
            click(tui, "[Close / Esc]")
            tui.wait("compact mouse close", lambda: "CHANGES /" not in tui.text())
            tui.check(
                "compact editor and Close never refresh",
                count.read_text().count("call") == 2,
            )
            tui.send(b"v")
            tui.wait(
                "compact review reopened",
                lambda: "[Refresh]  [jj]  [Close]" in tui.text(),
            )
            executable.write_text("#!/bin/sh\nprintf 'call\n' >> calls\n")
            tui.send(b"r")
            tui.wait("empty patch notice", lambda: "No changes relative" in tui.text())
            resize(tui, 20, 9)
            tui.send(b"gG")
            tui.wait("empty-result last page", lambda: "recorded base." in tui.text())
            tui.check(
                "End pages the empty-result notice despite empty patch document",
                count.read_text().count("call") == 3,
            )
            tui.send(b"\x1b")
            tui.send(b"q")
            tui.wait_exit()
        with sqlite3.connect(database) as db:
            final = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        assert final["tasks"] == saved["tasks"] and final["drafts"] == []
        assert sorted(path.name for path in workspace.iterdir()) == ["calls"]
        assert list(home.iterdir()) == []
        print("PASS: review error/retry changes no stored task, run or draft")
    print("Temporary fake jj only. No real repository, agent or credentials accessed.")


if __name__ == "__main__":
    main()
