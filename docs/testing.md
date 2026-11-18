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
- `scripts/smoke-codex-local.py` and `scripts/smoke-codex-sandbox.py`: explicit
  opt-in installed-Codex loopback checks with dummy credentials. Never part of
  normal tests or a real-provider/model approval.

All fixture output is evidence of fixture behavior only. A simulated completion
must not be represented as a real source-code or model verification result.
