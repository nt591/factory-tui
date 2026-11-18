# Local distribution and startup

## Install one command

```sh
./scripts/install.sh --prefix "$HOME/.local"
~/.local/bin/factory-tui --version
```

Installation is explicit and creates only `<prefix>/bin/factory-tui`. It refuses
an existing file or symlink instead of replacing a potentially running program.
It does not edit PATH, shell startup files, config, credentials, or databases.
Place `<prefix>/bin` on PATH yourself. Uninstall by deleting that binary explicitly;
conversation databases and config stay untouched.

The installed executable runs without opam or the checkout. Its startup config
is still `~/.config/factory-tui/config.toml` (or XDG_CONFIG_HOME), so launch is just
`factory-tui` after configuration. Default startup never enables live execution.
`--version` and `--help` read no config. `--no-config` keeps the current memory-only
behavior. Codex/jj executables are explicit runtime dependencies only for their
respective features, not ordinary demo navigation.

## Build a local archive

```sh
python3 scripts/package.py --output /tmp/factory-tui-local.tar.gz
```

The command runs formatting, builds, and unit tests, then writes a new archive.
Existing output paths are refused. It contains the binary, README, non-secret
example config files, selected operational docs, and `build.json` with compiler,
installed package versions, source revision, dirty-check status, and binary digest.
The archive does not contain user config, conversations, credentials, or `_opam`.

Extract with `tar -xzf <archive>` into an existing directory and execute its
`bin/factory-tui`. Archive paths are relative and have a single platform-named root.
Archive entry timestamps and gzip metadata are fixed. Packaging identical bytes
and metadata is repeatable; this is not proof of reproducible compilation. Source
paths, compiler version, and other environment inputs can affect executable bytes.

## Platform boundary

This package is built and tested for the local macOS/Apple Silicon platform only.
The native binary links the macOS system SQLite and system runtime libraries,
not an opam install path. It is not statically linked, signed for distribution,
or notarized. Do not claim Windows/Linux portability from this local verification.
A copied macOS binary may require manual Gatekeeper handling on another machine;
use normal platform security checks rather than bypassing them automatically.

Application/compiler dependencies are recorded in build metadata. Standard OCaml
5.3.0, ocamllsp 1.23.1, and ocamlformat 0.29.0 are the verified development tools.
OxCaml stays an optional deferred experiment. `factory_tui.opam.locked` records the current transitive application dependency
versions. Install with `opam install --locked . --deps-only` in the project switch;
refresh the lock intentionally with `opam lock ./factory_tui.opam` after changing
dependencies. The optional odoc documentation dependency is not included because
it is not installed here. Lock generation is verified, but recreating a completely
fresh switch from the lock is not yet tested. Distributable signing/notarization
remains future work.

## Verify an extracted binary

```sh
uv run --with pyte python scripts/smoke-terminal.py \
  --binary /absolute/extracted/package/bin/factory-tui
```

The smoke exercises board/chat, mouse/Vim navigation, paste, storage restart,
workspace creation and real review, fake runner, and confirmed live-mode execution
with a fake executable. No real model call is made. This is separate from tests
that verify an installed Codex against a loopback fixture.

`python3 scripts/smoke-package.py` verifies archive contents, repeated packaging,
extracted startup with opam absent from PATH, and explicit install/refusal inside
temporary directories. It does not install the app into the user's PATH.

## Local measurements

`python3 scripts/measure.py` builds in a new temporary Dune directory and times ten
`--version` launches. Dependencies are already installed; this does not measure
compiler/dependency installation, terminal readiness, or a GPUI comparison.

November 17, 2026, macOS 26.7.1 arm64 / OCaml 5.3.0:

- Executable: 3,807,512 bytes (about 3.6 MiB).
- Fresh Dune build directory: 1.441 seconds.
- Median `--version` process launch: 6.473 milliseconds.
- Earlier PTY demo RSS samples were about 5 MiB; these are single-process samples,
  not peak memory including Codex workers or retained conversation growth.

These are observations from this machine, not performance guarantees. Packaging
was verified twice from identical build bytes, and an extracted executable passed
the full PTY smoke. The harness drains the PTY while waiting for shutdown, so
terminal output cannot block the tested app just because the test stopped reading.
