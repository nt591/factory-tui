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
option-like revisions, and Git-only/relative sources. Plain command stdout/stderr,
output limits, literal arguments, and timeout/reaping checks use the separate
compiled `test_command` fixture; see `docs/testing.md` for their scope.

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
recent workspace-backed task, including after restart. The jj executable remains explicit and the task instruction starts blank.
Optional `[workspace]` startup defaults can prefill jj/source/parent/revision/model
without any process or directory creation. Configured fields override remembered
values; unspecified fields keep task-derived defaults. jj changes in creation or
review are reused during the session, then restored from config on next launch.

Form/controller tests and the PTY smoke create workspaces only in temporary jj
repositories. They cover modal keyboard/mouse isolation, paste safety, field
navigation, background creation, Queued/no-run state, persistence and reopening,
and retaining an existing destination after a failed duplicate creation.

## Changes review pane

Press `v` on a workspace-backed task. The full-screen changes pane keeps the task
ID/title attached to its own review object. It does not start a command on opening.
Enter an absolute jj executable if needed (`i` edits it), then press Enter or `r`
to refresh. Refresh snapshots the workspace and reads the diff relative to its
recorded base on a background worker. The pane distinguishes not-loaded, loading,
empty diff, patch, and error states. Paths are remembered for this application
session after creation or review, not silently guessed from a global install.

`j/k`, Page Up/Down, and the mouse wheel scroll; `g/G` goes to top/bottom.
Page keys use the visible patch height. Ctrl-U/D moves a half-page, and Ctrl-B/F
moves a full page, using the same visible patch height. These controls do not
navigate or edit the path while the executable field is active; only plain Enter
refreshes that field. Modified shortcuts do not implicitly run jj. `]` jumps to the next file, and `[` jumps
to the previous file. Multi-file patches also show clickable Prev/Next file buttons.
File jumps put the header at the top, even for a short final file, and reset the
horizontal offset. Navigation stops at the first/last file rather than wrapping.
The footer shows the current file number/count and supplied path. Quoted paths
remain opaque display text; navigation never uses them as command arguments.
The diff uses addition/deletion/hunk colors and preserves line text without word
wrapping.
`h/l` or Left/Right scroll long lines horizontally in four-cell steps; `0`
returns to the start. Ctrl-wheel also scrolls horizontally. The footer shows
the current column offset. Cropping uses terminal cells, not UTF-8 byte offsets.
Widening the terminal clamps any unneeded offset; refreshing resets the viewport.
Path editing treats h/l as literal text and does not move the diff. Escape returns to the same task
chat; it does not accept the task. During a bounded refresh, close waits for
completion rather than abandoning a worker; shutdown joins it. Review blocks
underlying board, run, and acceptance shortcuts. Its buttons are clickable.

A task with no workspace shows an error instead of a demo patch. Patches are
read on explicit refresh and not saved into the conversation database. Each review
owns its task ID and workspace; results cannot update another task's chat.
`Changes` owns the background job, `Review` owns input/scroll state, and
`Review_view` renders the result. `Diff_document` indexes immutable patch lines
and file headers once per loaded result; its representation is abstract. Header
recognition ignores added lines and hunk content when deriving file labels.
Their interfaces hide worker handles and state representation. Tests and the PTY
smoke verify real added files in a temporary workspace, empty/error states, modal
isolation, file/viewport navigation, scrolling, and return to chat.

`Diff_display` prepares sanitized rows and maximum terminal-cell width once when a
patch loads. Rendering measures only visible rows; horizontal clamping reads the
cached maximum. Scrolling and resize reuse this data, while refresh discards it.
The raw `Diff_document` stays unchanged. This uses extra memory for sanitized
lines so large patches are not repeatedly scanned on the foreground redraw path.
A synthetic measurement of this specific preparation work is in `docs/testing.md`;
it is not a full UI-performance or native-app comparison.
