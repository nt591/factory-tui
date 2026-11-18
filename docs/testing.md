# Test fixture boundaries

Normal checks run through `scripts/check.sh`: formatting is a separate gate,
Dune builds and tests use their normal parallel scheduling, and the local Python
response-fixture tests use neither a server nor an agent. Runtime limits must not
be increased solely to make a test pass. A subsequent passing run is not evidence
that an unexplained failure was fixed.

## Native plain-command fixtures

`test_command` launches its own compiled test executable with an explicit fixture
mode. Only the child mode prints fixture output, returns a known exit, sleeps,
closes its output pipes, or reports the supplied directory/argument. It never
opens a real repository, invokes a shell, or loads agent credentials.

This exercises the public `Command.run` API with controlled executable behavior:

- one-second success deadline and separate 0.1-second forced timeouts;
- stdout/stderr size errors with exact error-message checks;
- concurrent draining of a 256 KiB stderr burst and retained stdout;
- nonzero exit results, literal argument arrays, and working directory;
- timeout after output descriptors close, plus direct-child reaping;
- invalid limits/paths/arguments, repeated launches, and eight-way concurrent
  commands with independent streams/outcomes.

These checks were moved out of `test_workspace` so jj integration and plain
process I/O are separate concerns. Real jj commands remain in the workspace
checks. Shell scripts remain in harness integration tests where shell/descendant
behavior is itself part of the boundary under test.

## Investigation of the former script-fixture timeout

The successful plain-command fixture previously executed a freshly created
`#!/bin/sh` script directly with a one-second deadline. Some default parallel
Dune/package runs timed out. Temporary instrumentation showed no stdout/stderr,
open pipes, and an unreaped running child at the deadline; the failure was not
caused by the command's output-size limit. Instrumentation was removed.

On November 18, 2026, a separate Python launch probe, outside `Command.run`,
created 16 executable scripts and launched them with eight concurrent workers.
Direct first launches took 0.195–0.822 seconds, while subsequent explicit
`/bin/sh <script>` launches took 0.012–0.018 seconds and returned identical output.
This supports fresh script-startup latency as a confounding input. The explicit
shell launches followed direct launches, so the probe does not isolate caching,
security checks, filesystem behavior, or the precise OS cause. No general macOS
or Spawn defect is claimed, and no production spawn behavior was changed.

The plain I/O fixture now uses the compiled child executable instead of timing
fresh script startup. Success/error/timeout assertions and production deadlines
are unchanged. Three normal parallel full-suite runs and the package checks
passed after the fixture change. This establishes the native fixture's verified
behavior, not a guarantee that arbitrary fresh executables always start promptly.
Real commands can still hit their configured deadline; the application must report
that failure rather than silently retrying or declaring success.

## Other checks

- `scripts/smoke-terminal.py`: PTY input, rendering, lifecycle, persistence,
  workspaces, review, and confirmed live-mode behavior using fake executables.
- `scripts/smoke-package.py`: archives and install/refusal in temporary prefixes.
- `scripts/smoke-codex-local.py`, `scripts/smoke-codex-sandbox.py`, and
  `scripts/smoke-codex-ui.py`: explicit opt-in installed-Codex loopback checks with
  dummy credentials. The UI probe links workspace creation, confirmation, editing,
  review, resume, acceptance, and archived-chat restart. Its bounded PTY helper is
  in `scripts/fixtures/terminal.py`. These checks are never part of normal tests
  or a real-provider/model approval.

All fixture output is evidence of fixture behavior only. A simulated completion
must not be represented as a real source-code or model verification result.

Pure `test_run_status` covers selected-run start/completion/failure/interruption
text, acceptance guidance, and stale/background-event isolation. The stop/retry checkpoint test also
rejects any unexpected error callback while the replacement runs, then requires
completion guidance instead of stale waiting text. Archive first-run tests cover
selection repair, direct zoom, filtering, and retained read-only chat.

## Grapheme wrapping and terminal width

`test_text_layout` compares complete grapheme sequences and retained UTF-8 bytes
before/after wrapping, using Notty's measured cell width. It covers combining
accents, skin-tone modifiers, flags, joined emoji, keycaps, explicit blank lines,
control sanitization, malformed input, and oversized-cluster cropping. These
checks do not establish the width used by a terminal emulator or font.

The compact PTY probe places a skin-tone emoji near a row boundary and checks
that the emoji and modifier remain on the same logical display row. During this
check, Notty and pyte disagreed on that emoji's width at the last available cells;
the test leaves enough room for both widths. This is a documented display-width
limit, not a reason to split a grapheme. Exact right-edge emoji rendering requires
terminal-specific coverage and is not claimed by this test.

## Diff redraw preparation

`test_diff_display` verifies prepared row sanitization, malformed-text replacement,
terminal-cell width, bounded slices, reused row strings, and unchanged raw patch.
Real-jj review tests verify cache construction, idle/resize reuse, and refresh
invalidation. `Review_view` reads the cached width and visible row slice rather
than sanitizing/measuring every line on each redraw.

An opt-in synthetic measurement runs no command or workspace operation:

```sh
opam exec --switch=. -- dune exec test/test_diff_display.exe -- --measure
```

On November 18, 2026, a local 20,000-line synthetic Unicode patch yielded:

- Initial sanitized display preparation: 65.499 ms.
- Twenty full sanitation/terminal-width scans: 212.739 ms total.
- Twenty cached-width lookups plus 30 visible-row images each: 0.069 ms total.

The full-scan path uses the prior sanitation and Notty measurement operations.
The cached path excludes initial preparation and stores extra sanitized row data.
These are local single-run observations, not timing assertions or a whole-TUI,
real-provider, terminal-output, or native-GUI performance comparison. Initial
preparation still runs when the bounded patch result is delivered; no asynchronous
preparation or large-transcript performance claim follows from this measurement.

## Chat image window

`Chat_viewport.visible_rows` selects at most the visible chat height before Notty
image construction. `test_chat_window` verifies exact top/middle/end slices,
hidden panes, boundary clamping, paused-history append behavior, and that an
unrenderable offscreen row cannot reach the image constructor. Existing viewport,
search, and PTY streaming tests cover complete UI behavior.

```sh
opam exec --switch=. -- dune exec test/test_chat_window.exe -- --measure
```

A local November 18, 2026 synthetic run used 20,000 rows and twenty image-building
passes. Constructing every row after offset 10 took 59.595 ms total; constructing
thirty visible rows took 0.042 ms total. This excludes wrapping, message/search
indexing, viewport anchoring, other panes, and terminal output. It is a single-run
component measurement, not a whole-TUI latency or native-GUI comparison. Full
logical chat rows are still generated to preserve anchors and search; no large-chat
wrapping-cache claim is made.

## Unchanged transcript layout

`Chat_layout` caches the current task's wrapped rows and anchor list. The key is
task ID, content width, and physical identity of the immutable message list. New
stream text or queued-message acknowledgements create a new list and rebuild
affected message blocks; task/width changes rebuild all blocks even with the same list. Height-only resize and changes
to next-run settings reuse the document. Structurally equal replacement lists
rebuild conservatively. The single-entry cache is transient and is not a snapshot
field. Unit/UI tests check these cases and sanitized body text; existing terminal
streaming, search, and history checks exercise the integration.

```sh
opam exec --switch=. -- dune exec test/test_chat_layout.exe -- --measure
```

On November 18, 2026, a local synthetic transcript of 2,000 messages (8,000 wrapped
rows) took 229.677 ms total for twenty forced layout/anchor rebuilds. Twenty cache
hits took 0.000954 ms total. This timer-resolution-sensitive number is not a
whole-TUI latency claim: it excludes search matching, viewport scans, image
construction, and terminal output. The cache retains extra wrapped text and
anchors. This historical measurement forced full transcript rebuilds; later
message-block reuse is measured separately below. Neither measurement establishes
whole-application performance.

## Unchanged search matches

`Chat_search` skips recomputing matches for the same query and immutable message
list. Query changes invalidate the cache; streamed replacements refresh membership
and preserve the selected message when it still matches. Clearing search releases
retained messages and resets the highlight index. Tests cover query changes on the
same list, append/removal, stale-highlight removal, and large-list selection/seek.

```sh
opam exec --switch=. -- dune exec test/test_search_cache.exe -- --measure
```

A local November 18, 2026 synthetic run with 2,000 matching messages measured
40.045 ms for twenty forced match rebuilds and 0.045061 ms for twenty cached syncs
plus thirty highlight lookups per pass. This is a component observation, not a
whole-TUI benchmark. It excludes layout, viewport scans, terminal output, and
match navigation; changed lists still perform a full match scan.

Repository sidebar overflow has a separate temporary-board terminal check:

```sh
uv run --with pyte --with pillow python scripts/smoke-sidebar.py \
  --preview /tmp/factory-sidebar.png
```

It uses forty synthetic repositories in a temporary SQLite snapshot, no agents or
real workspaces. It checks wheel scrolling, visible click targets, filtered cards,
and reset to the top. Unit tests also cover clipped hitboxes, resize, following a
selected repository, and modal wheel ownership. The fixture preserves selected
chat when filtering, as the product contract requires.

Independent Kanban scrolling has a temporary-board terminal check:

```sh
uv run --with pyte --with pillow python scripts/smoke-columns.py \
  --preview /tmp/factory-columns.png
```

It creates a SQLite fixture with ten Queued and ten Ready tasks, then verifies
column-specific scrolling, retained chat selection, keyboard-following, manual
top positioning, and unchanged saved task content. It starts no agent and touches
no real workspace. Unit tests additionally verify selected state movement,
Start-following, unrelated stream updates, modal blocking, and compact-list input.

## Menu execution-mode disclosure

`test_menu_content` covers simulation, fake-process, replay, read-only live, and
workspace-write live instructions. It verifies that live help/settings do not
advertise simulated harness cycling, accepted-task settings remain read-only,
and the actual rendered menu leaves tasks and confirmation unchanged. The opt-in
installed-Codex UI check browses Help/Settings before confirming and requires zero
loopback requests from that browsing.

During this increment on November 18, 2026, one default parallel suite reported
`Command timeout exceeded.` in `test_command`; a second unchanged suite passed.
No fixture case or OS cause was isolated from that error. This is not evidence
that native fixtures eliminate all startup latency or that menu edits affect
command behavior. Command implementation, one-second success deadlines, and
parallel scheduling remain unchanged. The failure remains a reliability limit
requiring case-specific evidence if it recurs.

Paused chat while scrolling the board has a separate replay-only PTY check:

```sh
uv run --with pyte --with pillow python scripts/smoke-board-history.py \
  --preview /tmp/factory-board-history.png
```

The fixture uses a temporary event file and no SQLite, workspace, credentials,
or agent. It compares only the chat content region, allowing Activity updates
to change. The arrival wait observes the updated event count before checking the
anchor. It verifies board focus, subsequent output, mouse return to chat, and
explicit End-follow. Unit tests additionally verify remembered distances and
unchanged snapshots; keyboard resets keep their explicit fresh-position behavior.

## Streaming message-block reuse

Within the current task/width, `Chat_layout` reuses a block only when its message
ID and immutable record identity match. Updates still assemble aggregate row and
anchor lists, but unchanged message text is not sanitized or wrapped again.
The next block index contains only current messages. Tests check physical row and
anchor reuse, replacement rebuilding, author/delivery updates, current ordering,
removal/reappearance, and task/width invalidation.

The existing `test_chat_layout.exe -- --measure` command now also measures twenty
single-message changes among 2,000 messages. On November 18, 2026, forced full
rebuilds took 232.177 ms total; reuse of unchanged blocks took 5.743 ms total.
This includes changed-block wrapping and aggregate row/anchor assembly, but not
search, viewport scanning, images, terminal output, or application event delivery.
It is a local component measurement, not a GUI comparison or streaming throughput
claim. Aggregate list rebuilding remains linear in transcript size.

During the same increment, an initial parallel suite again reported a native
`test_command` timeout without identifying its case. After adding failure context,
a later parallel suite reported `repeated output 19: Command timeout exceeded.`
Direct invocation and other parallel suites passed. Test failures now name
initial/repeated I/O cases and concurrent batch/worker; no production behavior,
success deadline, timeout assertion, or parallel scheduling was changed. Passing
reruns do not establish that startup reliability is fixed.

A direct Python probe of 128 compiled native fixture children, with eight workers
and one-second completion deadlines, observed no failure (median 0.012 s, maximum
0.063 s). Three parallel suites with temporary timeout-state instrumentation also
passed; instrumentation observed only the deliberate 0.1-second timeout cases and
was removed. Neither probe reproduced the unexpected repeated-output timeout or
isolated its cause. The original command source was restored byte-for-byte, and
final checks run without instrumentation. No startup guarantee follows from these
negative reproduction results; the new case-specific error context is retained.

Incremental layout is also compared against a fresh cache over sixty deterministic
stream updates, including changing text, author/delivery labels, message order,
content width, and task identity. Equality checks cover all rows and anchors;
separate physical-identity tests verify that reuse actually occurs.

## Fresh locked switch reconstruction

The opt-in `scripts/smoke-fresh-switch.py` creates a temporary opam root and an
empty switch. It downloads metadata/sources and installs application dependencies
with `--locked --deps-only`, then checks exact installed versions against the
checked-in lock. It builds in a separate Dune directory and runs parallel unit
checks and the full terminal fixture against that fresh binary. The temporary
root, compiler, dependencies, and build are removed on normal success or failure;
a new report file retains stage outcomes. The project switch, personal shell
configuration, editor, real workspaces, and credentials are not modified.

```sh
python3 scripts/smoke-fresh-switch.py --reconstruct \
  --report /tmp/factory-fresh-switch-new.json
```

This is compiler/dependency reconstruction on the current host, not a clean OS
installation. Network, opam, the system compiler/linker, pkg-config, SQLite, jj,
Python, and uv must already work. The lock covers application dependencies, not
ocamlformat, ocamllsp, or optional odoc. This heavy check is not part of normal
`check.sh`; `test-fresh-lock.py` exercises its comparison logic without installing
anything or starting a process.

November 18, 2026: the first unmodified compiler/dependency reconstruction failed
in topkg. The matching `ocamlbuild` crash report identified SIGSEGV at
`caml_unix_pipe`. With explicit `--macos-compiler-workaround`, reconstruction
passed all 52 exact locked versions, fresh build, parallel unit tests, and full
PTY smoke using the fresh binary. The compiler's generated runtime header also
showed the requested pipe2/dup3/accept4 functions disabled. No project switch or
opam sandbox change was made; temporary resources were removed. The compact
committed evidence is `docs/verification/fresh-switch-macos.json`.

## Tool-payload decoding cache

`test_tool_cache` verifies reused descriptions/raw lines, replacement updates,
removal/reappearance, task changes, stale-document safety, and decoder equivalence
for commands, MCP, file changes, future kinds, and legacy text. Cached Activity
rows are compared with uncached rows, and source-run labels remain tied to the
current records rather than the cached payload. Renderer checks confirm reuse and
unchanged snapshots. Existing terminal and installed-agent loopback tests cover
raw/readable toggles and retained historical tool attribution after resume.

```sh
opam exec --switch=. -- dune exec test/test_tool_cache.exe -- --measure
```

On November 18, 2026, 200 tools with 100 output lines each took 42.060 ms total for
twenty full readable-decoding passes and 0.072 ms for cached descriptions. The
cache was warm for the second path. This component measurement excludes wrapping,
row assembly, source-run labels, image construction, and terminal output; it is
not a whole-TUI or GUI comparison. The cache retains decoded text in addition to
raw payloads, and representations are forced only when expanded inspection needs
them. Large-output wrapping and aggregate Activity rows are still rebuilt.

During the tool-cache increment, one parallel suite reported `working directory:
Command timeout exceeded.` in the native command fixture. Tool-cache and other
checks completed, but that suite was not successful. Case-specific context now
shows the reliability issue is not confined to the previously observed repeated
output case. Production Command code, one-second success deadlines, and test
parallelism remain unchanged; later passing reruns do not prove this issue fixed.

The headless execution cancellation fixture waits for its own temporary launch
marker before requesting cancellation. Its prelaunch-cancellation case remains
separate. A former 50 ms wall-clock trigger could expire during the durable
checkpoint and fail before spawning, so it did not reliably exercise runtime
cancellation. The marker gates the intended test boundary; it changes no process
or storage implementation, timeout, or production cancellation policy.


## Scrollable confirmation fixture

```sh
uv run --with pyte --with pillow python scripts/smoke-confirmation.py \
  --preview /tmp/factory-confirmation.png
```

This runs the actual TUI against a temporary SQLite snapshot and a fixed shell
harness. Its recorded workspace has only a temporary `.jj` marker; it is not a
jj integration test. No installed model executable, credential, provider, or real
checkout is accessed. Checks cover complete identity tails, skipped-row blocking,
Vim/paging/wheel controls, button wheel isolation, resize/new-dialog reset,
mouse cancellation and confirmation, exact retained identity/prompt, and one
persisted Ready run. Previews show the locked and reviewed views. Pass `--binary`
to use an already-built executable without rebuilding it. Displayed-row coverage
is a UI safety gate, not evidence of human comprehension or a sandbox audit.


## Adjustable pane replay fixture

```sh
uv run --with pyte --with pillow python scripts/smoke-panes.py \
  --preview /tmp/factory-panes.png
```

The real terminal consumes temporary replay events; no agent, credential or
workspace operation is used. The check exercises counted Vim resize commands,
stacked/wide geometry, paused history during appended events, draft retention,
resized composer clicks, modal/paste isolation, compact/zoom preservation and
reset. It captures stacked and wide frames. `--binary` uses an existing build.
Pure `test_pane_layout` covers constraints and snapshot isolation separately.


## Layout configuration fixture

```sh
uv run --with pyte --with pillow python scripts/smoke-layout-config.py \
  --preview /tmp/factory-layout-config.png
```

This uses temporary HOME/XDG directories and TOML files. It checks default and
explicit discovery, no-config bypass, stacked/wide startup shares, Settings,
runtime adjustment and reset without writes, and disk edits taking effect on the
next launch. An explicit live launch uses a never-started local shell fixture and
a temporary database to verify configuration/CLI plumbing, not execution or jj.
Invalid percentages fail before storage opens and do not expose source text.
`--binary` uses an existing executable. No credentials or model are accessed.


The board-history replay check also exercises the Latest border button:

```sh
uv run --with pyte --with pillow python scripts/smoke-board-history.py \
  --preview /tmp/factory-chat-position.png
```

A temporary event file supplies output while chat is paused and board owns focus.
The check verifies preserved visible content, the wrapped-row cue, wheel isolation
on Latest, mouse follow and later followed output. It does not use a database,
agent, credentials or workspace. `test_chat_position` separately checks pure target
alignment, saved-state isolation, search/editor/modal behavior and terminal bounds.


## Long reply composer fixture

```sh
uv run --with pyte --with pillow python scripts/smoke-composer.py \
  --preview /tmp/factory-composer.png
```

The real TUI uses an empty temporary replay file, SQLite, and isolated HOME/XDG.
It pastes an 18-line Unicode draft, checks bottom/top/middle window ranges, edits
at the top, exits without submitting, restarts, and queues the exact retained
text. No run is added. Startup recovery of an existing simulated Working attempt
is accounted for before checking unchanged run history at submission. No agent,
credentials or workspace are accessed. `--binary` avoids rebuilding; previews
show top and bottom. Pure `test_composer_layout` covers wrapped text and bounds.


## Wrapped transcript author fixture

```sh
uv run --with pyte --with pillow python scripts/smoke-chat-author.py \
  --preview /tmp/factory-chat-author.png
```

Temporary SQLite messages contain long fixture author labels and delivery states.
An empty replay file disables timed updates. The terminal check opens chat,
verifies both author tails and bodies, searches the full author, then verifies
exact stored messages/runs. HOME/XDG are temporary; no agent, credentials or real
workspace are used. `--binary` avoids rebuilding. Pure `test_chat_author` checks
header tones, bounds, index uniqueness and body-anchor preservation.


## Row-aligned board navigation fixture

```sh
uv run --with pyte --with pillow python scripts/smoke-board-navigation.py \
  --preview /tmp/factory-board-navigation.png
```

The real terminal loads a temporary SQLite board with five Queued, five Needs you
and two Ready tasks; Working is empty. An empty replay file prevents timed events.
Checks cover row-aligned horizontal movement, skipping the empty column, counts,
short-column clamping, destination visibility and its expanded chat. Final saved
tasks/runs/drafts remain exact; only selection changes. HOME/XDG are isolated.
No agent, credentials or real workspace are accessed. `--binary` avoids rebuilding.


## Filtered board summary fixture

```sh
uv run --with pyte --with pillow python scripts/smoke-board-summary.py \
  --preview /tmp/factory-board-summary.png
```

A temporary SQLite board has a long repository identity and task title. An empty
replay file prevents timed events. The TUI filters by repository and a long query,
resizes to 60 columns, verifies visible counts, clicks the displayed search span
to inspect the complete query, and clicks the view label to enter Archive. Saved
tasks/runs remain exact. HOME/XDG are temporary; no model, credentials or real
workspace are used. `--binary` avoids rebuilding. Pure `test_board_summary` covers
sanitation, fallback widths, non-overlapping spans and input/modal isolation.


## Review failure and retry fixture

```sh
uv run --with pyte --with pillow python scripts/smoke-review-notice.py \
  --preview /tmp/factory-review-notice.png
```

A temporary task points to a temporary directory and a fake jj shell executable.
The first explicit refresh returns failure; its printed fixture output remains
withheld. The TUI displays wrapped failure/retry guidance at 60 columns and pages
it at 30 columns. Open, pasted paths, reading and paging start no command. Replacing
the fixture does not retry until explicit `r`, which returns a fixed patch. Checks
verify three explicit calls total (failure, patch, empty result), End paging of
an empty-result notice despite its empty patch document, and exact saved
task/run/draft retention. This does not test real jj semantics: those remain in test_review. No model, credentials or real
repository are accessed. `--binary` avoids rebuilding. Pure test_review_notice
covers sanitation, wrapped limits, empty/idle states and document-free End.


## Shared terminal sanitation checks

`test_terminal_text` runs in the normal Dune suite. It checks explicit line and
multiline policies against the previous decode/control algorithm, all C0/DEL/C1
values, malformed and incomplete UTF-8, 2,000 seeded random byte strings, printable
BMP scalar encodings, CRLF behavior, idempotence and editor-state isolation.
The terminal component tests remain the integration checks for wrapping, widths,
search, confirmation, path input and drafts; full PTY/review/composer checks verify
readability and retained text through actual input. These checks do not claim
universal font/terminal grapheme width or broader terminal-security containment.


The review-notice PTY fixture also checks responsive review controls. It closes a
pasted-path editor by mouse before any command, reopens its retained executable,
uses compact Refresh and jj buttons at 30 columns, and closes the compact path
editor without a command. The fixture still counts only its three explicit
refreshes. test_review_controls sweeps widths 0–180 in editing/non-editing and
single/multiple-file modes, checking full brackets, target bounds and separation.
No label is truncated into a clickable action. Wide existing review tests retain
full-label file-button geometry and real-jj behavior.


## Precise chat reflow fixture

```sh
uv run --with pyte --with pillow python scripts/smoke-chat-reflow.py \
  --preview /tmp/factory-chat-reflow.png
```

A temporary replay supplies a long body and later growing output. The real TUI
pauses inside the body, changes widths repeatedly, verifies the original position
inside the first visible row and exact row restoration at the original width,
then resumes following with End. No storage, agent, credentials or real workspace
are accessed. `--binary` avoids rebuilding. test_chat_reflow covers sanitized byte
starts, complete grapheme boundaries, empty/newline rows, width/height changes,
anchor uniqueness, Unicode and saved-state isolation.

During this increment, one parallel test_process run failed its existing
`callback failure teardown bounded` one-second assertion. The isolated process
suite passed afterward. The precise cause is not established; deadlines and
runtime code were not changed, and a passing rerun is not a diagnosis.


The filtered-board summary PTY also verifies compact task title omission and
visible task ID/state at 60 columns. test_task_row covers cell bounds, grapheme
sequences, controls, long IDs, exact hit identity and expanded complete titles.
These are display changes only; full stored task/run data remains unchanged.


## Input-limit feedback fixture

```sh
uv run --with pyte --with pillow python scripts/smoke-input-limit.py \
  --preview /tmp/factory-input-limit.png
```

A temporary SQLite snapshot holds a full 64-KiB queued-task draft. The real TUI
rejects an added paste, shows the warning without moving its cursor, retains the
warning during cursor motion, then deletes one byte and accepts one replacement.
Final draft bytes are exact; no message/run is added. An empty replay and isolated
HOME/XDG avoid agents, credentials and workspace access. `--binary` avoids rebuilding.
Pure test_input_limits also covers chat query limits, malformed UTF-8 expansion,
editor/backing-value synchronization, whole-cluster rejection and storage errors.

An initial parallel run in this increment hit test_process's existing
`invalid event cleanup bounded` timing assertion. The full rerun passed without
changing deadlines or runtime process code. The cause remains undiagnosed.


`test_form_limits` constructs a full field in memory and exercises the public form
input API, including multi-byte paste rejection, exact text/cursor retention,
recovery, other-field/cursor isolation and retained operational messages. Ui renders
the supplied form to verify visible rejection and no creation request. This does
not simulate pasting 64 KiB through a PTY. Normal workspace creation/feedback remains
covered by the full terminal regression. No path inspection or subprocess is used
by this unit test.


Wheel-target unit checks cover all pane/column perimeter edges, title clicks,
search-strip exclusion and positive bounded interior rectangles through small
terminal sizes. The board-history PTY additionally sends wheel events over column,
chat and Activity titles before normal body scrolling and mouse Latest follow.
It uses only temporary replay events. Full terminal checks cover existing modal,
sidebar, column-body and reply interactions with the separated geometry.


## Confirmation preparation cache

Normal test_confirmation_cache compares cached and uncached views, raw-detail and
width invalidation, unchanged scrolling, height-query inactivity, new-dialog reset
and missing-task refusal. Existing test_confirmation_layout and smoke-confirmation
exercise shown-row coverage, exact current identity, reflow reset and confirmed
fake execution. To measure only disclosure height/render work:

```sh
opam exec --switch=. -- dune exec test/test_confirmation_cache.exe -- --measure
```

One local run with a 60-KiB title and 20 frames reported 0.77 ms / 5,971,488 allocated
bytes with reuse versus 209.19 ms / 609,733,312 without reuse, including disclosure
of both the title and its initial queued instruction. It includes image
construction, but not full Ui, terminal output or process work. Measurement uses
no model or workspace. No elapsed-time or allocation ratio is a unit-test gate.


The smoke-confirmation PTY now discloses two actual queued replies beside a long
old title. Sent history is excluded; multiline/Unicode queued content is visible
across reviewed pages. The fake harness receives exactly the queued texts joined
by two LF bytes, not the task title or historical instruction. Pure test_run_prompt
covers queue/captured-ID selection, exact separators/byte length, later-reply
exclusion, queued text/ID authorization invalidation and unchanged sent-history
compatibility. Preparation caching retains these checks and avoids prompt assembly
solely for redraw counters.

The live-runner integration test now acknowledges captured instructions and adds
17 later 64-KiB replies before the first process poll. Public next-run preflight
rejects that oversized queue, while the already confirmed fixture sends its exact
original instruction and reaches Ready. All later replies remain queued. This
runs only a temporary fake executable/workspace and does not use a model.
One parallel process-suite attempt in this increment hit the existing callback
teardown timing assertion; its isolated rerun passed. Deadlines and process code
were unchanged. A passing rerun does not diagnose the cause.


Run-prompt unit checks cover validated capture ordering, acknowledged flags,
missing/duplicate/empty ID rejection and ambiguous message records. Model.send tests
reject duplicate and invalid-length reply IDs. The temporary live-runner integration
corrupts a captured ID before its first poll, verifies that no fixture marker is
created, checks channel failure and retained queue, and roundtrips its resulting
snapshot. This tests the in-process guard, not support for loading corrupt snapshots;
the codec independently rejects invalid captured references.


`test_system_messages` checks repeated same-revision notices, collisions with user
and imported history, stable earlier records, queued prompt retention and 200 unique
notice IDs. It roundtrips the strict codec, renders restored chat and saves/reopens
a temporary SQLite database with exact IDs/text. No agents, credentials or real
workspace operations are used. Existing corrupt snapshots remain rejected rather
than automatically repaired.

## Large captured-turn acknowledgement

`test_turn_ack` checks 20,000 messages and 10,000 captured IDs with a later reply.
It verifies only captured queued flags change, sent/later records remain identical,
repeated acknowledgement reuses the transcript document and revision still advances.
The strict snapshot codec roundtrips a large capture and rejects missing/duplicate
references after indexed lookup. No subprocess or workspace is used.

```sh
opam exec --switch=. -- dune exec test/test_turn_ack.exe -- --measure
```

One local three-pass comparison reported 1.47 ms for indexed reductions and 2355.72 ms
for the previous submitted-list membership scan. This is scoped CPU work, excluding
storage, transcript rendering and terminal output. No elapsed-time threshold or
performance ratio is asserted by tests.

## Reply queue summary fixture

```sh
uv run --with pyte --with pillow python scripts/smoke-queue-summary.py \
  --preview /tmp/factory-queue-summary.png
```

Temporary replay events acknowledge and interrupt the seeded task while replies
are queued through actual terminal input. Checks distinguish captured instructions,
unsent drafts and later replies, then verify acknowledgement and stop retention.
No storage, agent, credentials or real workspace are used. Pure test_queue_summary
covers state transitions, accepted-task copy, border widths and saved-state
isolation. `--binary` avoids rebuilding.

## Literal search matching

`test_literal_search` compares the shared matcher with the prior substring scan
for fixed empty/case/UTF-8/malformed-byte/metacharacter cases and 3,000 seeded
text/query pairs. It also checks reuse after unrelated matching, one-MiB repeated
prefixes, and board/chat text/author integration. No processes or storage are used.

```sh
opam exec --switch=. -- dune exec test/test_literal_search.exe -- --measure
```

One scoped ten-search measurement with 300,001 text bytes and a 256-byte query
reported 6.42 ms / 96 allocated bytes for prepared matching versus 50.25 ms /
818,312,496 bytes for the prior substring scan. It excludes full UI/rendering and
is not a test performance gate. Search remains literal and ASCII-case-insensitive;
Unicode case folding is not introduced.


## One-build UI regression suite

```sh
uv run --with pyte --with pillow python scripts/check-ui.py \
  --output /tmp/factory-ui-check-new
```

The runner checks formatting and runs scripts/check.sh, then all 17 fixture-only
PTY cases sequentially against the same executable. It never invokes the installed
Codex, sandbox probes, fresh-switch reconstruction or a real provider. Each child
uses --binary so it cannot rebuild during terminal execution. Sidebar, column and
board-history fixtures support the same option while retaining standalone build
behavior. --case may be repeated; selected cases run in catalogue order, once each.
--list has no build/process/output-directory side effects. --binary tests an
existing executable and explicitly skips format/build/unit gates in its report.
FACTORY_BUILD_DIR is respected when the suite builds the application.

Output paths are new private directories, never overwritten. Without --output a
new private temporary path is retained and printed. report.json updates atomically
after each step and records passed/failed/not_run/interrupted states, exit codes,
elapsed time, selected cases and the executable digest. Logs and PNGs contain only
fixture data but remain sensitive artifacts. The runner fails fast; a failed or
interrupted run is not presented as complete coverage. Interrupt cleanup terminates
and reaps the child process group, escalating only if it will not exit. Escaped
descendants remain outside that containment, as for the application runner.
The normal Python unit check tests planning, report transitions, failure/interrupt
handling and cleanup with injected callables/mocks, not real UI subprocesses.

All previews currently use the macOS Menlo font. The report is fixture regression
evidence, not a visual-quality verdict, provider/sandbox audit, clean-OS validation
or public release gate. Inspect relevant captures. CLI invocation/execution and
package reproducibility/install checks remain separate commands.

`test_search_navigation` traverses all 20,000 matching results and verifies ordinal,
message identity, wraparound and one-shot seeks. Reordering preserves selected ID
with a new ordinal; selected-match removal chooses a valid replacement; replacing
with a single result and clearing remove old membership. Tests have no performance
threshold. The full fixture UI suite retains actual search count/highlight/input
coverage. One initial parallel process test hit its existing invalid-event cleanup
one-second assertion; it remains unrelated/undiagnosed, with no deadline changes.

## Error teardown timing: observed phase separation

On November 18, 2026, temporary instrumentation reproduced the parallel
`invalid event cleanup bounded` failure. Spawn returned in 0.000950 seconds;
the first malformed-event record was delivered at 2.274373 seconds. Cleanup
started at 2.274400 and ended at 2.274968 seconds: about 0.568 milliseconds.
The original assertion timed the entire run, so this failure did not demonstrate
slow teardown. Another fixture in the same run also delayed first output beyond
two seconds. The underlying startup delay is still undiagnosed. No general
macOS/Spawn defect or improvement in runtime launch latency is claimed.

Temporary runtime instrumentation was removed, with Process restored byte-for-byte.
The invalid-event test emits a valid readiness event immediately before its malformed
record and times teardown from delivery on the existing monotonic clock. The callback
exception test times from entry into its failing callback. Both retain the one-second
cleanup bound and now assert the specific error and direct-child reaping. A fixture
that deliberately waits 1.1 seconds before readiness proves that startup is not
counted as teardown. Separate timeout/cancellation and inherited-pipe bounds remain
unchanged. Shell fixtures remain because JSONL delivery and descendants are the
boundary under test. These checks do not guarantee arbitrary script startup time.

Task-update unit checks cover distinct stream/tool/run keys, stale-event exclusion,
compact badge text, board-only and modal-obscured retention, visible detail clearing,
restore reset and snapshot isolation. The board-history PTY now selects another task,
appends two chunks of one background message, checks one badge, completes the run,
verifies the badge follows Ready while selection stays fixed, then inspects that
card and checks badge clearing. No agent, credentials or real workspace are used.

`test_stream_identity` supplies colliding user and output IDs to the reducer and
checks start/send refusal, overlapping run-prefix history, legitimate replacement,
queued and sent user-record preservation, failure stickiness through successful
exit events, snapshot validity and rendered diagnostics. The corrupt in-memory case
is a guard test, not a claim that the loader permits corrupt snapshots. No agent,
credentials or real workspace are used. The full UI suite exercises normal stream
replacement, movement and persistent conversations separately.

`test_id_allocation` covers stale task/reply/run counters, tool/output namespace
collisions, max-int wrap, unchanged ordinary sequences and retained-record isolation.
It restores a strict snapshot, creates a unique task/reply and roundtrips updated
state. A temporary SQLite save/reopen case starts from a stale counter and saves
one new task without rewriting old identities. No agent, credentials or real
workspace are used; demo-start coverage uses only scheduled fixture events.

Run-status tests inject a persistence warning and reduce accepted start/message/
completion/failure/stop events. They verify the footer warning survives, task state
still changes and events remain queued for persistence. Rendering checks visible
warning text. This is a controller priority test, not a PTY database-failure probe
or automatic storage recovery test; real temporary database errors are tested by
the persistence suite.

Task-attention unit checks cover awaiting input, failure, interruption, latest-run
selection, missing history, Ready omission, update coexistence and snapshot isolation.
The queue-summary replay PTY additionally checks the seeded question card and the
interrupted task's board reason after returning from chat. Full diagnostics remain
in conversation; no model or real workspace is accessed by this fixture.

`test_reply_visibility` composes from paused history, submits successfully and checks
visible exact text, follow state, unchanged active run and independent Activity memory.
It repeats with an older search match, then checks empty failed submission and unsent
Escape preserve position. The board-history PTY queues a reply after Home and verifies
it appears without starting a run. No model or real workspace is used.

`test_input_feedback` covers visible submission errors, retained editor/message state,
cursor-only feedback, recovery, model immutability, storage-warning priority, blank
task validation and limit-warning precedence. `smoke-input-feedback.py` exercises
empty reply, invalid model correction, and blank task recovery through actual terminal
input in isolated HOME/XDG with an empty replay. It uses no agent or storage and is
included in check-ui.py. Preview captures the editor with its error line.

Input-feedback tests also submit valid reply/model/task edits under an injected
persistence warning. They verify accepted local values, cleared field validation,
visible Storage error after editor exit and no additional run. This is a pure
controller/rendering priority check, not a PTY disk-failure or recovery probe.

Acceptance summary tests retain a queued follow-up and unsent draft through Done,
roundtrip the strict codec, inspect archived state and verify read-only hitboxes,
width limits and storage-warning priority. The board-history PTY accepts a Ready
task with two pending instructions and a draft and checks visible retention markers
without reply/run controls. No model or workspace operation is used.

`smoke-restart-selection.py` builds a temporary board with one active task and one
selected accepted task, including its retained draft. Two real UI restarts verify
accepted chat selection, independent active counters, read-only controls, expanded
answer and exact saved tasks/drafts/selection. HOME/XDG are isolated; no agent or
workspace operation is used. The case is included in check-ui.py. Unit restart and
onboarding tests cover accepted selection, empty filters, absent IDs and empty state.

## End-to-end performance

`scripts/bench-e2e.py` measures the real binary through a PTY against temporary
SQLite and replay workloads. See `docs/performance.md` for commands, parameters,
raw samples, resource attribution and observer limitations. `passed` establishes
correctness of the measured workflow, not a latency budget. Pure report/statistics/
fixture tests run through `scripts/check.sh`; the benchmark remains opt-in.

The pure `scripts/test-compare-e2e.py` suite checks successful self/candidate
comparison, zero baselines, metadata mismatches, incomplete/invalid samples,
resource uniqueness and CLI refusal. The comparison command rejects the two
checked-in scale workloads as incompatible rather than treating scale as a
candidate regression. It runs no executable or external service.

## Startup config preview

`python3 scripts/smoke-config.py` checks the --check-config CLI using temporary
HOME/config/storage paths, a deliberately invalid untouched database and a must-
not-run executable. It covers path resolution, defaults/override, invalid configs
and conflict rejection without requiring a terminal. Pure Config_preview checks
run with dune runtest. Package smoke checks the standalone preview command and
included configuration instructions. Setup checks establish syntax/resolution,
not that a path, revision, database or model is usable.

## Continuous factory workflow

The `workflow` case in `scripts/check-ui.py` runs
`scripts/smoke-workflow.py` against a temporary jj source/workspace and SQLite
board. It covers create, cancellation, confirmed fake run, real diff review,
acceptance with retained draft and read-only restart in one continuous flow.
It checks exact prompt/policy, one invocation, source preservation and unchanged
persisted history on restart. No installed agent, real model or credentials are
used. Explicit diff refresh remains a user action. The UI catalogue now has 18
cases; the fake runner demonstrates integration, not real sandbox enforcement.
