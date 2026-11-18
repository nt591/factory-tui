#!/usr/bin/env python3
"""Verify the complete factory loop with temporary jj and a fake process, not a model."""

import argparse
import json
import os
import shutil
import sqlite3
import subprocess
import tempfile
from pathlib import Path

from fixtures.terminal import Terminal


def snapshot(database):
    with sqlite3.connect(database) as db:
        return json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    jj = shutil.which("jj")
    if jj is None:
        parser.error("jj must be installed for temporary workspace checks.")
    with tempfile.TemporaryDirectory(prefix="factory-workflow-") as temporary:
        directory = Path(temporary).resolve()
        source, parent, home = (
            directory / name for name in ("source", "tasks", "home")
        )
        for path in (source, parent, home):
            path.mkdir()
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home), TMPDIR=str(directory))
        subprocess.run(
            [jj, "git", "init", "--colocate", str(source)],
            env=env,
            check=True,
            capture_output=True,
        )
        (source / "source.txt").write_text("Original source content\n")
        subprocess.run(
            [jj, "-R", str(source), "describe", "-m", "Fixture source"],
            env=env,
            check=True,
            capture_output=True,
        )

        def source_commit():
            return subprocess.check_output(
                [
                    jj,
                    "--ignore-working-copy",
                    "-R",
                    str(source),
                    "log",
                    "-r",
                    "@",
                    "--no-graph",
                    "-T",
                    "commit_id",
                ],
                env=env,
                text=True,
            ).strip()

        original_commit = source_commit()
        database = directory / "board.sqlite"
        config = directory / "config.toml"
        config.write_text(
            "[storage]\ndatabase='board.sqlite'\n"
            f"[workspace]\njj={json.dumps(jj)}\nsource={json.dumps(str(source))}\n"
            f"parent={json.dumps(str(parent))}\nrevision='@'\nmodel='fixture-model'\n"
        )
        marker = directory / "invocations.jsonl"
        executable = directory / "fake-runner"
        executable.write_text(
            "#!/usr/bin/env python3\n"
            + f"""
import json
import pathlib
import sys
arguments = sys.argv[1:]
prompt = sys.stdin.read()
with pathlib.Path({str(marker)!r}).open('a') as output:
    output.write(json.dumps({{'arguments': arguments, 'prompt': prompt, 'cwd': str(pathlib.Path.cwd())}}) + '\\n')
pathlib.Path('implementation.txt').write_text('Reviewed fixture implementation\\n')
for event in [
    {{'type': 'thread.started', 'thread_id': 'workflow-thread'}},
    {{'type': 'turn.started'}},
    {{'type': 'item.completed', 'item': {{'type': 'agent_message', 'id': 'answer', 'text': 'Fixture implementation ready for review'}}}},
    {{'type': 'turn.completed'}},
]:
    print(json.dumps(event), flush=True)
"""
        )
        executable.chmod(0o700)
        command = [
            str(binary),
            "--live-ui",
            "--workspace-write",
            "--config",
            str(config),
            "--codex-executable",
            str(executable),
        ]
        with Terminal(command, env, columns=180, rows=50) as tui:
            tui.ready()
            tui.check(
                "new configured live board is empty and starts nothing",
                "Your factory starts here" in tui.text() and not marker.exists(),
            )
            tui.send(b"n")
            tui.wait("workspace form", lambda: "Source repository" in tui.text())
            tui.send(b"\t" * 4 + b"Implement the fixture task\x13")
            tui.wait(
                "workspace task created", lambda: "Workspace task created" in tui.text()
            )
            tui.check("creation does not execute the runner", not marker.exists())
            tui.send(b"s")
            tui.wait("run confirmation", lambda: "Confirm live run" in tui.text())
            tui.check(
                "confirmation names write policy and queued instruction",
                "WRITE ACCESS" in tui.text()
                and "Implement the fixture task" in tui.text()
                and not marker.exists(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-confirmation"))
            tui.send(b"\x1b")
            tui.check("cancelling confirmation starts nothing", not marker.exists())
            tui.send(b"s")
            tui.send(b"\x1b[6~" * 20)
            tui.send(b"y")
            tui.wait(
                "confirmed fixture completes",
                lambda: "/ Ready / conversation" in tui.text(),
            )
            tui.send(b"e")
            tui.wait(
                "fixture answer visible",
                lambda: "Fixture implementation ready for review" in tui.text(),
            )
            calls = [json.loads(line) for line in marker.read_text().splitlines()]
            tui.check(
                "one confirmed fake process receives exact instruction",
                len(calls) == 1 and calls[0]["prompt"] == "Implement the fixture task",
            )
            tui.check(
                "confirmed invocation carries requested workspace-write policy",
                'sandbox_mode="workspace-write"' in calls[0]["arguments"],
            )
            workspace = Path(calls[0]["cwd"])
            tui.check(
                "fixture change stays in isolated workspace",
                workspace.parent == parent
                and (workspace / "implementation.txt").exists()
                and not (source / "implementation.txt").exists(),
            )
            tui.send(b"vr")
            tui.wait(
                "real jj review",
                lambda: "+Reviewed fixture implementation" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-review"))
            tui.send(b"\x1b")
            tui.send(b"iRetained unsent draft\x1b")
            tui.send(b"a")
            tui.wait(
                "explicit acceptance", lambda: "/ Done / conversation" in tui.text()
            )
            tui.check(
                "accepted task retains read-only draft",
                "draft retained" in tui.text()
                and "i reply" not in tui.screen.display[-2],
            )
            tui.send(b"q")
            tui.wait_exit()
            tui.check("workflow exits successfully", tui.process.returncode == 0)
        saved = snapshot(database)
        task = saved["tasks"][0]
        assert len(saved["tasks"]) == 1 and task["state"] == "done"
        assert task["thread"] == "workflow-thread" and len(task["runs"]) == 1
        assert task["runs"][0]["simulated"] is False
        assert task["runs"][0]["policy"] == "workspace-write"
        assert saved["drafts"] == [[task["id"], "Retained unsent draft"]]
        with Terminal(command, env, columns=180, rows=50) as tui:
            tui.ready()
            tui.send(b"e")
            tui.wait(
                "accepted conversation restored",
                lambda: "Fixture implementation ready for review" in tui.text(),
            )
            tui.check(
                "restart never resumes accepted runner",
                len(marker.read_text().splitlines()) == 1,
            )
            tui.check(
                "restored task stays read-only",
                "draft retained" in tui.text()
                and "s confirm" not in tui.screen.display[-2]
                and "i reply" not in tui.screen.display[-2],
            )
            if args.preview:
                tui.preview(args.preview)
            tui.send(b"q")
            tui.wait_exit()
        assert snapshot(database) == saved
        assert source_commit() == original_commit
        assert (source / "source.txt").read_text() == "Original source content\n"
        assert (
            workspace / "implementation.txt"
        ).read_text() == "Reviewed fixture implementation\n"
        assert not (source / "implementation.txt").exists()
        print(
            "PASS: full create/confirm/run/review/accept/restart loop preserves source and exact SQLite history"
        )
    print(
        "Temporary jj/SQLite and fake executable only. No model, credentials, merge or push."
    )


if __name__ == "__main__":
    main()
