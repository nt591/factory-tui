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
stream text or queued-message acknowledgements create a new list and rebuild;
task/width changes rebuild even with the same list. Height-only resize and changes
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
anchors, and a changed message list still rebuilds the full transcript. Incremental
per-message wrapping and whole-application performance are not verified here.

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
