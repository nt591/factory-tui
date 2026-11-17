# Factory TUI

An independent OCaml terminal prototype for a software factory. The in-flight
Rust/GPUI app in `../factory` is not a dependency and is not modified.

The interface borrows bottom's dashboard structure: bordered panes, visible
focus, compact status widgets, mouse selection, search, and pane expansion.
Session rules are adapted from Factory's Rust session and event reducers, not
linked through FFI. This is an interaction prototype, not a live agent runner.

## Run

A project-local OCaml 5.3 switch is installed under `_opam`:

```sh
cd ~/dev/factory-tui
./scripts/run.sh
```

Default launches use simulated tasks and timed fixture updates. The Working
card moves to Ready after about eight seconds without manual column movement.
Selection follows the task's ID as it moves. All tasks and drafts live in memory.
Quitting discards them. No agents, credentials, database, or workspaces are opened.

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

## Interface

- Click a card to focus it and inspect its conversation and activity.
- Double-click, Enter, or `e` expands the selected task. Escape returns.
- Four columns: Queued, Working, Needs you, Ready. `d` opens accepted tasks.
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
- `i` composes a reply; Enter queues it. Escape keeps a task-specific draft.
- `n` creates a task. `m` edits the next-run model; `H` cycles Codex / Claude.
  Both harnesses are simulated. Selection starts no process.
- `s` starts a simulated run, `x` interrupts it. Activity retains each run's
  original harness/model, timestamps, and outcome.
- `a` accepts a Ready task. Acceptance does not merge, push, or delete anything.
- `f` pauses/resumes demo events. `?` opens help. `q` or Ctrl-C quits.
- The bottom action bar is clickable. Mouse reporting needs a supporting terminal;
  keyboard controls remain available without it.

Pasted shortcuts cannot execute actions or submit messages. Terminal control
characters in event content are replaced before rendering.

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

## Implementation sequence

Follow [docs/implementation.md](docs/implementation.md), adapted from the native
Factory app. The terminal shell and simulated session steps are complete.
Composition, next-run harness/model selection, and run history are implemented
for simulation. Next is opt-in SQLite, bounded supervision, gateway setup, isolated jj
workspaces/review, and distribution.

Use tested increments and move local `main` to each completed jj commit.
No remote is configured and nothing is pushed without an explicit request.

A lighter UI does not eliminate execution, durability, or safety work. No
performance comparison with the Rust application has been established yet.
