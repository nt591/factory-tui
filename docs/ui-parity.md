# Terminal UI target

Use the native Factory mock's structure, not its exact colors or buttons:
repository navigation, four active columns, bounded cards, and a persistent chat
for the selected task. Keep bottom-style pane focus, expansion, and Vim navigation.

## Implemented and verified

- Wide terminals show a repository sidebar. `R` cycles repository filters at any
  size; `b` returns to the active board. Filters do not close the selected chat.
- Four active columns contain bordered task cards with wrapped titles, repository,
  message count, and queued delivery count. Accepted tasks live in Archive.
- Card selection opens its chat and activity. Double-click or Enter/e expands
  task detail; Escape returns. Automatic state movement retains task selection.
- Accepted tasks retain their open chat and are read-only; acceptance does not
  merge, push, or delete a workspace.
- A visible reply composer shows the next-run harness/model and queued delivery.
  Task drafts persist when configured SQLite storage is enabled.
- Tool output is collapsed by default and expanded with `t`; readable summaries
  retain supplied status, exit codes, commands, results, and file operations. `T`
  shows preserved raw payloads. Recent tool activity precedes historical runs
  so it is not buried behind the run ledger. Run history retains
  original settings and outcomes.
- `?` opens Help and Settings tabs. Tab/h/l switches tabs; j/k and the mouse wheel
  scroll. Tab labels are clickable. The overlay blocks the underlying controls.
- Settings shows simulation/replay mode, memory or selected SQLite storage, and
  the selected task's next-run settings. `m` opens model editing and `H` cycles
  the simulated harness. Database changes require restarting with TOML/CLI config.
- Narrow layouts use a list and expandable detail; medium layouts stack board
  and chat; wide layouts use a sidebar and side-by-side board/detail.

## Evidence

Reducer/controller tests cover repository filtering, retained chat selection,
accepted read-only state, tool expansion, menu isolation, settings content, and
mouse hitboxes. Frame tests cover 1x1 through 180x50 terminals, including menus.
The PTY smoke covers cards moving to Ready, queued replies, click/zoom, Vim keys,
Help/Settings, repository filtering, wide/narrow resize, and TOML save/reopen.

Rendered PTY captures at 120x36 and 180x50 were inspected on November 17, 2026.
The board, expanded chat, and Settings overlay are separate preview artifacts
from `scripts/smoke-terminal.py --preview /tmp/factory-tui.png`.

## Remaining work

Confirmed `--live-ui` execution is implemented for workspace tasks. Fake-process
UI checks cover startup inactivity, per-run confirmation, small-screen blocking,
streaming, and cancellation; real gateway behavior is not verified.
The `v` changes pane now shows real workspace patches with explicit refresh, empty/error/loading
states, vertical/horizontal scrolling, and return to chat.
The `W` creation form creates isolated Queued tasks with persistent workspace identity and explicit source-snapshot disclosure. Simulation currently uses
fixture data only. Do not present a simulated tool result as real verification.
The composer supports multiline drafts (Ctrl-L or Alt-Enter), extended-grapheme
cursor movement, insertion/deletion, and newline-preserving paste. Further refinements may include
configurable layouts and improved terminal-dependent emoji rendering. Chat search now uses
literal matching, visible message counts, and n/N navigation anchored to IDs.
Changes review is implemented as a full-screen pane rather than a drawer.

Live workspace-write must be explicit on launch; the banner and confirmation
disclose it. Run history shows requested policy. Fixture tests demonstrate a reviewable file change. An opt-in installed-Codex
sentinel probe additionally checks exact read-only/write/escalation cases locally;
it is not a security audit. Write confirmations include temporary-directory
access, which is permitted by the harness policy alongside workspace writes.

While reading earlier chat, appended output and growth in previous streamed
messages preserve a task/message/row anchor. End explicitly resumes following.
The paused-history label appears in the chat header. Height changes retain the
anchor when it fits; column reflow preserves the approximate wrapped row within
the message. Viewport state is transient and never rewrites saved chats/drafts.

New live databases show an empty real board with an actionable workspace/chat/run/
review walkthrough rather than demo seed tasks. Live `n` opens workspace creation;
demo `n` remains a simulated task. Existing saved tasks are preserved. Empty
archives explain acceptance; filtered boards expose an explicit clear-filters
button that keeps the selected chat available. Unit/frame tests and the PTY smoke
verify first creation, confirmation cancellation, and restart without reseeding.

Activity supports full-width expansion: focus the pane and press e. Tool summaries,
raw payloads, run history, and scroll controls remain available. Returning with e
restores the preceding board/task layout; Escape returns with Activity focus.
Tab/compose/search restore a visible conversation rather than editing a hidden
pane. Expansion is transient and changes no task, draft, or execution state.
The PTY smoke verifies complete tool-output lines and return to the task chat.

A confirmed live retry can wait for a previous workspace process to finish
cleanup. Activity exposes that waiting state without moving away from the task
chat. Stop and shutdown interrupt waiting requests; no implicit process starts
as the application closes. Coordination applies within one live runner.

Changes review has file navigation: `]`/`[` and clickable Prev/Next file buttons
jump between real Git-format file headers. The footer shows file number/count
and the supplied path; jumps reset horizontal scrolling and put a short final
file at the top instead of hiding its header behind the viewport clamp. Page
keys use the actual visible patch height. The immutable `Diff_document` index
lives beside review input/rendering with an explicit interface. Pure parser tests,
real-jj review tests, and PTY keyboard/mouse checks cover multi-file navigation.
No task, draft, database, or workspace is changed by navigation.

Short terminal bodies show the focused pane rather than hiding the editor behind
the board. `i` and chat search expose the conversation; Tab/Ctrl-W can select
Activity or return to the board. This does not enable zoom or alter saved drafts.
`Pane_layout` chooses the split without a controller dependency. Compact input,
focus cycling, and frame/hit bounds are covered by unit tests and a 60x20 PTY
compose/focus sequence. Larger stacked/side-by-side layouts keep their thresholds.

Activity metadata wraps at the pane width instead of clipping task titles,
repository/workspace paths, and next-model IDs. Workspace-backed tasks also show
the exact base used by changes review. Focus Activity and press `e` for full-width
inspection; scroll keys reach metadata, tools, and captured run history. Logical
row construction lives in pure `Activity_content.ml/.mli`, separate from Notty
rendering and the controller. Tests verify complete content before/after wrapping,
raw/readable tools, captured policies, and unchanged persisted state. The PTY
workspace workflow reconstructs and checks the full recorded paths and base from
the expanded pane.

The action bar reflects the selected task: Working offers Stop, Ready offers
Accept, and accepted tasks omit run/edit controls. Start requires queued input;
live mode labels it `s confirm`, requires workspace-backed Codex, and omits
unsupported harness cycling. Replay omits process controls; workspace creation
requires configured storage. Inspection/review/acceptance precede secondary
settings so they fit compact screens. Shortcuts remain available and pass the
same controller/preflight checks; the bar is guidance, not authorization. Pure
`Action_bar.ml/.mli` construction performs no filesystem or process operations.
Unit and PTY checks cover visible controls and unchanged execution gates.

Wrapping keeps extended grapheme clusters together across row boundaries: accents,
flags, skin-tone modifiers, joined emoji, and keycaps are not split into separate
rows. `Text_layout.ml/.mli` owns terminal-cell and word wrapping; the UI sanitizes
text first. A grapheme wider than the pane is kept intact in the logical row and
cropped by the final image rather than divided. This does not solve differences
in terminal/font emoji width. Unit tests compare grapheme sequences and retained
bytes, and the compact PTY composer checks a boundary-adjacent skin-tone emoji.
Stored text and drafts are not rewritten by rendering.

Help/Settings includes a fixed position row with the visible range/total and an
explicit more-above/more-below cue. Page keys use the visible menu height, and
switching tabs resets to the top. The cue occupies reserved space rather than
covering content. `Menu_window.ml/.mli` computes row selection and clamping;
keyboard/mouse dispatch stays in the controller. Unit and compact-terminal PTY
checks cover paging, bottom instructions, tab reset, frame bounds, and background
control isolation. Saved tasks and drafts do not change while browsing the menu.
