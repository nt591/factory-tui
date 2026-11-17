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

import pyte

parser = argparse.ArgumentParser()
parser.add_argument("--preview", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
binary = root / "_build/default/bin/main.exe"
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
process = subprocess.Popen([str(binary)], stdin=slave, stdout=slave, stderr=slave, env=env)


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
    if args.preview:
        preview(args.preview)
    # SGR mouse positions are one-based terminal cells.
    send(b"\x1b[<0;3;5M\x1b[<0;3;5m")
    check("mouse selects a queued card", "T-101 / Queued / conversation" in text())
    send(b"e")
    check("task expansion hides the board", "Queued 3" not in text() and "T-101 / Queued / conversation" in text())
    send(b"\x1b")
    pump(0.2)
    check("Escape restores the board", "Queued 3" in text())
    send(b"i")
    send(b"\x1b[200~sxa\x1b[201~")
    check("paste edits without executing shortcuts", "Reply (queued): sxa" in text())
    send(b"\r")
    check("reply enters conversation", "sxa" in text() and "Reply queued" in text())
    send(b"s")
    check("fixture start automatically moves card", "T-101 / Working / conversation" in text())
    pump(8.0)
    check("completion automatically moves card to Ready", "T-101 / Ready / conversation" in text())
    send(b"a")
    send(b"d")
    check("accepted tasks appear in archive", "T-101" in text() and "Done" in text())
    send(b"?")
    check("help opens", "Panes" in text() or "Press ? or Escape" in text())
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
    process = subprocess.Popen([str(binary), "--events", str(root / "examples/events.jsonl")],
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
finally:
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=3)
    os.close(master)
    os.close(slave)
