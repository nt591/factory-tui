#!/usr/bin/env python3
"""Measure fixture-only TUI input/event-to-screen latency through a real PTY."""

import argparse
import copy
import datetime
import hashlib
import importlib.metadata
import json
import math
import os
import platform
import resource
import select
import sqlite3
import subprocess
import tempfile
import termios
import time
from pathlib import Path

from fixtures.terminal import Terminal


class Probe(Terminal):
    def __init__(self, *args, **kwargs):
        self.output_bytes = 0
        super().__init__(*args, **kwargs)

    def observe(self, predicate, timeout):
        deadline = time.perf_counter() + timeout
        while True:
            if predicate():
                return
            if self.process.poll() is not None:
                raise RuntimeError("TUI exited before the expected screen state.")
            remaining = deadline - time.perf_counter()
            if remaining <= 0:
                print(self.text())
                raise TimeoutError(
                    "Expected screen state did not arrive before deadline."
                )
            ready, _, _ = select.select([self.master], [], [], remaining)
            if ready:
                data = os.read(self.master, 65536)
                if not data:
                    raise RuntimeError("PTY closed before the expected screen state.")
                self.output_bytes += len(data)
                self.stream.feed(data)

    def latency(self, action, predicate, timeout):
        if predicate():
            raise ValueError("Expected screen state already exists before the action.")
        started = time.perf_counter()
        action()
        self.observe(predicate, timeout)
        return (time.perf_counter() - started) * 1000

    def input(self, data):
        remaining = memoryview(data)
        while remaining:
            remaining = remaining[os.write(self.master, remaining) :]

    def wait_exit(self, timeout=15):
        deadline = time.perf_counter() + timeout
        while self.process.poll() is None:
            remaining = deadline - time.perf_counter()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(self.process.args, timeout)
            ready, _, _ = select.select([self.master], [], [], min(0.01, remaining))
            if ready:
                try:
                    data = os.read(self.master, 65536)
                except OSError:
                    data = b""
                self.output_bytes += len(data)
                if data:
                    self.stream.feed(data)

    def startup(self, timeout):
        self.observe(
            lambda: (
                not (termios.tcgetattr(self.slave)[3] & termios.ICANON)
                and "FACTORY / terminal" in self.text()
                and "conversation" in self.text()
            ),
            timeout,
        )


def distribution(samples):
    ordered = sorted(samples)
    if not ordered or any(not math.isfinite(value) or value < 0 for value in ordered):
        raise ValueError("Samples must be finite, nonnegative and nonempty.")
    return {
        "samples_ms": samples,
        "count": len(samples),
        "median_ms": ordered[len(ordered) // 2]
        if len(ordered) % 2
        else (ordered[len(ordered) // 2 - 1] + ordered[len(ordered) // 2]) / 2,
        "p95_ms": ordered[math.ceil(len(ordered) * 0.95) - 1],
        "max_ms": ordered[-1],
    }


def read(database):
    with sqlite3.connect(database) as db:
        return json.loads(db.execute("SELECT payload FROM snapshot").fetchone()[0])


def seed_snapshot(saved, tasks, messages):
    seed = next(task for task in saved["tasks"] if task["state"] == "queued")
    result = copy.deepcopy(saved)
    result["tasks"] = []
    for index in range(tasks):
        task = copy.deepcopy(seed)
        task.update(
            id=f"P-{index:04}",
            title=f"Performance task {index:04}",
            repository="perf-fixture",
        )
        task["messages"] = [
            {
                "id": f"P-{index:04}/prompt",
                "author": "You",
                "text": task["title"],
                "queued": True,
            }
        ]
        if index == 0:
            task["messages"] += [
                {
                    "id": f"history-{row:05}",
                    "author": "Fixture",
                    "text": f"History row {row:05}: deterministic benchmark content.",
                    "queued": False,
                }
                for row in range(messages)
            ]
        result["tasks"].append(task)
    result.update(selected="P-0000", drafts=[], serial=tasks + messages + 100)
    return result


def rss(pid):
    value = subprocess.check_output(
        ["ps", "-o", "rss=", "-p", str(pid)], text=True, timeout=5
    ).strip()
    return int(value) * 1024


def write_report(path, report):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as output:
        temporary = Path(output.name)
        try:
            json.dump(report, output, indent=2)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def run(args, report):
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        subprocess.run([str(root / "scripts/build.sh")], cwd=root, check=True)
    binary = (args.binary or root / "_build/default/bin/main.exe").resolve()
    report.update(
        binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
        binary_bytes=binary.stat().st_size,
        platform=platform.platform(),
        architecture=platform.machine(),
        pyte_version=importlib.metadata.version("pyte"),
        python_version=platform.python_version(),
        benchmark_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        timestamp_utc=datetime.datetime.now(datetime.UTC).isoformat(),
    )
    samples = {}

    def record(name, value):
        samples.setdefault(name, []).append(value)
        report["latency"] = {
            key: distribution(values) for key, values in samples.items()
        }

    with tempfile.TemporaryDirectory(prefix="factory-e2e-perf-") as temporary:
        directory = Path(temporary)
        home = directory / "home"
        home.mkdir()
        events = directory / "events.jsonl"
        events.write_text("")
        database = directory / "board.sqlite"
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home), TMPDIR=str(directory))
        command = [
            str(binary),
            "--no-config",
            "--events",
            str(events),
            "--database",
            str(database),
        ]
        with Probe(command, env, columns=args.columns, rows=args.rows) as tui:
            tui.startup(args.timeout)
            tui.input(b"q")
            tui.wait_exit(args.timeout)
        fixture = seed_snapshot(read(database), args.tasks, args.messages)
        with sqlite3.connect(database) as db:
            db.execute("UPDATE snapshot SET payload=?", (json.dumps(fixture),))
        for iteration in range(args.runs):
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            observer_started = time.process_time()
            started = time.perf_counter()
            with Probe(command, env, columns=args.columns, rows=args.rows) as tui:
                tui.startup(args.timeout)
                tui.observe(
                    lambda: "P-0000 / Queued / conversation" in tui.text(), args.timeout
                )
                record("sqlite_startup", (time.perf_counter() - started) * 1000)
                memory = [rss(tui.process.pid)]
                for step in range(args.interactions):
                    marker = f"Reply-{iteration}-{step}"
                    actions = [
                        (
                            "board_search",
                            b"/Performance task 0001\r",
                            lambda: (
                                "P-0001 / Queued / conversation" in tui.text()
                                and "BOARD SEARCH" not in tui.screen.display[-1]
                            ),
                        ),
                        (
                            "board_reset",
                            b"b",
                            lambda: (
                                f"{args.tasks} tasks" in tui.screen.display[2]
                                and "Show card" not in tui.screen.display[2]
                            ),
                        ),
                        (
                            "card_navigation",
                            b"k",
                            lambda: "P-0000 / Queued / conversation" in tui.text(),
                        ),
                        (
                            "chat_expand",
                            b"e",
                            lambda: "e return" in tui.screen.display[-2],
                        ),
                        (
                            "composer_open",
                            b"i",
                            lambda: "INSERT / Enter queues" in tui.screen.display[-1],
                        ),
                        (
                            "paste",
                            b"\x1b[200~" + marker.encode() + b"\x1b[201~",
                            lambda marker=marker: (
                                marker in tui.text()
                                and "INSERT / Enter queues" in tui.screen.display[-1]
                            ),
                        ),
                        (
                            "queue_reply",
                            b"\r",
                            lambda marker=marker: (
                                marker in tui.text()
                                and "Reply (queued):" not in tui.text()
                            ),
                        ),
                        (
                            "history_top",
                            b"\x1b[H",
                            lambda: (
                                "History row 00000" in tui.text()
                                and "[Latest / End]" in tui.text()
                            ),
                        ),
                        (
                            "history_latest",
                            b"\x1b[F",
                            lambda marker=marker: (
                                marker in tui.text()
                                and "[Latest / End]" not in tui.text()
                                and "reading history" not in tui.text()
                            ),
                        ),
                        (
                            "chat_return",
                            b"e",
                            lambda: "e expand" in tui.screen.display[-2],
                        ),
                        (
                            "board_focus",
                            b"b",
                            lambda: "hjkl/arrows: cards" in tui.screen.display[-1],
                        ),
                    ]
                    for name, data, predicate in actions:
                        report["current_action"] = name
                        record(
                            name,
                            tui.latency(
                                lambda data=data: tui.input(data),
                                predicate,
                                args.timeout,
                            ),
                        )
                memory.append(rss(tui.process.pid))
                output_bytes = tui.output_bytes
                started = time.perf_counter()
                tui.input(b"q")
                tui.wait_exit(args.timeout)
                record("sqlite_shutdown", (time.perf_counter() - started) * 1000)
                if tui.process.returncode != 0:
                    raise RuntimeError("SQLite UI did not exit successfully.")
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            report["resources"].append(
                {
                    "workload": "sqlite",
                    "iteration": iteration,
                    "observer_cpu_seconds": time.process_time() - observer_started,
                    "child_user_cpu_seconds": after.ru_utime - before.ru_utime,
                    "child_system_cpu_seconds": after.ru_stime - before.ru_stime,
                    "rss_samples_bytes": memory,
                    "observed_terminal_bytes": output_bytes,
                }
            )
            current = read(database)
            messages = current["tasks"][0]["messages"]
            original = fixture["tasks"][0]["messages"]
            replies = messages[len(original) :]
            expected = [
                f"Reply-{run}-{step}"
                for run in range(iteration + 1)
                for step in range(args.interactions)
            ]
            if (
                messages[: len(original)] != original
                or [message["text"] for message in replies] != expected
                or not all(message["queued"] for message in replies)
                or current["tasks"][1:] != fixture["tasks"][1:]
                or current["selected"] != "P-0000"
                or current["drafts"] != [["P-0000", ""]]
            ):
                raise AssertionError(
                    "SQLite restart did not retain exact fixture history and queued replies."
                )
        events.write_text("")
        command = [str(binary), "--no-config", "--events", str(events)]
        for iteration in range(args.runs):
            events.write_text(
                "".join(
                    json.dumps(
                        {
                            "task_id": "T-102",
                            "run_id": "demo-102",
                            "type": "message",
                            "item_id": f"history-{row:05}",
                            "text": f"Replay history {row:05}",
                        }
                    )
                    + "\n"
                    for row in range(args.messages)
                )
            )
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            observer_started = time.process_time()
            started = time.perf_counter()
            with Probe(command, env, columns=args.columns, rows=args.rows) as tui:
                tui.startup(args.timeout)
                tui.observe(
                    lambda: f"Replay history {args.messages - 1:05}" in tui.text(),
                    args.timeout,
                )
                record("replay_startup_backlog", (time.perf_counter() - started) * 1000)
                memory = [rss(tui.process.pid)]
                tui.input(b"e")
                tui.observe(lambda: "e return" in tui.screen.display[-2], args.timeout)
                for step in range(args.interactions):
                    marker = f"Stream-{iteration}-{step}"
                    envelope = {
                        "task_id": "T-102",
                        "run_id": "demo-102",
                        "type": "message",
                        "item_id": "perf-stream",
                        "text": marker,
                    }

                    def append(envelope=envelope):
                        with events.open("a") as output:
                            output.write(json.dumps(envelope) + "\n")

                    report["current_action"] = "stream_replacement"
                    record(
                        "stream_replacement",
                        tui.latency(
                            append,
                            lambda marker=marker: marker in tui.text(),
                            args.timeout,
                        ),
                    )

                def complete():
                    with events.open("a") as output:
                        for event in (
                            {"type": "turn.completed"},
                            {"type": "process.exited", "code": 0},
                        ):
                            output.write(
                                json.dumps(
                                    {"task_id": "T-102", "run_id": "demo-102", **event}
                                )
                                + "\n"
                            )

                report["current_action"] = "automatic_ready"
                record(
                    "automatic_ready",
                    tui.latency(
                        complete,
                        lambda: "T-102 / Ready / conversation" in tui.text(),
                        args.timeout,
                    ),
                )
                memory.append(rss(tui.process.pid))
                output_bytes = tui.output_bytes
                tui.input(b"q")
                tui.wait_exit(args.timeout)
                if tui.process.returncode != 0:
                    raise RuntimeError("Replay UI did not exit successfully.")
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            report["resources"].append(
                {
                    "workload": "replay",
                    "iteration": iteration,
                    "observer_cpu_seconds": time.process_time() - observer_started,
                    "child_user_cpu_seconds": after.ru_utime - before.ru_utime,
                    "child_system_cpu_seconds": after.ru_stime - before.ru_stime,
                    "rss_samples_bytes": memory,
                    "observed_terminal_bytes": output_bytes,
                }
            )
        if list(home.iterdir()):
            raise AssertionError("Benchmark wrote unexpected user configuration.")
    report.pop("current_action", None)
    report["status"] = "passed"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--interactions", type=int, default=5)
    parser.add_argument("--tasks", type=int, default=200)
    parser.add_argument("--messages", type=int, default=200)
    parser.add_argument("--columns", type=int, default=120)
    parser.add_argument("--rows", type=int, default=36)
    parser.add_argument("--timeout", type=float, default=15)
    args = parser.parse_args()
    if args.report.exists():
        parser.error("Report already exists. Select a new path.")
    if not (
        1 <= args.runs <= 100
        and 1 <= args.interactions <= 100
        and 2 <= args.tasks <= 10000
        and args.rows <= args.messages <= 10000
        and 100 <= args.columns <= 300
        and 24 <= args.rows <= 100
        and 0 < args.timeout <= 120
    ):
        parser.error("Invalid workload dimensions or deadline.")
    report = {
        "status": "running",
        "schema_version": 1,
        "scope": "Fixture-only process/PTY/SQLite and replay. No agent, credentials, network, real workspace or GUI comparison.",
        "measurement": "perf_counter input/event-write to expected parsed PTY screen. Includes app loop, output transport and pyte observer; excludes terminal GUI paint. No fixed post-input sleeps. No warmup removal. Repeated local launches, not cold-OS launches.",
        "resource_scope": "RSS samples are main TUI process, not peak. Child CPU includes two ps samplers per workload; bootstrap/build excluded. Shutdown includes PTY drain and SQLite flush, with up to 10 ms exit-observation quantization. Terminal-byte counts stop before shutdown.",
        "parameters": {
            key: value
            for key, value in vars(args).items()
            if key not in ("binary", "report")
        },
        "latency": {},
        "resources": [],
    }
    try:
        run(args, report)
    except BaseException as error:
        report.update(
            status="interrupted" if isinstance(error, KeyboardInterrupt) else "failed",
            error=f"{type(error).__name__}: {error}",
        )
        raise
    finally:
        write_report(args.report, report)
    print(f"PASS: E2E perf evidence: {args.report}")
    for name, values in report["latency"].items():
        print(
            f"{name}: median {values['median_ms']:.3f} ms / p95 {values['p95_ms']:.3f} ms / n={values['count']}"
        )


if __name__ == "__main__":
    main()
