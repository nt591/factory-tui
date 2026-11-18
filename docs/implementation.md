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


Review_notice produces sanitized, wrapped idle/loading/error/empty-result body rows.
Error diagnostics and explicit retry guidance are not clipped to one line. Patch
content remains in Diff_document/Diff_display with unwrapped line navigation and
horizontal scroll. Review tracks the current notice row count so End works without
a patch document; rendered capacity still drives page navigation. The changes view
updates these transient counts without running a command. Retry remains explicit,
command output remains withheld, and scrolling/reflow never changes task state.
Pure notices/viewport tests and a fake-jj temporary-workspace PTY check verify full
failure text, narrow paging and Home/End, no command on paste/open/page, only
explicit retries, unwrapped patch recovery, empty-result paging and unchanged
stored tasks/runs/drafts.


Shared terminal text sanitation lives in Terminal_text.ml/.mli instead of duplicated
loops in board summaries, transcript/composer layout, review notices/views, diff
display, live confirmation, footer input, search banners and workspace input.
Explicit line/multiline entry points retain the established malformed-UTF-8 and
C0/DEL/C1 behavior; only multiline retains LF. Controller.clean preserves its API.
Raw Text_edit UTF-8 repair remains separate because editor controls and line breaks
must not be normalized as a side effect of display. No dependency or persisted
schema changes are required. Tests compare the extracted policy against the prior
algorithm over fixed controls, malformed sequences, 2,000 deterministic byte
strings and printable BMP scalars; they check idempotence, Unicode validity,
printable grapheme preservation and unchanged editor state. Existing component
and terminal tests verify call-site integration and exact retained text.


Review_controls.ml/.mli supplies one responsive strip of complete ASCII labels
and exact hit spans. Wide label positions remain unchanged. Compact strips retain
Refresh/jj/Close, then file buttons when space allows; minimal strips prioritize
Close and expose no partial labels or targets. Path editing exposes only Close,
not a Refresh button. Review_view uses the strip for both image text and actions,
retaining body capacity and existing key validation. Pure exhaustive width tests
and the fake-jj review PTY check verify label/hit agreement, narrow Refresh/path/
Close clicks, path-editor Close, retained executable on reopen, no implicit command
and exactly three explicit fixture refreshes. Real-jj review/file tests remain.


Chat body anchors now use byte positions in sanitized UTF-8 text, not wrapped-row
indices. Text_layout.wrap_positions returns each grapheme-wrapped row's source
start; ordinary wrap uses the same implementation. Chat_layout keeps public row
indices for styling/tests but emits position-based body anchors, with the spacer
beyond the final byte. Header anchors remain non-positive row indices. Chat_viewport
keeps the precise body anchor during passive reflow instead of replacing it with
the earlier start of the containing row, preventing repeated resize drift. Explicit
scroll/search/Latest still choose a new position; hidden panes retain anchors and
terminal-end bounds can clamp them. This does not diff-map replaced text. Pure
Unicode/newline/source-offset/width-roundtrip tests and a real replay PTY verify
body containment across repeated widths, exact row restoration, later output,
height changes, unchanged saved data and explicit follow. Header reflow still uses
row-relative retention. No dependency or persistence schema changes are introduced.


Task_row.ml/.mli computes bounded compact/archive list previews. Short rows retain
familiar spacing; titles exceeding available cells receive a grapheme-safe ellipsis.
Long IDs cannot push the state out of the row: tighter fallback prioritizes state
and abbreviates ID/title. Ui still registers the exact task ID over the visible
row. No task text, order, selection semantics or saved state is rewritten. Pure
width/Unicode/control tests and the compact filtered-board PTY verify omission
markers, ID/state visibility, exact hit identity and full expanded instruction.


Controller input updates now validate normalized Text_edit text before changing
editor and backing draft/query/model/title together. Oversized values, including
UTF-8 repairs that increase byte length, are rejected atomically. Text_edit's
bounded insert rejection is disclosed with transient input_limit feedback instead
of silent success. The lower shortcut footer shows the warning while editing
without taking the edit cursor row; cursor-only movement retains it, and actual
valid text changes clear it. Existing storage errors are not overwritten. No
persisted schema change is required. Pure tests cover 64-KiB/256-byte limits,
Unicode whole-cluster rejection, normalization synchronization, recovery, visible
warning, exact retained submission and saved-state isolation. A temporary SQLite
PTY verifies over-limit paste, unchanged cursor/tail, cursor-only warning retention,
delete/insert recovery and exact saved draft without submission or a new run.


Workspace_form records the field whose insertion was rejected by the editor's
64-KiB bound. Its status prefixes field-local rejection feedback while retaining
existing validation/operational reports. Rejected insertions leave text/cursor
unchanged; cursor motion and edits to other fields preserve the warning. An actual
text edit in the affected field clears only the rejection marker. The abstract
form API is unchanged. Pure full-field/Unicode/render tests verify atomic rejection,
recovery, independent feedback and no task/creation request. Existing terminal
workspace creation and feedback checks continue to verify normal form integration;
full-limit rejection itself is verified by supplied-form rendering, not a PTY paste.


Ui frames separate full pane focus rectangles from interior scroll rectangles.
Conversation interiors exclude the search strip; Activity and compact-list interiors
exclude all four borders. Column wheel matching likewise uses the column interior,
not its heading/range border. Click focus still uses the full pane and explicit
Latest targets keep their priority. No page capacity, selection or persistence rule
changes. Pure perimeter/search-strip/positive-geometry tests and the replay history
PTY verify title-wheel inactivity, normal body scroll, paused-anchor retention and
Latest follow. Existing modal/sidebar scroll regions remain unchanged.


Live_confirmation caches one prepared disclosure by raw detail values and width.
Height selection and rendering share its sanitized wrapped rows and width check;
rendering slices only the visible array window. Height changes reset review coverage
without rewrapping unchanged text, while raw-detail/width changes rebuild preparation
and invalidate coverage at render. New-dialog reset drops both cache and coverage.
Authorization still checks current raw details and shown dimensions, not cache
presence. Pure cached/uncached equality and invalidation tests, complete-disclosure
checks and the fake-run PTY verify the safety boundary. A scoped local 60-KiB-title
measurement (20 height/render frames, including image construction) reported 0.77 ms
and 6.0 MB allocation with reuse versus 209.19 ms and 609.7 MB without reuse
with both the title and initial queued instruction displayed. This
excludes full Ui, terminal output and process work and is not a timing test gate.


Run_prompt.ml/.mli is the pure prompt selection/assembly boundary shared by live
preflight, confirmed execution and the confirmation disclosure. Queued messages
retain transcript order; submitted messages are selected by captured IDs, with
later replies excluded. Text assembly keeps exact bytes and uses two LF separators.
Combined byte count is computed without assembling a large prompt on redraw.
Live_confirmation distinguishes single-line metadata from LF-preserving instruction
blocks, shows queued count/bytes and each captured message ID/text, and compares
these raw details before authorization. Queued text/ID changes invalidate cache
and coverage; sent history is omitted. Unsent drafts are not included. Pure tests
verify exact Unicode/multiline assembly, capture selection and changed-message
refusal. The full-disclosure fake-run PTY now uses an old sent instruction plus two
new queued replies and checks the exact bytes received by the temporary harness.
No real model, credential or workspace access is introduced.

Live_runner's pre-spawn check validates the captured submitted prompt, not the
current aggregate queue. Replies posted after confirmation belong to later turns
and cannot make a valid earlier run fail its 1-MiB prompt bound. Captured messages
are selected by run IDs even after their queued flags are acknowledged. Public
next-run preflight still checks the whole current queue and rejects over-limit
instructions. A temporary live-run integration test adds 17 full later replies
before poll, verifies next-run rejection, then confirms the earlier fixture receives
only its original instruction and reaches Ready with later replies still queued.
Model/sandbox/checkpoint/workspace-slot validation remain unchanged.


Run_prompt.captured_text validates nonempty unique submitted IDs and exactly one
matching message per ID before assembling a live prompt. Missing/duplicate captures
produce a reported Failed/Exited outcome before checkpoint or spawn, retaining
queued instructions and a valid recovery snapshot. Raw submitted selection remains
a permissive query helper; execution uses the validated entry point. Model.send
rejects empty/overlong or existing reply IDs before appending, matching snapshot
identity constraints. Pure capture/insertion tests and a temporary live-runner
integration test verify refusal, no executable marker, failure-channel disclosure,
retained queued messages and recoverable encoding. Existing acknowledged capture,
future-queue isolation and exact prompt tests remain in force. No persistence schema
or supported valid-run behavior is changed.


Model.system allocates a distinct message ID when multiple notices share a task
revision or an existing user/imported message occupies the standard notice ID.
The first free suffix is selected against current message identities; normal
non-colliding IDs remain unchanged. Notices append without modifying earlier
records, queued instructions, task revision or lifecycle. Pure identity/codec/chat
checks and a temporary SQLite save/reopen check verify repeated diagnostics remain
readable and persist with exact unique IDs. This does not repair existing corrupt
snapshots or alter their validation rules.

Turn_started uses indexed captured-ID membership rather than scanning the submitted
list for every message. Only still-queued captured records are rebuilt; sent history
and later replies keep their immutable records. If no queued flags change, the
original transcript list is retained so Chat_layout can reuse its prepared document.
The event still increments revision normally. Snapshot captured-reference validation
also uses a message-ID index after its existing uniqueness checks. Pure 20,000-message
tests verify chronology, late replies, record/cache reuse and codec rejection of
missing/duplicate references. A scoped local three-pass comparison measured 1.47 ms
for indexed reductions versus 2355.72 ms for the previous membership scan; this
excludes storage, rendering and terminal output and is not a timing test gate.

Queue_summary.ml/.mli separates unacknowledged captured instructions from replies
held for the next turn. It uses active submitted-ID membership and queued flags;
sent history and unsent drafts are excluded. The composer title reports awaiting
ack/next counts or a normal idle queued count, bounded to its border width. No edit
rows or page capacity are consumed. Pure state/render checks and a replay PTY
verify draft exclusion, queued submission, turn acknowledgement and interruption
retention without automatic execution. The title does not imply progress or token
consumption, and accepted tasks do not advertise a runnable queue.

Literal_search.ml/.mli prepares a literal ASCII-case-folded needle and prefix
fallback table. Matching scans supplied bytes without lowercasing the complete
text or allocating candidate substrings, and repeated prefixes do not rescan prior
input. Chat_search prepares on query changes; board filtering prepares once per
visible-task computation. Controller.contains retains its supported argument order.
Empty-query, UTF-8 byte, non-regex and ASCII-only folding semantics remain unchanged.
Pure fixed/seeded-reference tests and repeated-prefix large-text cases verify exact
agreement with the previous algorithm. A scoped ten-search measurement reported
6.42 ms / 96 allocated bytes versus 50.25 ms / 818.3 MB for the prior scan on a
300,001-byte repeated-prefix text and 256-byte query. This excludes whole-UI work
and does not impose timing or allocation thresholds in tests.


scripts/check-ui.py consolidates the full terminal regression and 16 dedicated UI
fixtures into one sequential verification command. A single format/build/unit phase
precedes the PTYs, which all use the exact selected --binary without rebuilding.
New private output directories retain atomic reports, per-case logs and previews;
failures stop immediately and preserve later cases as not_run. Existing binary
mode skips build/unit gates explicitly. Pure Python tests cover planning, report
state and interrupt cleanup without running UI processes. The suite excludes
installed agents, provider calls, sandbox probes and toolchain reconstruction;
package/CLI checks remain separate. This improves repeatable verification rather
than claiming real-provider or release completeness.

Chat_search retains matches in chronological array order and indexes each matching
message ID to its result ordinal. Match counters and n/N movement no longer scan
the result list; changed immutable messages rebuild the array/index together.
Selection remains ID-based across reorder/streaming; removed selected matches
choose the first surviving result, and pending seeks retain their existing behavior.
Public interfaces and literal matching are unchanged. Pure 20,000-result traversal
checks cover wraparound, reorder, selected removal, index pruning and clear/single/
empty cases. Existing full UI/search fixtures verify visible counts and navigation.
No timing threshold or whole-app speed claim is introduced.

Process error-teardown verification now measures from readiness/event delivery,
not whole-run script startup. A reproduced failure had first delivery at 2.274373s
and cleanup lasting only 0.568ms, exposing a misattributed timing assertion. Tests
retain the one-second teardown bound, assert exact error outcomes/direct-child
reaping and include intentionally delayed readiness. Timeout, cancellation and
pipe-drain bounds are unchanged. Runtime Process code is byte-identical; startup
latency remains an unresolved operational input, not a diagnosed cleanup defect.

Task_updates.ml/.mli tracks distinct accepted message/tool/lifecycle update keys
per task and run in abstract transient state. Stream replacements share a key;
stale reducer-rejected events add nothing. Cards show a new-update count and compact
rows use [N new]. Markers follow exact task identity across state movement. Visible
conversation or Activity clears the selected task after layout, but board-only
layouts and modal-obscured details do not. Restoring snapshots resets markers rather
than treating historical content as new. This is a detail-view change indicator,
not proof a user read every message or tool. No marker is saved or alters task/run
state. Pure event/visibility/compact/modal tests and the board-history replay PTY
verify background chunks, automatic movement, selected-chat stability and badge
clear on inspecting the moved task. Existing fixture suite covers normal layouts.

Run output may replace only an existing nonqueued message with the captured harness
label and no submitted-instruction ownership. A collision with user/Factory/other
history preserves that record, emits a diagnostic and marks the run failed so later
completion cannot make it Ready. Model.start refuses a retained message/tool namespace
under the new run prefix, including overlapping nested run names. Model.send refuses
reply IDs under the active output prefix. Valid stream replacements are unchanged.
Pure reducer/start/send tests cover namespace refusal, queued/sent history protection,
sticky failure, strict snapshot roundtrip and readable channel diagnostics. This is
an in-process identity guard, not authentication of imported authors or a new stored
provenance schema; invalid stored snapshots are not repaired.

Id_allocation.ml/.mli supplies unused counter-based identities against retained
tasks, messages, tools, run records and active runs. Output namespace prefixes are
reserved so a stale run counter cannot claim existing stream history. Controller
next_id advances to the returned counter without renumbering retained records.
Normal noncolliding sequences stay unchanged; max-int counters wrap to nonnegative
candidates and still probe occupancy. The module uses a temporary membership index,
not persisted global allocation state. Pure stale-counter/prefix/limit tests and
a temporary SQLite restart/creation check verify exact retained records, unique
new tasks/replies, valid snapshot encoding and unchanged explicit-start rules.
This does not permit loading corrupt snapshots or guarantee cross-process global IDs.

Accepted run events do not replace a current Storage error footer with normal
start/completion/stop guidance. Task reduction, update markers and pending event
storage continue normally; the warning does not suppress lifecycle movement or
claim that unsaved state is durable. Pure event/render checks cover success,
failure and interruption under a persistence warning, plus ordinary guidance when
the warning is no longer present. This guard does not reconnect or retry storage.

Task_attention.ml/.mli derives a short Needs_you reason from the newest recorded
run status: awaiting input, failure, or interruption. Missing/inconsistent history
uses neutral Needs attention copy; other states have no attention reason. Card
metadata shares this pure view with compact previews, preserving update badges.
No error-text parsing, lifecycle change or stored-history mutation is introduced.
Pure lifecycle/record-order/render tests and the queue replay PTY verify input
request and interruption reasons on the board while queued replies stay intact.

Successful reply submission follows the current task's latest chat after appending
its queued message. This makes the submitted instruction visible rather than leaving
it below a paused-history viewport. Existing Follow_chat behavior retains the query,
consumes a pending seek and resets only chat anchoring/distance. Failed submissions
and unsent Escape keep the paused position; Activity memory and run state are not
changed. Pure input/render tests and the board-history replay PTY verify immediate
queued-reply visibility, search retention, failed/unsent anchors, independent Activity
position and no automatic execution.

Transient input_error makes submit-validation feedback visible below the footer
editor, independently of normal status. Reply/model failures retain text/cursor and
backing values; blank task creation now reports an instruction requirement. Actual
text changes or entering another input action clear the error; cursor movement does
not. Input-limit warnings retain precedence. Failure feedback does not overwrite a
current Storage error. Pure editor/render tests and a dedicated replay PTY verify
empty reply, invalid model, blank task and valid recovery. The fixture is part of
the one-build UI catalogue, now 17 cases. No new bindings or persistence fields.

Successful local reply/model/task submission clears input-specific errors without
replacing a current Storage error footer. The accepted local value still updates,
reply follow behavior remains intact, and no automatic retry or durability claim
is made. A shared private submission-success helper enforces that priority. Pure
input/render checks cover all three submission paths, visible warnings after editor
exit, retained local values and unchanged runs. Database failure injection is covered
by persistence tests; this increment tests controller warning priority only.

Acceptance_summary.ml/.mli discloses pending data retained when Ready becomes Done.
The accepted detail border shows retained queued-message count and nonempty draft
presence rather than advertising another turn; the status states retained work was
not sent. Existing immutable messages/drafts/run records are unchanged. Acceptance
continues to perform no merge/push/workspace deletion and exposes no execution or
composer controls afterward. Storage-error status retains precedence. Pure state/
codec/width tests and the board-history replay PTY verify acceptance with queued
follow-ups and a draft, visible retained markers and read-only controls. Restart
checks inspect the preserved archive rather than auto-resuming its pending work.

Controller.restore validates saved selection against retained tasks, not visible
board cards. A valid accepted or filtered-out conversation remains selected while
board filters stay independent. A missing ID falls back to the first visible task,
then a retained task if the filtered board is empty. Empty snapshots clear selection.
Existing selection resets initialize transient reading state and recovery status
remains accurate; no task/draft/history is rewritten or agent resumed. Pure active/
archive/filter/missing/empty tests and a repeated SQLite PTY restart verify accepted
chat and read-only drafts alongside an active board. The dedicated restart-selection
case joins the full fixture UI catalogue, now 17 cases.

Archive sidebar/toggle actions and normal-mode Escape retain a valid selected
conversation even when its card is outside the visible board. View changes do not
reset transcript search or remembered Chat/Activity positions. Missing identities
still fall back to visible cards; explicit board navigation selects a visible task.
Board search keeps its existing match-selection behavior. Pure controller tests
and the SQLite restart PTY cover active-chat/archive and accepted-chat/active-board
switches, mouse/keyboard input, retained read-only drafts and unchanged task history.
No new keybindings, persistence fields or execution behavior are added.

The composer PTY readiness condition includes its submit-guidance footer as well
as the draft window. This prevents assertion against an observed partial redraw;
its existing timeout and content checks remain unchanged.

The board summary identifies a selected conversation whose card is hidden by the
active/archive or repository/search filters. Its Show card control clears board
filters and selects the matching active or Archive view without reselecting the
task, resetting transcript search, sending a draft or starting a run. Expansion
closes so the card can be inspected. Full labels have exact mouse targets; narrow
headers use a short label and omit the button below its minimum usable width.
Controller/layout tests and temporary SQLite PTYs verify active and accepted
reveal, retained conversation data, input/modal isolation and no execution.

Shortcut_guidance.ml/.mli supplies a width-bounded bottom-row hint for the current
input mode, pane focus, expansion and transcript search. Reply editing shows INSERT,
Enter queues, draft-preserving Escape and newline controls. Model/task/search editors
state their own submit and Escape behavior. Normal chat hints describe scrolling
and Latest rather than card movement; Activity names readable/raw tools. Expanded
views say return, and the pending pane prefix names pane controls. Input-limit and
validation feedback keep precedence. No binding, state transition, persistence or
execution behavior changes. Pure layout/render tests and the input-feedback PTY
verify the mode changes and recovery from validation errors.

Input_controls.ml/.mli supplies editor-only Queue/Apply/Create/Finish, Close and
reply-Newline buttons. The action row no longer advertises inert normal-mode
controls during input. Clicks use the same Enter/Escape/Ctrl-L handler as keyboard
input, including validation, exact draft/newline retention and storage-warning
priority. Targets carry their input mode; different-mode stale frames and modal
input cannot execute them. Full labels alone receive hitboxes; small terminals
omit buttons that cannot fit. Normal card clicks and modal controls retain their
existing input isolation. Pure mouse/render tests and the input-feedback PTY
verify clicked submission, newline, model correction, task creation and search
closure without starting agents.

E2E performance now has an opt-in real-binary PTY/SQLite/replay benchmark in
scripts/bench-e2e.py. It measures input/event-to-visible-state latency without
fixed post-input waits, retains raw samples and checks exact SQLite history/replies
across launches. Replay measures transcript backlog, stream replacement and event-
driven Ready movement. CPU, sampled main-process RSS, terminal bytes and binary/
observer metadata are reported. Pure measurement-helper tests are part of check.sh.
See docs/performance.md for scope and reproducible commands. These measurements
establish a baseline, not a release latency target or native-GUI comparison.

E2E baseline comparison is available through scripts/compare-e2e.py. It validates
complete raw action/resource samples and their statistics before comparing reports.
Workload and measurement metadata must match; failed/interrupted or incompatible
reports are rejected without a speedup claim. Executable hashes can differ for a
candidate build. Human and JSON output disclose latency/resource deltas without
release gates or statistical significance claims. Nine pure validation/CLI tests
run in check.sh. See docs/performance.md for repeat/candidate comparison commands.

Startup configuration can be inspected with --check-config PATH and an optional
--database override. Config_preview.ml/.mli describes validated/resolved defaults
as JSON without opening SQLite, checking path existence, running jj or starting
agents. Conflicting execution/check modes are refused before resource access;
invalid source is not echoed. Pure preview tests and temporary CLI checks cover
relative/home paths, layout/workspace defaults, override, malformed/missing config,
mode isolation and unchanged invalid database/sentinel executable. Commands and
limits are in docs/configuration.md. This is setup validation, not provider or
workspace compatibility verification.

The fixture UI catalogue includes a full workflow case: a configured empty live
board creates an isolated temporary jj task, cancels one run confirmation, confirms
a fake workspace-write process, displays its answer/Ready state, explicitly reads
the real jj diff, retains an unsent draft on acceptance, and reopens the accepted
read-only conversation. Exact SQLite history, one invocation, captured prompt/policy,
unchanged source commit/content and retained workspace file are checked. This is a
fake executable, not a model or sandbox security check. The continuous case joins
the 18-case one-build UI suite and complements the broader terminal checks.

The continuous workflow includes a second confirmed turn before acceptance.
Next-run model editing and a queued follow-up start nothing by themselves. The
fake invocation must resume workflow-thread, receive only the new queued prompt,
and use the changed model in the same workspace. Both completed run records keep
unique identities; the first record/settings and original message prefix remain
byte-for-byte JSON-equivalent. Real jj review includes the second file. Accepted
restart preserves both turns and the unsent draft without a third invocation.
This strengthens fake-process workflow evidence, not installed-agent/provider
resume compatibility or sandbox enforcement.

The continuous workflow holds its second fake process behind a bounded release
file, queues a reply while Working, and inspects the durable checkpoint before
releasing completion. The late reply remains queued outside the active run's
submitted IDs; no third process starts and the captured prompt stays unchanged.
Acceptance and restart retain that exact queued reply plus the unsent draft in a
read-only conversation. This verifies the next-turn queue boundary end to end,
not live provider delivery or sandbox enforcement. No runtime behavior changes.

Gateway URL configuration supports an exported base_url_environment reference
alongside the existing literal base_url. Explicit --list-models --gateway PATH
reads only the referenced API key for a bounded authenticated catalogue request;
setup/checks resolve URL without requesting a model or reading the key. The
LiteLLM example names LITELLM_BASE_URL/LITELLM_API_KEY. Command.run_input supplies
bounded concurrent stdin/output over a SIGPIPE-safe socket without secret argv
or files. Curl disables user config, retains TLS verification and does not follow
redirects. Catalogue JSON is bounded/validated and failures withhold bodies and
stderr. Pure and loopback tests cover paths, auth, environment, limits and secret
redaction. Manual model entry remains; picker and real-provider compatibility are
not yet verified. See docs/gateway.md for discovery and read-only live testing.
