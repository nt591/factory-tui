# Implementation audit

This audit checks the requested software-factory workflow, not merely whether the
project compiles. The original objective remains a usable board whose cards move
from updates and open a task chat, with a restrained mock-inspired layout and
accessible help/settings. The staged native-app implementation remains the guide.

## Evidence checked

| Requirement | Current implementation and verification | Result |
| --- | --- | --- |
| Live first-run UX | New live databases begin empty with workspace/chat/run/review guidance; live n/W creates a workspace task. Existing snapshots are preserved; demo launches retain samples. Unit and PTY verify creation and restart without reseeding. | Implemented |
| Four self-updating columns | `Model.apply` derives Queued/Working/Needs you/Ready. Factory and PTY tests verify automatic movement from both timer and supervised process events; installed-agent PTY checks Working/Ready against SQLite and rendered card identity. Selected-run status updates offer review/retry; stale/background events cannot overwrite another task's status. | Implemented |
| Open and explore a task | Controller/Ui selection, split chat/activity, Enter/e and double-click task expansion, full-width focused Activity expansion; PTY verifies click, expansion, Escape, and selected identity after movement. | Implemented |
| Reading position | Transient task/message/row viewport preserves history position on append and earlier stream growth; End follows updates. Unit/PTY verify reading anchors and no saved mutations from layout. Chat image construction is bounded to the visible window; pure window tests and a scoped component measurement cover the optimization with a single-entry wrapped-transcript cache. Pure/UI tests cover message/task/width invalidation, stable anchors, and persistence isolation; streaming/search PTY checks cover full behavior. | Implemented; approximate wrapped-row retention on width reflow |
| Transcript search | Contextual / or S, literal matching by text/author, n/N cycling, stable message identity, visible counts/highlighting, no saved-draft mutations. Unchanged query/messages reuse match results; streaming/query invalidation and indexed highlight membership have pure/large-list checks. Unit and PTY checks. | Implemented |
| Readable mock-inspired layout | Bordered cards with wrapped titles and grapheme-safe ellipsis for omitted preview rows (full instructions verified in chat), repository sidebar with bounded click/scroll geometry and forty-repository PTY coverage, selected card tint, persistent transcript/composer, readable command/MCP/file activity and preserved raw payloads. Board overflow headers expose visible card/list ranges with pure/PTY paging checks. Activity wraps complete paths/titles/model IDs and displays the recorded review base; pure and PTY metadata checks verify no truncation or saved-state mutation. Rendered PTY captures were inspected at 120x36 and 180x50. | Implemented; user visual preference still matters |
| Help/settings | `?` opens tabbed modal, keyboard/mouse tabs, scrolling, current storage and next-run settings with mode-correct simulation/fake/replay/live guidance from a pure content module; live menu browsing is exercised by the installed-agent loopback PTY check. A reserved row shows visible range/overflow, and paging uses menu height. Unit/PTY tests verify compact paging, tab reset, modal isolation, and content. Contextual footer actions reflect task state/mode without replacing keyboard or live-confirmation validation; unit/PTY checks cover Working/Ready/Done controls. | Implemented |
| Vim navigation | hjkl, gg/G, counts, Ctrl-W pane selection, half/full-page keys, and mode-specific editing. Tests include actual terminal-decoded control bytes. Compact lists follow displayed task order across states, while four-column boards keep column semantics; resize/filter/state-change unit and compact PTY checks cover the distinction. | Implemented |
| Mouse and resizing | Card selection, expansion, buttons, modal hitboxes, wheel; non-modal wheel dispatch uses visible scroll regions so footer/composer/headings cannot move keyboard-focused panes (unit/PTY checks); exact frame/hit bounds from 1x1 through 180x50. Live authorization blocked below 64x13. Kanban column wheel positions are independent and route from actual frame geometry; unit/dedicated PTY checks cover clamping, selected-task movement and persistence isolation. Short-body layouts expose the focused chat/editor or Activity rather than hiding them; compact unit/PTY checks include drafting and focus cycling. PTY checks actual escape/input sequences. | Implemented |
| Compose and queue instructions | Abstract Text_edit cursor state, multiline draft, Ctrl-L/Alt-Enter newline, safe bracketed paste, captured submitted messages acknowledged only at turn start. Drafts/queued replies survive persistence. | Implemented; grapheme-aware movement/deletion and wrapping; terminal-dependent emoji width and oversized-cluster cropping |
| Settings/history | Next-run model/harness settings do not rewrite captured run records. Activity shows active run age/frozen recorded duration with timestamp edge-case and PTY coverage; age includes pre-spawn waits and does not imply progress. Requested read/write policy is captured per run and legacy snapshots default read-only. Live Codex-only preflight and active model-capture tests. Normal/menu H cannot switch live Codex to unsupported Claude; explicit recovery of imported Claude and accepted editor refusal have unit and loopback shortcut coverage. | Implemented; Claude is simulation only |
| SQLite and restart | Versioned snapshots, separate run rows, ordered events, transaction rollback, exclusive ownership, coalesced bounded writes, shutdown flush, Working recovery. Storage and PTY save/reopen cover real temporary databases. | Implemented |
| Low-effort configuration | Optional default/XDG TOML, explicit file, CLI override/no-config, capped reads and rejected unknown fields. Argument-free startup discovery and optional editable workspace defaults with no creation on launch are covered by the PTY smoke. | Implemented |
| Installed sandbox cases | Opt-in loopback fixed-tool sentinel probe on Codex 0.166.0/macOS: read-only deny, task/temp writes allow, ordinary sibling deny, never-escalation refuse. No real credentials or model. | Exact cases verified; not a security audit |
| Stop/retry ownership | Live runner serializes task/canonical workspace ownership through checkpoint, cancellation, drain and join; independent directories run concurrently. Temporary alias/checkpoint tests detect overlap and waiting-run shutdown. | Implemented within one runner; not global process containment |
| Supervision | Bounded stdout/stderr/lines/events, monotonic timeout, cancellation/process-group cleanup, checkpoint-before-spawn, bounded queue/separate outcome. Fake-process tests plus confirmed live-mode PTY path. | Implemented within documented process-group limits |
| Codex/provider/resume | Pure preview, explicit headless execution and live UI; exact thread ownership/mismatch checks. Installed Codex 0.166.0 headless and confirmed TUI execution/resume pass isolated loopback Responses fixtures. The TUI path edits a file, reviews its actual patch, accepts, and reopens archived chat. | Implemented; real provider behavior not verified |
| Isolated workspaces | Explicit W form, existing jj source, new outside-source task workspace, exact base, no automatic conversion/fetch, disclosure of source snapshot. Temporary jj tests and PTY create/save/reopen. | Implemented |
| Real changes review | Task-bound abstract background diff job, explicit refresh, actual patch/empty/loading/error states, vertical/horizontal scrolling and return to chat. PTY reads real added files in a temporary workspace; file indexing, previous/next keyboard and mouse navigation, short-final-file alignment, and viewport-sized paging have pure/real-jj/PTY coverage. Sanitized display/width caching eliminates full-patch scans on redraw; pure/real-jj checks cover refresh/resize lifecycle, and a scoped synthetic measurement is documented. | Implemented |
| Acceptance is separate | Only Ready can be accepted; no merge/push/delete in acceptance. Controller/review tests verify retained read-only chat and blocked background shortcuts; installed-agent PTY verifies acceptance preserves source commit/workspace base/file and archived-chat restart. | Implemented |
| Modularity and formatting | Every library `.ml` has a matching `.mli`. Subsystem folders and Demo namespace; abstract resource handles and native scoped let-bindings. `scripts/format.sh --check` and Dune compilation enforce formatting/interfaces. | Implemented; one Dune library and exposed controller state remain |
| Editor | Project-switch LSP/Conform configuration, pinned editor tools, `.ml`/`.mli` attachment and formatting checks in actual Neovim config. | Verified locally |
| Local distribution | Standalone binary, explicit refusal-to-overwrite install, repeatable archive metadata, transitive opam lock, temporary package/install tests. Extracted binary runs with opam absent from PATH and passes the full PTY smoke. | Implemented for local macOS arm64 |
| Measured footprint | `scripts/measure.py`, fresh build directory and version-launch median; system-only dylib links inspected. No matched GUI measurement exists. | Local measurements only |
| Step-by-step jj commits | `jj log`, local main bookmarks, format/build/tests before increments; no remote/push. | Followed |
| OxCaml | Explicitly deferred at user request; failed old bootstrap and interrupted newer attempt are distinguished in `docs/oxcaml.md`. | Non-blocking TODO |

## Remaining work, not claimed complete

1. **Broader sandbox validation and approvals.** The installed Codex 0.166.0
   loopback sentinel probe now exercises fixed shell commands on macOS: read-only
   write denial, workspace + runtime TMPDIR write access, ordinary sibling denial,
   and explicit never-approval escalation refusal. Its corrected TMPDIR layout
   also exposed a task-only disclosure error; the UI/docs now include temporary
   directories. This finite probe does not prove all auxiliary/protected paths,
   symlink variants, network restrictions, or containment. Interactive approval/
   steering still needs a suitable harness protocol rather than exec JSONL.
2. **Real provider compatibility.** Loopback fixtures prove protocol plumbing,
   not a model's tools, reasoning, credentials, billing, or provider behavior.
   Real gateway checks need user-selected configuration and explicit approval;
   no real key or model request is needed for normal tests.
3. **Fresh-machine release validation.** The lock was generated and checked
   against the existing switch; a completely new switch reconstruction, cross-OS
   support, signing, and notarization are not verified. The local archive is not
   represented as a public production release.
4. **Additional usability refinements.** Configurable panes, terminal-dependent
   emoji rendering and fully abstract controller view state remain
   candidates. They do not justify claiming current rendering or interaction
   quality from unit tests alone; keep inspecting PTY captures.
5. **Fresh executable startup limits.** The unreliable one-second fresh shell
   script fixture is replaced with a native child fixture using the same public
   command API and unchanged deadlines. Three parallel suites and package checks
   pass. A separate launch probe supports fresh script startup as a confounding
   factor, but its precise OS cause remains unproven. See `docs/testing.md`.
   Production command timeouts remain reported errors; no silent retries or
   increased runtime limits are introduced.
6. **Operational limits.** Group cancellation does not contain descendants that
   deliberately escape their group. Abrupt application termination can lose
   writes since the last checkpoint and leave an unassociated created workspace.
   Conversation/tool content is sensitive. These limits remain documented.

The active goal is not marked complete by this audit. The UI and local execution
foundation are verified, but the full software-factory implementation still has
broader security and provider/release boundaries that must not be replaced with
narrow fixture success claims.

## Repeat the verification

```sh
./scripts/format.sh --check
./scripts/check.sh
python3 scripts/smoke-invocation.py
python3 scripts/smoke-execution.py
uv run --with pyte --with pillow python scripts/smoke-terminal.py \
  --preview /tmp/factory-tui-audit.png
python3 scripts/smoke-package.py
```

Optional installed-agent loopback integration (dummy credentials only):

```sh
python3 scripts/smoke-codex-local.py --codex /absolute/path/to/codex
python3 scripts/smoke-codex-sandbox.py --codex /absolute/path/to/codex
uv run --with pyte python scripts/smoke-codex-ui.py --codex /absolute/path/to/codex
```

For a packaged binary pass `--binary` to the PTY smoke. Package/installation
checks use temporary destinations. Do not install into the user's PATH, fetch,
push, or contact a real model as a side effect of this audit.
