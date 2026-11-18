# Harness supervision

This layer is implemented in OCaml and is independent of the Rust app. It is
connected to the UI only through explicit `--fake-harness` mode. Default Start
uses demo timers.
No Codex invocation, gateway credentials, or real workspace access occurs here.

## Event decoder

`Harness.decode` accepts Codex-style JSONL events for thread identity, turn start,
completion/failure, streamed agent messages, and command/tool/file activity.
Known event fields are validated. Unknown events retain their raw JSON for
inspection. Errors do not echo source content. Tool payloads are retained as JSON.
The decoder is not evidence of compatibility with an installed Codex version.

## Process layer

`Process.run` takes an absolute executable, arguments, and working directory.
It passes arguments directly without building a shell command and delivers the
prompt through stdin. A nonblocking select loop writes stdin while concurrently
draining stdout/stderr. Stderr is counted and drained, not retained.

Limits: 1 MiB prompt and JSONL line, 16 MiB per output stream, 100,000 events,
with a default five-minute timeout measured on a monotonic clock. Smaller limits
are supported for tests. Output is delivered through a callback before process
exit. Callbacks must return promptly; a blocking callback cannot be preempted.
Callback failures cancel the process and return an error.

The maintained `spawn` library handles working directory, standard-stream
redirection, and process-group creation. `Spawn.safe_pipe` coordinates pipe
creation with spawning on macOS to avoid descriptor-inheritance races. A small
C binding remains only for the monotonic clock.

Cancellation sends SIGKILL to the child group and reaps the direct child. Parent
exit terminates remaining ordinary descendants and drains remaining pipes.
Output pipes that stay open after parent exit have a bounded cleanup interval.
The macOS zombie transition can briefly refuse group signals; the runner checks
and reaps the child rather than treating this as successful cancellation of a
running process. macOS builds and lifecycle tests are verified; other platforms
are not yet verified.

This is lifecycle supervision, not a security sandbox. Descendants that deliberately
create a new session/group can escape group cancellation. No process-containment
claim is made for such executables. Run cancellation is immediate, not graceful.

Success requires exit zero, an explicit turn-completed event, and no fatal event
or cancellation. Exit zero alone is not success. The outcome is published only
after output draining finishes.

## Foreground delivery

`Run_handle` executes the runner on a background thread. The delivery queue is
bounded to 128 events by default. Overflow cancels the process and produces a
terminal error. Completion has separate storage, so a full queue cannot discard
it. Draining consumes events in order. Closing cancels and joins the worker.

A checkpoint callback must return success before spawning. Tests verify that a
refused checkpoint prevents any executable side effect. UI storage integration
must submit and acknowledge the Working snapshot in that callback before a live
run starts. The fake UI path submits and acknowledges this checkpoint before spawn.
A live Codex workflow has not been implemented.

## Validation

```sh
opam exec --switch=. -- dune exec test/test_process.exe
```

Tests use executable shell fixtures in temporary directories. They cover prompt
delivery, event streaming, concurrent stderr draining, completion/exit gates,
malformed output, line/stream/event limits, callback failure, timeout, cancellation,
parent exit with inherited pipes, bounded foreground delivery, checkpoint refusal,
and cancel/join. They never invoke Codex, load credentials, or modify real workspaces.

## Fake process UI

```sh
./scripts/run.sh --fake-harness
./scripts/run.sh --fake-harness --database /tmp/factory-fixture.sqlite
```

Startup creates no harness process. Select a task and press `s` to run a fixed
shell fixture through the real process supervisor. Its output streams into chat;
validated completion plus exit moves the card to Ready. Replies during work remain
queued. `x` interrupts; exit cancels and joins pending runners. The banner makes
clear that no model call or Codex agent is involved. Harness/model selectors are
only simulated labels here, not a choice of fixture executable. Replay and fake
process modes cannot be combined.

Controller/runner tests and the PTY smoke verify this path, including SQLite
checkpoint refusal, output replacement, cancellation, shutdown, and saved events.
Next add Codex invocation, resume identity, and gateway validation in separate
increments; fake tests do not prove live compatibility.

## Codex invocation builder

`Codex.invocation` builds a process configuration only. It does not spawn Codex,
read credentials, or open a database. It requests JSONL, ignores user config,
sets read-only sandboxing and never approvals, and passes the prompt through stdin.
An explicit thread ID selects `exec resume`; no `--last` or implicit session lookup
is used. The working directory is set by the supervisor for both new and resumed
runs. Model/thread IDs reject option-like and control-character values.

Argument forms were inspected against the installed Codex help on November 17,
2026. Pure tests validate the constructed arguments. No live compatibility or
native resume claim follows from those checks. The TUI still exposes fake runs
only; gateway configuration and loopback integration remain the next steps.

## Invocation preview

Inspect the actual argument builder through the CLI without starting an agent:

```sh
./scripts/run.sh --dry-run-codex \
  --codex-executable /absolute/path/to/codex \
  --workspace /absolute/existing/workspace --model model-id
```

Add `--resume <explicit-thread-id>` and/or `--gateway <non-secret-config.toml>`
for those variants. The executable is explicit so the preview does not select a
shell function, guess an installation path, or execute a version probe. The output
is JSON with separate argument strings, working directory, timeout, stdin prompt
source, and explicit no-process/no-credentials/no-database flags.

The preview does not read default Factory config. Interactive/storage/snapshot
options cannot be combined with it. Invocation-specific options outside dry-run
are rejected rather than silently ignored. The CLI smoke uses a temporary fake
executable with a marker and verifies it is never started:

```sh
python3 scripts/smoke-invocation.py
```

A preview is not evidence of provider compatibility or successful live execution.

## Explicit headless execution

```sh
printf '%s' 'Inspect this workspace without changing files.' | \
  ./scripts/run.sh --run-codex \
    --codex-executable /absolute/path/to/codex \
    --workspace /absolute/existing/workspace --model model-id \
    --database /absolute/path/to/board.sqlite
```

This is real execution when given a real Codex executable. It can incur model
usage and use that executable's existing authentication. `--ignore-user-config`
does not isolate authentication. Supply `--gateway PATH` to use an explicit
non-secret provider file. Only the named environment reference is configured;
Codex accesses the credential when executing. The application does not import
shell credentials or create a gateway key.

The command requires explicit executable, workspace, model, database, and a
nonempty stdin prompt capped at 64 KiB. It does not read the default startup TOML.
Prompts remain on stdin, not process arguments. The workspace must already exist;
this increment does not create isolated jj workspaces. Read-only sandbox and
never-approval settings are requested; there is no interactive approval channel.
Do not treat this as a production execution workflow until the installed-Codex
loopback and gateway compatibility checks are complete.

Execution acknowledges its Working snapshot in SQLite before spawning. It applies
streamed events through the same task reducer, preserves ordered known events,
and saves a terminal snapshot before reporting success. Storage failure cancels
execution or prevents launch; errors are returned instead of claiming data saved.
Ctrl-C/SIGTERM request cancellation. Run history records non-simulated execution;
messages from those runs are not labeled as simulated. Earlier snapshots missing
this field default to simulation. Default TUI runs remain simulated, even when
viewing history created by this explicit command.

Add `--resume ID` only for a thread already recorded in the same database. Resume
must match that task's recorded workspace and Codex harness. A returned different
thread identity is rejected. New prompts append to the existing chat; queued
instructions join the next prompt. Accepted tasks cannot be resumed. Exit zero
without completion yields Needs you and a nonzero CLI exit.

The CLI prints a small task/thread/state summary, not conversation text. Database
conversation and tool content remains sensitive. An initial storage/checkpoint
failure prevents launch; a later storage failure can leave an interrupted Working
snapshot that recovers to Needs you on reopening.

Validation uses fake executables only:

```sh
python3 scripts/smoke-execution.py
```

Unit tests cover persistence, explicit resume, mismatched identity, malformed
harness output, cancellation, and checkpoint refusal. These do not prove live
Codex, model gateway, or platform sandbox compatibility.

## Installed Codex loopback verification

```sh
python3 scripts/smoke-codex-local.py --codex /absolute/path/to/codex
```

This opt-in check uses isolated temporary HOME/CODEX_HOME, a dummy key, and a
loopback Responses server. It verifies execution, persisted Ready state, streamed
answer, and same-thread resume through the OCaml CLI. Verified November 17, 2026
with codex-cli 0.166.0. No real model gateway or credentials are used. Tool execution
and platform sandbox enforcement are not exercised by the fixed-answer fixture.

## Confirmed live UI execution

```sh
./scripts/run.sh --live-ui --codex-executable /absolute/path/to/codex
# Storage comes from startup TOML, or explicitly:
./scripts/run.sh --live-ui --codex-executable /absolute/path/to/codex \
  --database /absolute/path/to/board.sqlite --gateway /path/to/gateway.toml
```

**A real executable can use existing Codex authentication and incur model usage.**
`--live-ui` must be explicitly selected; it cannot be combined with fake/replay
modes. SQLite storage and an executable accessible at an absolute path are required.
An optional gateway file is validated without reading its referenced key. No
process starts while configuring or launching the app. Default launches remain
simulated, and there is no live-setting auto-enable field in the startup TOML.

Only workspace-backed Codex tasks can run. `W` creates such a task; `i` adds queued
instructions and `m` edits the next-run model. `s` asks for confirmation, showing
model, workspace, new/resumed thread, usage/auth disclosure, and requested read-only
sandbox. Enter/`y` confirms; Escape/`n` cancels. Pasted text cannot authorize a run.
At less than 64 columns or 13 rows confirmation is blocked; resize or cancel.

Confirmation creates a non-simulated run record. The runner captures that run's
model/harness selection, snapshots Working, and waits for the SQLite acknowledgment
before spawn. Later selector edits affect only the next run. Known events stream
into the selected chat and move cards through the existing reducer; messages posted
while Working remain queued for the next confirmed turn. Captured thread identity
must match the resumed harness thread; a mismatch cancels the process and cannot
replace the stored identity. The fixed provider/executable is shared for the launch.

`x` records interruption and requests cancellation; stale events are rejected.
Shutdown cancels and joins live handles before final task/event persistence.
Storage errors prevent launching or cancel running handles, and are displayed.
Foreground writes remain asynchronous; abrupt termination can lose updates since
the last acknowledged write. Ready comes from validated completion plus process
exit, not from a claim that every asynchronous update is already on disk.

The UI displays LIVE ENABLED / CONFIRMED CALLS throughout. Demo seed cards may
remain visible, but tasks without isolated workspaces cannot run in live mode.
Acceptance still changes only task state; it never merges, pushes, or deletes.
The exec adapter requests read-only sandboxing and provides no interactive approval
channel. This is not a verified code-writing workflow or proof of platform sandbox
containment. Real gateway compatibility still requires explicit user-approved checks.

`test_live_runner` and the PTY smoke verify this UI path with temporary jj workspaces
and a fake executable, including startup inactivity, cancel/confirm, paste isolation,
small-terminal gating, streaming, captured model selection, resume mismatch, late
queued messages, checkpoint refusal, and stop/shutdown. The installed-Codex loopback
check verifies the headless path only; live UI behavior against a real model provider
has not been exercised.
