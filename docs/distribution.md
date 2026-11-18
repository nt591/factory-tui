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

Development checks require Python 3.9 or later for pure fixture tests; the
installed OCaml executable does not require Python.

Application/compiler dependencies are recorded in build metadata. Standard OCaml
5.3.0, ocamllsp 1.23.1, and ocamlformat 0.29.0 are the verified development tools.
OxCaml stays an optional deferred experiment. `factory_tui.opam.locked` records the current transitive application dependency
versions. Install with `opam install --locked . --deps-only` in the project switch;
refresh the lock intentionally with `opam lock ./factory_tui.opam` after changing
dependencies. The optional odoc documentation dependency is not included because
it is not installed here. A new temporary opam root/switch was reconstructed from
the lock on November 18, 2026 with the explicit macOS compiler workaround below;
all 52 locked versions, application build, parallel tests, and the fresh binary's
terminal workflow passed. This does not reconstruct editor tools or validate a
fresh OS. Distributable signing/notarization remains future work.

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

## Opt-in dependency reconstruction

```sh
python3 scripts/smoke-fresh-switch.py --reconstruct \
  --report /tmp/factory-fresh-switch-new.json
```

The command creates a temporary opam root and empty switch, installs the checked-in
lock, verifies exact application/compiler package versions, builds in a temporary
Dune directory, and checks the resulting binary with unit and terminal fixtures.
No project switch, editor, shell profile, config, or installation prefix is changed.
Sources/metadata are downloaded, so this is intentionally separate from normal
checks. It requires the current host's system libraries and development tools;
it is not fresh-OS validation or byte-reproducible compilation.

This Mac's newer SDK requires the compiler workaround documented in README:

```sh
python3 scripts/smoke-fresh-switch.py --reconstruct --macos-compiler-workaround \
  --report /tmp/factory-fresh-switch-macos-new.json
```

That explicit option records configure overrides in the report and leaves opam's
build sandbox enabled. The unmodified compiler bootstrap can crash `ocamlbuild`
in `caml_unix_pipe`; apply the workaround before compiler construction, not after
installing the dependent tools. The option is rejected on non-macOS hosts.
The report records exact package checks and stage outcomes. Failure reports retain
bounded package build output, not environment dumps. Temporary resources are
removed after checks; user configuration and the project switch remain untouched.

### Reconstruction evidence

`docs/verification/fresh-switch-macos.json` records the successful November 18,
2026 check on macOS 26.7.1 arm64, including exact installed packages, compiler
overrides, stages, and tested application source revision. Without overrides,
the first attempt failed in topkg; the matching `ocamlbuild` macOS crash report
at 02:52:56 identified SIGSEGV and `caml_unix_pipe`. That attempt did not reach
application compilation. No application dependency versions changed to obtain
the successful result, and no sandbox was disabled.

The successful attempt took 197.694 seconds to construct the compiler and install
locked dependencies, 2.319 seconds for application build, 14.899 seconds for the
parallel suite, and 65.458 seconds for terminal fixtures. These include existing
host tools/network inputs and are single-run observations, not reproducible timing
or GUI-performance claims. Temporary roots were removed and the project switch
remained unchanged. Reconstruction still needs a working system toolchain.
