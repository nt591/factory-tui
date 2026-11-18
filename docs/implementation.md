# Implementation sequence

This plan adapts the product and implementation sequence in `../factory/README.md`
and its development instructions. The native application is a reference, not a
runtime dependency. Implement the core in OCaml. Do not modify the native checkout.

## Product contract

A board of self-updating agent sessions. Each task opens a persistent work channel
and has an isolated workspace. Select a headless harness and gateway model for
each run. Keep past run selections immutable.

Columns: Queued, Working, Needs you, Ready. Only explicit acceptance marks Done.
Completion needs validated harness events and a successful process outcome.
Replies sent during work queue for the next turn unless explicitly interrupted.
Acceptance does not merge, push, or delete a workspace.

## Steps and gates

1. **Terminal shell — complete.** Build and launch the OCaml/Notty executable.
   Verify terminal cleanup, resizing, mouse input, and visible focus.
2. **Simulated sessions — complete.** Typed reducer, stable task/run identity,
   channels, stream-item replacement, and event-driven movement. Reject stale
   events. Selection follows task identity when its state changes.
3. **Composition and run selection — complete for simulation.** Queued replies,
   task-specific drafts, simulated acceptance, harness/model selection, and
   immutable run records exist. Tests verify edits affect only the next run.
   Models and harness selections do not establish live compatibility.
4. **SQLite persistence — complete for simulation.**
   The versioned snapshot codec retains tasks, drafts, selection, and run records.
   SQLite stores snapshots, a separate run table, and cursor-paged ordered events
   in one transaction. Temporary-file tests verify reopen, exclusive ownership,
   rollback, private new-file permissions, unsupported databases, and recovery.
   A background worker coalesces snapshots and retains bounded event batches.
   The UI saves through explicit TOML configuration or `--database`; no config
   means memory-only startup. Tests cover 200 queued saves, final flush, write
   errors, and PTY save/reopen with task drafts and interruption recovery.
   Both explicit headless execution and confirmed live UI runs now acknowledge
   their Working checkpoint before spawning.
   Unconfigured launches create no database. Stored conversations are sensitive.
5. **Codex supervision — process/fake UI and explicit headless path implemented.**
   The Codex-style decoder, bounded runner, and background delivery handle are
   tested with fake executables. `--fake-harness` starts nothing on launch; an
   explicit Start streams fixture events into chat. Stop/shutdown cancel and join.
   With SQLite, the Working checkpoint is acknowledged before spawning. Tests
   verify checkpoint refusal, stream replacement, queued replies, and stored
   process events. Details: `docs/harness.md`. The invocation builder validates
   model/directory and explicit resume identity and requests read-only execution.
   Loopback verifies installed Codex; real gateway behavior remains unverified. `--dry-run-codex` exposes
   a structured invocation preview with no executable, credential, or database
   access. CLI tests verify no process side effect and rejection of conflicting
   modes. `--run-codex` explicitly executes with a required database and stdin
   prompt, preserving known events and non-simulated run origin. Fake tests cover
   resume identity, cancellation, malformed output, and checkpoint refusal.
   Installed Codex 0.166.0 execution and resume pass an isolated loopback fixture.
   Confirmed live UI integration passes fake-process tests and the PTY smoke.
   `--live-ui --workspace-write` explicitly selects task-directory write policy,
   shown in confirmation and captured per run. Fixture editing/review is tested.
   Real gateway UI behavior, sandbox enforcement, and approvals remain unverified.
6. **Gateway setup — validation and provider builder complete; integration pending.**
   `Gateway` validates a capped non-secret TOML file, HTTPS/loopback endpoints, and
   environment-key references without reading secrets or contacting the network.
   `--check-gateway` validates without opening storage or starting agents. Codex
   provider overrides are pure and tested for new/resumed threads. Details:
   `docs/gateway.md`. Installed-Codex headless loopback checks pass; real gateway
   checks remain pending. Setup starts no agent and reads no secret.
   Dry-run invocation must disclose no credentials. Verify protocol compatibility
   against a loopback fixture before an explicitly requested real gateway check.
   Configuration validity does not prove model compatibility.
7. **Isolated jj workspaces — creation and changes review integrated.**
   `Workspace` resolves an exact base and creates a new destination outside the
   source checkout without fetching or integrating. `Workspace.diff` returns a
   bounded real patch. Temporary-repository tests verify isolation, exact parent,
   source preservation, and rejection of unsafe inputs. Details: `docs/workspaces.md`.
   Workspace identity is attached before the first run and persisted with task
   snapshots; legacy tasks still load. `W` opens a modal creation form when SQLite
   is configured. A bounded background job creates the workspace, then selects its
   Queued chat without starting an agent. Form and PTY checks verify input safety,
   persistence/reopening, and isolation. `v` opens explicit background diff review
   with real patch/empty/error states and task-bound result ownership. Horizontal
   scrolling uses terminal cells, with h/l, arrows, 0, and Ctrl-wheel verified on
   long Unicode lines. Review never
   accepts, integrates, or deletes. `--live-ui` explicitly enables confirmed
   workspace-backed Codex execution with a durable Working checkpoint. Acceptance
   remains separate from merge and push. Live calls require explicit live mode;
   workspace creation and review require explicit user actions.
8. **Local distribution and lifecycle — implemented; release portability pending.**
   Vim navigation, repository sidebar,
   bordered cards, grapheme-aware multiline editing/paste, anchored reading views,
   transcript search,
   Help/Settings tabs,
   and terminal smoke tests
   exist. UI guidance and visual verification are in `docs/ui-parity.md`.
   Standalone install and repeatable local archive packaging include build metadata,
   dependency lock, operational docs, and temporary-install checks. Signing,
   notarization, and fresh-machine lock reconstruction are not verified. Local
   build/footprint measurements are in `docs/distribution.md`.
   Do not claim a GUI performance advantage without a comparable measurement.

A step can require several tested commits. Keep storage, process supervision,
and UI integration in separate increments when this makes validation clearer.
Do not mark a step complete from a mock test that does not cover its live boundary.

## Commit workflow

The repo is already jj-initialized. Do not initialize it again or rewrite the
existing tested history. No remote is configured; do not fetch or push.

For each increment:

```sh
./scripts/format.sh --check
opam exec --switch=. -- dune build @install
opam exec --switch=. -- dune runtest --force
# Run the PTY smoke when input, rendering, or lifecycle changes.
uv run --with pyte python scripts/smoke-terminal.py
git diff --check
jj commit -m "[factory-tui] Describe the tested increment"
jj bookmark set main -r @-
```

Update this plan and README with verified behavior and remaining limits in the
same commit. Keep business logic out of `bin/main.ml`. Follow the subsystem layout in
`docs/modules.md`; keep implementation/interface pairs together. Tests must not use live
agents, credentials, or real workspaces. Preserve simulation labels until an
explicit live path exists. Never push without an explicit request.

## Optional compiler follow-up

OxCaml is deferred at the user's request. Continue on the verified standard OCaml
switch. `docs/oxcaml.md` records the bootstrap failure, interrupted newer attempt,
and required application/editor checks before adopting compiler extensions. This
TODO does not block any of the product steps above.

Demo seed data and fake runners live in `lib/demo` as `Demo.Seed` and
`Demo.Runner`. Runner ownership is abstract and delivery uses a callback context,
so fixture implementation does not depend on the terminal controller.

## Current audit

`docs/audit.md` maps the original UI/product requirements to inspected source,
tests, terminal behavior, and packaged execution. Read-only execution, real gateway
compatibility, and fresh-machine release validation are not claimed complete.
