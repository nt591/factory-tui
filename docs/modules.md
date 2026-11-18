# Module boundaries

## Source layout

```text
lib/
  domain/     # Task, run, message, and lifecycle data
  storage/    # Snapshot codec, event replay, SQLite, persistence worker
  agent/      # Harness decoder, process supervision, Codex, gateway, preview
  workspace/  # Isolated jj creation and real diffs
  terminal/   # Controller, rendering, configuration, app loop
  demo/       # Seed data, timed fixture events, fake process runner
  support/    # Small shared control-flow helpers
  dune
bin/          # CLI entry point
test/        # Unit and integration checks
```

The subsystem grouping follows the organizational idea in Hack's
`hphp/hack/src`, without copying its scale or build graph. Dune's
`include_subdirs unqualified` keeps one wrapped `Factory_tui` library, so existing
module names and `.mli` APIs do not change. File names must be unique across these
directories. Each implementation and its interface stay beside each other.

These are source groups, not enforced library-level dependency boundaries.
Splitting them into independent Dune libraries is a later refactor if it provides
useful dependency enforcement. The current terminal/controller/fixture integration
is coupled; moving directories alone does not remove that coupling.


Each library module has an explicit interface. The compiler checks implementations
against these interfaces during the normal Dune build.

- `Model`: immutable task/run/event data and lifecycle transitions. Records and
  variants are public because reducers, codecs, and rendering inspect them.
- `Snapshot`: the persistence payload, encode/decode, restart recovery, and the
  run-record encoder used by the SQL store. JSON parsing helpers remain private.
- `Events`: replay envelope encode/decode and an abstract file/FIFO source. Callers
  close the source through an idempotent operation, not its raw descriptor.
- `Live_runner`: abstract validated executable/provider config and background live
  handle ownership. Preflight restricts execution to workspace-backed Codex tasks;
  a callback context keeps it independent of controller/rendering internals.
  Its explicit policy is captured on each run; configuration defaults to read-only.
- `Live_confirmation`: task-specific usage/auth disclosure rendering and hitboxes;
  small terminals cannot authorize a hidden confirmation.
- `Changes`: abstract background diff ownership for one task/workspace, with
  explicit refresh, poll, and join. Results never mutate another task.
- `Review`: abstract changes-pane state, executable editing, and scrolling.
- `Review_view`: diff display and modal hitboxes; no process or task mutations.
- `Workspace_form`: abstract field/editor state; local validation and input only.
- `Workspace_dialog`: form rendering/hitboxes, independent of controller and jobs.
- `Task_creation`: abstract background job for workspace creation and task assembly;
  it uses domain APIs and never starts an agent or owns UI/persistence.
- `Workspace`: abstract validated workspace identity, exact-base creation, and
  bounded real diffs. No automatic Git conversion, fetching, integration, or deletion.
- `Command`: bounded plain stdout capture and stderr draining for jj operations;
  internal descriptors and spawn/cleanup helpers are private.
- `Execution`: explicit headless task execution, checkpoint-before-spawn, event
  reduction, resume ownership checks, and final persistence. No UI default starts it.
- `Invocation_preview`: validated JSON preview of execution arguments and safety
  flags. It can load an explicit non-secret gateway file but never starts a run.
- `Gateway`: abstract validated endpoint and environment-reference configuration.
  Parsing/validation errors omit file contents; no credentials/network are read.
- `Codex`: pure invocation construction with explicit directory/model/thread
  validation; no subprocess or credentials are accessed.
- `Harness`: normalized decoded event plus raw JSON. Parser exceptions and helpers
  stay private. Unknown events can be inspected without extending the public type.
- `Process`: configuration, outcome, and a bounded runner. Spawn setup, clocks,
  descriptors, signal handling, and cleanup helpers remain private.
- `Run_handle`: abstract background ownership with cancel, drain, outcome, close.
  Queue, mutex, and worker thread cannot be accessed by callers.
- `Storage` and `Persistence`: abstract database and background-worker ownership.
  Callers cannot access SQLite handles, advisory locks, or internal queues.
- `Controller`: actions, UI state, and supported interaction/lifecycle operations.
  Its mutable state record is public because the current renderer and app loop
  read and update it. Navigation algorithms and command dispatch helpers remain
  private. This is not yet an abstract controller with a read-only view model.
- `Text_edit`: abstract bounded UTF-8 text and cursor state, with insertion,
  deletion, line navigation, and codepoint movement. It performs no UI actions.
- `Ui`: frame/hitbox data, render, mouse dispatch, and tested text wrapping. Theme,
  borders, image composition, and pane rendering helpers stay private.
- `Demo.Runner`: abstract ownership of fixture runs with poll/close. Its fixed
  script, running handles, and checkpoint details remain private. It receives a
  callback context rather than depending on Controller or terminal rendering.
- `App`: snapshot and interactive entry points only.
- `Demo`: namespace for `Seed` (seed data/timed events) and `Runner` (fake
  subprocess delivery). Implementations live together under `lib/demo`.
  Controller supplies the runner callback context; demo code never imports it.

No functor is required for these boundaries. Keep modules small and add a functor
only when a concrete dependency must be parameterized; do not expose internals to
make tests convenient. Current integration tests use the same public interfaces
as the application. Resource handles stay abstract even in tests.

## Resource scopes with binding operators

`Scope` provides a native `let@` binding operator for callback-style scopes:

```ocaml
open Scope

let read filename =
  let channel = open_in filename in
  let@ () = on_exit (fun () -> close_in_noerr channel) in
  really_input_string channel (in_channel_length channel)
```

The remainder of the block is the callback. `on_exit` still uses `Fun.protect`,
so normal returns and exceptions both run cleanup. Nested scopes clean up inside
out. Cleanup failures retain `Fun.Finally_raised` semantics; this is not an error
suppression mechanism. No PPX or Jane Street library dependency is required.

Use this when a cleanup callback creates nesting. A short existing helper such
as `statement db sql (fun stmt -> ...)` or mutex wrapper can stay explicit.
Do not confuse a scope binding with asynchronous or result `let*` sequencing.
Cleanup belongs to the lexical remainder, so keep post-cleanup result inspection
outside it: the app loop ends its scope before inspecting final storage errors.
The helper does not acquire resources, infer ownership, or register an automatic
global cleanup stack; place each binding after successful acquisition.
