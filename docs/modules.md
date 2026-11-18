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
  Canonical workspace slots retain ownership through cancellation/checkpoint/join;
  waiting task IDs are exposed, not process or mutex internals.
- `Live_confirmation`: task-specific usage/auth disclosure rendering and hitboxes;
  small terminals cannot authorize a hidden confirmation.
- `Changes`: abstract background diff ownership for one task/workspace, with
  explicit refresh, poll, and join. Results never mutate another task.
- `Review`: abstract changes-pane state, executable editing, and scrolling.
  Cursor-separated executable text supports shared horizontal editor layout
  without exposing the Text_edit handle.
- `Review_view`: diff display, modal hitboxes, and visible patch scroll geometry;
  no process or task mutations. Path editing exposes no patch wheel target.
- `Diff_display`: abstract prepared sanitized patch lines and maximum terminal-cell
  width. Review builds it per loaded patch; rendering slices only visible rows and
  resizing reuses the width. The raw document remains separate and unchanged.
- `Diff_document`: abstract immutable patch-line/file index, bounded row slices,
  and previous/next file lookup. Supplied paths remain display text, not commands.
- `Workspace_defaults`: optional typed startup preferences shared by config and
  form initialization; it holds no instruction, credentials, or execution permission.
- `Workspace_form`: abstract field/editor state and form-local setup/error status;
  local validation and input only. Background task status cannot replace dialog
  feedback; controller creation paths explicitly report form outcomes.
  Submission validation focuses the first invalid field; ordinary validation
  remains side-effect-free. Cursor-separated text parts support horizontal display
  windows without exposing the editor handle. Text_layout selects whole graphemes around the cursor.
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
  The renderer supplies transient board list/column mode so navigation follows
  the displayed task order; this mode is not a persisted task preference.
- `Repository_labels`: pure shortest distinguishing path suffixes for cards/sidebar.
  A reversed-component index disambiguates duplicate basenames without path I/O.
  Filter actions, persistence, and Activity retain original repository strings.
- `Sidebar_window`: pinned navigation and bounded repository rows with a reserved
  overflow cue. The frame supplies the visible repository scroll region; hidden
  entries create no click targets. Filter changes restore selection-follow mode.
- `Column_scroll`: abstract per-state manual board positions. Task selection and
  state movement restore following in the destination column; positions never
  become snapshot fields. The frame holds visible column geometry for wheel input.
- `Board_window`: pure visible-item selection, selection/manual-scroll offsets,
  and card/list range cues. The renderer uses one window definition for content
  and overflow labels; the helper changes no task or viewport state.
- `Task_guidance`: pure selected-task footer copy from lifecycle, queued input,
  workspace/harness and mode. It does no filesystem preflight or execution.
  Controller refreshes it on selection without masking storage errors.
- `Board_guidance`: pure empty-state copy and action selection for live, demo,
  archive, and filtered boards. It starts no jobs and owns no persistence.
- `Run_time`: pure run-age/recorded-duration text from supplied timestamps. It
  never changes lifecycle state or reads the clock. Invalid/reversed times remain
  unavailable instead of being represented as zero duration.
- `Activity_content`: pure logical task metadata, tool groups, and captured-run
  rows. It has no controller, rendering, process, or storage dependency. The UI
  wraps each row at the actual pane width before computing scroll bounds.
- `Tool_activity`: pure summaries of actual harness command, MCP, and file-change
  fields, with raw payload access. It does not execute tools or infer success.
- `Chat_layout`: abstract single-entry transcript cache keyed by task, pane width,
  and immutable message-list identity. Within that task/width, unchanged message
  records reuse wrapped row/anchor blocks across streaming updates. New records
  rebuild; removed records leave the current index. No task, persistence, process,
  theme, or controller behavior lives in this module.
- `Chat_viewport`: abstract reading anchor keyed by task/message and wrapped row.
  Appended output and earlier stream growth do not move a paused reading view.
  Explicit scrolling/search seeking changes the anchor; End resumes following.
  Its bounded visible-row selection prevents offscreen chat image construction.
- `Chat_search`: abstract transient query/matching-message selection, anchored
  by stable message ID. It searches content/authors without modifying tasks.
  Unchanged immutable messages reuse query matches; indexed membership supports
  visible-row highlighting. Clear releases retained cache data.
- `Text_edit`: abstract bounded UTF-8 text and cursor state, with insertion,
  deletion, line navigation, and extended-grapheme movement. Segmentation uses
  Uuseg; cached boundaries are private and malformed UTF-8 is normalized. It performs no UI actions.
- `Menu_content`: pure mode-specific Help/Settings rows. Simulation, fake, replay,
  and live modes state their actual invocation boundary. No controller, Notty,
  filesystem, process, or authentication dependency is required.
- `Menu_window`: pure menu row selection, viewport clamping, and visible
  position/overflow cues. Ui supplies wrapped content and owns rendering; the
  controller uses the resulting capacity for page navigation.
- `Action_bar`: contextual labels/actions from task state and session-mode flags.
  It does not run preflight, read paths, change tasks, or grant execution permission.
  Keyboard dispatch and live confirmation retain their own validation.
- `Pane_scroll`: abstract transient chat/Activity offset memory. Mouse focus
  switches restore the target offset; selecting a task clears both. Board-focused
  redraws use remembered chat distance. Explicit chat resets clear distance and
  viewport anchor together. Unfocused
  Activity renders its remembered visible window with bounded row images. History
  anchoring remains in Chat_viewport and no position is persisted.
- `Pane_layout`: pure board/detail split selection from body size and focus.
  It has no controller, persistence, terminal, or process dependency.
- `Text_layout`: grapheme-preserving terminal-cell and word wrapping for sanitized
  text. It has no controller or resource state; Ui sanitizes text before wrapping.
  A cluster wider than the pane stays whole and is cropped by rendering.
  Bounded row previews reserve a grapheme-safe ellipsis for hidden title content.
- `Ui`: frame/hitbox data, render, mouse dispatch, and tested text wrapping.
  Separate visible scroll rectangles prevent footer/composer/sidebar-heading wheel
  input from affecting keyboard-focused panes. Modal content has a separate
  wheel region; overlay controls and background never scroll hidden content. Theme, borders, image composition, and pane rendering helpers stay private. Activity
  expansion preserves the previous task layout and exposes full-width output.
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

Loopback Responses fixtures are grouped under `scripts/fixtures/`, with separate
answer/resume and sandbox-sentinel integration entry points. The sandbox fixture
uses only supplied temporary command paths and never chooses a real provider.
Pure fixture tests run under `scripts/check.sh` without a server or subprocess;
installed-agent execution remains a separate explicit opt-in command.

`Live_confirmation` computes required height from sanitized, grapheme-wrapped
identity/disclosure rows. The UI limits that height to the terminal; insufficient
space removes authorization controls. Button geometry uses the computed row,
not a fixed coordinate. It starts no process or workspace operation.
