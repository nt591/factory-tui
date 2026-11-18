#!/usr/bin/env python3
"""Check persistent destination tabs and draft-safe command navigation with fixtures."""

import argparse
import os
import subprocess
import tempfile
from pathlib import Path

from fixtures.terminal import Terminal


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-commands-ui-") as temporary:
        directory = Path(temporary)
        replay = directory / "empty.jsonl"
        replay.write_text("")
        home = directory / "home"
        home.mkdir()
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home), TMPDIR=str(directory))
        for columns in (60, 120, 240):
            with Terminal(
                [str(binary), "--no-config", "--events", str(replay)],
                env,
                columns=columns,
                rows=36,
            ) as tui:
                tui.ready()
                tui.check(
                    "both destinations are visible",
                    "Board" in tui.screen.display[1]
                    and "Archive" in tui.screen.display[1],
                )
                tui.check(
                    "navigation mode is explicit",
                    "NAVIGATION /" in tui.screen.display[-1],
                )
                tui.send(b"\r")
                tui.wait("insert mode", lambda: "INSERT /" in tui.screen.display[-1])
                tui.send(b"\x1b[200~Keep this reply\x1b[201~")
                tui.send(b"\x10")
                tui.wait("commands open", lambda: "Commands / Ctrl-P" in tui.text())
                tui.send(b"archive")
                tui.check(
                    "command distinguishes task action from destination",
                    "Open Archive" in tui.text()
                    and "Accept & archive task" in tui.text(),
                )
                if args.preview:
                    tui.preview(
                        args.preview.with_stem(
                            args.preview.stem + f"-{columns}-palette"
                        )
                    )
                tui.send(b"\x1b")
                tui.check(
                    "cancel returns to insert with draft",
                    "INSERT /" in tui.screen.display[-1]
                    and "Keep this reply" in tui.text(),
                )
                tui.send(b"\x1b")
                tui.check(
                    "Escape returns directly to board with draft",
                    "NAVIGATION /" in tui.screen.display[-1]
                    and "hjkl/arrows: cards" in tui.screen.display[-1]
                    and "Keep this reply" in tui.text(),
                )
                tui.send(b"\r")
                tui.check("Enter resumes insert", "INSERT /" in tui.screen.display[-1])
                tui.send(b"\x10archive\r")
                tui.wait(
                    "Archive area",
                    lambda: (
                        "Archive" in tui.screen.display[2]
                        and "tasks accepted" in tui.screen.display[2]
                    ),
                )
                tui.check(
                    "Archive command focuses navigation",
                    "NAVIGATION /" in tui.screen.display[-1],
                )
                if args.preview:
                    tui.preview(
                        args.preview.with_stem(
                            args.preview.stem + f"-{columns}-archive"
                        )
                    )
                tui.click_text("Board", row=1)
                tui.wait("Board area", lambda: "Session board" in tui.screen.display[2])
                tui.send(b"\x10reply\r")
                tui.check(
                    "Reply command restores saved draft",
                    "Keep this reply" in tui.text()
                    and "INSERT /" in tui.screen.display[-1],
                )
                tui.click_text("Archive", row=1)
                tui.check(
                    "Archive tab works directly from insert",
                    "tasks accepted" in tui.screen.display[2]
                    and "NAVIGATION /" in tui.screen.display[-1],
                )
                tui.send(b"\x1b")
                tui.check(
                    "Escape returns from Archive to Board",
                    "Session board" in tui.screen.display[2],
                )
                tui.send(b"\x10no-matching-command\r")
                tui.check(
                    "no matches cannot execute", "No matching commands" in tui.text()
                )
                tui.send(b"\x1b")
                tui.send(b"q")
                tui.wait_exit()
                tui.check(
                    "command navigation exits cleanly", tui.process.returncode == 0
                )
        assert list(home.iterdir()) == []
    print("Temporary replay only. No agents, credentials, network or real workspaces.")


if __name__ == "__main__":
    main()
