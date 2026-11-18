#!/usr/bin/env python3
"""Build and inspect a package using only temporary output and install directories."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile

root = Path(__file__).resolve().parent.parent
checks = 0


def check(name, condition):
    global checks
    checks += 1
    if not condition:
        raise AssertionError(name)


def invoke(command, **kwargs):
    return subprocess.run(command, cwd=root, text=True, capture_output=True, timeout=120, **kwargs)


with tempfile.TemporaryDirectory(prefix="factory-package-") as temporary:
    temporary = Path(temporary)
    archive = temporary / "factory.tar.gz"
    result = invoke(["python3", "scripts/package.py", "--output", str(archive)])
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    check("archive created", archive.is_file())
    second = temporary / "repeat.tar.gz"
    result = invoke(["python3", "scripts/package.py", "--output", str(second)])
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    check("same build packages repeatably", archive.read_bytes() == second.read_bytes())
    extracted = temporary / "extracted"
    extracted.mkdir()
    with tarfile.open(archive) as tar:
        members = tar.getmembers()
        check("archive entries are relative regular files", all(
            item.isfile() and not item.name.startswith("/") and ".." not in Path(item.name).parts
            for item in members))
        check("archive excludes user config and storage", all(
            not item.name.endswith((".sqlite", ".lock")) and "_opam" not in Path(item.name).parts
            for item in members))
        tar.extractall(extracted)
    package = next(extracted.iterdir())
    binary = package / "bin/factory-tui"
    metadata = json.loads((package / "build.json").read_text())
    check("binary digest verified", metadata["binary_sha256"] == hashlib.sha256(binary.read_bytes()).hexdigest())
    check("compiler recorded", metadata["compiler"] == "5.3.0")
    env = {"PATH": "/usr/bin:/bin", "HOME": str(temporary), "LANG": "en_US.UTF-8"}
    result = invoke([str(binary), "--version"], env=env)
    check("binary runs without opam on PATH", result.returncode == 0 and result.stdout.strip() == "factory-tui 0.1.0")
    result = invoke([str(binary), "--snapshot", "--size", "80x24"], env=env)
    check("packaged snapshot renders", result.returncode == 0 and "FACTORY / terminal" in result.stdout)
    check("snapshot creates no default config", not (temporary / ".config").exists())
    result = invoke(["python3", "scripts/package.py", "--output", str(archive)])
    check("existing archive refused", result.returncode != 0)
    prefix = temporary / "install"
    result = invoke([str(root / "scripts/install.sh"), "--prefix", str(prefix)])
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    installed = prefix / "bin/factory-tui"
    check("explicit temporary install works", installed.is_file() and os.access(installed, os.X_OK))
    result = invoke([str(installed), "--version"], env=env)
    check("installed command works without checkout environment", result.returncode == 0)
    original_digest = hashlib.sha256(installed.read_bytes()).hexdigest()
    result = invoke([str(root / "scripts/install.sh"), "--prefix", str(prefix)])
    check("existing installed binary refused", result.returncode != 0
          and hashlib.sha256(installed.read_bytes()).hexdigest() == original_digest)
    check("install writes only the binary", sorted(path.name for path in (prefix / "bin").iterdir()) == ["factory-tui"])

print(f"Passed {checks} package checks. Temporary install only; no user files modified.")
