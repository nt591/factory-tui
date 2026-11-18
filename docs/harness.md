# Harness supervision

This layer is implemented in OCaml and is independent of the Rust app. It is
connected through explicit `--fake-harness` and `--live-ui` modes. Default Start
uses demo timers. Fake mode uses local shell fixtures; live mode requires an
explicit executable, workspace task, SQLite, and per-run confirmation. Live Codex
can access authentication and incur model usage. Setup alone starts no process.

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
The confirmed live UI uses the same checkpoint-before-spawn boundary.

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
Codex invocation, resume identity, and gateway validation are also implemented.
Fake tests alone do not prove installed-agent or real-provider compatibility.

## Codex invocation builder

`Codex.invocation` builds a process configuration only. It does not spawn Codex,
read credentials, or open a database. It requests JSONL, ignores user config,
defaults to read-only sandboxing and never approvals, and passes the prompt
through stdin. Explicit live-UI write policy is described below.
An explicit thread ID selects `exec resume`; no `--last` or implicit session lookup
is used. The working directory is set by the supervisor for both new and resumed
runs. Model/thread IDs reject option-like and control-character values.

Argument forms were inspected against the installed Codex help on November 17,
2026. Pure tests validate the constructed arguments. No live compatibility or
native resume claim follows from those checks. Separate installed-Codex loopback
checks exercise headless and confirmed TUI execution/resume. Real-provider checks
remain pending.

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
this headless command does not create isolated jj workspaces. Read-only sandbox and
never-approval settings are requested; there is no interactive approval channel.
Installed-Codex loopback checks pass; broader sandbox and real-provider checks
remain incomplete. Do not infer production readiness from the local fixture.

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
model, workspace, new/resumed thread, usage/auth disclosure, and requested
sandbox policy (read-only by default). Enter/`y` confirms; Escape/`n` cancels. Pasted text cannot authorize a run.
At less than 64 columns or 13 rows confirmation is blocked; resize or cancel.
Complete task/model/workspace/thread details wrap in a bounded scrollable dialog.
Run stays locked until every row has been shown; jumping past rows does not count.
Resize/reflow, changed details, and reopening reset this gate. Use Vim/arrows,
paging keys, or body-only wheel input. Run/Cancel remain pinned below the content.

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

The UI displays LIVE ENABLED / CONFIRMED CALLS throughout (LIVE WRITE for explicit
write mode). A newly initialized live database contains no demo tasks; its empty
board provides actionable onboarding. `n` and `W` both open workspace creation
in live mode. Previously saved tasks are never deleted or silently replaced by
this initialization; saved demo cards may remain, but unattached tasks cannot
run live. Fresh simulation boards retain sample cards. Empty archived/filter
states have separate guidance and explicit return/clear actions.
Acceptance still changes only task state; it never merges, pushes, or deletes.
The exec adapter defaults to read-only sandboxing and provides no interactive
approval channel. An explicit workspace-write option is described below. This is not a verified code-writing workflow or proof of platform sandbox
containment. Real gateway compatibility still requires explicit user-approved checks.

`test_live_runner` and the PTY smoke verify this UI path with temporary jj workspaces
and a fake executable, including startup inactivity, cancel/confirm, paste isolation,
small-terminal gating, streaming, captured model selection, resume mismatch, late
queued messages, checkpoint refusal, and stop/shutdown. The installed-Codex loopback
check verifies the headless path only; live UI behavior against a real model provider
has not been exercised.

## Explicit workspace-write policy

Read-only remains the default for every launch, including headless execution and
preview. Enable write access only with an explicit live-UI flag:

```sh
./scripts/run.sh --live-ui --workspace-write \
  --codex-executable /absolute/path/to/codex
```

This selects Codex's requested `workspace-write` sandbox for isolated workspace
**tasks**, not the source repository. This policy also allows temporary-directory
writes (including `TMPDIR`) and Codex's own runtime state; it is not a filesystem
allowlist containing only the task directory. The confirmation discloses the
workspace and temporary-directory access. SQLite and per-run confirmation are still
required. The banner says LIVE WRITE / CONFIRMED CALLS and the confirmation says
WRITE ACCESS: workspace + temp directories. Setup/launch starts no process;
paste cannot confirm. Demo/unattached tasks cannot obtain write-mode runs. No startup TOML
setting silently enables writes. `--workspace-write` is rejected outside live UI;
headless execution and its dry-run continue to use read-only policy.

The policy is captured per run and persisted alongside its model, harness, and
execution origin. Existing runs are unchanged; snapshots without a policy default
to read-only. A changed future configuration cannot rewrite the active run's
requested policy. Simulation cannot record write-mode execution. The runner waits
for the Working checkpoint before spawning, as in read-only mode.

The adapter still sets `approval_policy="never"`: it does not implement interactive
approvals. This flag means Codex cannot ask the TUI for permission escalation;
commands outside the requested sandbox should be denied by the installed harness.
No automatic review/approval, danger-full-access, writable additional directories,
or automatic merge/push is added. Review actual changes with `v`; acceptance only
marks Done. To return to read-only, restart without `--workspace-write`.

The test fixture writes into a temporary task workspace only after observing the
write-policy argument, then streams completion. Unit/PTY checks verify explicit
confirmation, output, a real reviewable patch, untouched source checkout, captured
policy, backward-compatible persistence, and unchanged earlier run records. This
verifies our policy plumbing and workflow, **not OS sandbox enforcement**. A fake
executable is not a security sandbox. The installed-Codex sentinel integration
below now checks specific write and escalation-denial cases. Network restrictions, all protected path variants, and
full containment are not established by that finite probe. The earlier
installed-Codex answer/resume loopback returns no tool calls and does not prove
those properties.

## Installed Codex sandbox sentinel probe

```sh
python3 scripts/smoke-codex-sandbox.py --codex /absolute/path/to/codex
```

This opt-in script starts the installed executable with a loopback Responses
fixture and a dummy key. HOME and CODEX_HOME are isolated; only PATH/LANG and
script-created environment settings are passed to the child. It obtains the
read-only invocation from the app's dry-run builder, then changes only the sandbox
policy for the write case, as the app's tested `Codex.with_policy` does. It does
not drive the live TUI or claim end-to-end provider verification.

The agent advertises its tools; the server returns a fixed shell-tool call:
write one sentinel in the workspace, one in an ordinary sibling directory, and one in a separate runtime
TMPDIR. It observes the subsequent tool result and verifies file presence/content.
A third case explicitly requests `require_escalated` with never approvals, checking
an explicit refusal and no sentinel writes. If the installed tool cannot express
that request, the test fails rather than claiming approval refusal was verified.
Only script-owned temporary paths are touched. The test never requests changes
to real repositories, personal files, or credentials.

Verified locally on November 17, 2026, macOS 26.7.1 arm64, codex-cli 0.166.0:

- Read-only: workspace, runtime TMPDIR, and ordinary sibling writes denied.
- Workspace-write: workspace and runtime TMPDIR writes allowed; sibling denied.
- Workspace-write plus escalation request: explicit never-approval refusal;
  no workspace, TMPDIR, or sibling writes occurred.

The first probe mistakenly made the entire temporary test root TMPDIR, which
made its supposed sibling test path writable. The corrected probe assigns TMPDIR
to a separate child directory. This revealed an overly narrow UI disclosure, not
a demonstrated sandbox bypass. The confirmation/docs now explicitly include
workspace + temporary directories. Do not describe workspace-write as task-only.

These are exact observed cases, not a general security audit: permitted auxiliary
paths, protected metadata, symlink variants, network access, session isolation,
and descendant containment need independent coverage. A real gateway/model/tool
selection is still unverified. Interactive approval/steering is still unsupported;
the current execution policy denies escalation rather than asking the user.

Shared fixed-answer/function-call fixtures live in `scripts/fixtures/`. Pure
fixture tests (`python3 scripts/test-responses.py`) validate event sequences and
advertised tool shapes without a subprocess, network server, or filesystem work.
The original answer/resume integration stays a separate opt-in command.

## Stop/retry workspace ownership

The live runner retains a task/workspace slot until its previous handle has
finished output draining, published its terminal outcome, and been joined.
A newly confirmed retry can enter Working immediately, but it does not spawn
while the old run is cancelling or awaiting a SQLite checkpoint. Activity shows
that it is waiting for previous workspace-process cleanup. Once the slot is free,
the replacement still requires its own durable Working checkpoint before spawn.

Slots use the canonical directory, so two tasks referring to the same workspace
through a symlink cannot overlap within one live runner. Independent workspace
directories are not serialized against each other. This is in-process coordination,
not a global workspace lock: unrelated applications, a separate Factory process
with a different database, and deliberately escaped descendants are not contained
by this mechanism. Workspace settings must not be treated as process containment.

Old-run output and outcomes are discarded by run identity once a retry replaces
it. Old terminal errors do not replace the replacement's status. Closing the runner
cancels and joins owned handles, then records interruption for confirmed runs that
were still waiting and had no handle. Shutdown never starts such queued runs.

`test_run_serialization` verifies a live sleeper blocks an aliased workspace while
another workspace completes, stop/retry during a deliberately blocked temporary
SQLite checkpoint, stable replacement identity, waiting-state rendering, and
shutdown of both running and waiting tasks. All commands use fake executables and
temporary workspaces. Disabling the workspace-slot guard causes the alias test to
fail, confirming that the test detects the overlap regression rather than merely
checking the final task states.

## Installed Codex through the terminal workflow

Explicit opt-in; not part of normal tests:

```sh
uv run --with pyte python scripts/smoke-codex-ui.py \
  --codex /absolute/path/to/codex --jj /absolute/path/to/jj
# Optional macOS PNG captures:
uv run --with pyte --with pillow python scripts/smoke-codex-ui.py \
  --codex /absolute/path/to/codex --preview /tmp/factory-codex-ui.png
```

Verified on November 18, 2026, macOS 26.7.1 arm64, codex-cli 0.166.0. The script
creates temporary jj source/task workspaces and a real SQLite board. HOME,
CODEX_HOME, and TMPDIR are isolated, and the only key supplied is a dummy loopback
key. The server returns a fixed shell call that writes one task-workspace sentinel,
then a fixed answer. No real model or gateway is contacted.

The probe drives terminal input, not controller shortcuts: empty startup → workspace
form → Queued → write disclosure → confirmation → Working → file and answer →
Ready → task zoom → actual jj patch → queued follow-up → confirmed saved-thread
resume → acceptance → archive → shutdown/restart → accepted chat. It checks both
rendered UI and SQLite state. A response gate holds the first loopback response
until Working is visible and saved; the test does not assume a minimum agent delay.
The source checkout commit and task base remain unchanged, and the workspace/file
remain after acceptance. The selected-run footer offers review/acceptance rather
than continuing to claim that a completed run is waiting for a checkpoint.

Codex's Git-directory gate rejects jj task workspaces because they have `.jj` but
no `.git`. `Live_runner.prepare` adapts only workspace-backed tasks with recorded
identity and existing jj metadata, using `--skip-git-repo-check`. This bypasses
neither sandbox restrictions nor never-approval policy. The headless invocation
builder retains the Git-directory gate. Both new and explicit-resume forms are
covered by pure policy tests and the installed-agent terminal probe.

The PTY helper is separate from response/tool fixtures and has bounded waits,
shutdown draining, and cleanup. Existing fake-terminal coverage remains separate.
This probe proves this installed executable's local workflow only; provider tool
selection, billing, network behavior, broad sandbox security, interactive approvals,
and public release portability remain outside its scope.
