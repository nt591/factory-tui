#!/usr/bin/env python3
"""Check explicit CLI execution using a fake executable in a temporary workspace."""
import json
from pathlib import Path
import sqlite3
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


with tempfile.TemporaryDirectory(prefix="factory-cli-execution-") as temporary:
    directory = Path(temporary).resolve()
    database = directory / "board.sqlite"
    executable = directory / "fixture-codex"
    marker = directory / "launched"
    executable.write_text("""#!/bin/sh
cat > prompt.txt
touch launched
printf '%s\\n' '{"type":"thread.started","thread_id":"fixture-thread"}'
printf '%s\\n' '{"type":"turn.started"}'
printf '%s\\n' '{"type":"item.completed","item":{"type":"agent_message","id":"reply","text":"Fixture answer"}}'
printf '%s\\n' '{"type":"turn.completed"}'
""")
    executable.chmod(0o700)
    base = [str(binary), "--run-codex", "--codex-executable", str(executable),
            "--workspace", str(directory), "--model", "fixture-model",
            "--database", str(database)]
    for extra in [["--dry-run-codex"], ["--snapshot"], ["--fake-harness"], ["--live-ui"],
                  ["--config", str(directory / "missing.toml")]]:
        result = subprocess.run(base + extra, input="task", capture_output=True, text=True, timeout=3)
        check("execution conflicts rejected", result.returncode != 0)
    result = subprocess.run(base, input="", capture_output=True, text=True, timeout=3)
    check("empty prompt rejected before database creation", result.returncode != 0 and not database.exists())
    check("invalid modes start no executable", not marker.exists())
    result = subprocess.run(base, input="Initial task", capture_output=True, text=True, timeout=5)
    check("explicit execution succeeds", result.returncode == 0)
    summary = json.loads(result.stdout)
    check("execution summary reports Ready", summary["state"] == "Ready" and summary["succeeded"])
    check("conversation is not printed", "Fixture answer" not in result.stdout)
    with sqlite3.connect(database) as db:
        saved = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        check("ordered execution events persisted", db.execute("SELECT count(*) FROM events").fetchone()[0] == 5)
    task = saved["tasks"][0]
    check("execution origin recorded", task["runs"][0]["simulated"] is False)
    check("message author is not simulated", task["messages"][-1]["author"] == "Codex")
    result = subprocess.run(base + ["--resume", "fixture-thread"], input="Follow up",
                            capture_output=True, text=True, timeout=5)
    check("explicit resume succeeds", result.returncode == 0)
    resumed = json.loads(result.stdout)
    check("resume retains task identity", resumed["task_id"] == summary["task_id"])
    check("resume submits only new prompt", (directory / "prompt.txt").read_text() == "Follow up")
    result = subprocess.run(base + ["--resume", "unknown-thread"], input="Follow up",
                            capture_output=True, text=True, timeout=5)
    check("unknown resume rejected", result.returncode != 0)
    executable.write_text("#!/bin/sh\ncat >/dev/null\nexit 0\n")
    result = subprocess.run(base, input="Incomplete turn", capture_output=True, text=True, timeout=5)
    check("exit zero alone returns failure", result.returncode == 1
          and json.loads(result.stdout)["state"] == "Needs you")

print(f"Passed {checks} CLI execution checks. Fake executable; no model calls.")
