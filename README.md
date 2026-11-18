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
workspaces are opened on launch by either mode; `W` is an explicit workspace
creation action.

For a fresh checkout:

```sh
opam switch create . ocaml-base-compiler.5.3.0 --no-switch -y
opam install --switch=. --locked . --deps-only -y
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

On this Mac's SDK, use those configure variables during compiler creation:

```sh
ac_cv_func_pipe2=no ac_cv_func_dup3=no ac_cv_func_accept4=no \
  ac_cv_func_ppoll=no MACOSX_DEPLOYMENT_TARGET=14.0 \
  opam switch create . ocaml-base-compiler.5.3.0 --no-switch -y
opam install --switch=. --locked . --deps-only -y
```

Otherwise a fresh lock install can fail while building `topkg` through
`ocamlbuild`. An isolated reconstruction check is available without changing your
project switch or shell configuration:

```sh
python3 scripts/smoke-fresh-switch.py --reconstruct --macos-compiler-workaround \
  --report /tmp/factory-fresh-switch-new.json
```

The explicit workaround is macOS-only; omit it when the system does not require
it. This downloads/builds the compiler and locked dependencies in a temporary opam
root, then verifies the application and terminal workflow. It is not a fresh-OS
or cross-platform certification. See `docs/distribution.md` for scope.

Use standard OCaml first. OxCaml is not required by this prototype.

## Standalone command and local package

```sh
./scripts/install.sh --prefix "$HOME/.local"
~/.local/bin/factory-tui --version
```

Installation is explicit, refuses an existing binary, and changes no config or
shell startup files. The installed executable does not require opam or the checkout
to run. Add your chosen prefix's `bin` directory to PATH yourself, then startup is
just `factory-tui` with the same TOML configuration. Live mode remains opt-in.

To create a local platform archive without installing:

```sh
python3 scripts/package.py --output /tmp/factory-tui-local.tar.gz
```

It runs format/build/tests and includes the executable, usage docs, non-secret
examples, and build metadata. `factory_tui.opam.locked` records dependency versions;
a new machine still needs the documented compiler/SDK setup to build from source.
This is a local macOS arm64 package, not a signed/notarized cross-platform release.
See [docs/distribution.md](docs/distribution.md). Packaging and temporary install
checks run via `python3 scripts/smoke-package.py`.

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
- Double-click or Enter/`e` on a card expands its task chat. Focus Activity with
  Tab or Ctrl-W, then `e` gives tool output the full terminal width; `e`/Escape
  returns to the preceding task layout. Task selection, drafts, and run state
  remain unchanged. Tab or `i` returns from Activity-only display to visible chat.
- Four columns contain bordered cards: Queued, Working, Needs you, Ready.
  `d` opens accepted tasks. Acceptance leaves the selected chat open and read-only.
- Wide layouts show a repository sidebar. `R` cycles repositories at any size;
  `b` returns to all active tasks. Repository filtering does not close the chat.
- Wide terminals place the board and task detail side by side. Medium terminals
  stack them. Narrow terminals use a compact task list with expandable detail.
- Tab / Shift-Tab cycle panes forward / backward. The focused pane is highlighted.
- Vim navigation in normal mode:
  - `h/l`: previous / next nonempty column, preserving the selected row where
    possible and clamping to the last card in a shorter column.
    `j/k`: next / previous card.
  - `gg` / `G`: first / last card in the current column (or archive).
  - Counts repeat moves: `3j`, `2l`. Counts are capped at 999.
  - In task detail, `j/k` scroll one line; `gg/G` go to top / bottom.
  - Ctrl-U / Ctrl-D move half a page; Ctrl-B / Ctrl-F move a full page.
    On the board, these move selection by the visible card capacity.
  - Ctrl-W then `h/j/k/l` focuses Board / Conversation / Activity by direction;
    Ctrl-W `w` cycles panes. Expanded mode keeps focus inside task detail.
  - Ctrl-W `+` / `-` grows / shrinks the focused board or detail region by one
    row (stacked) or column (side by side). Conversation and Activity share the
    detail region. A count before Ctrl-W repeats the adjustment, such as `5Ctrl-W+`.
    Ctrl-W `=` restores configured startup defaults, or automatic sizes if unset.
    The independent width/height preferences
    scale on terminal resize and last only for this launch; zoom keeps them intact.
    Minimum sizes prevent one region from hiding the other.
  - `i` enters the reply composer; Escape returns to normal mode and keeps the draft.
    Navigation keys are literal text while composing or searching.
  - Pending counts and `g` / Ctrl-W prefixes appear in the status line.
- Arrow keys or `hjkl` navigate. Compact task lists follow displayed row order
  across states; four-column boards keep vertical motion within a column and
  horizontal motion between columns. Mouse wheel and Page Up/Down scroll.
  Status counters describe the repository/search-filtered board, not hidden tasks.
  Overflowing columns/lists show the visible range and above/below arrows.
  Wheel input targets the visible pane under the pointer, not keyboard focus;
  footer/composer surfaces do not scroll another pane. Chat and Activity retain
  separate positions when switching mouse focus; selecting a task resets both.
  Activity stays at its remembered visible row while chat has focus. Scrolling
  a board column also leaves paused chat history anchored as new output arrives.
  Mouse-wheel positions are independent per Kanban column. Selecting a card or
  moving the selected task to a new state restores following in its column.
  Long card titles use a two-row preview with an ellipsis; opening the card shows
  the complete task instruction.
  Conversations follow new messages until you scroll back. A message/row anchor
  then preserves the reading position as output arrives; End resumes following.
  Search seeking and explicit navigation move the anchor. The chat header marks
  history reading; resizing width preserves the message and approximate wrapped
  row, not a byte-exact text position. Only visible chat rows become terminal
  images; the full logical history remains available for anchors and search.
  Wrapped rows are reused while the current task's messages and pane width stay
  unchanged. Streaming changes rewrap only replaced message records; earlier
  unchanged messages reuse their rows and anchors. Task/width changes rebuild the
  transient cache, and removed messages leave it.
- `/` searches the focused pane: title/repository/task ID on the board, or message
  text and author in chat. `S` opens chat search from any pane. Enter finishes the
  query; `n/N` selects the next/previous matching message while focused in chat.
  Matches are literal, ASCII-case-insensitive (Unicode otherwise exact), capped
  at 256 query bytes, and counted once per message. Escape clears chat search
  before leaving task zoom. Search never changes saved drafts or task content.
  Unchanged transcripts reuse matches; new stream text or query changes refresh
  the transient match/highlight index. Long-query banners keep match counts and
  navigation visible; display abbreviation does not change the query.
- `i` composes a reply; Enter queues it. Ctrl-L or Alt-Enter inserts a newline.
  Arrows move the cursor, Home/End move within a line, and Backspace/Delete edit.
  Multiline paste preserves newlines without submitting or activating shortcuts.
  Escape keeps a task-specific draft. Cursor movement and deletion use extended
  grapheme clusters, so combining accents, flags, skin tones, and joined emoji
  stay together. Chat/composer/activity/card wrapping also keeps grapheme clusters
  on one row. Oversized clusters are cropped by the pane, not split; displayed
  width for complex emoji still depends on the terminal and font.
- `n` creates a demo task; `W` opens explicit workspace task creation (SQLite).
  `m` edits the next-run model; `H` cycles Codex / Claude.
  Both harnesses are simulated. Selection starts no process.
- `s` starts a simulated run, `x` interrupts it. Activity retains each run's
  original harness/model, timestamps, and outcome.
- `a` accepts a Ready task. Acceptance does not merge, push, or delete anything.
- Tool output is collapsed by default; `t` expands it in Activity. Commands show
  supplied status/exit codes and plain output; MCP calls show server/tool and
  arguments/results; file changes list paths and operations. `T` switches between
  readable activity and the preserved raw payload. Missing status/output is marked
  unknown or not supplied, never inferred as success. Tool content is sensitive.
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
Unknown fields are rejected. `[storage].database` controls persistence; optional
`[workspace]` fields prefill the creation form, as described below.

Optional pane defaults use integer percentages:

```toml
[layout]
board_width_percent = 55
board_height_percent = 40
```

Each value is optional and must be from 10 to 90. Width controls the board share
of the main area in side-by-side mode; height controls it in stacked mode. The
sidebar is excluded. Omitted values use the automatic layout. Terminal limits
can clamp the displayed sizes to keep both regions usable without discarding
the preference. Ctrl-W `+`/`-` adjusts the current launch; Ctrl-W `=` restores these
startup defaults. Runtime adjustment does not write the config. File edits take
effect on the next launch, and `--no-config` uses automatic defaults. The Settings
tab displays the loaded startup shares. Layout configuration does not select a
task, change storage, enable live mode, or start an agent.

Config reads are capped at 64 KiB and errors do not echo file content. Do not
put credentials in this file. Snapshot mode does not read the default config.

## Optional workspace form defaults

Add this to your startup TOML after configuring SQLite:

```toml
[workspace]
jj = "/absolute/path/to/jj"
source = "~/dev/project"
parent = "~/dev/factory-workspaces"
revision = "main@origin"
model = "coding-large"
```

Every field is optional. Paths accept `~/`, absolute paths, or paths relative to
this config file. Source and parent must already exist when you create a task;
reading this configuration creates no directories, fetches no revisions, and
starts no agents. Press `W`, type the task instruction, then explicitly create
with Ctrl-S. All fields remain editable before submission.

Configured source/parent/revision/model values override remembered task values
only for the fields you set. Unset fields retain the latest workspace-backed
task's source, parent, exact base, and model. The jj path starts from configuration;
manual creation/review edits reuse that chosen path for this session. Restarting
uses the config again. This also prefills jj for changes review, avoiding retyping.
Task instructions are always blank. `--no-config` bypasses these defaults.

There is no config key that silently enables live execution, write access, or a
credential. Defaults never move an existing task to a different workspace or
change past run history. Change fields in the form for a one-off task.

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
resume identity and read-only arguments without launching anything. Explicit headless
execution is tested with fake executables and an opt-in installed-Codex loopback
fixture. Real provider compatibility remains unverified.

## Explicit live UI mode

```sh
./scripts/run.sh --live-ui --codex-executable /absolute/path/to/codex
```

A new live database starts with an empty real board, not sample cards. The
onboarding panel explains workspace creation, task chat, confirmed runs, review,
and acceptance. `n` or `W` opens the workspace form in live mode; neither starts
an agent. Existing database tasks and chats are preserved, including any demo
cards previously saved there. Fresh simulation launches still include sample
cards. Empty archive and filtered-board states explain what to do next.

SQLite must be configured through TOML or `--database`. Optional `--gateway PATH`
selects an explicit non-secret provider file. **A real Codex executable can use
existing authentication and incur model usage.** Launch starts no process; the
banner marks live mode. Only workspace-backed Codex tasks can run.

Create a task with `W`, queue instructions with `i`, and press `s` to inspect the
confirmation. Enter/`y` runs; Escape/`n` cancels. Pasted text cannot confirm, and
terminals smaller than 64x13 must resize first. Complete task/model/workspace/thread
details wrap in a scrollable dialog. Use `j/k`, arrows, `Ctrl-U/D/B/F`, or the
mouse wheel to review them; `g/G` or Home/End moves to an edge. Run stays locked
until every disclosure row has been shown. Jumping past rows does not count as
reviewing them. Resizing, changing run details, or reopening resets this check.
Every run waits for its SQLite
Working checkpoint before spawn. Streaming output updates the same chat and moves
its card. `x` cancels; shutdown cancels/joins and flushes. `v` reviews real changes.

Next-run selector changes do not alter active runs. Replies while Working stay
queued. Resume uses the task's saved thread and verifies returned identity.
Acceptance does not merge/push/delete. Requested sandboxing defaults to read-only;
explicit workspace-write is described below. Interactive approvals and real
broader code-writing sandbox validation remain pending. Specific local sentinel
cases are verified as documented below.

The UI integration is verified with fake executables and an opt-in installed-Codex
loopback fixture: workspace creation, confirmed write, card movement, chat, actual
jj diff, same-thread resume, acceptance, and archived-chat restart. Recorded jj
workspaces skip Codex's Git-directory check but retain sandbox and approval policy.
Arbitrary headless directories do not get that exception. No real provider is used.
See [docs/harness.md](docs/harness.md) for limits and persistence semantics.

Live Stop/retry keeps the task workspace occupied until the old process has
finished draining and cleanup. A confirmed replacement waits without spawning;
Activity explains the wait. Independent workspaces can still run concurrently.
Symlink aliases share a slot within the same runner. This is not a cross-process
workspace lock. Shutdown interrupts confirmed waiting runs rather than starting
them. See `docs/harness.md` for the coordination boundary.

## Explicit code-editing mode

```sh
./scripts/run.sh --live-ui --workspace-write --codex-executable /absolute/path/to/codex
```

Read-only is still the default. `--workspace-write` must be explicit for live UI
and applies only to workspace-backed Codex tasks. The banner and every run
confirmation disclose write access. Setup starts nothing; paste cannot authorize
a run. The selected policy is captured and saved with each run; old snapshots and
old launches remain read-only. `v` reviews actual changes; acceptance never
merges, pushes, or deletes anything.

Codex is instructed to use `workspace-write` with never approvals—there is no
interactive approval channel or automatic permission escalation. The requested
write policy also allows temporary directories and harness runtime state, not
only task files; the confirmation discloses workspace + temporary directories. No danger-full-
access flag or extra writable directory is added. Restart without this flag to
return to read-only. Headless execution and preview remain read-only.

Unit and terminal tests use a fake executable editing a **temporary** task
workspace and verify the resulting real diff. They do not by themselves prove installed Codex's OS sandbox. An additional
opt-in sentinel probe now verifies specific read-only/write/never-escalation cases
on the installed executable against a local fixture. It is not a complete
security audit or real provider test. See [docs/harness.md](docs/harness.md).

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
inspect the chat. TUI Start uses simulation unless `--live-ui` is explicitly selected; live mode
adds per-run confirmation and requires isolated task workspaces.

Only fake-executable execution has been verified. Installed-Codex/gateway
compatibility, interactive approvals, real provider UI checks remain
pending. Confirmed live UI execution is implemented and tested with fake processes. Isolated workspace task creation is available separately via `W`. See [docs/harness.md](docs/harness.md) for the full safety boundary.
`python3 scripts/smoke-execution.py` runs fake CLI execution checks only.

## Gateway configuration validation

A separate non-secret gateway TOML file holds `base_url` and `key_environment`
(the name of an environment variable, not its value). Validate it locally:

```sh
./scripts/run.sh --check-gateway examples/gateway.toml
```

The check opens no database, reads no key, starts no agent, and makes no network
request. Valid settings do not prove model or Responses compatibility. Gateway
provider construction is available to explicit headless or live UI execution;
configuration validation alone does not approve a model call.
See [docs/gateway.md](docs/gateway.md) for validation rules and the next checks.

## Source organization

- `lib/domain/`: task/run types and state transitions.
- `lib/storage/`: snapshots, replay events, SQLite, and background saves.
- `lib/agent/`: harness decoding, supervision, Codex, gateway, and dry-run preview.
- `lib/workspace/`: explicit isolated jj workspace creation and bounded real diffs.
- `lib/terminal/`: controller, rendering, startup config, and app loop.
- `lib/demo/`: `Demo.Seed` fixtures and `Demo.Runner` fake process execution.
- `lib/support/`: shared resource-scope binding operators.
- `bin/`, `test/`, `scripts/`, `docs/`: entry point, checks, tooling, and guidance.

Subsystem folders preserve the current `Factory_tui.Model`, `Factory_tui.Ui`, etc.
module APIs. Dune includes subdirectories without adding namespace layers.

## Workspace layer

The isolated jj workspace API is implemented and tested in temporary repositories.
It resolves an exact base, creates a new outside-source workspace, and returns
real bounded diffs. It never fetches, merges, pushes, deletes, or converts a
Git-only repository automatically. Ordinary jj creation may snapshot source
uncommitted files, so UI integration must disclose that behavior.

Workspace task identity persists with the conversation. With configured SQLite,
press `W` to create a workspace-backed task: Tab/Shift-Tab selects fields, Enter
moves to the next, Ctrl-S creates, and Escape cancels before submission. Long
values follow the cursor horizontally; Home/End reveals the prefix/suffix without
changing the stored path or instruction. The form
shows the source-snapshot disclosure and its own setup/validation status; background
run updates do not erase form errors. Invalid submission moves focus to the first
field that needs correction, without changing entered values or starting a job.
Editing that field clears its stale error and requests another Ctrl-S check;
creation/storage failures remain visible while editing. Creation runs in the background and selects
the new Queued chat; it starts no agent. Source, parent, exact base, and model are
remembered from previous workspace-backed tasks unless overridden by optional
TOML workspace defaults. jj's path is explicit but can be configured once.

Press `v` to open real changes review for the selected workspace task. Opening
runs nothing: enter jj's absolute path if needed, then Enter/`r` refreshes in the
background. `i` edits the path with a cursor-following viewport for long values;
Home/End reveals its prefix/suffix. `j/k`, Page Up/Down, and the wheel scroll; Escape
returns to chat. `]`/`[` jump to next/previous files; multi-file patches also have
clickable Prev/Next buttons. The footer shows file position, and jumps reset the
horizontal offset. Page keys move by the visible patch height; Ctrl-U/D moves a
half-page and Ctrl-B/F a full page. Paging controls are inactive during path editing. Empty and failed
diffs are explicit states, not sample patches.
Review does not accept, merge, push, or delete. Wheel input over its path field,
header, or buttons does not scroll the patch. `h/l` or Left/Right scroll long
diff lines horizontally; `0` returns to their start. Ctrl-wheel also scrolls
horizontally. Offsets use terminal cells, preserving UTF-8 text. Display rows and
maximum width are prepared per refresh, so redraw/resize does not scan the full
patch. Raw patch text remains unchanged.
Creation requires durable storage;
a save failure leaves the new directory for inspection instead of deleting it.
See [docs/workspaces.md](docs/workspaces.md) for the API limits and next steps.

In short terminals, the focused pane fills the body: `i` shows the chat/composer,
Tab cycles to Activity and the board, and Ctrl-W moves focus as usual. Drafts and
selection survive these layout changes; explicit `e` zoom remains separate.

Activity wraps long task titles, repository/workspace paths, and next-model IDs
rather than clipping them. Run history displays newest attempts first, with active
run age and recorded ended duration; stored chronology is unchanged. Age starts
at confirmation (including pre-spawn waits), not process spawn; wall-clock anomalies
show unavailable time rather than invented values. Workspace tasks show their
exact review base. Expanded tools identify their recorded source run and its
captured settings, including simulation/live origin and policy. Unmatched legacy
items report an unrecorded origin rather than using current settings. Unchanged
tool payloads reuse readable/raw decoding; collapsed groups request only the latest
item description and hide detailed output.
Focus Activity and press `e` to inspect full-width metadata, tools, and run history;
scroll as needed. Overflowing Activity shows the visible wrapped-row range and
above/below arrows in its border without consuming an output row. Inspection does
not change the task or its workspace.

Model, task-title, and search footer editors follow their cursor when values are
long. Home/End reveals the prefix/suffix; display clipping does not shorten the
submitted text. Long middle edits show text on both sides of the cursor. Short
values retain key hints beside the input.

Selecting a card also refreshes the footer with its task ID and next-step guidance,
without clearing storage errors or starting a run.

The action bar follows task state: Working shows Stop, Ready shows Accept, and
accepted tasks show inspection rather than run/edit controls. Live Start says
`s confirm`; it still opens the per-run confirmation. Keyboard shortcuts retain
validation even when their actions are absent from the bar.
The reply composer also uses mode-correct controls: live tasks display Codex-only
selection, and Enter queues the next turn even while a run is active. Long model
names cannot push queue instructions off the composer line; the display shortens
the model label while retaining its full value for the next run.

Help/Settings shows the visible row range and indicates more content above or
below. Its instructions reflect simulation, fake-process, replay, or live mode;
live mode names Codex-only execution and the per-run confirmation. Live `H`
keeps Codex (or explicitly selects it for an imported Claude task); it starts no
run. Accepted tasks cannot open the model editor or change harness. Page Up/Down moves by the current menu height; switching tabs returns to
the top. Wheel input scrolls only menu content, not tabs or the background.
`?` or Escape closes the menu without changing tasks or drafts.

Cards and sidebar show short distinguishing repository-path suffixes. Full paths
remain in Activity and continue to define filters and saved workspace identity.

The wide repository sidebar keeps navigation pinned and scrolls repository rows
with the mouse wheel. It shows an overflow range; `R` brings the current filter
into view, and `b` returns to all repositories. Hidden entries are not clickable.

Compact headers put the execution mode first so simulation, replay, and live
write/read policy remain recognizable in small terminals. Resizing never enables
execution; live confirmation still requires every disclosure row to be shown.

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
for simulation and explicit Codex execution. SQLite/TOML configuration, bounded
supervision, gateway validation, isolated jj workspaces/review, and local packaging
are implemented. Broader sandbox/approval support, real-provider checks, and
fresh-machine release validation remain pending.

Use tested increments and move local `main` to each completed jj commit.
No remote is configured and nothing is pushed without an explicit request.

A lighter UI does not eliminate execution, durability, or safety work. No
performance comparison with the Rust application has been established yet.

Restart feedback reports how many Working tasks were recovered as interrupted and
how many nonempty drafts were retained. No interrupted runs are reported when the
saved board was already idle. Recovery still starts no process.

## Verification and remaining scope

See [docs/audit.md](docs/audit.md) for a requirement-by-requirement evidence map.
The usable board/chat, persistence, workspace creation/review, and local package
are implemented. Current Codex execution defaults to read-only and supports explicit confirmed
workspace-write in live UI. Interactive approvals, broader sandbox/security validation,
real gateway behavior, and fresh-machine
release validation are not claimed complete. OxCaml remains a deferred TODO.

Optional installed-Codex sandbox checks use a fixed loopback fixture and isolated
sentinel paths, not a real gateway or model:

```sh
python3 scripts/test-responses.py
python3 scripts/smoke-codex-sandbox.py --codex /absolute/path/to/codex
uv run --with pyte python scripts/smoke-codex-ui.py --codex /absolute/path/to/codex
```

The local probe verifies denial of read-only writes, workspace + temporary-directory
access in write mode, denial of ordinary sibling writes, and never-approval
escalation refusal. The UI probe exercises the complete task workflow with a fixed
shell call in a temporary workspace. It also checks the completion footer and
opening accepted chat after restart. See `docs/harness.md` for scope and exclusions.

Test boundaries and the native command-fixture investigation are documented in
[docs/testing.md](docs/testing.md). Normal tests keep parallel scheduling and
production timeout limits; plain I/O checks do not time freshly created scripts.


When chat has more wrapped rows than its viewport, its lower border shows the
visible row range. While reading history, `[Latest / End]` is a mouse button:
click it to focus chat and resume following output, without starting a run or
sending a draft. End remains the keyboard equivalent when chat is focused. Search
queries stay available for `n/N`; Activity keeps its own reading position. The
button takes no transcript row, disappears while following, and is omitted if
the complete label cannot fit. Wheel input on the button does not scroll.


Long replies show a `draft rows first-last/total` cue on the composer's lower
border, with arrows for hidden text above/below. These are wrapped display rows,
not logical line numbers. The editor keeps the cursor visible without taking a
row away from the draft; normal preview shows its tail. Arrow/Home/End navigation
and Escape retain the complete draft. Enter queues the full text, not just the
visible window. The cue is absent when the draft fits.


Transcript author labels wrap across rows instead of losing their suffix at the
pane edge. All wrapped header rows keep the author/queued styling. Imported long
authors and queued/sent labels remain readable and searchable; the original stored
message stays unchanged. Body-row anchors do not shift when an author grows.


The board summary keeps filtered task counts visible when repository labels or
search queries are long. It uses the same distinguishing repository suffixes as
the sidebar; full repository/filter identity is unchanged. Click the displayed
view label to toggle Archive, or the displayed `/` search text to edit the full
query. Hitboxes follow these labels rather than fixed terminal columns. On very
small widths, counts take priority and omitted controls have no click target.


Changes-view notices now wrap in the review body. If a failure or troubleshooting
message exceeds the pane, use `j/k`, Page Up/Down, Ctrl-U/D/B/F, or Home/End to read
it. Resizing reflows notices, not patch lines; diffs retain horizontal scrolling.
Reading or paging an error never retries the command. `r`/Enter remains an explicit
refresh, and command output is still withheld from failure messages.


Review buttons adapt to the terminal width. Wide panes keep full labels; narrow
panes use complete compact buttons, with Close taking priority at the smallest
sizes. A clipped or omitted button has no mouse target. While editing the jj path,
only Close is available as a button; Enter still explicitly refreshes. File buttons
appear only when multiple files and enough space exist; `[`/`]` remain available.


While reading a long chat message, changing terminal or pane width keeps the same
body-text position in the first visible row. Returning to the original width
restores that row, rather than keeping an obsolete wrapped-line number. End or
Latest still resumes following. Near the transcript end, viewport bounds can
clamp the position; edits that replace earlier text are not tracked as a diff.


Compact task lists mark shortened titles with a grapheme-safe ellipsis. Ordinary
rows retain task ID/state columns; when identities are too long or space is tight,
the state takes priority and the ID/title are abbreviated. Mouse targets still
select the exact stored task, and opening chat shows the complete instruction.


Input-limit rejection is visible while editing: a footer warning states that the
edit was not applied. Reply/footer values are capped at 64 KiB after UTF-8 repair;
chat search remains capped at 256 bytes. Rejected edits leave the cursor, editor
text and saved draft/query unchanged. Cursor motion keeps the warning; deleting
text or making a valid text change clears it. Enter queues the retained text only.
