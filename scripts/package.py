#!/usr/bin/env python3
"""Package a verified local executable; this does not install or launch an agent."""
import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
VERSION = "0.1.0"


def output(command):
    return subprocess.check_output(command, cwd=ROOT, text=True).strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True, help="New archive path; existing files are refused")
    args = parser.parse_args()
    archive = args.output.expanduser().absolute()
    if archive.exists():
        parser.error("Output already exists; choose a new archive path.")
    if not archive.parent.is_dir():
        parser.error("Output parent must already exist.")
    subprocess.run([str(ROOT / "scripts/format.sh"), "--check"], cwd=ROOT, check=True)
    subprocess.run([str(ROOT / "scripts/check.sh")], cwd=ROOT, check=True)
    build_dir = Path(os.environ.get("FACTORY_BUILD_DIR", ROOT / "_build"))
    if not build_dir.is_absolute():
        build_dir = ROOT / build_dir
    binary = build_dir / "default/bin/main.exe"
    if not binary.is_file():
        parser.error("Expected executable is missing from the selected build directory.")
    switch = os.environ.get("FACTORY_OPAM_SWITCH", str(ROOT))
    metadata = {
        "version": VERSION,
        "platform": platform.system(),
        "architecture": platform.machine(),
        "revision": output(["jj", "log", "-r", "@-", "--no-graph", "-T", "commit_id"]),
        "working_copy_clean": output(["jj", "diff", "--summary"]) == "",
        "compiler": output(["opam", "exec", f"--switch={switch}", "--", "ocamlc", "-version"]),
        "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "packages": output(["opam", "list", f"--switch={switch}", "--installed", "--columns=name,version", "--short"]),
    }
    prefix = f"factory-tui-{VERSION}-{platform.system().lower()}-{platform.machine()}"
    files = {"bin/factory-tui": (binary.read_bytes(), 0o755),
             "README.md": ((ROOT / "README.md").read_bytes(), 0o644),
             "examples/config.toml": ((ROOT / "examples/config.toml").read_bytes(), 0o644),
             "examples/gateway.toml": ((ROOT / "examples/gateway.toml").read_bytes(), 0o644),
             "examples/live-test.toml": ((ROOT / "examples/live-test.toml").read_bytes(), 0o644),
             "examples/litellm.toml": ((ROOT / "examples/litellm.toml").read_bytes(), 0o644),
             "build.json": ((json.dumps(metadata, indent=2) + "\n").encode(), 0o644)}
    for name in ("harness.md", "workspaces.md", "distribution.md", "configuration.md", "gateway.md", "sessions.md"):
        files["docs/" + name] = ((ROOT / "docs" / name).read_bytes(), 0o644)
    # Fixed archive metadata makes packaging the same bytes repeatable.
    with tempfile.NamedTemporaryFile(dir=archive.parent, delete=False) as temporary:
        staged = Path(temporary.name)
    try:
        with staged.open("wb") as destination:
            with gzip.GzipFile(fileobj=destination, mode="wb", filename="", mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as tar:
                    for name, (data, mode) in sorted(files.items()):
                        info = tarfile.TarInfo(prefix + "/" + name)
                        info.size, info.mode, info.mtime = len(data), mode, 0
                        info.uid = info.gid = 0
                        tar.addfile(info, io.BytesIO(data))
        os.link(staged, archive)
    finally:
        staged.unlink(missing_ok=True)
    print(f"Package: {archive}")
    print(f"SHA256: {hashlib.sha256(archive.read_bytes()).hexdigest()}")
    print("Local platform package only. No installation, signing, or model call.")


if __name__ == "__main__":
    main()
