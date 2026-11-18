#!/usr/bin/env python3
"""Verify Enter sends directly under configured policy without per-run prompts."""

import argparse
import json
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
    repo = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(repo / "scripts/build.sh")], check=True)
    binary = (args.binary or repo / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-send-") as temporary:
        directory = Path(temporary).resolve()
        home = directory / "home"
        home.mkdir()
        root = directory / "work"
        root.mkdir()
        marker = directory / "calls"
        executable = directory / "fake-codex"
        executable.write_text(
            "#!/usr/bin/env python3\n"
            + f"""
import json, pathlib, sys
prompt = sys.stdin.read()
with pathlib.Path({str(marker)!r}).open('a') as out:
    out.write(json.dumps({{'prompt':prompt,'arguments':sys.argv[1:]}})+'\\n')
for event in [{{'type':'thread.started','thread_id':'send-thread'}},{{'type':'turn.started'}},
    {{'type':'item.completed','item':{{'type':'agent_message','id':'reply','text':'Answer: '+prompt}}}},
    {{'type':'turn.completed'}}]:
    print(json.dumps(event),flush=True)
"""
        )
        executable.chmod(0o700)
        (directory / "codex").symlink_to(executable)
        config = directory / "config.toml"
        config.write_text(
            '[storage]\ndatabase="board.sqlite"\n[workspace]\nmode="folder"\nsource='
            + json.dumps(str(root))
            + '\nmodel="fixture-model"\n'
        )
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home), TMPDIR=str(directory))
        env["PATH"] = str(directory) + os.pathsep + env.get("PATH", os.defpath)
        command = [str(binary), "--config", str(config)]
        with Terminal(command, env) as tui:
            tui.ready()
            assert not marker.exists()
            tui.send(b"n")
            tui.send(b"First question\r")
            tui.wait(
                "first answer",
                lambda: (
                    "Answer: First question" in tui.text()
                    and "/ Ready / conversation" in tui.text()
                ),
            )
            tui.check(
                "Enter creates and runs without a confirmation popup",
                "Confirm live run" not in tui.text(),
            )
            tui.send(b"iSecond question\r")
            tui.wait(
                "followup answer",
                lambda: (
                    "Answer: Second question" in tui.text()
                    and "/ Ready / conversation" in tui.text()
                ),
            )
            calls = [json.loads(line) for line in marker.read_text().splitlines()]
            assert [call["prompt"] for call in calls] == [
                "First question",
                "Second question",
            ]
            assert calls[1]["arguments"][:2] == ["exec", "resume"]
            assert all(
                'sandbox_mode="read-only"' in call["arguments"] for call in calls
            )
            if args.preview:
                tui.preview(args.preview)
            tui.send(b"q")
            tui.wait_exit()
        with Terminal(command, env) as tui:
            tui.ready()
            assert len(marker.read_text().splitlines()) == 2
            tui.send(b"q")
            tui.wait_exit()
        with sqlite3.connect(directory / "board.sqlite") as db:
            saved = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        assert len(saved["tasks"][0]["runs"]) == 2
        assert list(root.iterdir()) == []
    print(
        "PASS: default real UI, Enter-to-run, idle reply resume, configured read-only policy and request-free restart. Fake executable only."
    )


if __name__ == "__main__":
    main()
