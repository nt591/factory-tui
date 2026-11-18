# Implementation audit

This audit checks the requested software-factory workflow, not merely whether the
project compiles. The original objective remains a usable board whose cards move
from updates and open a task chat, with a restrained mock-inspired layout and
accessible help/settings. The staged native-app implementation remains the guide.

## Evidence checked

| Requirement | Current implementation and verification | Result |
| --- | --- | --- |
| Live first-run UX | New live databases begin empty with workspace/chat/run/review guidance; live n/W creates a workspace task. Existing snapshots are preserved; demo launches retain samples. Unit and PTY verify creation and restart without reseeding. | Implemented |
| Four self-updating columns | Status counters match repository/search/archive-filtered cards (unit and repository PTY coverage); a width-aware summary keeps these counts visible beside long filters, with pure and compact temporary-board PTY checks for actual label/search click spans and unchanged exact identities; selected chat remains independent of board filters. `Model.apply` derives Queued/Working/Needs you/Ready. Factory and PTY tests verify automatic movement from both timer and supervised process events; installed-agent PTY checks Working/Ready against SQLite and rendered card identity. Selected-run status updates offer review/retry; stale/background events cannot overwrite another task's status. | Implemented |
| Open and explore a task | Controller/Ui selection, split chat/activity, Enter/e and double-click task expansion, full-width focused Activity expansion; selection refreshes task-ID/next-step footer guidance without hiding storage errors or starting runs. Pure/PTY checks cover the guidance; PTY verifies click, expansion, Escape, and selected identity after movement. | Implemented |
| Reading position | Transient task/message/body-byte viewport preserves history position on append and earlier stream growth; separate chat/Activity offsets prevent mouse focus switches from mixing history distance and tool rows; unfocused Activity retains its visible window and creates only visible-row images; board mouse focus also preserves paused chat history during incoming output, with unit and dedicated replay PTY tests; End or the bounded Latest border button follows updates; pure and replay PTY checks cover row ranges, click alignment, independent Activity offsets, search retention, wheel isolation and later followed output. Unit/PTY verify reading anchors and no saved mutations from layout. Chat image construction is bounded to the visible window; pure window tests and a scoped component measurement cover the optimization with a single-entry wrapped-transcript cache that reuses unchanged message blocks during streaming. Pure/UI tests cover message/task/width invalidation, stable anchors, and persistence isolation; streaming/search PTY checks cover full behavior. | Implemented; body-byte retention across width reflow; header row retention and bounded near-end clamping |
| Transcript search | Full wrapped author labels retain their suffix/delivery state with pure and stored-message PTY verification; full-author search leaves saved data unchanged. Contextual / or S, literal matching by text/author, n/N cycling, stable message identity, visible counts/highlighting even with long queries (pure width/query-retention and PTY checks), no saved-draft mutations. Unchanged query/messages reuse match results; streaming/query invalidation and indexed highlight membership have pure/large-list checks. Unit and PTY checks. | Implemented |
| Readable mock-inspired layout | Compact list rows disclose title/ID omission with state-aware previews (pure width/Unicode and compact PTY checks), and bordered cards with wrapped titles and grapheme-safe ellipsis for omitted preview rows (full instructions verified in chat), short distinguishing repository path labels (full filter/workspace identity preserved; pure/sidebar PTY checks), repository sidebar with bounded click/scroll geometry and forty-repository PTY coverage, selected card tint, persistent transcript/composer, readable command/MCP/file activity and preserved raw payloads, latest supplied summaries/source context while collapsed (unit/fake PTY checks), with a lazy selected-task decode cache (unit equivalence/reuse/invalidation tests, no saved-state changes). Expanded tools identify recorded source-run settings/origin/policy, with explicit unrecorded legacy fallback (unit and fake/installed-agent PTY checks). Activity overflow borders show visible wrapped-row ranges/directions without reducing content capacity (unit/streaming PTY checks). Board overflow headers expose visible card/list ranges with pure/PTY paging checks. Activity wraps complete paths/titles/model IDs and displays the recorded review base; pure and PTY metadata checks verify no truncation or saved-state mutation. Rendered PTY captures were inspected at 120x36 and 180x50. | Implemented; user visual preference still matters |
| Help/settings | `?` opens tabbed modal, keyboard/mouse tabs, scrolling, current storage and next-run settings with mode-correct simulation/fake/replay/live guidance from a pure content module; live menu browsing is exercised by the installed-agent loopback PTY check. A reserved row shows visible range/overflow, and paging uses menu height. Unit/PTY tests verify compact paging, tab reset, modal isolation, and content. Contextual footer actions reflect task state/mode without replacing keyboard or live-confirmation validation; unit/PTY checks cover Working/Ready/Done controls. | Implemented |
| Vim navigation | hjkl, gg/G, counts, Ctrl-W pane selection, half/full-page keys, and mode-specific editing, including cursor-following footer inputs for long models/titles/searches and replies, with forward context for middle edits shared by workspace and review path fields (pure width/submission and PTY cursor/Home/End checks). Tests include actual terminal-decoded control bytes. Compact lists follow displayed task order across states, while four-column boards keep column semantics with row-aligned horizontal moves, empty-column skipping and short-destination clamping (pure rules and temporary-board PTY checks); resize/filter/state-change unit and compact PTY checks cover the distinction. | Implemented |
| Mouse and resizing | Card selection, expansion, buttons, modal hitboxes, wheel; non-modal wheel dispatch uses distinct interior scroll regions (perimeter/search-strip unit checks and title-wheel replay PTY checks) so footer/composer/headings cannot move keyboard-focused panes; modal content regions also exclude tabs, status, titles, path fields, buttons and background (unit/PTY checks); exact frame/hit bounds from 1x1 through 180x50. Compact mode-first headers and tiny-height rendering preserve execution badges (all-mode unit/resize PTY checks). Live authorization is blocked below 64x13 and until every wrapped disclosure row has been shown; gaps skipped by paging cannot authorize. Unit/PTY checks cover full identities, dynamic button alignment, Unicode sanitation, and non-authorizing clipped layouts. Kanban column wheel positions are independent and route from actual frame geometry; unit/dedicated PTY checks cover clamping, selected-task movement and persistence isolation. Short-body layouts expose the focused chat/editor or Activity rather than hiding them; compact unit/PTY checks include drafting and focus cycling. PTY checks actual escape/input sequences. | Implemented |
| Compose and queue instructions | Abstract Text_edit cursor state, multiline draft, Ctrl-L/Alt-Enter newline, safe bracketed paste, captured submitted messages acknowledged only at turn start. Drafts/queued replies survive persistence. Pure Composer_layout and long-draft replay/SQLite PTY checks verify cursor-following wrapped-row ranges, top/middle/bottom cues without reduced edit capacity, exact Unicode edits across restart and complete queued submission. Composer selection copy is mode/width-aware and explicitly labels Enter as queuing; long model IDs do not hide queue or live-harness instructions (bounded-content and long-model PTY checks); unit/controller and installed-agent PTY checks cover live controls and unchanged active-run identity. | Implemented; grapheme-aware movement/deletion and wrapping; terminal-dependent emoji width and oversized-cluster cropping |
| Settings/history | Next-run model/harness settings do not rewrite captured run records. Activity shows newest-first attempts without reversing stored chronology (unit/codec and installed-agent resume UI checks), plus active run age/frozen recorded duration with timestamp edge-case and PTY coverage; age includes pre-spawn waits and does not imply progress. Requested read/write policy is captured per run and legacy snapshots default read-only. Live Codex-only preflight and active model-capture tests. Normal/menu H cannot switch live Codex to unsupported Claude; explicit recovery of imported Claude and accepted editor refusal have unit and loopback shortcut coverage. | Implemented; Claude is simulation only |
| SQLite and restart | Versioned snapshots, separate run rows, ordered events, transaction rollback, exclusive ownership, coalesced bounded writes, shutdown flush, Working recovery. Storage and PTY save/reopen cover real temporary databases. Pure pre-recovery summaries and restart PTY checks report actual interrupted-task and retained-draft counts, without claiming every reopen is interrupted. | Implemented |
| Low-effort configuration | Optional default/XDG TOML, explicit file, CLI override/no-config, capped reads and rejected unknown fields. Argument-free startup discovery and optional editable workspace defaults with no creation on launch are covered by the PTY smoke. Optional typed layout percentages have parser/layout tests and discovered/explicit/no-config PTY coverage; reset uses loaded defaults without writing config. | Implemented |
| Installed sandbox cases | Opt-in loopback fixed-tool sentinel probe on Codex 0.166.0/macOS: read-only deny, task/temp writes allow, ordinary sibling deny, never-escalation refuse. No real credentials or model. | Exact cases verified; not a security audit |
| Stop/retry ownership | Live runner serializes task/canonical workspace ownership through checkpoint, cancellation, drain and join; independent directories run concurrently. Temporary alias/checkpoint tests detect overlap and waiting-run shutdown. | Implemented within one runner; not global process containment |
| Supervision | Bounded stdout/stderr/lines/events, monotonic timeout, cancellation/process-group cleanup, checkpoint-before-spawn, bounded queue/separate outcome. Fake-process tests plus confirmed live-mode PTY path. | Implemented within documented process-group limits |
| Codex/provider/resume | Pure preview, explicit headless execution and live UI; exact thread ownership/mismatch checks. Installed Codex 0.166.0 headless and confirmed TUI execution/resume pass isolated loopback Responses fixtures. The TUI path edits a file, reviews its actual patch, accepts, and reopens archived chat. | Implemented; real provider behavior not verified |
| Isolated workspaces | Explicit W form, existing jj source, new outside-source task workspace, exact base, no automatic conversion/fetch, disclosure of source snapshot. Temporary jj tests and PTY create/save/reopen. Invalid submission focuses the first failing field without changing values; actual edits clear only that field’s stale validation feedback, while operational reports remain visible (unit and Ctrl-S/edit PTY checks). Form-local status prevents background task updates from erasing validation/creation errors (pure event, real-jj failure, and PTY setup tests). Long form values use cursor-following horizontal windows with grapheme-safe text/render and PTY Home/End coverage. | Implemented |
| Real changes review | Task-bound abstract background diff job, explicit refresh, actual patch/empty/loading/error states, vertical/horizontal scrolling and return to chat. PTY reads real added files in a temporary workspace; file indexing, previous/next keyboard and mouse navigation, short-final-file alignment, and viewport-sized Page/Ctrl-U/D/B/F paging with editor/modifier isolation and cursor-following long executable fields have pure/real-jj/PTY coverage. Sanitized display/width caching eliminates full-patch scans on redraw; pure/real-jj checks cover refresh/resize lifecycle, and a scoped synthetic measurement is documented. | Implemented |
| Acceptance is separate | Only Ready can be accepted; no merge/push/delete in acceptance. Controller/review tests verify retained read-only chat and blocked background shortcuts; installed-agent PTY verifies acceptance preserves source commit/workspace base/file and archived-chat restart. | Implemented |
| Modularity and formatting | Every library `.ml` has a matching `.mli`. Subsystem folders and Demo namespace; abstract resource handles and native scoped let-bindings. `scripts/format.sh --check` and Dune compilation enforce formatting/interfaces. | Implemented; one Dune library and exposed controller state remain |
| Editor | Project-switch LSP/Conform configuration, pinned editor tools, `.ml`/`.mli` attachment and formatting checks in actual Neovim config. | Verified locally |
| Fresh locked compiler build | New temporary opam root/empty switch; all 52 locked package versions checked, application build and parallel tests passed, full PTY smoke used fresh binary. Unmodified macOS bootstrap crashed ocamlbuild at caml_unix_pipe; explicit recorded compiler overrides passed. Evidence: docs/verification/fresh-switch-macos.json. | Verified on this host; not clean-OS/editor/cross-OS validation |
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
3. **Fresh-machine release validation.** A new temporary opam root, compiler and
   all 52 locked application packages were reconstructed and checked on this Mac.
   Its application build, parallel unit tests, and full fresh-binary PTY smoke
   passed with an explicit SDK/runtime configure workaround. The unmodified
   bootstrap failed before application compilation. This does not validate a new
   operating system, editor tools, cross-OS support, signing or notarization. The
   local archive is not represented as a public production release.
4. **Additional usability refinements.** Terminal-dependent
   emoji rendering and fully abstract controller view state remain
   candidates. They do not justify claiming current rendering or interaction
   quality from unit tests alone; keep inspecting PTY captures.
5. **Fresh executable startup limits.** The unreliable one-second fresh shell
   script fixture is replaced with a native child fixture using the same public
   command API and unchanged deadlines. Three parallel suites and package checks
   pass. A separate launch probe supports fresh script startup as a confounding
   factor, but its precise OS cause remains unproven. See `docs/testing.md`.
   Native fixtures later also reported intermittent timeouts, including repeated
   output launch 19. Case-specific test diagnostics now identify operations and
   concurrent workers. Direct/native and instrumented parallel probes did not
   reproduce the unexpected case; its cause remains unresolved. Production command
   timeouts remain reported errors; no silent retries or increased runtime limits
   are introduced.
6. **Operational limits.** Group cancellation does not contain descendants that
   deliberately escape their group. Abrupt application termination can lose
   writes since the last checkpoint and leave an unassociated created workspace.
   Conversation/tool content is sensitive. These limits remain documented.

Terminal_text centralizes the existing UI sanitation policy behind explicit line
and multiline entry points. Pure corpus tests verify equivalence and editor-state
isolation; component and terminal checks cover integration. Raw Text_edit repair
remains separate, and no persistence/dependency change is introduced.

Review_controls produces complete responsive labels and exact hit spans. Pure
width sweeps and fake-jj compact mouse checks cover path-editor Close, narrow
Refresh/jj/Close and retained command inactivity during closing/reflow.

Review failure notices also wrap and page without a patch document. Pure and
fake-jj PTY checks verify complete retry guidance, output privacy, no implicit
retry during reading/reflow, explicit patch recovery and saved-state isolation.

Precise chat body anchors survive passive width reflow without accumulated row
start drift. Pure and replay PTY checks verify containment, exact width-roundtrip
restoration and later streaming. Header anchors remain row-relative and end bounds
can clamp. An isolated rerun passed an intermittent process teardown timing failure;
its cause is not diagnosed and no timeout was relaxed.

Input-limit rejection now preserves normalized editor/backing-value synchronization
and exposes transient feedback while editing. Pure and full-draft SQLite PTY
checks verify rejection, recovery and exact retained text. One process cleanup
timing assertion failed in an initial parallel run; the rerun passed unchanged,
which does not diagnose its cause.

Run confirmations also support long disclosures in a bounded scrollable viewport.
Pure and temporary-harness PTY checks cover shown-row coverage, skipped gaps,
resize/new-dialog reset, fixed button targets and an explicitly confirmed fake run.
This does not prove human comprehension or real-provider safety.

Primary board/detail regions also support launch-local proportional resizing via
counted Ctrl-W +/- and reset via Ctrl-W =. Pure and replay PTY tests verify limits,
actual borders, reading position, drafts, mouse composer targets and restoration.
Optional typed TOML startup percentages are also verified through parser/layout
checks and temporary-config PTYs: discovery, no-config, reset, next-launch edits,
Settings disclosure and no automatic writes. Preferences are not stored in task
snapshots, and layout configuration cannot enable execution.

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

Opt-in compiler/dependency reconstruction (downloads, no model calls):

```sh
python3 scripts/smoke-fresh-switch.py --reconstruct --macos-compiler-workaround \
  --report /tmp/factory-fresh-switch-new.json
```

The workaround is only for the documented macOS SDK/runtime mismatch. No project
switch, personal shell/editor config, or install prefix changes. See distribution
and testing docs for prerequisites and scope.

Optional installed-agent loopback integration (dummy credentials only):

```sh
python3 scripts/smoke-codex-local.py --codex /absolute/path/to/codex
python3 scripts/smoke-codex-sandbox.py --codex /absolute/path/to/codex
uv run --with pyte python scripts/smoke-codex-ui.py --codex /absolute/path/to/codex
```

For a packaged binary pass `--binary` to the PTY smoke. Package/installation
checks use temporary destinations. Do not install into the user's PATH, fetch,
push, or contact a real model as a side effect of this audit.


Workspace-form input rejection has pure full-field and supplied-form render checks
for exact cursor/text retention, named feedback, Unicode recovery and operational
report preservation. The full-limit case is not claimed as a PTY paste check;
normal creation and form feedback remain covered by the terminal regression.


Confirmation preparation reuse has pure cached/uncached layout equivalence and
invalidation checks plus complete-disclosure and fake-run PTY coverage. A scoped
local component measurement shows reduced wrapping/allocation, not whole-app or
cross-machine performance. Cache presence does not grant review coverage.


Live confirmation now includes the actual queued instruction IDs/text and combined
prompt byte count through the shared Run_prompt selection/assembly module. Pure
raw-change invalidation and fake-run PTY checks verify exact next-run prompt bytes,
multiline/Unicode retention, sent-history exclusion and later-reply capture rules.
This remains fixture verification, not real-provider compatibility.

Captured-prompt pre-spawn validation is covered by a fake-run integration check
with acknowledged instructions and an oversized future queue. Earlier exact stdin
and completion remain independent of next-turn queue limits. An intermittent
process callback-teardown timing assertion still has no diagnosed cause; no deadline
or cleanup code was changed to pass it.


Capture integrity has pure ID-resolution tests and a temporary live-runner guard
check: missing references fail before spawn, retain queued instructions, report a
channel failure and leave a valid snapshot. Reply identity validation precedes
append/persistence. This is not permission to load or repair corrupt stored data;
codec constraints remain independent.
