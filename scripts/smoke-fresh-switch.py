#!/usr/bin/env python3
"""Opt in to compiler/dependency reconstruction in a temporary opam root."""

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import tempfile
import time
from pathlib import Path


def verify_versions(lock, installed):
    if "depends: [" not in lock or "]" not in lock.split("depends: [", 1)[1]:
        raise ValueError("The lock must contain a dependency block")
    dependency_block = lock.split("depends: [", 1)[1].split("]", 1)[0]
    expected = {}
    for line in dependency_block.splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r'\s*"([^"\n]+)"\s*\{= "([^"\n]+)"\}\s*', line)
        if match is None:
            raise ValueError(
                "Fresh-switch check requires exact locked dependency versions"
            )
        name, version = match.groups()
        if name in expected:
            raise ValueError("Duplicate locked dependency")
        expected[name] = version
    actual = dict(line.split() for line in installed.splitlines() if line.strip())
    mismatches = {
        name: {"expected": version, "installed": actual.get(name)}
        for name, version in expected.items()
        if actual.get(name) != version
    }
    if mismatches:
        raise ValueError(
            "Installed versions differ from lock: " + json.dumps(mismatches)
        )
    if not expected:
        raise ValueError("The lock must contain dependencies")
    return len(expected)


def compiler_overrides(enabled, system):
    if not enabled:
        return {}
    if system != "Darwin":
        raise ValueError("The macOS compiler workaround is supported only on macOS")
    return {
        "ac_cv_func_pipe2": "no",
        "ac_cv_func_dup3": "no",
        "ac_cv_func_accept4": "no",
        "ac_cv_func_ppoll": "no",
        "MACOSX_DEPLOYMENT_TARGET": "14.0",
    }


def package_log_tails(root, command_log):
    logs = root / "log"
    named = [
        logs / Path(value).name
        for value in re.findall(r"# output-file\s+(\S+\.out)", command_log)
    ]
    named = [file for file in named if file.is_file()]
    recent = (
        named[-5:]
        or sorted(logs.glob("*.out"), key=lambda file: file.stat().st_mtime)[-5:]
    )
    tails = {}
    for file in recent:
        with file.open("rb") as source:
            source.seek(max(0, file.stat().st_size - 12000))
            tails[file.name] = source.read(12000).decode(errors="replace")
    return tails


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--reconstruct",
        action="store_true",
        required=True,
        help="Explicit opt-in to downloads and compiler/dependency builds",
    )
    parser.add_argument(
        "--macos-compiler-workaround",
        action="store_true",
        help="Explicit configure overrides for the documented macOS SDK/runtime mismatch",
    )
    parser.add_argument(
        "--report", type=Path, required=True, help="New JSON report path"
    )
    args = parser.parse_args()
    report = args.report.expanduser().absolute()
    if report.exists() or not report.parent.is_dir():
        parser.error("Report must be a new path in an existing directory")
    repo = Path(__file__).resolve().parent.parent
    opam = shutil.which("opam")
    if not opam:
        parser.error("opam must be installed")
    overrides = compiler_overrides(args.macos_compiler_workaround, platform.system())
    stages = []
    with tempfile.TemporaryDirectory(prefix="factory-fresh-switch-") as temporary:
        directory = Path(temporary).resolve()
        env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("OPAM", "OCAML", "CAML", "FACTORY_", "ac_cv_"))
            and key != "MACOSX_DEPLOYMENT_TARGET"
        }
        env.update(OPAMROOT=str(directory / "opam-root"), OPAMYES="1", OPAMJOBS="4")
        env.update(overrides)
        switch = "factory-lock-check"
        env.update(
            FACTORY_OPAM_SWITCH=switch, FACTORY_BUILD_DIR=str(directory / "build")
        )
        logfile = directory / "commands.log"

        def run(name, command, timeout=900):
            print(f"CHECK: {name}", flush=True)
            started = time.monotonic()
            with logfile.open("ab") as output:
                output.write(("\n" + name + "\n").encode())
                child = subprocess.Popen(
                    command,
                    cwd=repo,
                    env=env,
                    stdout=output,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
                try:
                    code = child.wait(timeout=timeout)
                except BaseException:
                    # Build children share this process group, not the user's shell group.
                    try:
                        os.killpg(child.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    try:
                        child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(child.pid, signal.SIGKILL)
                        child.wait()
                    raise
            stages.append(
                {
                    "name": name,
                    "seconds": round(time.monotonic() - started, 3),
                    "exit_code": code,
                }
            )
            if code:
                raise RuntimeError(
                    f"{name} failed ({code}):\n"
                    + logfile.read_text(errors="replace")[-12000:]
                )

        try:
            run(
                "isolated opam metadata",
                [opam, "init", "--bare", "--no-setup", "--yes"],
                180,
            )
            run(
                "empty compiler switch",
                [opam, "switch", "create", switch, "--empty", "--no-switch", "--yes"],
                180,
            )
            run(
                "locked application dependencies",
                [
                    opam,
                    "install",
                    f"--switch={switch}",
                    "--locked",
                    "--deps-only",
                    ".",
                    "--yes",
                ],
                1800,
            )
            installed = subprocess.check_output(
                [
                    opam,
                    "list",
                    f"--switch={switch}",
                    "--installed",
                    "--columns=name,version",
                    "--short",
                ],
                env=env,
                cwd=repo,
                text=True,
                timeout=30,
            )
            checked_packages = verify_versions(
                (repo / "factory_tui.opam.locked").read_text(), installed
            )
            run("fresh application build", [str(repo / "scripts/build.sh"), "@install"])
            run("fresh parallel tests", [str(repo / "scripts/check.sh")])
            binary = directory / "build/default/bin/main.exe"
            run("fresh binary version", [str(binary), "--version"], 10)
            run(
                "fresh binary terminal workflow",
                [
                    "uv",
                    "run",
                    "--with",
                    "pyte",
                    "python",
                    str(repo / "scripts/smoke-terminal.py"),
                    "--binary",
                    str(binary),
                ],
                240,
            )
            data = {
                "result": "passed",
                "stages": stages,
                "packages": installed,
                "verified_locked_packages": checked_packages,
                "compiler_overrides": overrides,
                "lock_sha256": hashlib.sha256(
                    (repo / "factory_tui.opam.locked").read_bytes()
                ).hexdigest(),
                "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                "platform": platform.platform(),
                "scope": "Fresh temporary opam root/switch and Dune build; local system tools/libraries and network remain prerequisites. No model calls, user installation, or cross-OS claim.",
            }
            with report.open("x") as destination:
                destination.write(json.dumps(data, indent=2) + "\n")
            print(
                f"PASS: fresh locked build, parallel tests, and terminal workflow; report {report}"
            )
        except (RuntimeError, ValueError, subprocess.SubprocessError) as error:
            failure = {
                "result": "failed",
                "stages": stages,
                "error": str(error),
                "log_tail": logfile.read_text(errors="replace")[-12000:],
                "package_log_tails": package_log_tails(
                    directory / "opam-root", logfile.read_text(errors="replace")
                ),
                "compiler_overrides": overrides,
            }
            with report.open("x") as destination:
                destination.write(json.dumps(failure, indent=2) + "\n")
            raise


if __name__ == "__main__":
    main()
