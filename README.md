# Factory TUI

An independent OCaml terminal prototype for a software factory. The in-flight
Rust/GPUI app in `../factory` is not a dependency and is not modified.

The interface borrows bottom's dashboard structure: bordered panes, visible
focus, compact status widgets, mouse selection, search, and pane expansion.
Session rules are adapted from Factory's Rust session and event reducers, not
linked through FFI. The TUI remains a simulated interaction prototype; explicit headless Codex
execution is available separately and requires deliberate invocation.

## Run

A project-local OCaml 5.3 switch is installed under `_opam`:

```sh
cd ~/dev/factory-tui
./scripts/run.sh
```

Default launches use simulated tasks and timed fixture updates. The Working
card moves to Ready after about eight seconds without manual column movement.
Selection follows the task's ID as it moves. Without a database flag or a stored
config, tasks and drafts live in memory and quitting discards them. A configured
SQLite database saves conversations and drafts. No agents, credentials, or
workspaces are opened by either mode.

For a fresh checkout:

```sh
opam switch create . ocaml-base-compiler.5.3.0 --no-switch -y
opam install --switch=. . --deps-only -y
opam exec --switch=. -- dune build
```

This machine's SDK exposed `pipe2` at build time while the running system could
not call it. The local compiler uses configure overrides to avoid unavailable
Unix functions. If Dune or ocamlbuild crashes at `caml_unix_pipe`, rebuild:

```sh
ac_cv_func_pipe2=no ac_cv_func_dup3=no ac_cv_func_accept4=no \
  ac_cv_func_ppoll=no MACOSX_DEPLOYMENT_TARGET=14.0 \
  opam reinstall --switch=. ocaml-compiler -y
```

Use standard OCaml first. OxCaml is not required by this prototype.

## Alternate compiler builds

The default project-local switch is unchanged. Build scripts accept explicit
switch and build-directory overrides to keep experimental artifacts separate:

```sh
FACTORY_OPAM_SWITCH=<switch-name> FACTORY_BUILD_DIR="$PWD/_build-ox" ./scripts/check.sh
FACTORY_OPAM_SWITCH=<switch-name> FACTORY_BUILD_DIR="$PWD/_build-ox" ./scripts/run.sh --fake-harness
uv run --with pyte python scripts/smoke-terminal.py \
  --binary "$PWD/_build-ox/default/bin/main.exe"
```

`scripts/build.sh` builds `@install` by default or accepts Dune targets.
`scripts/check.sh` builds and runs all unit tests. Formatting and the editor
continue using the standard project switch unless configured separately.
OxCaml is deferred until later, not a supported build or implementation blocker.
See [docs/oxcaml.md](docs/oxcaml.md) for the failed bootstrap, interrupted newer
attempt, likely SDK issue, and retry checklist.

## Editor and formatting

Install the project-local developer tools:

```sh
./scripts/setup-editor.sh
./scripts/format.sh          # format OCaml and Dune files
./scripts/format.sh --check  # fail if formatting differs
```

`.ocamlformat` pins 0.29.0 with the conventional profile and a 90-column margin.
`ocamllsp` 1.23.1 is installed in the same opam switch as the compiler and libraries.
Formatting is checked before each implementation commit.

For LazyVim, enable its OCaml extra and copy `docs/editor/ocaml.lua` into
`~/.config/nvim/lua/plugins/ocaml.lua`. The override launches LSP and formatting
through the project-local opam switch, rather than a Mason-installed server or
whatever switch happens to be on the shell PATH. It also handles `.mli` buffers.
The override is installed in this machine's Neovim config. Headless checks verified
LSP attachment, hover, and Conform formatting for `.ml`, plus `.mli` attachment.
Restart Neovim after installing the override. Use `:LspInfo` and `:ConformInfo`
to inspect attachment and formatter availability. LazyVim's normal format mapping
(`<leader>cf`) uses ocamlformat for OCaml buffers.

Without the LazyVim override, start Neovim from the switch environment:

```sh
opam exec --switch=. -- nvim lib/domain/model.ml
```

Run `opam exec --switch=. -- dune build @install` after changing dependencies so
LSP has current Dune/Merlin build metadata. The editor setup does not install
plugins, modify shell startup files, or require global OCaml tool installations.

## Interface

- Click a card to focus it and inspect its conversation and activity.
- Double-click, Enter, or `e` expands the selected task. Escape returns.
- Four columns contain bordered cards: Queued, Working, Needs you, Ready.
  `d` opens accepted tasks. Acceptance leaves the selected chat open and read-only.
- Wide layouts show a repository sidebar. `R` cycles repositories at any size;
  `b` returns to all active tasks. Repository filtering does not close the chat.
- Wide terminals place the board and task detail side by side. Medium terminals
  stack them. Narrow terminals use a compact task list with expandable detail.
- Tab / Shift-Tab cycle panes forward / backward. The focused pane is highlighted.
- Vim navigation in normal mode:
  - `h/l`: previous / next nonempty column; `j/k`: next / previous card.
  - `gg` / `G`: first / last card in the current column (or archive).
  - Counts repeat moves: `3j`, `2l`. Counts are capped at 999.
  - In task detail, `j/k` scroll one line; `gg/G` go to top / bottom.
  - Ctrl-U / Ctrl-D move half a page; Ctrl-B / Ctrl-F move a full page.
    On the board, these move selection by the visible card capacity.
  - Ctrl-W then `h/j/k/l` focuses Board / Conversation / Activity by direction;
    Ctrl-W `w` cycles panes. Expanded mode keeps focus inside task detail.
  - `i` enters the reply composer; Escape returns to normal mode and keeps the draft.
    Navigation keys are literal text while composing or searching.
  - Pending counts and `g` / Ctrl-W prefixes appear in the status line.
- Arrow keys or `hjkl` navigate. Mouse wheel and Page Up/Down scroll.
  Conversations follow new messages until you scroll back; End resumes following.
- `/` searches title, repository, or task ID. Escape clears the finished search.
- `i` composes a reply; Enter queues it. Ctrl-L or Alt-Enter inserts a newline.
  Arrows move the cursor, Home/End move within a line, and Backspace/Delete edit.
  Multiline paste preserves newlines without submitting or activating shortcuts.
  Escape keeps a task-specific draft. Cursor movement uses Unicode codepoints,
  not complete grapheme clusters; combining sequences need care when editing.
- `n` creates a task. `m` edits the next-run model; `H` cycles Codex / Claude.
  Both harnesses are simulated. Selection starts no process.
- `s` starts a simulated run, `x` interrupts it. Activity retains each run's
  original harness/model, timestamps, and outcome.
- `a` accepts a Ready task. Acceptance does not merge, push, or delete anything.
- Tool output is collapsed by default; `t` expands it in Activity.
- `f` pauses/resumes demo events. `?` opens Help / Settings; Tab or `h/l` switches
  tabs, `j/k` scrolls, and Escape closes. Settings shows storage and next-run
  harness/model; `m` edits the model and `H` cycles the simulated harness.
- `q` or Ctrl-C quits.
- The bottom action bar is clickable. Mouse reporting needs a supporting terminal;
  keyboard controls remain available without it.

Pasted shortcuts cannot execute actions or submit messages. Terminal control
characters in event content are replaced before rendering.

The layout and verification record are in [docs/ui-parity.md](docs/ui-parity.md).

## State rules

The UI derives columns from state. It does not store card positions.
Each update carries a task ID and run ID. Old runs cannot alter current tasks.
Stream updates replace a message or tool item within the same run. Reused item
IDs in later runs cannot overwrite earlier activity.

Starting captures queued messages; `turn.started` acknowledges only that set.
Replies posted during work stay queued for the next run. Ready requires an
explicit completion event, exit zero, and no failure or input request.
Interruptions, failures, and exits without completion lead to Needs you.
Accepted tasks are read-only.

## Replay external fixture updates

```sh
./scripts/run.sh --events examples/events.jsonl
```

This replaces the demo timers with a tailed JSONL fixture. The seed's Working
task has `task_id=T-102`, `run_id=demo-102`. A regular file or FIFO can receive
new lines while the UI runs. Only complete newline-terminated records are read.
Lines are capped at 64 KiB; malformed records produce a visible error.

Example:

```json
{"task_id":"T-102","run_id":"demo-102","type":"message","item_id":"reply","text":"Working…"}
{"task_id":"T-102","run_id":"demo-102","type":"turn.completed"}
{"task_id":"T-102","run_id":"demo-102","type":"process.exited","code":0}
```

Other types: `turn.started`, `thread.started` (with `thread_id`), `tool`
(with `item_id` and `text`), `turn.failed`, `input.requested` (with `text`),
and `run.interrupted`. Replay messages still carry simulation labels.
This fixture format is not a live harness protocol. Replay mode cannot start runs.

## Validate

```sh
opam exec --switch=. -- dune build
opam exec --switch=. -- dune runtest
./scripts/run.sh --snapshot --size 120x36
```

The tests cover lifecycle gates, stale events, stream replacement, queued
messages, mouse hit-testing, zoom, search, drafts, and terminal-size bounds.
Snapshots do not need a TTY. Interactive mode requires one.

A separate PTY integration smoke checks mouse selection, expansion, bracketed
paste safety, automatic movement, acceptance, resize, and terminal restoration:

```sh
uv run --with pyte --with pillow python scripts/smoke-terminal.py \
  --preview /tmp/factory-tui.png
```

The preview uses the macOS Menlo font. Omit `--preview` for a portable smoke.

## Low-effort TOML setup

The app reads `~/.config/factory-tui/config.toml` if present. With an absolute
`XDG_CONFIG_HOME`, it reads `$XDG_CONFIG_HOME/factory-tui/config.toml` instead.
Create a config once:

```sh
mkdir -p ~/.config/factory-tui
cat > ~/.config/factory-tui/config.toml <<'TOML'
[storage]
database = "board.sqlite"
TOML
```

Then launch without database arguments:

```sh
~/dev/factory-tui/scripts/run.sh
```

To launch as `factory-tui`, add this alias to your shell configuration:

```sh
alias factory-tui="$HOME/dev/factory-tui/scripts/run.sh"
```

Config paths may be absolute, start with `~/`, or be relative to the directory
containing the config. The database parent must already exist. The app creates
the database, not arbitrary parent directories. No config or application-data
files are created just by launching in the default in-memory mode.

Override or bypass configuration explicitly:

```sh
./scripts/run.sh --config /path/to/config.toml
./scripts/run.sh --database /tmp/another-board.sqlite
./scripts/run.sh --no-config
```

CLI `--database` overrides the config path. CLI relative paths use the current
working directory. `--no-config` ignores the default config; combine it with
`--database` to use explicit storage without reading user configuration.
`--config` and `--no-config` cannot be combined. A missing default config is
optional; a missing explicit config or a malformed existing config is an error.
Unknown fields are rejected. The only supported setting is `[storage].database`.
Config reads are capped at 64 KiB and errors do not echo file content. Do not
put credentials in this file. Snapshot mode does not read the default config.

## Persistent conversations

SQLite persistence is opt-in through TOML or `--database`. Stored data includes
tasks, messages, tools, next-run settings, immutable run records, task-specific
drafts, selection, and the ID counter. Runs also have their own SQL table; event
batches have a monotonic cursor for paging. Snapshots, run rows, and appended
events commit or roll back together.

A dedicated worker owns the database. Pending snapshots coalesce; ordered events
are retained in a bounded queue. Normal exit and SIGTERM flush the final snapshot
and queued events. A failed write is displayed and causes a failed final exit,
not a false claim that data was saved. Abrupt termination can lose unflushed
updates; it is not a durable acknowledgment for live agent launch yet.

The storage API refuses symbolic links, foreign databases, unsupported schema
versions, and concurrent Factory TUI ownership. New databases and lock files are
private (0600). The advisory sidecar lock remains after close. This lock coordinates
Factory TUI processes, not unrelated applications that ignore it.

Restart recovery moves Working tasks to Needs you, records interruption, retains
queued replies and drafts, and never resumes an agent. Invalid snapshots return
an error instead of silently replacing conversation history. Stored conversation
and tool content is sensitive; do not share a database as a diagnostic log.

Tests use temporary files and fake data. They verify rollback under injected
failure, bounded busy-lock handling, cross-process ownership, 200 coalesced saves
without event loss, final flush, and a PTY save/reopen path through TOML.

## Local process fixture mode

The OCaml process runner and background delivery handle are implemented and tested
with fake executables. They cover streamed JSONL events, concurrent stderr draining,
bounded output, timeout, cancellation, process-group cleanup, event-queue overflow,
and checkpoint refusal before spawn. No Codex or credentials are used in tests.
Default Start still uses demo timers. To exercise the actual supervisor:

```sh
./scripts/run.sh --fake-harness
```

Launch starts no process. Press `s` to start a fixed local shell fixture, `x` to
stop it. Events stream into chat and move the card automatically. Shutdown cancels
and joins the fixture. With SQLite enabled, the Working snapshot is acknowledged
before spawn. The banner says FAKE HARNESS / NO MODEL CALLS. Harness and model
selections are simulated labels, not executable selection. No live Codex is run.

See [docs/harness.md](docs/harness.md) for limits and lifecycle guarantees. This
runner is not a security sandbox and does not contain descendants that escape
the process group. The fake UI path is verified. A pure Codex invocation builder validates explicit
resume identity and read-only arguments without launching anything. Explicit headless execution is tested with fake executables; installed Codex
and gateway compatibility remain unverified.

## Inspect an agent invocation without running it

```sh
./scripts/run.sh --dry-run-codex \
  --codex-executable /absolute/path/to/codex \
  --workspace /absolute/existing/workspace --model model-id
```

Optional `--resume ID` selects an exact thread; `--gateway PATH` adds the validated
non-secret provider settings. Output is structured JSON, not a shell command to
copy with ambiguous quoting. No executable, database, default user config, or
credential is accessed. A missing or malformed explicit gateway file is an error.
This command does not prove live or gateway compatibility.

`python3 scripts/smoke-invocation.py` checks the CLI with temporary fixture files.

## Explicit headless agent execution

```sh
printf '%s' 'Inspect the workspace without changing files.' | \
  ./scripts/run.sh --run-codex --codex-executable /absolute/path/to/codex \
    --workspace /absolute/existing/workspace --model model-id \
    --database /absolute/path/to/board.sqlite
```

**This can make real model calls and use existing Codex authentication.** It is
not an automatic startup behavior. A Working checkpoint is saved before launch;
events and final state are persisted. Ctrl-C/SIGTERM cancels the process group.
Use `--gateway PATH` for explicit provider settings and `--resume ID` for a thread
already recorded in this database/workspace. Read-only sandbox settings are
requested. The CLI returns only a small summary; open the database in the TUI to
inspect the chat. TUI Start still uses simulation, not this execution path.

Only fake-executable execution has been verified. Installed-Codex/gateway
compatibility, interactive approvals, and isolated workspace creation remain
pending. See [docs/harness.md](docs/harness.md) for the full safety boundary.
`python3 scripts/smoke-execution.py` runs fake CLI execution checks only.

## Gateway configuration validation

A separate non-secret gateway TOML file holds `base_url` and `key_environment`
(the name of an environment variable, not its value). Validate it locally:

```sh
./scripts/run.sh --check-gateway examples/gateway.toml
```

The check opens no database, reads no key, starts no agent, and makes no network
request. Valid settings do not prove model or Responses compatibility. Gateway
provider construction is implemented but not connected to live UI execution.
See [docs/gateway.md](docs/gateway.md) for validation rules and the next checks.

## Source organization

- `lib/domain/`: task/run types and state transitions.
- `lib/storage/`: snapshots, replay events, SQLite, and background saves.
- `lib/agent/`: harness decoding, supervision, Codex, gateway, and dry-run preview.
- `lib/terminal/`: controller, rendering, startup config, app loop, and fixtures.
- `lib/support/`: shared resource-scope binding operators.
- `bin/`, `test/`, `scripts/`, `docs/`: entry point, checks, tooling, and guidance.

Subsystem folders preserve the current `Factory_tui.Model`, `Factory_tui.Ui`, etc.
module APIs. Dune includes subdirectories without adding namespace layers.

## Module interfaces

All core modules have explicit `.mli` interfaces. Database, persistence worker,
run delivery, and replay sources have abstract handles. Domain records remain
inspectable for reducers, serialization, and rendering. Internal codec, spawn,
and navigation helpers are not exported. The controller state remains an exposed
UI record; it is not claimed to be fully encapsulated yet.

Native `Scope` let-bindings flatten resource cleanup blocks without a PPX or
changing `Fun.protect` semantics. See [docs/modules.md](docs/modules.md) for the
intended boundaries and a scope example.

## Implementation sequence

Follow [docs/implementation.md](docs/implementation.md), adapted from the native
Factory app. The terminal shell and simulated session steps are complete.
Composition, next-run harness/model selection, and run history are implemented
for simulation. Opt-in SQLite and TOML startup configuration are implemented.
Next are bounded supervision, gateway setup, isolated jj
workspaces/review, and distribution.

Use tested increments and move local `main` to each completed jj commit.
No remote is configured and nothing is pushed without an explicit request.

A lighter UI does not eliminate execution, durability, or safety work. No
performance comparison with the Rust application has been established yet.
