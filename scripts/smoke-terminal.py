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
    check("board column shows visible card range", "Queued 3 / 1-2/3" in text())
    rss = subprocess.check_output(["ps", "-o", "rss=", "-p", str(process.pid)], text=True).strip()
    print(f"Idle RSS sample: {int(rss) / 1024:.1f} MiB")
    send(b"h2j")
    check("counted vim motion selects card", "T-106 / Queued / conversation" in text())
    check("selection footer identifies the selected task", "T-106 / Instructions queued" in screen.display[-3])
    send(b"gg")
    check("gg selects first card", "T-101 / Queued / conversation" in text())
    check("selection footer follows keyboard task changes", "T-101 / Instructions queued" in screen.display[-3])
    send(b"\x1b[<65;5;35M")
    check("wheel over footer leaves queued window unchanged", "Queued 3 / 1-2/3" in text()
          and "T-101 / Queued / conversation" in text())

    send(b"G")
    check("G selects last card", "T-106 / Queued / conversation" in text())
    check("last-card selection updates visible range", "Queued 3 / 2-3/3" in text())
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
    send(b"i")
    send(b"\x1b[200~" + "aé👍🏽b".encode() + b"\x1b[201~")
    send(b"\x1b[D\x7f")
    check("terminal backspace removes complete skin-tone emoji", "Reply (queued): aéb" in text())
    send(b"\x1b[D\x1b[3~")
    check("terminal delete removes complete combining accent", "Reply (queued): ab" in text())
    send(b"\r")
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
    send(b"/line")
    send(b"\r")
    check("chat search displays matching message count", "/chat line" in text() and "1/1 messages" in text())
    send(b"nN")
    check("chat match navigation starts no run", "/chat line" in text() and "T-101 / Queued / conversation" in text())
    if args.preview:
        preview(args.preview.with_stem(args.preview.stem + "-chat-search"))
    send(b"\x1b")
    check("Escape clears chat search before zoom", "/chat line" not in text() and "T-101 / Queued / conversation" in text())

    send(b"\x1b")

    send(b"s")
    check("fixture start automatically moves card", "T-101 / Working / conversation" in text())
    check("working footer offers stop but not start or acceptance", "x stop" in screen.display[-2]
          and "s start" not in screen.display[-2] and "a accept" not in screen.display[-2])
    pump(8.0)
    check("completion automatically moves card to Ready", "T-101 / Ready / conversation" in text())
    check("ready footer offers acceptance without stale stop", "a accept" in screen.display[-2]
          and "x stop" not in screen.display[-2])
    send(b"a")
    send(b"d")
    check("accepted tasks appear in archive", "T-101" in text() and "Done" in text())
    check("accepted footer omits run and editing actions", all(label not in screen.display[-2]
          for label in ("s start", "x stop", "a accept", "i reply", "m model", "H harness")))
    send(b"?")
    check("help opens", "Help / Settings" in text())
    menu_rows = screen.display[2:33]
    send(b"\x1b[<65;1;10M\x1b[<65;20;4M")
    check("Help ignores wheel outside content and over tabs", screen.display[2:33] == menu_rows)
    send(b"\x1b[<65;20;8M")
    check("Help content still scrolls with wheel", screen.display[2:33] != menu_rows)
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
    send(b"bggj")
    check("compact j follows displayed list across states", any("› T-103" in row for row in screen.display))
    send(b"k")
    check("compact k returns to preceding displayed task", any("› T-102" in row for row in screen.display))
    send(b"G")
    check("compact G selects last task across all states", any("› T-106" in row for row in screen.display))
    send(b"gg2j")
    check("compact counted motion matches visible rows", any("› T-104" in row for row in screen.display))
    send(b"?")
    check("compact Help exposes content below", "more below" in text())
    send(b"\x1b[6~")
    check("compact Help page-down advances one visible page", "16-30/" in text())
    send(b"G")
    check("compact Help exposes content above at bottom", "more above" in text())
    if args.preview:
        preview(args.preview.with_stem(args.preview.stem + "-help-bottom"))
    send(b"\t")
    check("switching to Settings resets menu position", "1-15/" in text() and "SESSION SETTINGS" in text())
    send(b"\x1b")
    send(b"bgg")
    send(b"i")
    send(b"Compact visible reply")
    check("compact composing exposes chat and editor", "Reply / next turn" in text()
          and "Compact visible reply" in text() and "conversation" in text())
    send(b"\x0c" + b"a" * 55 + "👍🏽TAIL".encode())
    check("compact wrapping keeps the emoji modifier on the same row",
          any("👍🏽" in row and "TAIL" in row for row in screen.display[4:-4]))
    if args.preview:
        preview(args.preview.with_stem(args.preview.stem + "-compact-compose"))
    send(b"\x1b")
    send(b"\t")
    check("compact Tab exposes Activity", "activity" in text() and "next:" in text())
    send(b"\t")
    check("compact Tab returns to board", "Tasks / click" in text())
    send(b"i")
    check("compact draft survives focus cycling", "Compact visible reply" in text())
    send(b"\x1b")
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
        send(b"t")
        check("tool activity uses readable command summary", "Command / completed / exit 0" in text())
        check("command output displayed as text", "Fixed local fixture output" in text())
        if args.preview:
            preview(args.preview.with_stem(args.preview.stem + "-tool-activity"))
        send(b"\x17l")
        send(b"e")
        check("focused Activity expands to full width", " / activity / expanded" in text()
              and "Reply / next turn" not in text())
        check("expanded Activity exposes complete output line", "Fixed local fixture output. No workspace changes." in text())
        check("completed fixture history shows recorded duration", "recorded duration" in text())
        if args.preview:
            preview(args.preview.with_stem(args.preview.stem + "-activity-expanded"))
        send(b"T")
        check("raw tool diagnostics available", '"command_execution"' in text())
        send(b"T")
        send(b"e")
        check("Activity expansion returns to previous task layout", "Reply / next turn" in text()
              and " / activity / expanded" not in text())
        send(b"t")

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
        (Path(task["workspace"]["directory"]) / "review.txt").write_text(
            "A real workspace addition\n" + "x" * 180 + "界éLONG_LINE_END\n")

        (Path(task["workspace"]["directory"]) / "z-final.txt").write_text("Final file sentinel\n")

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
        send(b"\x17le")
        check("workspace Activity expands for inspection", "activity / expanded" in text())
        metadata = "".join(row.strip().strip("│").strip() for row in screen.display[4:-4])
        check("Activity retains full recorded workspace paths", task["workspace"]["source"] in metadata
              and task["workspace"]["directory"] in metadata)
        check("Activity exposes the exact diff base", task["workspace"]["base"] in metadata)
        if args.preview:
            preview(args.preview.with_stem(args.preview.stem + "-workspace-activity"))
        send(b"e\x17h")
        send(b"v")
        check("changes pane opens on selected task", "CHANGES / " + task["id"] in text())
        check("changes refresh disclosure visible", "Refresh snapshots the workspace" in text())
        send(b"/opt/homebrew/bin/jj\r")
        deadline = time.monotonic() + 5
        # A PTY read can end inside a frame; wait for its body and footer.
        while ("+A real workspace addition" not in text() or "file 1/2: review.txt" not in text()) and time.monotonic() < deadline:
            pump(0.05)
        check("real workspace patch appears in TUI", "+A real workspace addition" in text()
              and "review.txt" in text())
        check("review file position starts at the first file", "file 1/2: review.txt" in text())
        review_rows = screen.display[1:]
        send(b"\x1b[<65;10;35M\x1b[<81;10;35M")
        check("review buttons do not scroll the patch", screen.display[1:] == review_rows)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 12, cols, 0, 0))
        screen.resize(lines=12, columns=cols)
        os.kill(process.pid, signal.SIGWINCH)
        pump(0.2)
        send(b"\x04")
        check("review Ctrl-D pages by half the current viewport", "Line 3 / 16" in text())
        send(b"\x15")
        check("review Ctrl-U returns by half the current viewport", "Line 1 / 16" in text())
        send(b"\x06")
        check("review Ctrl-F pages by the current viewport", "Line 6 / 16" in text())
        send(b"\x02")
        check("review Ctrl-B returns by the current viewport", "Line 1 / 16" in text())
        send(b"i")
        path_before = screen.display[3]
        send(b"\x04\x15\x06\x02")
        check("review paging keys are inactive in executable editing", screen.display[3] == path_before
              and "Line 1 / 16" in text())
        send(b"\r")
        deadline = time.monotonic() + 5
        while "file 1/2: review.txt" not in text() and time.monotonic() < deadline:
            pump(0.05)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        screen.resize(lines=rows, columns=cols)
        os.kill(process.pid, signal.SIGWINCH)
        pump(0.2)
        send(b"]")
        check("next file key opens final file", "file 2/2: z-final.txt" in text()
              and "+Final file sentinel" in text()
              and "diff --git a/z-final.txt b/z-final.txt" in text().splitlines()[4])
        send(b"]")
        check("last file navigation does not wrap", "file 2/2: z-final.txt" in text())
        if args.preview:
            preview(args.preview.with_stem(args.preview.stem + "-review-last-file"))
        send(b"[")
        check("previous file key returns to first file", "file 1/2: review.txt" in text()
              and "+A real workspace addition" in text())
        send(b"\x1b[<0;60;35M\x1b[<0;60;35m")
        check("clicking next file opens final file", "file 2/2: z-final.txt" in text())
        send(b"\x1b[<0;47;35M\x1b[<0;47;35m")
        check("clicking previous file returns to first file", "file 1/2: review.txt" in text())
        check("long diff end initially clipped", "LONG_LINE_END" not in text())
        send(b"l" * 40)
        pump(0.3)
        check("horizontal keys reveal Unicode suffix", "界éLONG_LINE_END" in text())
        if args.preview:
            preview(args.preview.with_stem(args.preview.stem + "-review-horizontal"))
        send(b"0")
        check("zero restores patch start", "+A real workspace addition" in text() and "LONG_LINE_END" not in text())
        send(b"\x1b[<81;10;10M")
        check("Ctrl-wheel updates horizontal offset", "column +4" in text())
        send(b"0")

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

        executable.write_text("""#!/bin/sh
printf '%s\\n' "$@" > write-arguments.txt
cat >/dev/null
case "$*" in
  *sandbox_mode=\\\"workspace-write\\\"*) ;;
  *) exit 2 ;;
esac
printf 'fixture code change\\n' > write-result.txt
printf '%s\\n' '{"type":"thread.started","thread_id":"ui-fixture-thread"}'
printf '%s\\n' '{"type":"turn.started"}'
printf '%s\\n' '{"type":"item.completed","item":{"type":"agent_message","id":"reply","text":"Fixture implementation complete"}}'
printf '%s\\n' '{"type":"turn.completed"}'
""")
        screen.reset()
        process = subprocess.Popen([str(binary), "--live-ui", "--workspace-write", "--no-config",
                                   "--database", str(database), "--codex-executable", str(executable)],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        wait_ready()
        write_marker = Path(task["workspace"]["directory"]) / "write-result.txt"
        check("write policy opt-in shown in banner", "LIVE WRITE / CONFIRMED CALLS" in text())
        check("write mode startup changes no task files", not write_marker.exists())
        send(b"iImplement fixture\r")
        send(b"s")
        check("write confirmation is explicit", "WRITE ACCESS: workspace + temp directories" in text() and not write_marker.exists())
        if args.preview:
            preview(args.preview.with_stem(args.preview.stem + "-write-confirmation"))
        send(b"\x1b[200~y\r\x1b[201~")
        check("paste cannot authorize workspace writes", not write_marker.exists())
        send(b"y")
        deadline = time.monotonic() + 5
        while "Fixture implementation complete" not in text() and time.monotonic() < deadline:
            pump(0.05)
        send(b"e")
        check("confirmed fixture edits task workspace", write_marker.exists() and "Fixture implementation complete" in text())
        check("write fixture leaves source untouched", not (source / "write-result.txt").exists())
        send(b"v")
        send(b"/opt/homebrew/bin/jj\r")
        deadline = time.monotonic() + 5
        while "diff --git" not in text() and time.monotonic() < deadline:
            pump(0.05)
        send(b"G")
        check("fixture implementation is reviewable", "+fixture code change" in text())
        send(b"\x1b")
        send(b"q")
        wait_exit(5)
        check("write fixture UI exits cleanly", process.returncode == 0)
        with sqlite3.connect(database) as db:
            saved = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        write_task = next(t for t in saved["tasks"] if t["id"] == task["id"])
        check("write policy saved per run", write_task["runs"][-1]["policy"] == "workspace-write")
        check("earlier runs stay read-only", all(run["policy"] == "read-only" for run in write_task["runs"][:-1]))

    with tempfile.TemporaryDirectory(prefix="factory-history-scroll-") as directory:
        replay = Path(directory) / "events.jsonl"
        def replay_event(item, text):
            return json.dumps({"task_id":"T-102", "run_id":"demo-102", "type":"message",
                               "item_id":item, "text":text}) + "\n"
        tool_payload = json.dumps({"type":"command_execution", "command":"fixture only", "status":"completed",
                                   "aggregated_output":"\n".join(f"Tool history {i:02d}" for i in range(60))})
        tool_event = json.dumps({"task_id":"T-102", "run_id":"demo-102", "type":"tool",
                                 "item_id":"history-tool", "text":tool_payload}) + "\n"
        replay.write_text(tool_event + "".join(replay_event(f"history-{i}", f"History item {i:02d}") for i in range(24)))
        screen.reset()
        process = subprocess.Popen([str(binary), "--no-config", "--events", str(replay)],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        wait_ready()
        pump(0.3)
        send(b"e")
        check("chat initially follows latest replay output", "History item 23" in text())
        send(b"\x1b[H")
        send(b"6j")
        def top_chat_line():
            return screen.display[5].split("│")[1].strip()
        check("scroll reveals older message", top_chat_line() == "History item 01")
        check("paused history is disclosed", "reading history" in text())
        send(b"t")
        send(b"\x1b[<65;95;8M")
        check("Activity wheel does not borrow chat history offset", top_chat_line() == "History item 01"
              and "next: Codex" in text())
        def top_activity_line():
            return screen.display[4][82:118].strip()
        check("Activity wheel reaches its own metadata row", top_activity_line().startswith("run: demo-102"))
        activity_top = top_activity_line()
        with replay.open("a") as output:
            output.write(replay_event("later", "New output while reading history"))
        pump(0.3)
        check("incoming output does not move reading position", top_chat_line() == "History item 01"
              and "New output while reading history" not in text())
        with replay.open("a") as output:
            output.write(replay_event("history-0", "Earlier streamed message now has more text\n" * 5))
        pump(0.3)
        check("earlier stream growth keeps anchored message visible", top_chat_line() == "History item 01")
        send(b"\x1b[<0;10;10M\x1b[<0;10;10m")
        check("returning from Activity restores chat history position", top_chat_line() == "History item 01")
        check("unfocused Activity retains its visible window", top_activity_line() == activity_top)

        if args.preview:
            preview(args.preview.with_stem(args.preview.stem + "-history-anchor"))
        send(b"\x1b[F")
        check("End resumes following current output", "New output while reading history" in text()
              and "reading history" not in screen.display[3])
        with replay.open("a") as output:
            output.write(replay_event("newest", "Following resumed successfully"))
        pump(0.3)
        check("following tracks subsequent output", "Following resumed successfully" in text())
        send(b"q")
        wait_exit(5)
        check("anchored history UI exits cleanly", process.returncode == 0)

    with tempfile.TemporaryDirectory(prefix="factory-workspace-defaults-") as temporary:
        directory=Path(temporary).resolve()
        source=directory / "source"
        source.mkdir()
        subprocess.run(["/opt/homebrew/bin/jj", "git", "init", "--colocate", str(source)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        parent=directory / "tasks"
        parent.mkdir()
        config=directory / "config.toml"
        config.write_text('[storage]\ndatabase="board.sqlite"\n[workspace]\n'
                          'jj="/opt/homebrew/bin/jj"\nsource="source"\nparent="tasks"\n'
                          'revision="@"\nmodel="configured-model"\n')
        screen.reset()
        process=subprocess.Popen([str(binary), "--config", str(config)],
                                 stdin=slave, stdout=slave, stderr=slave, env=env)
        wait_ready()
        check("workspace config alone creates no directory", list(parent.iterdir())==[])
        send(b"W")
        check("configured jj visible in new form", "/opt/homebrew/bin/jj" in text())
        check("configured model visible in new form", "configured-model" in text())
        send(b"\t"*4)
        send(b"Only type the task instruction")
        pump(0.3)
        check("form reaches blank instruction with defaults", "Only type the task instruction" in text())
        if args.preview:
            preview(args.preview.with_stem(args.preview.stem + "-workspace-defaults"))
        send(b"\x13")
        deadline=time.monotonic()+5
        while "Workspace task created" not in text() and time.monotonic()<deadline:
            pump(0.05)
        check("prefilled form creates on explicit submit", "Workspace task created" in text())
        send(b"q")
        wait_exit(5)
        with sqlite3.connect(directory / "board.sqlite") as db:
            saved=json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        created=next(task for task in saved["tasks"] if task.get("workspace"))
        check("workspace config applied to created task", created["model"]=="configured-model"
              and created["workspace"]["source"]==str(source)
              and Path(created["workspace"]["directory"]).parent==parent)
        check("prefilled creation starts no run", created["runs"]==[] and created["active"] is None)
        screen.reset()
        process=subprocess.Popen([str(binary), "--config", str(config)],
                                 stdin=slave, stdout=slave, stderr=slave, env=env)
        wait_ready()
        send(b"W")
        check("jj default restored on next launch", "/opt/homebrew/bin/jj" in text())
        send(b"\x1b")
        send(b"v")
        check("configured jj available for review without retyping", "/opt/homebrew/bin/jj" in text())
        send(b"\x1b")
        send(b"q")
        wait_exit(5)
        check("defaults test exits cleanly", process.returncode==0)

    with tempfile.TemporaryDirectory(prefix="factory-live-onboarding-") as temporary:
        directory=Path(temporary).resolve()
        source=directory / "source"
        source.mkdir()
        subprocess.run(["/opt/homebrew/bin/jj", "git", "init", "--colocate", str(source)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        parent=directory / "workspaces"
        parent.mkdir()
        executable=directory / "no-auto-run"
        marker=directory / "unexpected-run"
        executable.write_text("#!/bin/sh\ntouch '" + str(marker) + "'\nexit 1\n")
        executable.chmod(0o700)
        config=directory / "config.toml"
        config.write_text('[storage]\ndatabase="new-board.sqlite"\n[workspace]\n'
                          'jj="/opt/homebrew/bin/jj"\nsource="source"\nparent="workspaces"\n'
                          'revision="@"\nmodel="fixture-model"\n')
        command=[str(binary), "--live-ui", "--config", str(config),
                 "--codex-executable", str(executable)]
        screen.reset()
        process=subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, env=env)
        wait_ready()
        check("first live launch is an empty real board", "Your factory starts here" in text()
              and "T-101" not in text())
        check("first live launch explains confirmed workflow", "Create workspace task" in text()
              and "Nothing runs until you explicitly confirm" in text())
        check("first live launch creates no workspace or agent", list(parent.iterdir())==[] and not marker.exists())
        with sqlite3.connect(directory / "new-board.sqlite") as db:
            saved=json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        check("initial live checkpoint contains no demos", saved["tasks"]==[] and saved["drafts"]==[])
        if args.preview:
            preview(args.preview.with_stem(args.preview.stem + "-onboarding"))
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 180, 0, 0))
        screen.resize(lines=50, columns=180)
        os.kill(process.pid, signal.SIGWINCH)
        pump(0.2)
        check("wide onboarding keeps sidebar and guidance", "Your factory starts here" in text()
              and "REPOSITORIES" in text())
        if args.preview:
            preview(args.preview.with_stem(args.preview.stem + "-onboarding-wide"))
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        screen.resize(lines=rows, columns=cols)
        os.kill(process.pid, signal.SIGWINCH)
        pump(0.2)
        send(b"n")
        check("live new-task key opens workspace form", "NEW WORKSPACE TASK" in text() and not marker.exists())
        send(b"\t"*4)
        send(b"My first real task")
        pump(0.2)
        send(b"\x13")
        deadline=time.monotonic()+5
        while "Workspace task created" not in text() and time.monotonic()<deadline:
            pump(0.05)
        check("onboarding creates a real queued chat", "My first real task" in text()
              and "Workspace task created" in text() and not marker.exists())
        send(b"s")
        check("first task still requires run confirmation", "Confirm live run" in text() and not marker.exists())
        send(b"\x1b")
        send(b"q")
        wait_exit(5)
        with sqlite3.connect(directory / "new-board.sqlite") as db:
            saved=json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
        check("first live workflow stores only the created task", len(saved["tasks"])==1
              and saved["tasks"][0]["messages"][0]["text"]=="My first real task"
              and saved["tasks"][0]["runs"]==[])
        screen.reset()
        process=subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, env=env)
        wait_ready()
        send(b"e")
        check("reopening live board preserves its real chat without reseeding", "My first real task" in text()
              and "T-101" not in text() and not marker.exists())
        send(b"q")
        wait_exit(5)
        check("first live onboarding exits cleanly", process.returncode==0)


    screen.reset()
    process = subprocess.Popen([str(binary), "--no-config", "--events", str(root / "examples/events.jsonl")],
                               stdin=slave, stdout=slave, stderr=slave, env=env)
    wait_ready()
    long_title = "Implement a complete software factory workflow with persistent task channels and retain the final instruction sentinel CARD_END"
    send(b"n")
    send(long_title.encode())
    send(b"\r")
    deadline = time.monotonic() + 5
    while ("Task created in memory" not in text() or not any("…" in row for row in screen.display[4:19])) and time.monotonic() < deadline:
        pump(0.05)
    check("long title preview marks hidden text", any("…" in row for row in screen.display[4:19]))
    if args.preview:
        preview(args.preview.with_stem(args.preview.stem + "-long-card"))
    send(b"e")
    check("long card opens the complete instruction", "CARD_END" in text())
    if args.preview:
        preview(args.preview.with_stem(args.preview.stem + "-long-card-chat"))
    send(b"q")
    wait_exit(5)
    check("long-card preview exits cleanly", process.returncode == 0)



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
