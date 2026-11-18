#!/usr/bin/env python3
"""Validate dry-run CLI behavior without executing an agent or reading user config."""
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
binary = root / "_build/default/bin/main.exe"
checks = 0


def check(name, value):
    global checks
    checks += 1
    if not value:
        raise AssertionError(name)


with tempfile.TemporaryDirectory(prefix="factory-preview-") as temp:
    directory = Path(temp)
    executable = directory / "must-not-run"
    marker = directory / "launched"
    executable.write_text(f"#!/bin/sh\ntouch '{marker}'\n")
    executable.chmod(0o700)
    base = [str(binary), "--dry-run-codex", "--codex-executable", str(executable),
            "--workspace", str(directory), "--model", "fixture-model"]
    result = subprocess.run(base, capture_output=True, text=True, timeout=3)
    check("dry-run succeeds without terminal", result.returncode == 0)
    preview = json.loads(result.stdout)
    check("process not launched", not marker.exists() and not preview["starts_process"])
    check("database not created", not list(directory.glob("*.sqlite*")))
    check("credential access disabled", not preview["reads_credentials"])
    check("working directory correct", preview["directory"] == str(directory))
    check("sandbox present", 'sandbox_mode="read-only"' in preview["arguments"])
    gateway = directory / "gateway.toml"
    gateway.write_text('base_url="http://127.0.0.1:4000/v1"\nkey_environment="FACTORY_UNSET_KEY"\n')
    result = subprocess.run(base + ["--resume", "explicit-thread", "--gateway", str(gateway)],
                            capture_output=True, text=True, timeout=3)
    check("gateway resume preview succeeds", result.returncode == 0)
    preview = json.loads(result.stdout)
    check("resume exact identity", preview["arguments"][:2] == ["exec", "resume"]
          and "explicit-thread" in preview["arguments"])
    check("environment reference preserved", 'model_providers.factory_gateway.env_key="FACTORY_UNSET_KEY"'
          in preview["arguments"])
    for extra in [["--workspace-write"], ["--database", str(directory / "forbidden.sqlite")], ["--snapshot"],
                  ["--fake-harness"], ["--live-ui"], ["--config", str(directory / "missing.toml")],
                  ["--resume", "--last"], ["--model", "-bad"]]:
        result = subprocess.run(base + extra, capture_output=True, text=True, timeout=3)
        check("unsafe or conflicting dry-run options rejected", result.returncode != 0)
    check("rejected checks create no database or process", not marker.exists()
          and not list(directory.glob("*.sqlite*")))
    gateway.write_text('api_key="accidental-secret"\n')
    result = subprocess.run(base + ["--gateway", str(gateway)], capture_output=True, text=True, timeout=3)
    check("invalid gateway rejected without echo", result.returncode != 0
          and "accidental-secret" not in result.stdout + result.stderr)
    result = subprocess.run([str(binary), "--model", "fixture-model"], capture_output=True, text=True, timeout=3)
    check("live options cannot silently fall back to simulation", result.returncode != 0)

print(f"Passed {checks} CLI invocation checks. No agent or gateway calls.")
