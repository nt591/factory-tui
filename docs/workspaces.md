# Isolated jj workspace API

`Workspace.create` takes an explicit absolute jj executable, source checkout,
destination, and revision. It resolves the revision to exactly one full commit
ID with `--ignore-working-copy`, then creates a named workspace on that exact
parent. The destination must be new, outside the source checkout, and have an
existing parent. Symlinks in parent paths are resolved before the containment
check. The source must already be a jj checkout; Git-only conversion is never
performed automatically.

No fetch, bookmark change, merge, push, or workspace deletion occurs. Ordinary
`jj workspace add` can snapshot the source's uncommitted files into its current
working-copy commit. It does not edit those files or move the source checkout.
Any UI creation action must disclose this behavior before submission.

If creation fails after making a partial destination, retain it for inspection.
The API does not delete or retry a failed creation. Workspace handles expose
source, destination, exact base commit, and name through accessors. Workspace identity can be attached to a queued task before its first run and
round-trips through SQLite. Older snapshots without workspace metadata still load.
Attachment cannot replace a workspace or redirect existing run history. Restoring
metadata validates its structure; it does not prove the directory still exists.
The explicit `W` creation action is available when the TUI uses SQLite storage.

## Review

`Workspace.diff` runs `jj diff --from <recorded-base> --to @ --git` inside the
isolated workspace. This snapshots the workspace to include current files. It
returns the real patch; it does not invent a sample patch or apply changes.
Acceptance remains a task-state decision, not integration or deletion.

Commands use direct argument arrays through Spawn, never generated shell command
strings. Stdout is capped at 2 MiB and stderr is drained with the same cap but
not retained or printed. The timeout is 15 seconds using the monotonic clock.
Failed jj commands return a generic error instead of leaking repository output.
The `Command` module supervises this plain-text output separately from harness
JSONL decoding. It is not a security sandbox for an arbitrary supplied executable.

## Verification

`test_workspace` initializes temporary jj repositories only. It verifies exact
parents, distinct task workspaces, inclusion of new files in patches, untouched
source files, rejection of existing/nested destinations, multi-commit revsets,
option-like revisions, and Git-only/relative sources. It also checks plain command
stdout/stderr handling, output limits, and bounded timeout cleanup.

No tests create a workspace in a real repository or start an agent. The test's
jj executable is the installed `/opt/homebrew/bin/jj`; application APIs require
an explicit path rather than silently selecting that installation.

## New workspace task UI

Configure storage with TOML or `--database`, then press `W` (or click Workspace
Task in the wide sidebar). The modal collects an absolute jj executable, existing
source checkout and workspace parent, explicit revision, next-run model, and task
instruction. Tab / Shift-Tab select fields; arrows/Home/End edit; Enter moves to
the next field. Ctrl-S or the Create button is the only submission action. Paste
cannot submit or invoke a background command. Escape cancels before submission.

Creation runs on a background thread. The modal remains open and input is blocked
while the bounded operation completes. Shutdown joins the operation; it does not
abandon a worker mid-creation. The new destination is `factory-<task-id>` under the
selected parent. The task enters Queued with its workspace identity and queued
instruction; no agent starts. The app selects its chat and asynchronously saves
task metadata using the existing persistence worker. If persistence fails after
creation, the directory remains and the storage error is displayed; do not delete
or repeat a creation blindly. Normal shutdown flushes pending saves. Abrupt exit
can leave a created directory without persisted task metadata.

Storage is required rather than silently creating real workspaces in a throwaway
demo board. Replay mode cannot create workspaces. Normal `n` still creates a demo
task only. New forms remember source, parent, exact base, and model from the most
recent workspace-backed task, including after restart. The jj executable remains
explicit and the task instruction starts blank.

Form/controller tests and the PTY smoke create workspaces only in temporary jj
repositories. They cover modal keyboard/mouse isolation, paste safety, field
navigation, background creation, Queued/no-run state, persistence and reopening,
and retaining an existing destination after a failed duplicate creation.
