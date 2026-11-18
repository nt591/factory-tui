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
