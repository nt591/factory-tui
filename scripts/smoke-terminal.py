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
    pump(0.4)
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
    process.wait(timeout=3)
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
    pump(0.4)
    check("JSONL fixture moves task to Ready", "T-102 / Ready / conversation" in text())
    check("replay mode is visible", "FIXTURE REPLAY" in text())
    process.terminate()
    process.wait(timeout=3)
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
        pump(0.4)
        send(b"hgg")
        send(b"s")
        send(b"iReply after launch\r")
        send(b"iSaved draft\x1b")
        send(b"q")
        process.wait(timeout=3)
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
        pump(0.4)
        send(b"e")
        check("UI restart recovers working task", "T-101 / Needs you / conversation" in text())
        send(b"i")
        check("UI restart restores draft", "Saved draft" in text())
        send(b"\x1b")
        send(b"q")
        process.wait(timeout=3)
        check("reopened UI exits cleanly", process.returncode == 0)
        with sqlite3.connect(database) as db:
            check("ordered fixture events persisted", db.execute("SELECT count(*) FROM events").fetchone()[0] > 0)
        default_dir = Path(directory) / "factory-tui"
        default_dir.mkdir()
        (default_dir / "config.toml").write_text('[storage]\ndatabase = "../board.sqlite"\n')
        screen.reset()
        process = subprocess.Popen([str(binary)], stdin=slave, stdout=slave, stderr=slave,
                                   env={**env, "XDG_CONFIG_HOME": directory})
        pump(0.4)
        send(b"e")
        check("argument-free startup discovers TOML", "T-101 / Needs you / conversation" in text())
        send(b"q")
        process.wait(timeout=3)
        check("default-config UI exits cleanly", process.returncode == 0)

    with tempfile.TemporaryDirectory(prefix="factory-process-ui-") as directory:
        database = Path(directory) / "board.sqlite"
        screen.reset()
        process = subprocess.Popen([str(binary), "--fake-harness", "--no-config", "--database", str(database)],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        pump(0.4)
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
        process.wait(timeout=3)
        check("fake UI SIGTERM cancels and exits", process.returncode == 0)
        with sqlite3.connect(database) as db:
            saved = json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])
            task = next(t for t in saved["tasks"] if t["id"] == "T-101")
            check("shutdown records fixture interruption", task["state"] == "needs_you" and task["active"] is None)
            check("process events are stored", db.execute("SELECT count(*) FROM events").fetchone()[0] > 0)

finally:
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=3)
    os.close(master)
    os.close(slave)
