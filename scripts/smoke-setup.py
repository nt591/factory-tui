#!/usr/bin/env python3
"""Exercise the setup wizard and generated live launch with temporary fixtures."""

import argparse
import json
import os
import stat
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
    with tempfile.TemporaryDirectory(prefix="factory-wizard-") as temporary:
        directory = Path(temporary).resolve()
        home, session = directory / "home", directory / "session"
        home.mkdir()
        session.mkdir()
        marker = directory / "must-not-run"
        codex = directory / "fake-codex"
        codex.write_text(f"#!/bin/sh\ntouch '{marker}'\nexit 2\n")
        codex.chmod(0o700)
        env = {
            name: os.environ[name] for name in ("PATH", "LANG") if name in os.environ
        }
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home), TMPDIR=str(directory))
        config_dir = directory / "config"
        command = [
            str(root / "scripts/setup.sh"),
            "--binary",
            str(binary),
            "--config-dir",
            str(config_dir),
        ]
        answers = [str(codex), "", "", "fixture-model", "", "", str(session), "", "no"]
        result = subprocess.run(
            command,
            input="\n".join(answers) + "\n",
            env=env,
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert (
            result.returncode == 0 and not config_dir.exists() and not marker.exists()
        )
        answers[-1] = "yes"
        result = subprocess.run(
            command,
            input="\n".join(answers) + "\n",
            env=env,
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, result.stderr
        config = config_dir / "config.toml"
        gateway = config_dir / "gateway.toml"
        assert not (config_dir / "board.sqlite").exists() and not marker.exists()
        assert (
            stat.S_IMODE(config.stat().st_mode)
            == stat.S_IMODE(gateway.stat().st_mode)
            == 0o600
        )
        assert 'key_environment = "LITELLM_API_KEY"' in gateway.read_text()
        preview = subprocess.run(
            [str(binary), "--check-config", str(config)],
            env=env,
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert preview.returncode == 0
        settings = json.loads(preview.stdout)
        assert settings["workspace_mode"] == "folder"
        assert settings["workspace"]["source"] == str(session)
        assert settings["codex"]["reasoning_effort"] == "low"
        before = config.read_bytes(), gateway.read_bytes()
        result = subprocess.run(
            command,
            input="",
            env=env,
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert (
            result.returncode == 2
            and (config.read_bytes(), gateway.read_bytes()) == before
        )
        # A loopback endpoint is configured, but opening the UI must make no request.
        env["LITELLM_BASE_URL"] = "http://127.0.0.1:1/v1"
        with Terminal([str(binary), "--live-ui", "--config", str(config)], env) as tui:
            tui.ready()
            tui.send(b"n")
            tui.wait("wizard-selected folder mode", lambda: "FOLDER ROOT" in tui.text())
            tui.check(
                "setup defaults reach TUI without agent launch", not marker.exists()
            )
            if args.preview:
                tui.preview(args.preview)
            tui.send(b"\x1b")
            tui.send(b"q")
            tui.wait_exit()
            assert tui.process.returncode == 0
        assert list(session.iterdir()) == [] and not marker.exists()
        assert (config.read_bytes(), gateway.read_bytes()) == before
    print(
        "PASS: wizard cancel/save/overwrite refusal/private config and live form defaults. No real keys, network or agents."
    )


if __name__ == "__main__":
    main()
