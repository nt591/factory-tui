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
        release = directory / "release-followup"
        executable = directory / "fake-runner"
        executable.write_text(
            "#!/usr/bin/env python3\n"
            + f"""
import json
import pathlib
import sys
import time
arguments = sys.argv[1:]
prompt = sys.stdin.read()
with pathlib.Path({str(marker)!r}).open('a') as output:
    output.write(json.dumps({{'arguments': arguments, 'prompt': prompt, 'cwd': str(pathlib.Path.cwd())}}) + '\\n')
resumed = arguments[:2] == ['exec', 'resume']
if resumed:
    print(json.dumps({{'type': 'turn.started'}}), flush=True)
    deadline = time.monotonic() + 15
    while not pathlib.Path({str(release)!r}).exists():
        if time.monotonic() >= deadline:
            raise RuntimeError('The workflow did not release the follow-up fixture.')
        time.sleep(0.01)
if resumed:
    pathlib.Path('followup.txt').write_text('Reviewed follow-up implementation\\n')
else:
    pathlib.Path('implementation.txt').write_text('Reviewed fixture implementation\\n')
answer = 'Fixture follow-up ready for review' if resumed else 'Fixture implementation ready for review'
for event in [
    {{'type': 'thread.started', 'thread_id': 'workflow-thread'}},
    {{'type': 'turn.started'}},
    {{'type': 'item.completed', 'item': {{'type': 'agent_message', 'id': 'answer', 'text': answer}}}},
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
            first_task = snapshot(database)["tasks"][0]
            first_record = first_task["runs"][0]
            first_messages = first_task["messages"]
            tui.send(b"m\x1b[H")
            tui.send(b"\x1b[200~followup-\x1b[201~\r")
            tui.send(b"iAdd the follow-up file\r")
            tui.check(
                "queueing a follow-up and changing model do not start a run",
                len(marker.read_text().splitlines()) == 1,
            )
            tui.send(b"s")
            tui.wait("follow-up confirmation", lambda: "Confirm live run" in tui.text())
            tui.check(
                "follow-up confirmation discloses resume and new model",
                "workflow-thread" in tui.text()
                and "followup-fixture-model" in tui.text()
                and "Add the follow-up file" in tui.text(),
            )
            tui.send(b"\x1b[6~" * 20 + b"y")
            tui.wait(
                "follow-up run is Working",
                lambda: (
                    "/ Working / conversation" in tui.text()
                    and len(marker.read_text().splitlines()) == 2
                ),
            )
            tui.send(b"iQueue this for a later turn\r")
            tui.wait(
                "reply queued during work",
                lambda: (
                    "Queue this for a later turn" in tui.text()
                    and "/ Working / conversation" in tui.text()
                ),
            )
            tui.wait(
                "working queued reply saved",
                lambda: any(
                    message["text"] == "Queue this for a later turn"
                    for message in snapshot(database)["tasks"][0]["messages"]
                ),
            )
            working_task = snapshot(database)["tasks"][0]
            late_message = next(
                message
                for message in working_task["messages"]
                if message["text"] == "Queue this for a later turn"
            )
            tui.check(
                "Working checkpoint retains reply outside active submission",
                working_task["state"] == "working"
                and late_message["queued"]
                and late_message["id"] not in working_task["active"]["submitted"],
            )
            tui.check(
                "working reply does not spawn another process or alter captured prompt",
                len(marker.read_text().splitlines()) == 2
                and json.loads(marker.read_text().splitlines()[1])["prompt"]
                == "Add the follow-up file",
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-working"))
            release.touch()
            tui.wait(
                "follow-up run completes",
                lambda: (
                    "Fixture follow-up ready for review" in tui.text()
                    and "/ Ready / conversation" in tui.text()
                ),
            )
            calls = [json.loads(line) for line in marker.read_text().splitlines()]
            tui.check(
                "second confirmed run resumes exact thread with only new prompt",
                len(calls) == 2
                and calls[1]["arguments"][:2] == ["exec", "resume"]
                and calls[1]["arguments"][-2:] == ["workflow-thread", "-"]
                and calls[1]["prompt"] == "Add the follow-up file"
                and calls[1]["cwd"] == str(workspace),
            )
            model_index = calls[1]["arguments"].index("--model")
            tui.check(
                "second invocation captures changed next-run model",
                calls[1]["arguments"][model_index + 1] == "followup-fixture-model",
            )
            tui.send(b"vr")
            tui.wait("follow-up diff loaded", lambda: "diff --git" in tui.text())
            tui.send(b"G")
            tui.wait(
                "follow-up review",
                lambda: "+Reviewed follow-up implementation" in tui.text(),
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-followup"))
            tui.send(b"\x1b")
            tui.send(b"iRetained unsent draft\x1b")
            tui.send(b"a")
            tui.wait(
                "explicit acceptance", lambda: "/ Done / conversation" in tui.text()
            )
            tui.check(
                "accepted task retains queued reply and read-only draft",
                "1 queued retained" in tui.text()
                and "draft retained" in tui.text()
                and "i reply" not in tui.screen.display[-2],
            )
            tui.send(b"q")
            tui.wait_exit()
            tui.check("workflow exits successfully", tui.process.returncode == 0)
        saved = snapshot(database)
        task = saved["tasks"][0]
        assert len(saved["tasks"]) == 1 and task["state"] == "done"
        assert task["thread"] == "workflow-thread" and len(task["runs"]) == 2
        assert task["runs"][0]["simulated"] is False
        assert task["runs"][0]["policy"] == "workspace-write"
        assert task["runs"][0] == first_record
        assert task["messages"][: len(first_messages)] == first_messages
        assert task["runs"][1]["model"] == "followup-fixture-model"
        assert task["runs"][0]["model"] == "fixture-model"
        assert all(record["status"] == "completed" for record in task["runs"])
        assert all(record["simulated"] is False for record in task["runs"])
        assert len({record["id"] for record in task["runs"]}) == 2
        assert all(record["policy"] == "workspace-write" for record in task["runs"])
        assert (
            workspace / "followup.txt"
        ).read_text() == "Reviewed follow-up implementation\n"
        assert not (source / "followup.txt").exists()

        queued = [message for message in task["messages"] if message["queued"]]
        assert len(queued) == 1 and queued[0]["text"] == "Queue this for a later turn"
        assert len({message["id"] for message in task["messages"]}) == len(
            task["messages"]
        )
        assert saved["drafts"] == [[task["id"], "Retained unsent draft"]]
        with Terminal(command, env, columns=180, rows=50) as tui:
            tui.ready()
            tui.send(b"e")
            tui.wait(
                "accepted conversation restored",
                lambda: (
                    "Fixture implementation ready for review" in tui.text()
                    and "Fixture follow-up ready for review" in tui.text()
                ),
            )
            tui.check(
                "restart never resumes accepted runner",
                len(marker.read_text().splitlines()) == 2,
            )
            tui.check(
                "restored task stays read-only with queued reply retained",
                "1 queued retained" in tui.text()
                and "Queue this for a later turn" in tui.text()
                and "draft retained" in tui.text()
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
