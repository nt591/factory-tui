#!/usr/bin/env python3
"""Interactively write private, non-secret live TUI configuration. Start no agents."""

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def ask(label, default="", validate=lambda value: True):
    while True:
        value = (
            input(f"{label}" + (f" [{default}]" if default else "") + ": ").strip()
            or default
        )
        if validate(value):
            return value
        print("Invalid value. Please try again.")


def clean(value):
    return (
        bool(value)
        and len(value) <= 4096
        and all(ord(char) >= 32 and ord(char) != 127 for char in value)
    )


def path(value):
    return Path(value).expanduser().absolute()


def executable(value):
    candidate = path(value)
    return clean(value) and candidate.is_file() and os.access(candidate, os.X_OK)


def variable(value):
    return (
        len(value) <= 256 and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value) is not None
    )


def model(value):
    return (
        clean(value)
        and len(value.encode("utf-8")) <= 256
        and not value.startswith("-")
        and value not in ("your-model-id", "coding-large")
        and not any(char.isspace() for char in value)
    )


def toml(sections):
    return (
        "\n\n".join(
            f"[{section}]\n"
            + "\n".join(
                f"{key} = {json.dumps(value, ensure_ascii=False)}"
                for key, value in fields.items()
            )
            for section, fields in sections.items()
        )
        + "\n"
    )


def install(files, binary, home):
    created = []
    try:
        with tempfile.TemporaryDirectory(prefix="factory-setup-") as temporary:
            staging = Path(temporary)
            for index, (destination, text) in enumerate(files.items()):
                staged = staging / f"{index}.toml"
                staged.write_text(text)
                staged.chmod(0o600)
                if destination.name == "config.toml":
                    result = subprocess.run(
                        [str(binary), "--check-config", str(staged)],
                        check=False,
                        env={"HOME": str(home), "PATH": os.defpath},
                        capture_output=True,
                        timeout=10,
                    )
                    if result.returncode != 0:
                        raise ValueError(
                            "Generated configuration failed validation. No files saved."
                        )
            for destination, text in files.items():
                destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                with tempfile.NamedTemporaryFile(
                    dir=destination.parent, delete=False
                ) as output:
                    staged = Path(output.name)
                    output.write(text.encode())
                    output.flush()
                    os.fsync(output.fileno())
                try:
                    # A hard link publishes complete bytes and refuses existing paths atomically.
                    os.link(staged, destination)
                    created.append(destination)
                finally:
                    staged.unlink(missing_ok=True)
    except BaseException:
        for destination in created:
            destination.unlink(missing_ok=True)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config-dir",
        type=Path,
        help="New config location; existing files are never replaced.",
    )
    parser.add_argument(
        "--binary",
        type=Path,
        help="Existing TUI executable used only for config validation.",
    )
    args = parser.parse_args()
    home = Path.home()
    xdg = os.environ.get("XDG_CONFIG_HOME", "")
    base = Path(xdg) if xdg and Path(xdg).is_absolute() else home / ".config"
    directory = (args.config_dir or base / "factory-tui").expanduser().absolute()
    files = (directory / "config.toml", directory / "gateway.toml")
    if any(os.path.lexists(file) for file in files):
        parser.error(
            "Configuration already exists. Nothing was changed. Edit it or choose --config-dir PATH."
        )
    binary = (args.binary or ROOT / "_build/default/bin/main.exe").absolute()
    if args.binary is None and not binary.exists():
        print(
            "Building the TUI for config validation; no agent or gateway request starts."
        )
        subprocess.run([str(ROOT / "scripts/build.sh")], check=True, timeout=180)
    if not binary.is_file() or not os.access(binary, os.X_OK):
        parser.error("TUI binary is missing or not executable. Build it first.")
    print("Factory TUI setup — no model requests, credentials or agent launches.")
    print("Enter environment VARIABLE NAMES only. Do not paste an API key.")
    codex = ask("Codex executable", shutil.which("codex") or "", executable)
    url_name = ask("Gateway URL environment variable", "LITELLM_BASE_URL", variable)
    key_name = ask("Gateway key environment variable", "LITELLM_API_KEY", variable)
    chosen_model = ask("Exact model ID (from your gateway catalogue)", validate=model)
    effort = ask(
        "Reasoning effort: default / low / medium / high",
        "low",
        lambda value: value in ("default", "low", "medium", "high"),
    )
    mode = ask(
        "Working area: folder / existing / greenfield",
        "folder",
        lambda value: value in ("folder", "existing", "greenfield"),
    )
    workspace = {"mode": mode, "model": chosen_model}
    if mode != "greenfield":
        label = (
            "Existing session folder"
            if mode == "folder"
            else "Existing jj project repository"
        )
        source = ask(
            label,
            validate=lambda value: (
                clean(value)
                and path(value).is_dir()
                and (mode == "folder" or (path(value) / ".jj").is_dir())
            ),
        )
        workspace["source"] = str(path(source).resolve())
    if mode != "folder":
        workspace["jj"] = str(
            path(ask("jj executable", shutil.which("jj") or "", executable))
        )
        workspace["parent"] = str(
            path(
                ask(
                    "Existing workspace parent folder",
                    validate=lambda value: clean(value) and path(value).is_dir(),
                )
            )
        )
        if mode == "existing":
            workspace["revision"] = ask(
                "Base revision",
                "@",
                lambda value: (
                    clean(value) and len(value) <= 1024 and not value.startswith("-")
                ),
            )
    database = str(
        path(
            ask(
                "SQLite file (created by the TUI, not setup)",
                str(directory / "board.sqlite"),
                clean,
            )
        )
    )
    codex_fields = {"executable": str(path(codex)), "gateway": str(files[1])}
    if effort != "default":
        codex_fields["reasoning_effort"] = effort
    config = toml(
        {
            "storage": {"database": database},
            "codex": codex_fields,
            "workspace": workspace,
        }
    )
    gateway = f"base_url_environment = {json.dumps(url_name)}\nkey_environment = {json.dumps(key_name)}\n"
    print(f"\nSave config to {files[0]} and environment references to {files[1]}?")
    print(
        f"Mode: {mode}. Model: {chosen_model}. Setup creates no database or workspace."
    )
    if ask("Save: yes / no", "no", lambda value: value in ("yes", "no")) != "yes":
        print("Cancelled. No configuration saved.")
        return
    install({files[0]: config, files[1]: gateway}, binary, home)
    print("Saved private config files (0600). Your environment key was not read.")
    print("Read-only launch; each run still needs confirmation:")
    print(
        shlex.join(
            [str(ROOT / "scripts/run.sh"), "--live-ui", "--config", str(files[0])]
        )
    )
    print(
        "Add --workspace-write only when you intend writes. Existing folder mode is not an isolated checkout."
    )


if __name__ == "__main__":
    try:
        main()
    except (EOFError, KeyboardInterrupt):
        print("\nCancelled. No agent was started.")
        raise SystemExit(130) from None
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(
            f"Setup failed: {type(error).__name__}. No agent was started; inspect configuration before retrying."
        )
        raise SystemExit(2) from None
