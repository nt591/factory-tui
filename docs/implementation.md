# Implementation sequence

This plan adapts the product and implementation sequence in `../factory/README.md`
and its development instructions. The native application is a reference, not a
runtime dependency. Implement the core in OCaml. Do not modify the native checkout.

## Product contract

A board of self-updating agent sessions. Each task opens a persistent work channel
and has an isolated workspace. Select a headless harness and gateway model for
each run. Keep past run selections immutable.

Columns: Queued, Working, Needs you, Ready. Only explicit acceptance marks Done.
Completion needs validated harness events and a successful process outcome.
Replies sent during work queue for the next turn unless explicitly interrupted.
Acceptance does not merge, push, or delete a workspace.

## Steps and gates

1. **Terminal shell — complete.** Build and launch the OCaml/Notty executable.
   Verify terminal cleanup, resizing, mouse input, and visible focus.
2. **Simulated sessions — complete.** Typed reducer, stable task/run identity,
   channels, stream-item replacement, and event-driven movement. Reject stale
   events. Selection follows task identity when its state changes.
3. **Composition and run selection — complete for simulation.** Queued replies,
   task-specific drafts, simulated acceptance, harness/model selection, and
   immutable run records exist. Tests verify edits affect only the next run.
   Models and harness selections do not establish live compatibility.
4. **SQLite persistence — complete for simulation.**
   The versioned snapshot codec retains tasks, drafts, selection, and run records.
   SQLite stores snapshots, a separate run table, and cursor-paged ordered events
   in one transaction. Temporary-file tests verify reopen, exclusive ownership,
   rollback, private new-file permissions, unsupported databases, and recovery.
   A background worker coalesces snapshots and retains bounded event batches.
   The UI saves through explicit TOML configuration or `--database`; no config
   means memory-only startup. Tests cover 200 queued saves, final flush, write
   errors, and PTY save/reopen with task drafts and interruption recovery.
   Both explicit headless execution and confirmed live UI runs now acknowledge
   their Working checkpoint before spawning.
   Unconfigured launches create no database. Stored conversations are sensitive.
5. **Codex supervision — process/fake UI and explicit headless path implemented.**
   The Codex-style decoder, bounded runner, and background delivery handle are
   tested with fake executables. `--fake-harness` starts nothing on launch; an
   explicit Start streams fixture events into chat. Stop/shutdown cancel and join.
   With SQLite, the Working checkpoint is acknowledged before spawning. Tests
   verify checkpoint refusal, stream replacement, queued replies, and stored
   process events. Details: `docs/harness.md`. The invocation builder validates
   model/directory and explicit resume identity and requests read-only execution.
   Loopback verifies installed Codex; real gateway behavior remains unverified. `--dry-run-codex` exposes
   a structured invocation preview with no executable, credential, or database
   access. CLI tests verify no process side effect and rejection of conflicting
   modes. `--run-codex` explicitly executes with a required database and stdin
   prompt, preserving known events and non-simulated run origin. Fake tests cover
   resume identity, cancellation, malformed output, and checkpoint refusal.
   Installed Codex 0.166.0 execution and resume pass an isolated loopback fixture.
   Confirmed live UI integration passes fake-process tests and the PTY smoke.
   An installed-Codex PTY loopback check also verifies task creation, confirmed
   file editing, card movement/chat, actual jj review, same-thread resume, acceptance,
   and archived-chat restart. Recorded jj workspaces skip only Codex's Git-directory
   check; headless invocation retains it. New and resumed argument shapes are tested.
   `--live-ui --workspace-write` explicitly selects workspace-write policy,
   shown in confirmation and captured per run. Fixture editing/review is tested.
   An installed-Codex loopback sentinel probe verifies read-only/write boundaries
   and never-approval escalation refusal on this Mac, including permitted TMPDIR
   access. The confirmation discloses temp directories. Real gateway UI behavior,
   broader sandbox coverage, and interactive approvals remain unverified.
6. **Gateway setup — validation and provider builder complete; integration pending.**
   `Gateway` validates a capped non-secret TOML file, HTTPS/loopback endpoints, and
   environment-key references without reading secrets or contacting the network.
   `--check-gateway` validates without opening storage or starting agents. Codex
   provider overrides are pure and tested for new/resumed threads. Details:
   `docs/gateway.md`. Installed-Codex headless loopback checks pass; real gateway
   checks remain pending. Setup starts no agent and reads no secret.
   Dry-run invocation must disclose no credentials. Verify protocol compatibility
   against a loopback fixture before an explicitly requested real gateway check.
   Configuration validity does not prove model compatibility.
7. **Isolated jj workspaces — creation and changes review integrated.**
   `Workspace` resolves an exact base and creates a new destination outside the
   source checkout without fetching or integrating. `Workspace.diff` returns a
   bounded real patch. Temporary-repository tests verify isolation, exact parent,
   source preservation, and rejection of unsafe inputs. Details: `docs/workspaces.md`.
   Workspace identity is attached before the first run and persisted with task
   snapshots; legacy tasks still load. `W` opens a modal creation form when SQLite
   is configured. A bounded background job creates the workspace, then selects its
   Queued chat without starting an agent. Form and PTY checks verify input safety,
   persistence/reopening, and isolation. Optional TOML workspace defaults prefill
   the editable form and jj review path without commands or directory creation.
   `v` opens explicit background diff review
   with real patch/empty/error states and task-bound result ownership. Horizontal
   scrolling uses terminal cells, with h/l, arrows, 0, and Ctrl-wheel verified on
   long Unicode lines. `]`/`[` and clickable buttons jump file headers using an
   immutable patch index; the footer shows file position, and page keys use the
   viewport height. Short final-file headers stay visible. Sanitized display rows
   and maximum terminal width are prepared once per loaded result in `Diff_display`;
   redraw/resize do not scan the entire patch. Refresh invalidates both raw index
   and display cache. Unit/real-jj tests cover lifecycle and unchanged raw text.
   Review never
   accepts, integrates, or deletes. `--live-ui` explicitly enables confirmed
   workspace-backed Codex execution with a durable Working checkpoint. Acceptance
   remains separate from merge and push. Live calls require explicit live mode;
   workspace creation and review require explicit user actions.
8. **Local distribution and lifecycle — implemented; release portability pending.**
   Vim navigation, repository sidebar,
   bordered cards, grapheme-aware multiline editing/paste, anchored reading views,
   transcript search,
   readable/raw tool activity with focused full-width expansion, Help/Settings tabs,
   and terminal smoke tests
   exist. Short terminal bodies show the focused pane so composing and searching
   do not hide behind the board. A pure `Pane_layout` module selects splits;
   unit/PTY tests cover compact compose/focus cycling without changing drafts.
   Activity metadata wraps full task titles, repository/workspace paths, next-model
   IDs, and recorded review bases. Pure `Activity_content` produces logical rows;
   the renderer applies pane-width wrapping before scrolling. Unit/PTY checks
   cover complete workspace identity and retained read-only inspection.
   A contextual action bar offers only state/mode-relevant process, acceptance,
   editing, and workspace actions. Ready review/acceptance are prioritized for
   compact screens; live Start is labeled confirmation. Keyboard validation stays
   separate, and rendering starts no command. Unit/PTY tests check lifecycle bars.
   Grapheme-preserving text wrapping uses the same Uuseg boundary type as the
   editor. `Text_layout` is separate from controller/rendering state; sanitized
   chat, composer, activity, and card-title wrapping cannot split emoji sequences.
   Oversized clusters stay whole for pane cropping. Unit/PTY checks cover boundaries.
   Help/Settings shows its visible row range and overflow direction. Page keys
   use the current menu capacity and tab changes reset the position. Pure
   `Menu_window` selection preserves modal isolation and task/draft state; unit/PTY
   checks cover compact paging and bottom instructions.
   Chat image construction is bounded to the actual visible row window, including
   search-row space. Full logical rows remain available for history anchoring and
   search. `Chat_layout` caches wrapped rows/anchors for the current task and width,
   invalidating on immutable message-list replacement. Height/model changes reuse
   it; new stream text and delivery acknowledgements rebuild. The single cache is
   transient, with unit/streaming/search/PTY verification and scoped measurements.
   Compact-list navigation follows displayed task order across states, including
   arrows/counts/gg/G/pages. Four-column layouts keep state-local vertical and
   cross-column horizontal motion. Rendering updates transient navigation mode;
   resize/filter/state-change unit and PTY checks verify selection consistency.
   Board overflow shows visible card/list ranges and above/below arrows rather
   than a generic scroll label. Pure `Board_window` computes both visible items
   and cues; paging/selection tests verify matching ranges and retained task hits.
   Short columns with tasks request resize instead of falsely claiming emptiness.
   Transcript search reuses matches for unchanged query/message-list identity,
   rebuilding on streaming replacements or query changes. Indexed membership
   avoids repeated match-list walks while highlighting visible rows. Cache state
   stays transient; unit and large-list checks preserve selection/seek behavior.
   Two-row task-card previews mark hidden title content with a grapheme-safe
   ellipsis. Chat retains the complete instruction; pure/render/PTY tests verify
   the preview marker and unchanged task text, including Unicode boundaries.
   Repository sidebar rows are bounded to the pane, with pinned main navigation,
   a separate wheel scroll region, overflow cues, and selection-follow on filter
   changes. Hidden entries create no hitboxes over the footer. Pure/terminal tests
   verify large repository lists, clipping, resize, and modal input isolation.
   Kanban wheel positions are independent per column; compact-list scrolling stays
   separate. Frame geometry routes input to the column under the pointer. Explicit
   top positions differ from selection-following, and keyboard/state transitions
   restore following only in the target column. Unit and dedicated PTY fixtures
   verify independence, clamping, selection/movement, and snapshot isolation.
   Activity run history shows age for active records and frozen duration for ended
   records, using supplied wall-clock timestamps. Run age begins at confirmation,
   including checkpoint/cleanup waits, not necessarily process spawn. Pure
   `Run_time` handles invalid/reversed/missing timestamps without inventing time
   or changing completion. Unit and fixture PTY tests verify the displayed values.
   `Menu_content` generates Help/Settings copy from explicit execution mode,
   storage path, and selected task. Live copy names Codex-only execution and
   confirmation rather than advertising simulated harness cycling. Fake/replay
   copy states its actual process boundary; mode tests and installed-agent PTY
   checks verify browsing menus starts no invocation.
   UI guidance and visual verification are in `docs/ui-parity.md`.
   Standalone install and repeatable local archive packaging include build metadata,
   dependency lock, operational docs, and temporary-install checks. Signing,
   notarization, and fresh-machine lock reconstruction are not verified. Local
   build/footprint measurements are in `docs/distribution.md`.
   Do not claim a GUI performance advantage without a comparable measurement.

A step can require several tested commits. Keep storage, process supervision,
and UI integration in separate increments when this makes validation clearer.
Do not mark a step complete from a mock test that does not cover its live boundary.

## Commit workflow

The repo is already jj-initialized. Do not initialize it again or rewrite the
existing tested history. No remote is configured; do not fetch or push.

For each increment:

```sh
./scripts/format.sh --check
opam exec --switch=. -- dune build @install
opam exec --switch=. -- dune runtest --force
# Run the PTY smoke when input, rendering, or lifecycle changes.
uv run --with pyte python scripts/smoke-terminal.py
git diff --check
jj commit -m "[factory-tui] Describe the tested increment"
jj bookmark set main -r @-
```

Update this plan and README with verified behavior and remaining limits in the
same commit. Keep business logic out of `bin/main.ml`. Follow the subsystem layout in
`docs/modules.md`; keep implementation/interface pairs together. Tests must not use live
agents, credentials, or real workspaces. Preserve simulation labels until an
explicit live path exists. Never push without an explicit request.

## Optional compiler follow-up

OxCaml is deferred at the user's request. Continue on the verified standard OCaml
switch. `docs/oxcaml.md` records the bootstrap failure, interrupted newer attempt,
and required application/editor checks before adopting compiler extensions. This
TODO does not block any of the product steps above.

Demo seed data and fake runners live in `lib/demo` as `Demo.Seed` and
`Demo.Runner`. Runner ownership is abstract and delivery uses a callback context,
so fixture implementation does not depend on the terminal controller.

## Current audit

`docs/audit.md` maps the original UI/product requirements to inspected source,
tests, terminal behavior, and packaged execution. Read-only execution, real gateway
compatibility, and fresh-machine release validation are not claimed complete.

First-run live initialization starts with no seed tasks and persists an empty
board before displaying it. `n` opens workspace creation in live mode, while
simulation retains demo task creation. Existing snapshots are preserved rather
than reseeded. Archive/filter empty states provide distinct recovery actions.

Live retry ownership is serialized by task and canonical workspace directory
until the previous handle's output/outcome and join complete. Confirmed replacements
remain queued, independent directories can run concurrently, and shutdown interrupts
waiting runs without spawning them. Temporary checkpoint/alias tests verify this;
coordination is local to the runner, not a global workspace lock.

The installed-agent workflow probe is opt-in (`scripts/smoke-codex-ui.py`) and uses
only temporary repositories, isolated runtime/auth directories, dummy credentials,
and fixed loopback Responses events. Shared PTY control and preview rendering live
in `scripts/fixtures/terminal.py`; pure unit tests still start no agent or server.
Archive entry selects a visible accepted task when the saved selection is absent.
Selected-run lifecycle events replace stale checkpoint text with run/review/retry
guidance; acceptance shows retained read-only chat. Stale/background events do not
replace another task's status.

Live harness shortcuts preserve Codex instead of cycling to unsupported Claude.
An explicit H can select Codex for an imported simulated Claude task, without
starting a run or changing its captured history. Accepted tasks reject model-editor
entry as well as harness changes. Mode/content tests and the installed-agent
loopback workflow verify these shortcuts before confirmation; simulation still
supports its two-harness cycle.

Non-modal wheel dispatch uses visible pane rectangles rather than falling back to
keyboard focus. Chat, Activity, compact lists, columns, and repository rows retain
their own targets; composer/footer/pinned-sidebar surfaces do not move another
pane. Frame/mouse tests verify boundaries and snapshot isolation, and the PTY
smoke checks that footer wheel input leaves the board window unchanged.

Modal wheel input is limited to the rendered content region. Help/Settings tabs,
borders, position row, and background do not move menu content or the board.
Review titles, executable fields, and buttons do not scroll the patch; executable
editing removes its wheel target. Pure frame/input and PTY tests cover the content
boundary while preserving existing modal ownership and confirmation blocking.

Chat history distance and Activity row offset are remembered separately through
mouse/direct focus switches. A tool-pane wheel cannot borrow the chat-history
offset, and returning to chat restores its history position, including updates
received while Activity had focus. Explicit task selection resets both positions;
keyboard pane cycling retains its fresh-position behavior. Pure frame/input and
streaming PTY tests verify this; position memory is abstract and never serialized.

Activity keeps its remembered visible window when chat receives mouse focus.
Rendering clamps that offset to the current geometry and creates images only for
visible Activity rows. Zero-height panes do not replace remembered positions.
The logical tool/history content stays complete; unit and streaming PTY checks
cover focus switching, resize, retained history, and unchanged snapshots.

Board mouse focus preserves the selected chat's paused history. Unfocused chat
redraws use its remembered history distance, not the board's offset. Explicit
keyboard/task/zoom resets clear the viewport anchor and remembered distance
together. Pure frame checks and `scripts/smoke-board-history.py` verify column
scrolling, subsequent output, return to chat, and explicit End-follow without
changing saved tasks or starting an agent.

Explicit card/keyboard selection updates footer guidance for that task rather than
leaving another task's acceptance/completion notice visible. `Task_guidance` is
pure and names task ID, queued instructions, confirmation/setup prerequisites,
read-only acceptance, or replay boundaries. Selection does not mask storage errors
or invoke preflight. Pure and PTY tests verify correct identity and no new runs;
filtering still keeps the selected chat until a task is explicitly selected.

Changes review supports Ctrl-U/D half-page and Ctrl-B/F full-page movement using
its rendered patch capacity, including one-row panes. Control-letter decoding
matches the main TUI; unrelated/mixed modifiers cannot invoke refresh or path
editing. Paging keys are inactive while editing the executable, and modified
Enter cannot refresh it. Unit and resized-terminal PTY checks cover these paths.

Board counters use the same repository/search/archive-filtered task set as the
visible cards. Active views exclude accepted tasks; Archive counts only matching
accepted tasks. Filtering does not close a selected conversation outside the
board filter. Unit/render tests cover repository/query/empty/archive counts, and
the forty-repository PTY fixture checks counters after clicking a repository.

Live confirmation wraps the full task title, model, workspace path, and thread
identity instead of clipping them. Its height follows the required content within
the terminal bounds; Run is enabled only when the entire disclosure and buttons
fit, in addition to the 64-column/13-row minimum. Too-small terminals show the
required row count and remain non-authorizing. Button hitboxes track the actual
wrapped-content row. Unicode/small-screen unit tests and installed-agent/fake PTY
checks verify full workspace disclosure, paste isolation, and resize blocking.
