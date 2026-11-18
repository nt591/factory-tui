#!/usr/bin/env python3
"""Measure the local executable and an isolated clean build, without model calls."""
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="factory-clean-build-") as temporary:
    build = Path(temporary) / "build"
    env = {**os.environ, "FACTORY_BUILD_DIR": str(build)}
    started = time.perf_counter()
    result = subprocess.run([str(root / "scripts/build.sh")], cwd=root, env=env,
                            capture_output=True, text=True, timeout=120)
    build_seconds = time.perf_counter() - started
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    binary = build / "default/bin/main.exe"
    latencies = []
    for _ in range(10):
        started = time.perf_counter()
        subprocess.run([str(binary), "--version"], check=True, stdout=subprocess.DEVNULL)
        latencies.append(time.perf_counter() - started)
    print(json.dumps({
        "platform": platform.platform(),
        "architecture": platform.machine(),
        "compiler": subprocess.check_output(
            ["opam", "exec", f"--switch={root}", "--", "ocamlc", "-version"], text=True).strip(),
        "binary_bytes": binary.stat().st_size,
        "clean_build_seconds": round(build_seconds, 3),
        "version_startup_median_ms": round(sorted(latencies)[len(latencies) // 2] * 1000, 3),
        "scope": "Dependencies already installed; fresh Dune build directory. Version startup, not UI readiness.",
        "comparison": "No native-GUI comparison performed."
    }, indent=2))
