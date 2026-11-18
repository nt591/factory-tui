#!/usr/bin/env python3
"""Exercise the setup wizard and generated live launch with temporary fixtures."""

import argparse
import http.server
import json
import os
import sqlite3
import stat
import subprocess
import tempfile
import threading
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
        (directory / "codex").symlink_to(codex)
        env = {
            name: os.environ[name] for name in ("PATH", "LANG") if name in os.environ
        }
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home), TMPDIR=str(directory))
        env["PATH"] = str(directory) + os.pathsep + env.get("PATH", os.defpath)
        config_dir = directory / "config"
        command = [
            str(root / "scripts/setup.sh"),
            "--binary",
            str(binary),
            "--config-dir",
            str(config_dir),
        ]
        answers = [
            "",
            "",
            "manual",
            "fixture-model",
            "",
            "",
            "no",
        ]
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
        assert settings["workspace"]["source"] is None
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
        launch = directory / "launch"
        launch.write_text(
            "#!/bin/sh\ncd "
            + str(session)
            + "\nexec "
            + str(binary)
            + ' --live-ui --config "'
            + str(config)
            + '"\n'
        )
        launch.chmod(0o700)
        with Terminal([str(launch)], env) as tui:
            tui.ready()
            tui.send(b"n")
            tui.wait("wizard-selected folder mode", lambda: "FOLDER ROOT" in tui.text())
            tui.check(
                "setup uses launch cwd without agent launch",
                not marker.exists() and "Starting directory" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview)
            tui.send(b"Task from first launch directory\x13")
            tui.wait("cwd task created", lambda: "Workspace task created" in tui.text())
            tui.send(b"q")
            tui.wait_exit()
            assert tui.process.returncode == 0
        with sqlite3.connect(config_dir / "board.sqlite") as db:
            saved = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        assert saved["tasks"][0]["session_root"] == str(session)
        second = directory / "second-project"
        second.mkdir()
        launch.write_text(launch.read_text().replace(str(session), str(second)))
        with Terminal([str(launch)], env) as tui:
            tui.ready()
            tui.send(b"n")
            tui.wait("second launch creation form", lambda: "FOLDER ROOT" in tui.text())
            tui.send(b"Task from second launch directory\x13")
            tui.wait(
                "second cwd task created",
                lambda: "Workspace task created" in tui.text(),
            )
            tui.send(b"q")
            tui.wait_exit()
        with sqlite3.connect(config_dir / "board.sqlite") as db:
            saved = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        assert [task["session_root"] for task in saved["tasks"]] == [
            str(session),
            str(second),
        ]
        assert all(task["runs"] == [] for task in saved["tasks"])
        assert list(second.iterdir()) == []
        assert list(session.iterdir()) == [] and not marker.exists()
        assert (config.read_bytes(), gateway.read_bytes()) == before
        calls = []

        class Catalogue(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                calls.append((self.path, self.headers.get("Authorization")))
                body = b'{"data":[{"id":"fixture-api"},{"id":"fixture-worker"}]}'
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Catalogue) as server:
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                env.update(
                    LITELLM_BASE_URL=f"http://127.0.0.1:{server.server_port}/v1",
                    LITELLM_API_KEY="dummy-wizard-key",
                )
                discovered = directory / "discovered"
                answers = [
                    "",
                    "",
                    "fetch",
                    "worker",
                    "1",
                    "",
                    "",
                    "yes",
                ]
                result = subprocess.run(
                    [*command[:-1], str(discovered)],
                    input="\n".join(answers) + "\n",
                    env=env,
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=20,
                )
                assert result.returncode == 0, result.stderr
                assert calls == [("/v1/models", "Bearer dummy-wizard-key")]
                assert (
                    'model = "fixture-worker"'
                    in (discovered / "config.toml").read_text()
                )
                assert "dummy-wizard-key" not in result.stdout + result.stderr
                assert (
                    "dummy-wizard-key" not in (discovered / "gateway.toml").read_text()
                )
                skipped = directory / "skipped"
                answers = ["", "", "skip", "", "", "yes"]
                result = subprocess.run(
                    [*command[:-1], str(skipped)],
                    input="\n".join(answers) + "\n",
                    env=env,
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                assert result.returncode == 0 and len(calls) == 1
                assert "model =" not in (skipped / "config.toml").read_text()
                with Terminal(
                    [
                        str(binary),
                        "--live-ui",
                        "--config",
                        str(skipped / "config.toml"),
                    ],
                    env,
                ) as tui:
                    tui.ready()
                    tui.send(b"n")
                    tui.wait(
                        "skipped default form", lambda: "FOLDER ROOT" in tui.text()
                    )
                    tui.check(
                        "no model default requires task selection, not a placeholder",
                        "coding-large" not in tui.text()
                        and "your-model-id" not in tui.text(),
                    )
                    tui.send(b"\x1b")
                    tui.send(b"q")
                    tui.wait_exit()
                assert len(calls) == 1 and not marker.exists()
            finally:
                server.shutdown()
                worker.join()
    print(
        "PASS: wizard cancel/save/overwrite refusal/private config and live form defaults. Loopback discovery/dummy key only; no real gateway or agents."
    )


if __name__ == "__main__":
    main()
