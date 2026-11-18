#!/usr/bin/env python3
"""Verify TOML layout discovery, reset, and no-write behavior in isolated terminals."""

import argparse
import os
import subprocess
import tempfile
from pathlib import Path

from fixtures.terminal import Terminal


def chat_row(tui):
    return next(
        index
        for index, row in enumerate(tui.screen.display)
        if " / conversation" in row
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-layout-config-") as temporary:
        directory = Path(temporary).resolve()
        home = directory / "home"
        home.mkdir()
        xdg = directory / "xdg"
        config_dir = xdg / "factory-tui"
        config_dir.mkdir(parents=True)
        config = config_dir / "config.toml"
        configured = b"[layout]\nboard_width_percent=55\nboard_height_percent=40\n"
        config.write_bytes(configured)
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(xdg), TMPDIR=str(directory))
        command = [str(binary)]
        with Terminal(command, env) as tui:
            tui.ready()
            tui.wait("default layout config discovered", lambda: chat_row(tui) == 15)
            tui.check(
                "layout config does not enable execution", "SIMULATION" in tui.text()
            )
            tui.send(b"3\x17+")
            tui.wait("runtime adjustment", lambda: chat_row(tui) == 18)
            tui.check(
                "runtime resize does not write config",
                config.read_bytes() == configured,
            )
            tui.send(b"\x17=")
            tui.wait(
                "configured reset",
                lambda: (
                    chat_row(tui) == 15
                    and "Configured pane sizes restored" in tui.text()
                ),
            )
            tui.send(b"?\tG")
            tui.wait(
                "settings layout disclosure",
                lambda: (
                    "Board width: 55%" in tui.text()
                    and "Board height: 40%" in tui.text()
                ),
            )
            tui.check(
                "settings disclose the no-write boundary",
                "No config is written" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-settings"))
            tui.send(b"\x1b")
            modified = b"[layout]\nboard_width_percent=60\nboard_height_percent=45\n"
            config.write_bytes(modified)
            tui.send(b"\x17+")
            tui.send(b"\x17=")
            tui.check(
                "running reset uses launch defaults, not edited disk config",
                chat_row(tui) == 15 and config.read_bytes() == modified,
            )
            tui.send(b"q")
            tui.wait_exit()
        with Terminal(command, env) as tui:
            tui.ready()
            tui.wait("changed config on next launch", lambda: chat_row(tui) == 17)
            tui.check(
                "next launch reads revised percentage", config.read_bytes() == modified
            )
            tui.send(b"q")
            tui.wait_exit()
        with Terminal(command + ["--no-config"], env) as tui:
            tui.ready()
            tui.wait("no-config automatic layout", lambda: chat_row(tui) == 19)
            tui.check(
                "no-config preserves config bytes", config.read_bytes() == modified
            )
            tui.send(b"q")
            tui.wait_exit()
        explicit = directory / "explicit.toml"
        explicit.write_bytes(configured)
        with Terminal(
            command + ["--config", str(explicit)], env, columns=240, rows=50
        ) as tui:
            tui.ready()
            title = next(row for row in tui.screen.display if " / conversation" in row)
            tui.check(
                "explicit config applies wide board proportion",
                title.index("T-102 / Working / conversation") == 145,
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-wide"))
            tui.send(b"q")
            tui.wait_exit()
        executable = directory / "must-not-run"
        marker = directory / "agent-started"
        executable.write_text("#!/bin/sh\ntouch '" + str(marker) + "'\nexit 1\n")
        executable.chmod(0o700)
        database = directory / "live.sqlite"
        with Terminal(
            command
            + [
                "--config",
                str(explicit),
                "--database",
                str(database),
                "--live-ui",
                "--codex-executable",
                str(executable),
            ],
            env,
        ) as tui:
            tui.ready()
            tui.check(
                "live CLI uses layout config with explicit storage",
                "LIVE ENABLED" in tui.text()
                and "Your factory starts here" in tui.text(),
            )
            tui.send(b"?\tG")
            tui.wait(
                "live configured defaults", lambda: "Board height: 40%" in tui.text()
            )
            tui.check("live setup and layout start no process", not marker.exists())
            tui.send(b"\x1b")
            tui.send(b"q")
            tui.wait_exit()
        invalid = directory / "invalid.toml"
        invalid.write_text("[layout]\nboard_height_percent='hidden-layout-secret'\n")
        result = subprocess.run(
            command
            + [
                "--config",
                str(invalid),
                "--database",
                str(directory / "invalid.sqlite"),
            ],
            env=env,
            check=False,
            capture_output=True,
            text=True,
            timeout=3,
        )
        assert result.returncode != 0 and "integers from 10 to 90" in result.stderr
        assert "hidden-layout-secret" not in result.stdout + result.stderr
        assert not (directory / "invalid.sqlite").exists()
        assert explicit.read_bytes() == configured and config.read_bytes() == modified
        print("PASS: invalid defaults fail without exposing source or creating storage")
        print("PASS: layout-only launches create no extra databases or user config")
        assert sorted(path.name for path in directory.glob("*.sqlite")) == [
            "live.sqlite"
        ]
        assert list(home.iterdir()) == []
    print(
        "Temporary configs and local executable fixture only. No agent or credentials used."
    )


if __name__ == "__main__":
    main()
