#!/usr/bin/env python3
"""Verify visible validation feedback without discarding edited task text."""

import argparse
import os
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
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    with tempfile.TemporaryDirectory(prefix="factory-input-feedback-") as temporary:
        directory = Path(temporary)
        replay = directory / "empty.jsonl"
        replay.write_text("")
        home = directory / "home"
        home.mkdir()
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home), TMPDIR=str(directory))
        with Terminal(
            [str(binary), "--no-config", "--events", str(replay)], env
        ) as tui:
            tui.ready()
            tui.send(b"ei")
            tui.wait(
                "reply insert guidance",
                lambda: "INSERT / Enter queues" in tui.screen.display[-1],
            )
            tui.check(
                "reply hint names draft-preserving Escape and newline",
                "Esc keeps draft" in tui.screen.display[-1]
                and "Ctrl-L newline" in tui.screen.display[-1],
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-insert"))
            tui.send(b"\r")
            tui.wait(
                "empty reply feedback",
                lambda: "Message is empty." in tui.screen.display[-1],
            )
            tui.check(
                "empty reply leaves editor active", "Reply (queued):" in tui.text()
            )
            if args.preview:
                tui.preview(args.preview.with_stem(args.preview.stem + "-reply"))
            tui.send(b"Recovered reply")
            tui.wait(
                "feedback clears on edit",
                lambda: "INSERT / Enter queues" in tui.screen.display[-1],
            )
            tui.send(b"\r")
            tui.wait(
                "valid reply queued",
                lambda: (
                    "Recovered reply" in tui.text()
                    and "Reply (queued):" not in tui.text()
                ),
            )
            tui.send(b"m\x1b[H")
            tui.wait(
                "model edit guidance",
                lambda: "MODEL / Enter applies" in tui.screen.display[-1],
            )
            tui.send(b"\x1b[200~-\x1b[201~\r")
            tui.wait(
                "invalid model feedback",
                lambda: "Enter a model ID" in tui.screen.display[-1],
            )
            tui.check(
                "invalid model text retained at cursor",
                "-▏coding-large" in tui.text() and "Model (next run):" in tui.text(),
            )
            tui.send(b"\x7f\r")
            tui.wait("model corrected", lambda: "Next-run model updated" in tui.text())
            tui.send(b"n")
            tui.wait(
                "task creation guidance",
                lambda: "NEW TASK / Enter creates" in tui.screen.display[-1],
            )
            tui.send(b"\r")
            tui.wait(
                "blank task feedback",
                lambda: "Enter a task instruction" in tui.screen.display[-1],
            )
            tui.check("blank task stays in creation editor", "New task:" in tui.text())
            tui.send(b"Created after feedback\r")
            tui.wait(
                "task created",
                lambda: (
                    "Created after feedback" in tui.text()
                    and "New task:" not in tui.text()
                ),
            )
            tui.check(
                "recovered task is queued without automatic run", "Queued" in tui.text()
            )
            tui.send(b"\t")
            tui.wait(
                "Activity guidance",
                lambda: "t: tools" in tui.screen.display[-1],
            )
            tui.send(b"\t")
            tui.wait(
                "conversation guidance",
                lambda: "End: latest" in tui.screen.display[-1],
            )
            tui.send(b"S")
            tui.wait(
                "transcript search editing guidance",
                lambda: "CHAT SEARCH / Enter finishes" in tui.screen.display[-1],
            )
            tui.send(b"Created\r")
            tui.wait(
                "transcript result guidance",
                lambda: "n/N: matches" in tui.screen.display[-1],
            )
            tui.send(b"\x1b")
            tui.wait(
                "search cleared guidance",
                lambda: "End: latest" in tui.screen.display[-1],
            )
            tui.send(b"q")
            tui.wait_exit()
            tui.check(
                "input feedback fixture exits cleanly", tui.process.returncode == 0
            )
        assert list(home.iterdir()) == []
    print(
        "Temporary replay only. No agent, credentials, storage or real workspace access."
    )


if __name__ == "__main__":
    main()
