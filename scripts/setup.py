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


def discover_models(binary, gateway, url_name, key_name):
    with tempfile.TemporaryDirectory(prefix="factory-setup-models-") as temporary:
        filename = Path(temporary) / "gateway.toml"
        filename.write_text(gateway)
        filename.chmod(0o600)
        env = {"PATH": os.defpath, "HOME": temporary}
        for name in (url_name, key_name):
            value = os.environ.get(name)
            if value is not None:
                env[name] = value
        try:
            result = subprocess.run(
                [str(binary), "--list-models", "--gateway", str(filename)],
                check=False,
                env=env,
                capture_output=True,
                text=True,
                timeout=15,
            )
            if result.returncode != 0:
                print(
                    "Model discovery failed. Check the exported URL/key and gateway access."
                )
                return None
            models = json.loads(result.stdout)["models"]
            if (
                not isinstance(models, list)
                or len(models) > 10000
                or not all(isinstance(value, str) and model(value) for value in models)
            ):
                raise ValueError("Invalid catalogue")
            return sorted(set(models))
        except (OSError, ValueError, KeyError, subprocess.SubprocessError):
            print(
                "Model discovery failed or returned an invalid catalogue. Response withheld."
            )
            return None


def choose_default(binary, gateway, url_name, key_name):
    print("The default model is optional and applies to new tasks only.")
    print(
        "Fetch contacts your gateway and reads the referenced API key; no agent runs."
    )
    while True:
        action = ask(
            "Default model: fetch / retry / skip / manual",
            "fetch",
            lambda value: value in ("fetch", "retry", "skip", "manual"),
        )
        if action == "skip":
            return None
        if action == "manual":
            return ask("Default model ID (manual fallback)", validate=model)
        models = discover_models(binary, gateway, url_name, key_name)
        if models is None:
            continue
        if not models:
            print(
                "The gateway returned no models. Retry, skip or enter a model manually."
            )
            continue
        query = ""
        while True:
            matches = [value for value in models if query.lower() in value.lower()]
            print(
                f"\n{len(matches)} matching models. Listed IDs do not prove Codex compatibility."
            )
            for index, value in enumerate(matches[:30], 1):
                print(f"  {index}. {value}")
            if len(matches) > 30:
                print("More models exist; type a filter to narrow the list.")
            choice = input(
                "Number selects; text filters; Enter resets; /retry or /skip: "
            ).strip()
            if choice == "/skip":
                return None
            if choice == "/retry":
                break
            if choice.isdigit() and 1 <= int(choice) <= min(30, len(matches)):
                return matches[int(choice) - 1]
            query = choice


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
        help="Existing TUI executable for config validation and optional model discovery.",
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
    print(
        "Factory TUI setup — no agent launches. Optional discovery contacts your gateway."
    )
    print("Enter environment VARIABLE NAMES only. Do not paste an API key.")
    codex = ask("Codex executable", shutil.which("codex") or "", executable)
    url_name = ask("Gateway URL environment variable", "LITELLM_BASE_URL", variable)
    key_name = ask("Gateway key environment variable", "LITELLM_API_KEY", variable)
    gateway = f"base_url_environment = {json.dumps(url_name)}\nkey_environment = {json.dumps(key_name)}\n"
    chosen_model = choose_default(binary, gateway, url_name, key_name)
    effort = ask(
        "Reasoning effort: default / low / medium / high",
        "low",
        lambda value: value in ("default", "low", "medium", "high"),
    )
    mode = "folder"
    workspace = {"mode": mode}
    if chosen_model is not None:
        workspace["model"] = chosen_model
    print("New tasks start in the directory where you launch the TUI.")
    print(
        "Repository/workspace creation remains available per task; setup does not choose a project."
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
    print(f"\nSave config to {files[0]} and environment references to {files[1]}?")
    print(
        f"Mode: {mode}. Default model: {chosen_model or 'none; select per task'}. Setup creates no database or workspace."
    )
    if ask("Save: yes / no", "no", lambda value: value in ("yes", "no")) != "yes":
        print("Cancelled. No configuration saved.")
        return
    install({files[0]: config, files[1]: gateway}, binary, home)
    print("Saved private config files (0600). No API key value was saved.")
    print("Read-only launch; each run still needs confirmation:")
    print(
        shlex.join(
            [str(ROOT / "scripts/run.sh"), "--live-ui", "--config", str(files[0])]
        )
    )
    print(
        "Launch from the directory you want to work in. Add --workspace-write for edits; the starting directory is not an isolated checkout."
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
