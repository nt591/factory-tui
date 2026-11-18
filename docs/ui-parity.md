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
disclose it. Run history shows requested policy. Fixture tests demonstrate a
reviewable file change, not installed Codex sandbox enforcement.

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
