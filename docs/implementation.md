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
   dependency lock, operational docs, and temporary-install checks. Fresh temporary
   opam-root/compiler reconstruction from the lock passed on this Mac with an
   explicitly recorded compiler workaround; all locked packages and the fresh
   binary's parallel/terminal tests were verified. Signing, notarization, clean-OS
   validation, editor-tool reconstruction, and cross-OS support remain unverified. Local
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
identity. It grows to fit when possible and scrolls at the terminal height otherwise.
An abstract viewport records shown row intervals; Run stays locked until they cover
the entire disclosure. End cannot bypass unseen intermediate rows. New dialogs,
changed disclosures, and changed dimensions reset that coverage. Confirmation also
checks current policy/identity against the shown disclosure before queuing a run.
The minimum remains 64 columns and 13 rows. Buttons stay pinned below the row range;
wheel input acts only on the disclosure body. Vim/arrows, Home/End, Page Up/Down,
and Ctrl-U/D/B/F browse without starting an agent. Pure tests and a dedicated
fake-harness PTY check verify gaps, reset, paging, mouse cancellation/Run, exact
identity retention, and the durable confirmed-run path. This records displayed
rows, not proof that a person read them. No credentials or real model are used.

Streaming transcript layout reuses unchanged immutable message blocks within the
current task/content width. Changed text, authors, or queued labels rebuild their
block; task/width changes rebuild all blocks. Removed messages are absent from the
new cache, and reordered messages follow current transcript order. Aggregate row
and anchor lists still rebuild for a changed message list. Pure identity/lifecycle
tests and the existing streaming/search/history PTY checks verify this optimization.
No cache state is persisted. Native command fixtures now include failure case,
iteration, and concurrent-worker context; deadlines and scheduling are unchanged.

The opt-in `scripts/smoke-fresh-switch.py --reconstruct` installs the lock into a
new temporary opam root and empty switch, compares exact package versions, builds
in a separate Dune directory, and runs unit/terminal checks against that binary.
The documented macOS compiler workaround is explicit, platform-scoped, and included
in the report; it is not an OxCaml migration. The first unmodified bootstrap
failed at caml_unix_pipe; the workaround reconstruction passed without changing
locked versions or disabling the opam build sandbox. Evidence and limits are in
`docs/verification/fresh-switch-macos.json` and `docs/distribution.md`.

Cards and repository sidebar labels use shortest distinguishing path suffixes
computed across all current tasks, not just the filtered board. Duplicate basenames
include parent components; normalized collisions fall back to original strings.
`Repository_labels.ml/.mli` performs no path lookup or workspace operation. Exact
filter actions, task data, and full Activity paths remain unchanged. Unit and
sidebar PTY tests cover same-named repositories, filtering, and persisted identity.

Overflowing Activity panes display a visible wrapped-row range and above/below
arrows in their lower border. The same bounded window selects content and derives
the cue; it does not consume a tool-output row or change page size. Fitting panes
show no overflow indicator. Unit and streaming PTY checks cover initial/middle/
final ranges, retained output capacity, and unchanged snapshot behavior.

Workspace-form values use a grapheme-safe horizontal window around the editor
cursor, rather than always right-aligning long values. Home/End and cursor movement
expose the text being edited; unfocused values indicate clipping with an ellipsis.
Original paths/instructions remain in the form. Text/form unit and actual PTY
Home/End checks verify visible editing and no workspace side effects before submit.

The changes-view executable editor uses the same grapheme-safe cursor window as
workspace fields. Home/End reveals the beginning/end of long paths; editing does
not truncate the stored executable or start a refresh. Editing instructions stay
in the footer while the entire path row is available for cursor context. Pure
review-editor and actual PTY long-path/Home/End/paste tests verify behavior.

Activity run history displays newest attempts first under an explicit ordering
label. Captured model, harness, outcome, policy, and duration stay attached to each
record. The underlying task/snapshot retains chronological order; rendering never
sorts or rewrites saved history. Pure ordering/codec checks and the installed-agent
loopback UI test verify two attempts in the view after same-thread resume.

Expanded tool activity identifies the recorded source run with its captured harness,
model, simulation/live origin and execution policy. The scoped tool key, not the
selected next-run settings or raw payload item ID, determines that origin. Matching
uses the longest complete run-ID prefix; unmatched legacy keys say not recorded.
Raw/readable views retain this context. Unit and fake/installed-agent PTY checks
verify old tool attribution after a later attempt without changing stored events.

Workspace setup uses form-local status for guidance, validation, and creation
errors. Background task updates can change the application footer but cannot
erase the form's validation/error message. Submission and bounded creation failures
update both status channels; successful creation closes the form. Cancelling drops
the form-local status and leaves task data unchanged. Unit event/render tests,
real-jj failed-destination tests, and the PTY creation workflow cover this isolation.

Submitting an invalid workspace form focuses the first failing field in displayed
field order. Path errors identify the field; model/revision/instruction failures
also move directly to their editor. Ordinary validation remains side-effect-free,
and submitted values are not changed by recovery. Unit and Ctrl-S PTY checks
verify focused correction without a creation request or agent invocation.

Workspace validation feedback is scoped to its failing field. Changing that value
replaces the stale error with an explicit instruction to recheck all fields on
Ctrl-S; cursor movement, no-op deletion, and edits to other fields do not erase
it. Operational creation/storage reports remain visible while editing. The form
keeps feedback kinds private behind its existing status API. Unit and PTY checks
verify stale-error recovery, full resubmission validation, and report retention.

Footer editors for model, new-task, board/chat search, and queued reply show the
actual cursor through a grapheme-safe horizontal window. Short values retain key
hints; long values prioritize editable context over hints instead of clipping the
cursor. `Input_line.ml/.mli` sanitizes display only and changes no values. Unit
cursor/width/submission checks and PTY long-model/Home/End coverage verify behavior.

Expanded Activity reuses decoded readable/raw tool content while scoped item IDs
and immutable payloads are unchanged. `Tool_cache` retains only the rendered task's
current tools and prepares each representation lazily; collapsed groups request
only their latest item description, while other items and raw formatting remain deferred. Replaced payloads rebuild their entry, while removed items leave
the index. Current recorded source-run labels are not cached with the payload.
Unit decoder/lifecycle/render checks and full raw/readable PTY and installed-agent
resume coverage verify unchanged content and snapshot isolation.

Collapsed Activity shows the latest reducer-ordered tool summary and source-run
context without command/output details. Tool updates do not imply run completion;
the supplied decoder status remains authoritative, with explicit unknown fallback.
Unit and fake-process PTY checks verify current summary and hidden payload details.

Restart feedback reports the actual count of Working tasks recovered as interrupted
and the number of nonempty saved drafts retained. A board with no interrupted runs
says so instead of implying a recovery failure. `Restart_guidance.ml/.mli` reads
the pre-recovery snapshot; recovery still moves Working tasks to Needs you and
starts no process. Pure snapshot/controller and SQLite-restart PTY checks verify
accurate counts, retained editing text, and unchanged completion gates.

Single-line cursor windows reserve forward context when editing inside a long
value. Text after the cursor remains visible instead of placing the marker at
the far right with all upcoming characters hidden. Home and End retain prefix/
suffix behavior, short values retain their layout, and only whole graphemes enter
the display window. Shared text/form/review/footer unit and PTY model checks cover
this behavior; field values, submission, and execution remain unchanged.

Compact session headers put simulation/fake/replay/live policy before the app
identity so mode does not disappear behind a clipped title. Terminals shorter
than four rows omit footer controls rather than overwrite the mode header. Wide
headers stay unchanged. `Session_header.ml/.mli` generates the text; unit and PTY
resize checks cover simulation and live-policy visibility without starting runs.
Extremely narrow terminals can still truncate text; live authorization retains
its independent complete-disclosure geometry gate.

Reply-composer selection guidance follows execution mode. Live Codex tasks display
Codex-only controls instead of simulated harness cycling; imported Claude tasks
offer explicit H selection of Codex. Editing always describes Enter as queuing a
reply, including while Working. Pure mode/render/controller tests and the installed
agent loopback UI check verify these instructions without changing active-run
identity, captured settings, or per-run confirmation. Composer copy lives in the
pure `Composer_guidance.ml/.mli` module.

Composer guidance is fitted to its visible content width. When a model identifier
is long, editing/queue or live-harness controls precede an abbreviated selection
instead of being clipped behind it. Short values keep their existing selection
and hints; very narrow panes use compact instructions. Whole-grapheme clipping
changes display only. Unit/active-run and long-model PTY checks verify queue
visibility, unchanged captured run identity, and complete stored model values.

Transcript search banners prioritize match count and navigation when the query
exceeds the pane width. Short queries retain the existing layout; long-query
previews use a grapheme-safe ellipsis without changing the full editor or search
query. `Search_banner.ml/.mli` formats the text independently of matching and
input dispatch. Unit/compact-render and long-query PTY checks verify counts,
query retention, and no task/run creation from match navigation.


The primary board/detail split supports `Ctrl-W +/-` to grow/shrink the focused
region, with numeric counts before Ctrl-W; `Ctrl-W =` restores startup sizes.
Conversation and Activity resize the shared detail region. `Pane_layout` owns
abstract launch-local width/height preferences, scaled as proportions and clamped
against the current terminal. Compact/zoom layouts have no active adjustable
split and do not erase preferences. Taller stacked bodies reserve editor space;
small bodies retain the focus-sensitive fallback. No tasks, drafts, runs or
SQLite configuration are changed by layout commands. Modal/edit/paste input cannot
resize the underlying board. Storage errors remain visible. Pure tests verify
limits, orientation independence, restoration, counts and frame/hit bounds. The
dedicated replay PTY check verifies actual borders, history during new updates,
draft retention, resized composer clicks, compact/zoom restoration and reset.


Optional `[layout]` startup settings define `board_width_percent` and
`board_height_percent`, each an integer from 10 to 90. `Config` validates types,
range and unknown fields before opening storage. Typed abstract `Pane_layout`
defaults reach both simulation/replay/fake and explicit live UI startup. The
current layout still enforces its region minimums. Width refers to main content,
not the sidebar; height refers to the body. Settings discloses loaded defaults.
Ctrl-W `=` clears runtime overrides and returns to these launch defaults; changing
the TOML file requires a new launch. Neither runtime adjustment nor reset writes
a file. `--no-config` selects automatic sizes. Pure parser/layout/settings tests
and `scripts/smoke-layout-config.py` verify discovery, explicit/no-config paths,
CLI database override, reset, next-launch changes, startup inactivity, config byte
preservation, and rejected values without source disclosure or storage creation.


Overflowing chat shows a wrapped-row range on its lower border. Paused history
exposes a complete `[Latest / End]` hit target when the border is wide enough.
`Chat_position.ml/.mli` computes bounded copy and target geometry; no transcript
row is consumed. `Follow_chat` focuses Conversation and resets only its reading
anchor/distance, consuming any pending search seek while retaining query/matches.
It changes no task, draft or run. Independent Activity offsets are preserved.
The target disappears while following and is not exposed for a clipped label or
zero-capacity pane. Modal hit isolation and normal-input gating remain intact;
wheel input on the button is ignored. Pure rendering/input tests and the replay
PTY check verify target alignment, position during append, mouse follow, later
followed output, search retention and unchanged saved state.


Composer wrapping and cursor-following window computation live in the pure
`Composer_layout.ml/.mli` module. It accepts an optional abstract Text_edit editor
or a preview, sanitizes display text, preserves grapheme wrapping, and reports
visible wrapped-row range/overflow. The lower-border cue uses no editor capacity;
short drafts show no cue. Editing exposes the cursor window, while a saved preview
shows the tail. Ui retains mode-specific instructions and accepted-task read-only
policy. Layout/cursor moves do not change saved text, and submission queues the
complete draft. Pure Unicode/window/zero-capacity/UI checks and a temporary replay
SQLite PTY verify top/middle/bottom navigation, exact draft restart, retained edits,
and full queued submission without a new run.


Chat_layout sanitizes author labels before grapheme-safe word wrapping. Queued/sent
suffixes remain part of the complete displayed header, and each continuation uses
its author tone. Header anchor indices increase through zero; body indices still
start at one so an author replacement cannot renumber a paused body position.
Search seeks the first row of the message, including a multi-row header. Existing
message cache identity/invalidation remains intact. Pure tests cover full suffixes,
widths, controls, empty labels, queued tone, header index uniqueness, stable body
anchors during author growth, and stored-state isolation. A temporary SQLite PTY
checks long author tails, delivery labels, complete bodies, full-author search and
unchanged persisted messages/runs. No model or workspace operation is used.


Board selection rules live in the pure `Board_navigation.ml/.mli` module:
vertical/edge/page selection uses visible current-column order or compact/archive
list order. Horizontal column movement preserves the selected row ordinal, skips
empty columns, and clamps to the last card when the destination is shorter.
The next move uses the resulting ordinal, not a hidden preferred row. Visible
filters and current event-driven states define destinations; no stored card order
is changed. Controller applies only the selected identity and existing viewport
follow behavior. Pure tests and a temporary-board PTY check verify aligned cards,
shorter columns, empty-state skipping, counts, opening the selected chat, filters,
current-state movement, edge cases, bounded deltas, and saved task/run isolation.


`Board_summary.ml/.mli` lays out the view label, filtered task count and search
text within the actual main-content width. Long labels/queries are abbreviated
without changing exact repository/filter values; repository labels reuse the
sidebar's distinguishing suffix map. Counts take priority, including accepted
counts in Archive. The module returns label/search spans so Ui targets match
visible controls, including compact count-first fallback with no hidden label hit.
Extremely small widths show bounded count text with no absent control targets.
Pure tests and a temporary-board PTY check cover long paths/queries, compact
counts, Unicode-safe spans, visible search/archive clicks, exact query editing,
modal isolation and unchanged persisted task/run data.
