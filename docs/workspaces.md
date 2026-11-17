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
source, destination, exact base commit, and name through accessors. Identity
association with persisted tasks and the creation form are the next increments.
There is no UI workspace-creation action in this commit.

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
