"""Bounded PTY driver for opt-in terminal integrations."""

import fcntl
import os
import pty
import select
import struct
import subprocess
import termios
import time
from typing import ClassVar

import pyte


class TerminalScreen(pyte.Screen):
    def next_line(self):
        # NEL resets the column so full-width rows do not wrap twice.
        self.carriage_return()
        self.index()


class TerminalStream(pyte.ByteStream):
    escape: ClassVar[dict] = {**pyte.ByteStream.escape, "E": "next_line"}
    events = pyte.ByteStream.events | {"next_line"}


class Terminal:
    def __init__(self, command, env, columns=120, rows=36):
        self.master, self.slave = pty.openpty()
        self.process = None
        self.screen = TerminalScreen(columns, rows)
        self.stream = TerminalStream(self.screen)
        try:
            fcntl.ioctl(
                self.slave,
                termios.TIOCSWINSZ,
                struct.pack("HHHH", rows, columns, 0, 0),
            )
            self.process = subprocess.Popen(
                command,
                stdin=self.slave,
                stdout=self.slave,
                stderr=self.slave,
                env={**env, "TERM": "xterm-256color"},
            )
        except BaseException:
            os.close(self.master)
            os.close(self.slave)
            raise

    def __enter__(self):
        return self

    def __exit__(self, *_):
        try:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.wait_exit(3)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.wait_exit(3)
        finally:
            os.close(self.master)
            os.close(self.slave)

    def text(self):
        return "\n".join(self.screen.display)

    def pump(self, seconds=0.05):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            ready, _, _ = select.select(
                [self.master], [], [], max(0, deadline - time.monotonic())
            )
            if ready:
                try:
                    data = os.read(self.master, 65536)
                except OSError:
                    break
                if not data:
                    break
                self.stream.feed(data)

    def send(self, data):
        os.write(self.master, data)
        self.pump(0.15)

    def click_text(self, label, row=None):
        rows = range(self.screen.lines) if row is None else [row]
        y = next(y for y in rows if label in self.screen.display[y])
        x = self.screen.display[y].index(label)
        self.send(f"\x1b[<0;{x + 1};{y + 1}M\x1b[<0;{x + 1};{y + 1}m".encode())

    def toggle_board_view(self):
        label = "Archive" if "accepted" in self.screen.display[2] else "Session board"
        self.click_text(label, row=2)

    def wait(self, name, predicate, timeout=15):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.pump()
            if predicate():
                return
            if self.process.poll() is not None:
                raise AssertionError(
                    f"{name}: TUI exited ({self.process.returncode})\n{self.text()}"
                )
        raise AssertionError(f"{name}: timeout\n{self.text()}")

    def ready(self):
        self.wait(
            "terminal startup",
            lambda: (
                not (termios.tcgetattr(self.slave)[3] & termios.ICANON)
                and "FACTORY / terminal" in self.text()
            ),
        )

    def check(self, name, condition):
        if not condition:
            raise AssertionError(f"{name}\n{self.text()}")
        print(f"PASS: {name}")

    def wait_exit(self, timeout=5):
        # Shutdown can write terminal cleanup, so keep the PTY draining.
        deadline = time.monotonic() + timeout
        while self.process.poll() is None and time.monotonic() < deadline:
            self.pump()
        if self.process.poll() is None:
            raise subprocess.TimeoutExpired(self.process.args, timeout)
        self.pump()

    def preview(self, path):
        from PIL import Image, ImageDraw, ImageFont

        font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 17)
        width, height = 11, 23
        image = Image.new(
            "RGB", (self.screen.columns * width, self.screen.lines * height), "#131720"
        )
        draw = ImageDraw.Draw(image)
        colors = {
            "black": "#131720",
            "white": "#dae3ed",
            "cyan": "#76beda",
            "yellow": "#efb963",
            "green": "#93cb9a",
        }

        def color(value, default):
            if value in colors:
                return colors[value]
            if len(value) == 6:
                return "#" + value
            return default

        for y in range(self.screen.lines):
            for x in range(self.screen.columns):
                cell = self.screen.buffer[y][x]
                draw.rectangle(
                    (x * width, y * height, (x + 1) * width, (y + 1) * height),
                    fill=color(cell.bg, "#131720"),
                )
                draw.text(
                    (x * width, y * height),
                    cell.data,
                    font=font,
                    fill=color(cell.fg, "#dae3ed"),
                )
        image.save(path)
        print(f"Preview: {path}")
