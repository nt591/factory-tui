#!/usr/bin/env python3
"""Run local fixture UI checks sequentially against one executable and retain evidence."""

import argparse
import hashlib
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASES = (
    "terminal",
    "sidebar",
    "columns",
    "board-history",
    "board-navigation",
    "board-summary",
    "chat-author",
    "chat-reflow",
    "composer",
    "confirmation",
    "layout-config",
    "input-limit",
    "input-feedback",
    "restart-selection",
    "queue-summary",
    "review-notice",
    "panes",
)


def plan(binary, output, cases, build):
    steps = []
    if build:
        steps.extend(
            [
                ("format", [str(ROOT / "scripts/format.sh"), "--check"]),
                ("unit", [str(ROOT / "scripts/check.sh")]),
            ]
        )
    steps.extend(
        (
            case,
            [
                sys.executable,
                "-u",
                str(ROOT / f"scripts/smoke-{case}.py"),
                "--binary",
                str(binary),
                "--preview",
                str(output / f"{case}.png"),
            ],
        )
        for case in cases
    )
    return steps


def write_report(path, report):
    staged = path.with_suffix(".tmp")
    staged.write_text(json.dumps(report, indent=2) + "\n")
    staged.replace(path)


def finalize_report(output, report, binary):
    if binary.is_file():
        report["binary_sha256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
    report["previews"] = sorted(path.name for path in output.glob("*.png"))
    write_report(output / "report.json", report)


def stop_process(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


def run_command(command, log):
    with subprocess.Popen(
        command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True
    ) as process:
        try:
            return process.wait()
        except BaseException:
            stop_process(process)
            raise


def execute(steps, output, report, *, run=run_command):
    path = output / "report.json"
    report["steps"] = [
        {"name": name, "status": "not_run", "log": f"{name}.log"} for name, _ in steps
    ]
    report["status"] = "running"
    write_report(path, report)
    for index, (name, command) in enumerate(steps):
        step = report["steps"][index]
        step["status"] = "running"
        write_report(path, report)
        print(f"RUN: {name}", flush=True)
        started = time.monotonic()
        try:
            with (output / step["log"]).open("wb") as log:
                returncode = run(command, log)
        except (OSError, subprocess.SubprocessError) as error:
            step.update(
                status="failed",
                seconds=time.monotonic() - started,
                error_type=type(error).__name__,
            )
            report["status"] = "failed"
            write_report(path, report)
            print(
                f"FAIL: {name}; {type(error).__name__}; inspect {output / step['log']}",
                flush=True,
            )
            return 1
        except BaseException:
            step.update(status="interrupted", seconds=time.monotonic() - started)
            report["status"] = "interrupted"
            write_report(path, report)
            raise
        step.update(
            status="passed" if returncode == 0 else "failed",
            returncode=returncode,
            seconds=time.monotonic() - started,
        )
        report["status"] = "running" if returncode == 0 else "failed"
        write_report(path, report)
        if returncode != 0:
            print(f"FAIL: {name}; inspect {output / step['log']}", flush=True)
            return 1
        print(f"PASS: {name} ({step['seconds']:.1f}s)", flush=True)
    report["status"] = "passed"
    write_report(path, report)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--list", action="store_true", help="List cases without building or running"
    )
    parser.add_argument(
        "--case",
        action="append",
        choices=CASES,
        help="Run only named cases; repeatable",
    )
    parser.add_argument(
        "--binary",
        type=Path,
        help="Use an existing executable; skip format/build/unit gates",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="New directory for logs, report and previews; refuses existing paths",
    )
    args = parser.parse_args()
    if args.list:
        print("\n".join(CASES))
        return 0
    try:
        import PIL  # noqa: F401
        import pyte  # noqa: F401
    except ImportError:
        parser.error(
            "Run with: uv run --with pyte --with pillow python scripts/check-ui.py"
        )
    if args.binary is not None and (
        not args.binary.is_file() or not os.access(args.binary, os.X_OK)
    ):
        parser.error("--binary must name an existing executable")
    output = args.output.expanduser().absolute() if args.output else None
    if output is not None and (output.exists() or not output.parent.is_dir()):
        parser.error("--output must be a new directory with an existing parent")
    build_directory = Path(os.environ.get("FACTORY_BUILD_DIR", ROOT / "_build"))
    if not build_directory.is_absolute():
        build_directory = ROOT / build_directory
    binary = (args.binary or build_directory / "default/bin/main.exe").resolve()
    selected = set(args.case or CASES)
    cases = [case for case in CASES if case in selected]
    # Evidence contains fixture conversations. Keep it private and never overwrite a run.
    previous_umask = os.umask(0o077)
    try:
        if output is None:
            output = Path(tempfile.mkdtemp(prefix="factory-ui-check-")).resolve()
        else:
            output.mkdir(mode=0o700)
        report = {
            "scope": "Local fixture UI only. No installed agent or real model calls. Not provider/security/release validation.",
            "binary": str(binary),
            "cases": cases,
            "build_and_unit_gates": args.binary is None,
        }
        print(f"Evidence: {output}", flush=True)
        try:
            result = execute(
                plan(binary, output, cases, args.binary is None), output, report
            )
        finally:
            finalize_report(output, report, binary)
        print(f"Report: {output / 'report.json'}", flush=True)
        return result
    finally:
        os.umask(previous_umask)


if __name__ == "__main__":
    raise SystemExit(main())
