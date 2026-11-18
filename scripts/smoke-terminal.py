#!/usr/bin/env python3
"""Test a local terminal fixture. Requires pyte; Pillow is optional for previews."""
import argparse
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import termios
import time
import tempfile
import sqlite3
import json

import pyte

parser = argparse.ArgumentParser()
parser.add_argument("--preview", type=Path)
parser.add_argument("--binary", type=Path, help="Use an alternate compiler build")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
binary = args.binary.resolve() if args.binary else root / "_build/default/bin/main.exe"
master, slave = pty.openpty()
original = termios.tcgetattr(slave)
cols, rows = 120, 36
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
class TerminalScreen(pyte.Screen):
    def next_line(self):
        # NEL resets the column so full-width rows do not wrap twice.
        self.carriage_return()
        self.index()


class TerminalStream(pyte.ByteStream):
    escape = {**pyte.ByteStream.escape, "E": "next_line"}
    events = pyte.ByteStream.events | {"next_line"}


screen = TerminalScreen(cols, rows)
stream = TerminalStream(screen)
env = {**os.environ, "TERM": "xterm-256color"}
process = subprocess.Popen([str(binary), "--no-config"], stdin=slave, stdout=slave, stderr=slave, env=env)


def pump(seconds=0.25):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        ready, _, _ = select.select([master], [], [], max(0, end - time.monotonic()))
        if ready:
            try:
                data = os.read(master, 65536)
            except OSError:
                break
            if not data:
                break
            stream.feed(data)


def wait_ready():
    end = time.monotonic() + 10
    while time.monotonic() < end:
        pump(0.05)
        raw = not (termios.tcgetattr(slave)[3] & termios.ICANON)
        if raw and "FACTORY / terminal" in text():
            return
        if process.poll() is not None:
            raise AssertionError(f"TUI failed at startup ({process.returncode}): {text()}")
    raise AssertionError(f"TUI startup timeout: {text()}")


def wait_exit(timeout=5):
    # The app can write terminal cleanup while shutting down; keep the PTY draining.
    deadline = time.monotonic() + timeout
    while process.poll() is None and time.monotonic() < deadline:
        pump(0.05)
    if process.poll() is None:
        raise subprocess.TimeoutExpired(process.args, timeout)
    pump(0.05)


def send(data):
    os.write(master, data)
    pump()


def text():
    return "\n".join(screen.display)


def check(name, condition):
    if not condition:
        raise AssertionError(f"{name}\n{text()}")
    print(f"PASS: {name}")


def preview(path):
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 17)
    cell_w, cell_h = 11, 23
    image = Image.new("RGB", (screen.columns * cell_w, screen.lines * cell_h), "#131720")
    draw = ImageDraw.Draw(image)
    colors = {
        "default": "#131720", "black": "#131720", "white": "#dae3ed",
        "cyan": "#76beda", "yellow": "#efb963", "green": "#93cb9a",
    }
    def color(value, default):
        if value in colors:
            return colors[value] if value != "default" else default
        if len(value) == 6:
            return "#" + value
        return default
    for y in range(screen.lines):
        for x in range(screen.columns):
            cell = screen.buffer[y][x]
            draw.rectangle((x * cell_w, y * cell_h, (x + 1) * cell_w, (y + 1) * cell_h), fill=color(cell.bg, "#131720"))
            draw.text((x * cell_w, y * cell_h), cell.data, font=font, fill=color(cell.fg, "#dae3ed"))
    image.save(path)
    print(f"Preview: {path}")


try:
    wait_ready()
    check("board renders all columns", all(s in text() for s in ["Queued", "Working", "Needs you", "Ready"]))
    check("simulation is visible", "SIMULATION" in text())
    rss = subprocess.check_output(["ps", "-o", "rss=", "-p", str(process.pid)], text=True).strip()
    print(f"Idle RSS sample: {int(rss) / 1024:.1f} MiB")
    send(b"h2j")
    check("counted vim motion selects card", "T-106 / Queued / conversation" in text())
    send(b"gg")
    check("gg selects first card", "T-101 / Queued / conversation" in text())
    send(b"G")
    check("G selects last card", "T-106 / Queued / conversation" in text())
    send(b"\x17l")
    send(b"ggG")
    check("Ctrl-W pane navigation survives", process.poll() is None)
    send(b"\x17k")
    send(b"gg")
    check("Ctrl-W k returns to board", "T-101 / Queued / conversation" in text())
    if args.preview:
        preview(args.preview)
    # SGR mouse positions are one-based terminal cells.
    send(b"\x1b[<0;3;5M\x1b[<0;3;5m")
    check("mouse selects a queued card", "T-101 / Queued / conversation" in text())
    send(b"e")
    if args.preview:
        preview(args.preview.with_stem(args.preview.stem + "-chat"))
    check("task expansion hides the board", "Queued 3" not in text() and "T-101 / Queued / conversation" in text())
    send(b"\x1b")
    pump(0.2)
    check("Escape restores the board", "Queued 3" in text())
    send(b"i")
    send(b"\x1b[200~sxa\x1b[201~")
    check("paste edits without executing shortcuts", "Reply (queued): sxa" in text())
    send(b"\r")
    check("reply enters conversation", "sxa" in text() and "Reply queued" in text())
    send(b"iFirst line")
    send(b"\x0c")
    send(b"Second line")
    check("composer newline shortcut stays in edit mode", "Reply (queued):" in text() and "Second line" in text())
    send(b"\x1b[200~\rPasted third line\x1b[201~")
    check("multiline paste is not submitted", "Reply (queued):" in text())
    send(b"\x1b[D!")
    send(b"\r")
    send(b"e")
    check("multiline reply reaches chat", any(row.split("│")[1].strip() == "First line" for row in screen.display if "│" in row)
          and any(row.split("│")[1].strip() == "Second line" for row in screen.display if "│" in row)
          and "Pasted third lin!e" in text())
    if args.preview:
        preview(args.preview.with_stem(args.preview.stem + "-multiline"))
    send(b"\x1b")

    send(b"s")
    check("fixture start automatically moves card", "T-101 / Working / conversation" in text())
    pump(8.0)
    check("completion automatically moves card to Ready", "T-101 / Ready / conversation" in text())
    send(b"a")
    send(b"d")
    check("accepted tasks appear in archive", "T-101" in text() and "Done" in text())
    send(b"?")
    check("help opens", "Help / Settings" in text())
    send(b"\t")
    check("settings opens with memory status", "STORAGE" in text() and "In memory" in text())
    send(b"\x1b")
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 180, 0, 0))
    screen.resize(lines=50, columns=180)
    os.kill(process.pid, signal.SIGWINCH)
    pump()
    send(b"b")
    check("wide layout includes repository sidebar", "REPOSITORIES" in text() and "All repositories" in text())
    if args.preview:
        preview(args.preview.with_stem(args.preview.stem + "-wide"))
    send(b"R")
    check("repository keyboard filter selects factory", " factory  |" in text())
    send(b"b")
    send(b"?")
    send(b"\t")
    check("settings remains accessible at wide size", "SESSION SETTINGS" in text())
    if args.preview:
        preview(args.preview.with_stem(args.preview.stem + "-settings"))
    send(b"\x1b")
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 20, 60, 0, 0))
    screen.resize(lines=20, columns=60)
    os.kill(process.pid, signal.SIGWINCH)
    pump()
    check("narrow terminal resize survives", process.poll() is None and "FACTORY" in text())
    send(b"q")
    wait_exit(3)
    check("normal exit succeeds", process.returncode == 0)
    restored = termios.tcgetattr(slave)
    # The kernel can set PENDIN when terminal attributes are restored.
    restored[3] &= ~getattr(termios, "PENDIN", 0)
    original[3] &= ~getattr(termios, "PENDIN", 0)
    check("terminal settings restored", restored == original)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    screen.resize(lines=rows, columns=cols)
    screen.reset()
    process = subprocess.Popen([str(binary), "--no-config", "--events", str(root / "examples/events.jsonl")],
                               stdin=slave, stdout=slave, stderr=slave, env=env)
    wait_ready()
    check("JSONL fixture moves task to Ready", "T-102 / Ready / conversation" in text())
    check("replay mode is visible", "FIXTURE REPLAY" in text())
    process.terminate()
    wait_exit(3)
    check("SIGTERM exits cleanly", process.returncode == 0)
    restored = termios.tcgetattr(slave)
    restored[3] &= ~getattr(termios, "PENDIN", 0)
    check("SIGTERM restores terminal settings", restored == original)
    with tempfile.TemporaryDirectory(prefix="factory-tui-smoke-") as directory:
        database = Path(directory) / "board.sqlite"
        config = Path(directory) / "config.toml"
        config.write_text('[storage]\ndatabase = "board.sqlite"\n')
        screen.reset()
        process = subprocess.Popen([str(binary), "--config", str(config)],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        wait_ready()
        send(b"hgg")
        send(b"s")
        send(b"iReply after launch\r")
        send(b"iSaved draft\x1b")
        send(b"q")
        wait_exit(3)
        check("persisted UI exits cleanly", process.returncode == 0)
        check("TOML resolves database relative to config", database.exists())
        with sqlite3.connect(database) as db:
            saved = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        check("final flush retains task draft", ["T-101", "Saved draft"] in saved["drafts"])
        saved_task = next(t for t in saved["tasks"] if t["id"] == "T-101")
        check("final flush retains queued reply", any(m["text"] == "Reply after launch" and m["queued"] for m in saved_task["messages"]))
        screen.reset()
        process = subprocess.Popen([str(binary), "--config", str(config)],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        wait_ready()
        send(b"e")
        check("UI restart recovers working task", "T-101 / Needs you / conversation" in text())
        send(b"i")
        check("UI restart restores draft", "Saved draft" in text())
        send(b"\x1b")
        send(b"q")
        wait_exit(3)
        check("reopened UI exits cleanly", process.returncode == 0)
        with sqlite3.connect(database) as db:
            check("ordered fixture events persisted", db.execute("SELECT count(*) FROM events").fetchone()[0] > 0)
        default_dir = Path(directory) / "factory-tui"
        default_dir.mkdir()
        (default_dir / "config.toml").write_text('[storage]\ndatabase = "../board.sqlite"\n')
        screen.reset()
        process = subprocess.Popen([str(binary)], stdin=slave, stdout=slave, stderr=slave,
                                   env={**env, "XDG_CONFIG_HOME": directory})
        wait_ready()
        send(b"e")
        check("argument-free startup discovers TOML", "T-101 / Needs you / conversation" in text())
        send(b"q")
        wait_exit(3)
        check("default-config UI exits cleanly", process.returncode == 0)

    with tempfile.TemporaryDirectory(prefix="factory-process-ui-") as directory:
        database = Path(directory) / "board.sqlite"
        screen.reset()
        process = subprocess.Popen([str(binary), "--fake-harness", "--no-config", "--database", str(database)],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        wait_ready()
        check("fake harness mode is explicit", "FAKE HARNESS / NO MODEL CALLS" in text())
        with sqlite3.connect(database) as db:
            saved = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
            check("fake UI startup launches no run", all(t["active"] is None for t in saved["tasks"]))
        send(b"hgg")
        send(b"s")
        pump(1.2)
        send(b"e")
        check("process fixture moves selected card to Ready", "T-101 / Ready / conversation" in text())
        check("process fixture streams into chat", "Local fixture checks are complete" in text())
        send(b"iAnother fixture turn\r")
        send(b"s")
        send(b"x")
        pump(0.4)
        check("process fixture stop leaves Needs you", "T-101 / Needs you / conversation" in text())
        send(b"iFinal fixture turn\r")
        send(b"s")
        process.terminate()
        wait_exit(3)
        check("fake UI SIGTERM cancels and exits", process.returncode == 0)
        with sqlite3.connect(database) as db:
            saved = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
            task = next(t for t in saved["tasks"] if t["id"] == "T-101")
            check("shutdown records fixture interruption", task["state"] == "needs_you" and task["active"] is None)
            check("process events are stored", db.execute("SELECT count(*) FROM events").fetchone()[0] > 0)

    with tempfile.TemporaryDirectory(prefix="factory-workspace-ui-") as temporary:
        directory = Path(temporary).resolve()
        source = directory / "source"
        source.mkdir()
        subprocess.run(["/opt/homebrew/bin/jj", "git", "init", "--colocate", str(source)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        database = directory / "board.sqlite"
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        screen.resize(lines=rows, columns=cols)
        screen.reset()
        process = subprocess.Popen([str(binary), "--no-config", "--database", str(database)],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        wait_ready()
        send(b"W")
        check("workspace dialog opens", "NEW WORKSPACE TASK" in text())
        check("creation disclosure visible", "snapshot source files" in text() and "no automatic agent run" in text())
        send(b"\x1b[Z")
        send(b"/opt/homebrew/bin/jj\t")
        send(str(source).encode() + b"\t")
        send(str(directory).encode() + b"\t\t\t")
        send(b"Create an isolated task through the TUI")
        pump(0.5)
        check("workspace form remains explicit", "Task instruction" in text()
              and "Create an isolated task through the TUI" in text())
        if args.preview:
            preview(args.preview.with_stem(args.preview.stem + "-workspace"))
        send(b"\x13")
        pump(1.0)
        check("workspace creation selects queued chat", "Create an isolated task through the TUI" in text()
              and "No agent starts" in text())
        send(b"q")
        wait_exit(5)
        check("workspace UI exits cleanly", process.returncode == 0)
        with sqlite3.connect(database) as db:
            saved = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        task = next(t for t in saved["tasks"] if t.get("workspace"))
        check("created workspace identity persisted", task["workspace"]["source"] == str(source)
              and Path(task["workspace"]["directory"]).is_dir())
        (Path(task["workspace"]["directory"]) / "review.txt").write_text("A real workspace addition\n")

        check("created workspace task starts no run", task["state"] == "queued" and task["active"] is None
              and task["runs"] == [])
        check("complete task instruction retained", task["messages"][0]["text"] == "Create an isolated task through the TUI")
        check("original source not changed", not (source / "example.txt").exists())
        screen.reset()
        process = subprocess.Popen([str(binary), "--no-config", "--database", str(database)],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        wait_ready()
        send(b"e")
        check("created task chat restores after restart", "Create an isolated task through the TUI" in text())
        send(b"v")
        check("changes pane opens on selected task", "CHANGES / " + task["id"] in text())
        check("changes refresh disclosure visible", "Refresh snapshots the workspace" in text())
        send(b"/opt/homebrew/bin/jj\r")
        deadline = time.monotonic() + 5
        while "+A real workspace addition" not in text() and time.monotonic() < deadline:
            pump(0.05)
        check("real workspace patch appears in TUI", "+A real workspace addition" in text()
              and "review.txt" in text())
        if args.preview:
            preview(args.preview.with_stem(args.preview.stem + "-review"))
        send(b"\x1b")
        check("closing changes returns to task chat", "Create an isolated task through the TUI" in text()
              and "CHANGES / " not in text())

        send(b"q")
        wait_exit(3)
        check("reopened workspace UI exits cleanly", process.returncode == 0)
        executable = directory / "fake-codex"
        executable.write_text("""#!/bin/sh
cat > live-prompt.txt
touch live-started
printf '%s\\n' '{"type":"thread.started","thread_id":"ui-fixture-thread"}'
printf '%s\\n' '{"type":"turn.started"}'
sleep 0.2
printf '%s\\n' '{"type":"item.completed","item":{"type":"agent_message","id":"reply","text":"Live-mode local fixture answer"}}'
printf '%s\\n' '{"type":"turn.completed"}'
""")
        executable.chmod(0o700)
        marker = Path(task["workspace"]["directory"]) / "live-started"
        screen.reset()
        process = subprocess.Popen([str(binary), "--live-ui", "--no-config", "--database", str(database),
                                   "--codex-executable", str(executable)],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        wait_ready()
        check("live UI explicitly labeled", "LIVE ENABLED / CONFIRMED CALLS" in text())
        check("live UI starts no executable on launch", not marker.exists())
        send(b"s")
        check("Start requires confirmation", "Confirm live run" in text() and not marker.exists())
        check("confirmation discloses usage", "may incur model usage" in text())
        if args.preview:
            preview(args.preview.with_stem(args.preview.stem + "-live-confirmation"))
        send(b"\x1b[200~y\r\x1b[201~")
        check("paste cannot authorize execution", "Confirm live run" in text() and not marker.exists())
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 20, 60, 0, 0))
        screen.resize(lines=20, columns=60)
        os.kill(process.pid, signal.SIGWINCH)
        pump(0.2)
        send(b"\r")
        check("small terminal cannot authorize live execution", not marker.exists()
              and "larger terminal" in text())
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        screen.resize(lines=rows, columns=cols)
        os.kill(process.pid, signal.SIGWINCH)
        pump(0.2)

        send(b"\x1b")
        send(b"s")
        send(b"\r")
        deadline = time.monotonic() + 5
        while "Live-mode local fixture answer" not in text() and time.monotonic() < deadline:
            pump(0.05)
        send(b"e")
        check("confirmed process streams into chat", "Live-mode local fixture answer" in text() and marker.exists())
        check("confirmed process moves selected task Ready", " / Ready / conversation" in text())
        send(b"q")
        wait_exit(5)
        check("live fixture UI exits cleanly", process.returncode == 0)
        with sqlite3.connect(database) as db:
            saved = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        live_task = next(t for t in saved["tasks"] if t["id"] == task["id"])
        check("live UI run origin and thread saved", live_task["thread"] == "ui-fixture-thread"
              and live_task["runs"][-1]["simulated"] is False)
        check("live UI saved genuine author label", live_task["messages"][-1]["author"] == "Codex")
        executable.write_text("#!/bin/sh\ncat >/dev/null\ntouch cancel-started\nsleep 10\n")
        screen.reset()
        process = subprocess.Popen([str(binary), "--live-ui", "--no-config", "--database", str(database),
                                   "--codex-executable", str(executable)],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        wait_ready()
        send(b"iContinue fixture\r")
        send(b"s\r")
        cancel_marker = Path(task["workspace"]["directory"]) / "cancel-started"
        deadline = time.monotonic() + 5
        while not cancel_marker.exists() and time.monotonic() < deadline:
            pump(0.05)
        check("second confirmed fixture starts", cancel_marker.exists())
        send(b"x")
        pump(0.3)
        check("live cancellation is disclosed", "Live cancellation requested" in text())
        send(b"iContinue after stop\r")
        send(b"s\r")
        pump(0.1)
        process.terminate()
        wait_exit(5)
        check("live UI SIGTERM cancels and joins", process.returncode == 0)
        with sqlite3.connect(database) as db:
            saved = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        cancelled_task = next(t for t in saved["tasks"] if t["id"] == task["id"])
        check("live shutdown leaves task interrupted", cancelled_task["active"] is None
              and cancelled_task["state"] == "needs_you" and cancelled_task["runs"][-1]["status"] == "stopped")


finally:
    if process.poll() is None:
        process.terminate()
        try:
            wait_exit(3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
    os.close(master)
    os.close(slave)
