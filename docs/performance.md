# End-to-end performance baseline

Use the benchmark before adding interaction or optimizing the event loop. This is
an opt-in local measurement, not a claim that the TUI is faster than the native app.
It starts no agent, reads no credentials, calls no gateway, and touches no real
workspace. All application data and HOME/config paths are temporary.

## Run

Build once, then measure the exact executable:

```sh
./scripts/check.sh
uv run --with pyte python scripts/bench-e2e.py \
  --binary _build/default/bin/main.exe \
  --report /tmp/factory-e2e-baseline-new.json
```

Without `--binary`, the command builds before measuring. Do not run Dune,
formatting, package tests or other PTY suites at the same time. Close unrelated
heavy work if you want comparable local samples. Select a new report path; an
existing report is not overwritten.

Defaults: three launches per workload, five interaction cycles per launch,
200 SQLite tasks, 200 historical messages in the selected conversation, 120x36
terminal cells. Adjust `--runs`, `--interactions`, `--tasks`, `--messages`,
`--columns` and `--rows` to explore scale. The transcript must have at least as
many messages as terminal rows so history navigation has distinct screen states.
Terminal sizes are bounded to 100..300 columns and 24..100 rows. A failed screen
expectation fails the run; `--timeout` is a correctness deadline, not a latency
budget. No samples are removed as warmup or outliers.

## Workloads

**SQLite interaction:** seed an isolated database, then repeatedly launch the
real binary with it. Measure launch to selected conversation, board search for a
specific task, clearing the filter, card navigation, chat expansion, entering
insert mode, bracketed paste, queueing the reply, history top/latest, returning
from expansion, board focus and shutdown. Each launch retains earlier replies.
After shutdown, inspect SQLite for exact original history, ordered queued reply
text, unchanged other tasks, selection and cleared draft. These checks make
persistence part of the end-to-end workflow, not just a timed process launch.

**Replay updates:** launch the memory-only six-task fixture board with the supplied
historical-message backlog. Measure launch until the last supplied historical
message is visible, then repeated replacements of one stream item and the event
pair that moves Working to Ready. Selection must remain attached to T-102. Replay
supplies events; it is not a model or process-supervision throughput benchmark.
The replay task count stays six; `--tasks` scales the SQLite board only.

## What the report means

- Latency starts immediately before writing input or an event. It ends at the
  first parsed PTY screen that satisfies the expected state. The observer drains
  output without the smoke driver's fixed post-input waits. A state already
  present before the action is rejected rather than reported as zero latency.
- Measurements include the app loop, rendering, terminal transport, Python/pyte
  parsing and scheduling. They do **not** include a terminal GUI's paint/display
  latency. An expected visible state is not proof the whole frame has finished.
- Search includes a complete typed query and Enter, and paste includes the full
  bracketed payload. They are not single-key render costs. Compare like actions.
- Shutdown includes PTY drain, process exit and SQLite flush, with up to 10 ms
  exit-observation quantization. Repeated launch is not a cold-OS/cache benchmark.
- Raw milliseconds, count, median, nearest-rank p95 and maximum remain in the
  report. Three launch samples give weak tail evidence; use more runs before
  drawing conclusions about startup p95.
- Two RSS samples per workload inspect only the main TUI process. They are not
  peak memory. Child CPU includes the TUI and the two `ps` samplers, but excludes
  fixture bootstrap/build. Observer CPU is reported separately. Terminal-byte
  counts stop before shutdown. No agent descendants run in this benchmark.
- Report metadata includes platform, architecture, Python/pyte versions, workload
  dimensions, binary size/SHA-256 and benchmark SHA-256. Compare only compatible
  workloads and observers. Reports are atomic private files (0600). Failed or
  interrupted runs retain completed samples and the last named interaction.

`passed` means the benchmark completed its correctness checks. It does not mean
latency met a release target. Do not gate CI on these local observations yet.
First establish repeatability and choose explicit budgets for important actions.

## Test the measurement helpers

```sh
python3 scripts/test-bench-e2e.py
```

This pure test is included in `scripts/check.sh`. It mocks the terminal import;
no pyte installation, TUI, database or process is required. It checks statistical
summaries, fixture construction, pre-existing-state refusal and private reports.
The benchmark command itself is the end-to-end verification and stays opt-in.

## Initial local observations — November 18, 2026

macOS 26.7.1 arm64, Python 3.14.5, pyte 0.8.2. The reports contain exact runtime
versions and executable/observer hashes. Retained evidence:
`docs/verification/e2e-perf-200-20261118.json` and
`docs/verification/e2e-perf-1000-20261118.json`.

| Median, milliseconds | 200 tasks/messages, 120x36 | 1,000 tasks/messages, 180x50 |
| --- | ---: | ---: |
| SQLite launch to selected chat | 33.87 | 33.90 |
| Complete typed board search | 312.22 | 1,411.49 |
| Card navigation | 21.38 | 60.48 |
| Queue reply | 34.56 | 107.95 |
| Stream replacement | 132.25 | 137.60 |
| Launch through replay history backlog | 324.01 | 2,427.05 |

The smaller case used 3 launches and 5 interaction cycles (15 action samples).
The larger case used 2 launches and 2 cycles (4 action samples). Maximum sampled
SQLite RSS was about 15.0 MiB and 26.4 MiB respectively; these are not peaks.
Both scale **terminal size and data**, so the table cannot isolate the cost of
adding tasks or messages. The observer itself used substantial CPU; these values
are end-to-end screen-observation costs, not application-only render timings.

Search and backlog are useful places to investigate before layering more
interaction. Do not infer a bottleneck's cause from this table alone. Repeat with
one dimension changed at a time, then profile the relevant application and
observer work separately. No timing target, model throughput or GUI advantage is
claimed by either run.
