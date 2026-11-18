#!/usr/bin/env python3
"""Validate setup CLI using temporary configuration without opening its resources."""

import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "_build/default/bin/main.exe"
checks = 0


def check(name, condition):
    global checks
    checks += 1
    if not condition:
        raise AssertionError(name)


with tempfile.TemporaryDirectory(prefix="factory-check-config-") as temporary:
    directory = Path(temporary).resolve()
    home = directory / "home"
    home.mkdir()
    config = directory / "config.toml"
    marker = directory / "launched"
    executable = directory / "must-not-run"
    executable.write_text(f"#!/bin/sh\ntouch '{marker}'\n")
    executable.chmod(0o700)
    database = directory / "board.sqlite"
    database.write_bytes(b"Not a database; check must not open this file.")
    env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
    env.update(HOME=str(home), XDG_CONFIG_HOME=str(home))
    config.write_text(
        "[storage]\ndatabase='board.sqlite'\n"
        f"[workspace]\njj='{executable}'\nsource='missing-source'\nparent='~/tasks'\n"
        "revision='main@origin'\nmodel='fixture-model'\n"
        "[layout]\nboard_width_percent=55\nboard_height_percent=40\n"
    )
    before = database.read_bytes()

    def run(extra=()):
        return subprocess.run(
            [str(BINARY), "--check-config", str(config), *extra],
            check=False,
            env=env,
            cwd=directory,
            capture_output=True,
            text=True,
            timeout=5,
        )

    result = run()
    check("config check needs no terminal", result.returncode == 0)
    preview = json.loads(result.stdout)
    check(
        "resolved database path uses config directory",
        preview["storage"]["database"] == str(database),
    )
    check(
        "resolved workspace source uses config directory",
        preview["workspace"]["source"] == str(directory / "missing-source"),
    )
    check(
        "workspace home expansion uses isolated HOME",
        preview["workspace"]["parent"] == str(home / "tasks"),
    )
    check(
        "revision and model retained",
        preview["workspace"]["revision"] == "main@origin"
        and preview["workspace"]["model"] == "fixture-model",
    )
    check(
        "layout values retained",
        preview["layout"] == {"board_width_percent": 55, "board_height_percent": 40},
    )
    check(
        "preview discloses no side effects or compatibility check",
        all(
            preview[key] is False
            for key in (
                "opens_database",
                "starts_process",
                "checks_path_existence",
                "checks_gateway_compatibility",
            )
        ),
    )
    result = run(["--database", "override.sqlite"])
    check(
        "CLI override accepted without creating database",
        result.returncode == 0
        and json.loads(result.stdout)["storage"]["database"]
        == str(directory / "override.sqlite")
        and not (directory / "override.sqlite").exists(),
    )
    check(
        "config check never opens or repairs database", database.read_bytes() == before
    )
    check(
        "config check never runs jj or creates workspace",
        not marker.exists()
        and not (home / "tasks").exists()
        and not (directory / "missing-source").exists(),
    )
    for extra in (
        ["--live-ui"],
        ["--run-codex"],
        ["--dry-run-codex"],
        ["--snapshot"],
        ["--fake-harness"],
        ["--events", str(marker)],
        ["--config", str(config)],
        ["--no-config"],
        ["--check-gateway", str(config)],
        ["--codex-executable", str(executable)],
        ["--workspace", str(directory)],
        ["--model", "fixture"],
        ["--resume", "thread"],
        ["--gateway", str(config)],
        ["--workspace-write"],
    ):
        result = run(extra)
        check(
            "conflicting modes fail before side effects",
            result.returncode == 2
            and result.stdout == ""
            and not marker.exists()
            and database.read_bytes() == before,
        )
    for text in (
        "secret='must-not-echo'",
        "[storage]\ndatabase=123",
        "broken = ['must-not-echo'",
        "[workspace]\nmodel='-bad'",
        "[layout]\nboard_width_percent=99",
    ):
        config.write_text(text)
        result = run()
        check(
            "invalid config fails without printing source",
            result.returncode == 2
            and result.stdout == ""
            and "must-not-echo" not in result.stderr,
        )
    config.write_text("")
    preview = json.loads(run().stdout)
    check(
        "empty config previews memory-only defaults",
        preview["storage"]["database"] is None
        and all(value is None for value in preview["workspace"].values())
        and all(value is None for value in preview["layout"].values()),
    )
    config.unlink()
    check("missing explicit config fails", run().returncode == 2)
    config.mkdir()
    check("directory config fails", run().returncode == 2)
    check("isolated HOME remains empty", list(home.iterdir()) == [])

print(
    f"Passed {checks} setup-config CLI checks. Temporary files only; no agents, credentials or workspace operations."
)
