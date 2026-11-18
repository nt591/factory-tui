#!/usr/bin/env python3
"""Check default real startup and explicit demo isolation without agent calls."""

import argparse
import os
import sqlite3
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
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-default-mode-") as temporary:
        directory = Path(temporary).resolve()
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(
            HOME=str(directory), XDG_CONFIG_HOME=str(directory), TMPDIR=str(directory)
        )
        result = subprocess.run(
            [str(binary)],
            env=env,
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
        print("Fixture default diagnostic:", result.stderr.strip())
        assert (
            result.returncode == 2
            and "setup.sh" in result.stderr
            and result.stdout == ""
        )
        database = directory / "board.sqlite"
        with Terminal(
            [str(binary), "--demo", "--no-config", "--database", str(database)], env
        ) as tui:
            tui.ready()
            assert "SIMULATION" in tui.text()
            tui.send(b"q")
            tui.wait_exit()
        with sqlite3.connect(database) as db:
            before = db.execute("SELECT payload FROM snapshot").fetchone()[0]
        marker = directory / "must-not-run"
        executable = directory / "codex"
        executable.write_text(f"#!/bin/sh\ntouch '{marker}'\n")
        executable.chmod(0o700)
        config = directory / "config.toml"
        config.write_text(
            '[storage]\ndatabase="board.sqlite"\n[codex]\nexecutable="codex"\n'
        )
        with Terminal([str(binary), "--config", str(config)], env) as tui:
            tui.wait_exit()
            assert (
                tui.process.returncode == 2
                and "demo run history" in tui.text()
                and not marker.exists()
            )
        with sqlite3.connect(database) as db:
            assert db.execute("SELECT payload FROM snapshot").fetchone()[0] == before
        with Terminal([str(binary), "--demo", "--config", str(config)], env) as tui:
            tui.ready()
            assert "SIMULATION" in tui.text()
            tui.send(b"q")
            tui.wait_exit()
        assert not marker.exists()
    print(
        "PASS: default setup guidance, explicit demo, and refusal to reinterpret stored demo runs as real work."
    )


if __name__ == "__main__":
    main()
