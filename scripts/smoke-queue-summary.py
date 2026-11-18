#!/usr/bin/env python3
"""Verify captured acknowledgement and next-turn reply counts in a replay TUI."""

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path

from fixtures.terminal import Terminal


def event(kind):
    return json.dumps({"task_id": "T-102", "run_id": "demo-102", "type": kind}) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-queue-summary-") as temporary:
        directory = Path(temporary)
        replay = directory / "events.jsonl"
        replay.write_text("")
        home = directory / "home"
        home.mkdir()
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home), TMPDIR=str(directory))
        with Terminal(
            [str(binary), "--no-config", "--events", str(replay)], env
        ) as tui:
            tui.ready()
            tui.send(b"e")
            tui.wait("captured queue", lambda: "1 awaiting ack · 0 next" in tui.text())
            tui.send(b"i")
            tui.send(b"\x1b[200~Reply for later turn\x1b[201~")
            tui.check(
                "draft alone does not change queued counts",
                "1 awaiting ack · 0 next" in tui.text(),
            )
            tui.send(b"\r")
            tui.wait(
                "later reply queued", lambda: "1 awaiting ack · 1 next" in tui.text()
            )
            tui.check(
                "queued reply leaves active task Working",
                "T-102 / Working / conversation" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-before-ack"))
            with replay.open("a") as output:
                output.write(event("turn.started"))
            tui.wait(
                "capture acknowledged",
                lambda: "Reply / next turn · 1 queued" in tui.text(),
            )
            tui.check(
                "acknowledgement changes original prompt to sent",
                "You / sent" in tui.text() and "Reply for later turn" in tui.text(),
            )
            tui.send(b"iAnother later reply\r")
            tui.wait(
                "second next-turn reply",
                lambda: "Reply / next turn · 2 queued" in tui.text(),
            )
            with replay.open("a") as output:
                output.write(event("run.interrupted"))
            tui.wait(
                "interrupted queue preserved",
                lambda: (
                    "T-102 / Needs you / conversation" in tui.text()
                    and "Reply / next turn · 2 queued" in tui.text()
                ),
            )
            tui.check(
                "replay queue summary cannot start a process",
                "FIXTURE REPLAY" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-after-stop"))
            tui.send(b"q")
            tui.wait_exit()
            tui.check(
                "queue summary fixture exits cleanly", tui.process.returncode == 0
            )
        assert list(home.iterdir()) == []
    print("Temporary replay only. No model, credentials or workspace operations.")


if __name__ == "__main__":
    main()
