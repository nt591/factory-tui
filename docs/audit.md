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
uv run --with pyte --with pillow python scripts/check-ui.py \
  --output /tmp/factory-ui-audit-new
python3 scripts/smoke-invocation.py
python3 scripts/smoke-execution.py
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


Factory notice identity has repeated/collision tests, strict codec/chat checks and
a temporary SQLite reopen check. Same-revision diagnostics remain distinct without
rewriting user/imported history or queued prompts. Existing corrupt databases are
not repaired as part of this change.

Large-turn acknowledgement has pure 20,000-message coverage for captured-only flags,
later replies, immutable-record/cache reuse and strict reference validation. A scoped
local CPU comparison supports the indexing optimization, not whole-app latency or
cross-machine performance. No timing threshold is a safety/test gate.

Reply queue visibility has pure task/render checks and actual replay terminal input
coverage for captured acknowledgement, unsent drafts, next-turn replies and stop
retention. Counts describe delivery flags only, not model progress or billing.

Literal-search matching has fixed/seeded equivalence checks and repeated-prefix
large-text coverage. A scoped local measurement supports reduced allocations,
not whole-app or cross-machine performance. Existing board/chat search semantics
and terminal count/navigation checks remain in force.


The fixture UI suite now runs all dedicated board/chat/composer/confirmation/config/
review checks against one build, retaining logs, previews and a fail-fast JSON
report. It includes format/build/unit gates unless --binary explicitly skips them.
Its case catalogue excludes installed-agent and real-provider work; full fixture
success does not replace the unresolved security/provider/release boundaries.

Large search-result navigation has 20,000-result traversal and lifecycle tests.
Its private array/index changes no selection-by-ID semantics or persisted state.
The recurring process invalid-event cleanup timing assertion failed in an initial
parallel run; no deadline or process code was modified to hide it.

A temporary phase probe reproduced one process “cleanup” assertion failure: first
output arrived after 2.27s, while cleanup took about 0.568ms. Error-path tests now
measure from event delivery, keeping the existing one-second bound and checking
specific errors/direct-child reaping. Delayed-readiness coverage prevents startup
misclassification. Runtime code was restored byte-for-byte; the cause of delayed
startup and arbitrary launch-time guarantees remain unresolved.

Background-update badges have pure event/visibility tests and a replay PTY covering
stream chunk deduplication, automatic column movement, stable selected chat and
clear-on-inspection. Marks are launch-local and do not prove all content was read;
modal/board-only views retain them and snapshot restore does not badge old history.

Stream identity protection has pure namespace/collision tests and strict failed-run
snapshot/render checks. Retained user instructions cannot be silently replaced by
conflicting output, and a conflicted run cannot reach Ready. This does not authenticate
arbitrary imported author labels or repair existing corrupt databases.

Stale-counter ID allocation has pure namespace/limit checks and temporary SQLite
restart/creation coverage. Retained identities remain exact while new allocations
skip occupancy. This is local snapshot safety, not cross-process global identity
coordination or automatic repair of invalid stored data.

Run guidance preserves a current persistence-error footer while continuing task
reduction and pending-event retention. Success/failure/stop event and render tests
verify warning priority. No automatic storage recovery or durability claim is added.

Needs-you card reasons share a pure task/run-status view with compact previews.
Lifecycle/render tests and replay input/stop board checks verify reply-requested
and interruption visibility, recorded failure handling and retained queued replies.
Neutral fallback avoids inventing a reason from absent/inconsistent history.

Queued-reply visibility has pure input/viewport checks and a replay terminal case:
successful submission returns to latest, while failed/unsent editing retains history.
Search queries, Activity positions and active-run state remain separate.

Submission validation is visible during editing, with pure input/render checks and
a dedicated replay PTY for empty replies, invalid model IDs and blank task creation.
The shared UI catalogue includes this 16th case. Failed edits retain data/cursors;
valid recovery changes no execution boundary and adds no new keybindings.

Local submission success does not mask a persistence warning. Pure reply/model/task
input and rendering checks verify accepted local state, visible warning and no
extra runs; no automatic storage recovery or durability assertion is introduced.

Acceptance pending-data disclosure has pure state/codec/archive checks and a replay
PTY with queued follow-ups and an unsent draft. Their identities/content remain
retained; the accepted detail view reports retention, not next-turn execution.
No automatic sending, merge, push, workspace deletion or storage recovery is added.

Restart conversation selection has pure filter/archive/fallback tests and repeated
SQLite terminal coverage. Accepted chat remains selected independently of an active
board; retained drafts stay read-only and exact history is unchanged. The fixture UI
catalogue includes restart-selection as its 17th case. No agent resumes on restart.

Archive sidebar/toggle actions and normal-mode Escape retain a valid selected
conversation even when its card is outside the visible board. View changes do not
reset transcript search or remembered Chat/Activity positions. Missing identities
still fall back to visible cards; explicit board navigation selects a visible task.
Board search keeps its existing match-selection behavior. Pure controller tests
and the SQLite restart PTY cover active-chat/archive and accepted-chat/active-board
switches, mouse/keyboard input, retained read-only drafts and unchanged task history.
No new keybindings, persistence fields or execution behavior are added.

The composer PTY waits for both the draft window and its submit-guidance footer.
A captured partial redraw showed the window before the footer finished. Checking
both before asserting avoids treating that intermediate frame as the final view;
the deadline and all content assertions remain unchanged. Runtime rendering is
unchanged by this fixture condition.

Verification on 2026-11-18: the final one-build UI audit passed all 17 cases and
produced 58 previews. Evidence: `/tmp/factory-view-selection-ui-20261118-final/report.json`.
Archive/expanded-chat previews were inspected. CLI invocation (20), fake execution
(19), and temporary package (14) checks passed separately. These are fixture-only
results; provider, security and public-release limitations remain unchanged.

The board summary identifies a selected conversation whose card is hidden by the
active/archive or repository/search filters. Its Show card control clears board
filters and selects the matching active or Archive view without reselecting the
task, resetting transcript search, sending a draft or starting a run. Expansion
closes so the card can be inspected. Full labels have exact mouse targets; narrow
headers use a short label and omit the button below its minimum usable width.
Controller/layout tests and temporary SQLite PTYs verify active and accepted
reveal, retained conversation data, input/modal isolation and no execution.

Show-card verification on 2026-11-18 passed format/build/unit gates, including 141
board-summary checks, and all 17 fixture UI cases (58 previews). Evidence:
`/tmp/factory-show-card-ui-20261118/report.json`. The off-board Archive preview
was inspected. Separate CLI invocation (20), fake execution (19) and temporary
package (14) checks passed. Real-provider and release limitations remain unchanged.

Shortcut_guidance.ml/.mli supplies a width-bounded bottom-row hint for the current
input mode, pane focus, expansion and transcript search. Reply editing shows INSERT,
Enter queues, draft-preserving Escape and newline controls. Model/task/search editors
state their own submit and Escape behavior. Normal chat hints describe scrolling
and Latest rather than card movement; Activity names readable/raw tools. Expanded
views say return, and the pending pane prefix names pane controls. Input-limit and
validation feedback keep precedence. No binding, state transition, persistence or
execution behavior changes. Pure layout/render tests and the input-feedback PTY
verify the mode changes and recovery from validation errors.

Contextual shortcut verification on 2026-11-18 passed 106 pure input/render checks,
format/build/unit gates, and all 17 fixture UI cases with 59 previews. Evidence:
`/tmp/factory-shortcuts-ui-20261118/report.json`. The insert-mode preview was
inspected. Separate CLI invocation (20), fake execution (19) and temporary package
(14) checks passed. No installed provider or real model was called.

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

E2E perf now runs the real TUI executable through a PTY against isolated SQLite
and replay data. The 200-task/200-message and 1,000-task/1,000-message workloads
passed ordered-reply persistence, navigation/editor and event-driven Ready checks.
Raw latency/resource reports are retained under docs/verification/e2e-perf-*-20261118.json.
They include observer/binary hashes and explicit measurement limits. See
docs/performance.md for commands and dimensions. This is not live-provider,
model throughput, terminal GUI paint, peak-RSS or application-only profiling.
Five pure helper tests verify summaries, fixtures, stale-state refusal, private
reports and preservation of partial evidence on failure/interruption.

Perf-tool verification on 2026-11-18 passed formatting/build/unit gates and five
pure benchmark-helper tests. The default 3x5 workload, the 1,000-task/message 2x2
workload, and the build-on-demand 20-task/36-message smoke all completed exact
persistence and replay checks. Separate CLI invocation (20), fake execution (19)
and temporary package (14) checks passed. This increment changes no OCaml runtime
behavior; the preceding editor-controls increment passed all 17 fixture UI cases.

E2E comparison verification on 2026-11-18 passed nine pure comparison tests,
format/build/unit gates, CLI invocation (20), fake execution (19) and temporary
package (14) checks. An unchanged executable/observer repeat completed all default
workload checks and compared successfully against the retained 200-task report;
the different 1,000-task report was refused. Repeat and comparison evidence:
`/tmp/factory-e2e-perf-repeat-20261118.json` and
`/tmp/factory-e2e-perf-comparison-20261118.json`. No runtime optimization or timing
gate is introduced; profiling and performance cleanup remain follow-up work.

Startup config preview verification on 2026-11-18 passed format/build/unit gates,
10 pure preview checks and 34 temporary CLI setup checks. Existing invocation (20)
and fake execution (19) checks passed. The packaged command is checked with the
bundled example TOML and must create no SQLite file; configuration instructions
are included. No interactive render or process-runner behavior changes in this
increment. Config validity remains separate from resource/provider compatibility.
Temporary package smoke passed all 16 checks, including standalone config preview.

Continuous workflow verification on 2026-11-18 passed all 18 fixture UI cases
and format/build/unit gates with 62 previews. Evidence:
`/tmp/factory-workflow-ui-20261118/report.json`. Diff and accepted-restart previews
were inspected. The workflow verifies one confirmed fake process, exact queued
instruction and requested write policy, isolated file change, real jj review,
acceptance with retained draft and exact restart history/source preservation.
Separate setup CLI (34), invocation (20), fake execution (19) and temporary package
(16) checks passed. No real-model compatibility or sandbox enforcement is claimed.

Two-turn continuous workflow verification on 2026-11-18 passed all 18 fixture
UI cases and format/build/unit gates with 63 previews. Evidence:
`/tmp/factory-workflow-resume-ui-20261118/report.json`. The accepted transcript
preview shows both instructions/answers and distinct immutable model selections
in the run history. The resumed invocation receives only the follow-up prompt
on the exact same thread/workspace; cancellation, draft acceptance and restart
remain explicit and preserve source/history. Separate setup (34), invocation (20),
fake execution (19) and package (16) checks passed. This is fake-process integration,
not installed-agent or real-provider resume compatibility.

Working-reply isolation verification on 2026-11-18 passed all 18 fixture UI cases
and format/build/unit gates with 64 previews. Evidence:
`/tmp/factory-working-reply-ui-20261118/report.json`. The accepted restart preview
shows the late queued instruction and retained-draft/read-only disclosure. Before
completion, SQLite retains that reply outside the active submitted IDs; the fake
process keeps its original prompt and no third invocation starts. Both run records,
source preservation and exact restart history remain verified. Separate setup (34),
invocation (20), fake execution (19) and package (16) checks passed. No runtime
change, model call, provider-delivery claim or sandbox security claim is made.
