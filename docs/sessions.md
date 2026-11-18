# Session working areas

A session is a goal plus persistent chat, queued instructions and immutable run
history. It can start in an existing folder, an isolated checkout of an existing
project, or a new repository. Project registration is optional.

## Creation modes

Open the creation form with `n` in live mode or `W` with SQLite configured.

- **Existing project** (initial mode): enter a jj project repository and workspace
  parent, or use **Projects / Ctrl-P** to select a configured project. Creation
  resolves the revision and makes a separate checkout. It never automatically
  converts a Git-only source, fetches, merges or pushes.
- **Folder root / Ctrl-E**: the Source field becomes **Starting directory**.
  Wizard-generated configs use the launch directory automatically; enter the task
  goal. You can override the displayed directory. jj, workspace parent and
  revision are ignored. Creation records that folder, creates no files/checkouts,
  and starts no process. Codex runs with this directory as its working root.
- **New repository / Ctrl-N**: choose an existing workspace parent and enter the
  goal. Source and revision are ignored. Creation reserves a new task container,
  initializes a backing jj repository and creates a separate working checkout.
  Existing paths are never initialized in place; failed initialization retains
  its partial directory for inspection rather than deleting files.

Ctrl-E/Ctrl-N toggles the respective mode; selecting a registered project returns
to existing-project mode. Other field values remain editable and are retained
when switching. Enter sends and starts the task; Ctrl-S saves without starting it. Model
selection uses **Models / Ctrl-G** and performs no creation or execution.

A folder-rooted task can start in a project or a multi-service working folder:

```text
my-session/
  api/
  worker/
```

Choose `my-session/` as the session root and describe the desired behavior. With
an explicitly selected write policy, the agent can edit those working folders
and create additional project directories inside the root. It does not need a
pre-registered catalogue entry for every directory. Supply copies/checkouts rather
than original repositories when you want isolation. Creation does not copy them
for you, and the task does not automatically import other directories.

## Optional project shortcuts

Projects are local non-secret TOML defaults, not an access allowlist:

```toml
[projects.api]
source = "~/projects/example-api"
description = "API service"
revision = "@"

[projects.worker]
source = "~/projects/example-worker"
description = "Job processing service"
revision = "@"
```

Names must be unique TOML table keys made of letters, digits, hyphens or
underscores. At most 100 entries are accepted. Paths resolve relative to the
config file, with HOME expansion. Registration validates syntax only; it does not
scan, open, fetch or initialize the repositories. Picker filtering matches name,
description and path. A choice fills Source/revision and focuses the goal field;
parent, model and other fields remain unchanged. Manual paths still work.

## Execution and review boundaries

A working root is not a security sandbox. Live runs remain explicit and show the
actual root in Activity and filesystem policy in the launch banner. Read-only is the
default; `--workspace-write` deliberately permits writes according to Codex's
policy, including its permitted temporary directories. This policy is not a
claim of complete process containment, and roots can overlap. Avoid concurrent
sessions on overlapping work areas; current ownership serializes identical
canonical working directories, not all ancestor/descendant overlaps.

Folder roots persist across SQLite restart, follow-up/resume and interruption
recovery. The original queued instruction is not injected twice; later replies
remain queued for a future confirmed turn. No process starts just from opening,
creating or reopening a session. Acceptance keeps history/drafts and performs
no merge, push or workspace deletion.

The existing `v` review is a single jj-workspace diff. For folder roots it reports
that consolidated multi-repository review is unavailable; review each repository
with its own tools. Automatic repository attachment/discovery, consolidated
changes, root creation from the folder mode and agent-managed checkout operations
remain follow-up work. The agent can already organize work under its chosen root
using its tools, subject to the explicit execution policy.

## Verification

The `session-root` fixture runs a fake executable against a temporary folder with
two service directories. It verifies exact working directory/prompt, writes in
both services, a newly created service, Ready movement, persisted root and
request-free restart. The `workflow` fixture uses a registered project, verifies
two confirmed runs and real diff review, then creates a greenfield task without
running it. Pure tests cover root identity, codec/recovery, mode validation,
project selection, new-repository creation and retained partial failures.
No real repository, gateway credential or model call is used in these fixtures.

## Archive and restore

Only Ready tasks can be accepted/archived. Use **Ctrl-A**, not plain `a`; the old
function-key shortcut is disabled. The action bar labels the stronger shortcut.
Archived tasks keep their conversation, run history, working directory, queued
replies and draft. They are read-only until restored. No merge, push or deletion
occurs on archiving.

Click the persistent **Archive** tab above the board to open it. Plain `d` has no action.
Select the task and press **`u`** or click **Restore**
to put it back in Ready and return to the visible session board. This clears board
filters that could hide the restored card, but does not send any retained message
or start an agent. The next send is a separate action. `b` returns to the session
board without restoring a task. Restoration persists across SQLite restart.

## Section navigation

Tab cycles Board → Conversation → Activity; Shift-Tab goes back. The active section
has a heavy cyan boundary. All kanban lanes sit inside one board boundary; a card's
selection marker stays visible when you read its conversation. Use h/l or arrows
on the board to move between lanes. The active board has Working, Needs you and
Ready lanes. Saved tasks that have not run share Working but say Not started; this
does not launch them. Tab does not expand or resize sections; e still
expands explicitly. Narrow terminals show the focused detail when both sections
cannot fit.

Enter on a board card or double-click opens its expanded conversation. Writable
tasks start in insert mode; archived tasks stay read-only. Enter in a conversation
opens its reply editor without changing the view. e only expands. Escape from
INSERT, Conversation or expanded Activity returns directly to the board and retains
the draft. Tab/Shift-Tab leave editing and switch between Conversation and Activity
inside an expanded task. Enter/i resumes INSERT. Startup stays in board navigation.

## Delete a task

Press Ctrl-X while the Board or Archive list has focus to open task deletion.
Press y to confirm; n or Escape cancels. Enter is not confirmation. Bracketed paste
cannot confirm. Running tasks must be stopped with x and finish process cleanup
first. The dialog captures a task ID and rechecks it before deletion.

In a task view, Ctrl-X instead clears the unsent reply buffer. It keeps sent chat,
run history and workspace files. The editor remains in INSERT if it was editing.
Archived task drafts are read-only and cannot be cleared. Delete is disabled in the
command palette until you return to the board; Clear reply buffer is a separate
action. Neither action sends a message or starts an agent.

Deletion is permanent in the TUI: the task, chat, draft and stored run/event rows
are removed. SQLite commits those changes together; the UI keeps the task until
that checkpoint succeeds. Other tasks stay unchanged. Workspace files, external
agent sessions, replay input files and backups are not deleted. This is not secure
disk erasure. Use reversible archiving if you may want to restore the task.

## Commands without leaving your draft

Ctrl-P opens Commands from NAVIGATION or INSERT. Type a title to filter the actions,
use arrows to select and Enter to execute. Open Archive changes the destination;
Accept & archive task changes a Ready task. They are not the same command.
Unavailable actions show a reason and cannot execute. The action's current
availability is checked again when selected.

Escape or Ctrl-P cancels the palette and restores the editor mode, cursor and draft.
Opening, searching and canceling Commands send no message and start no agent.
A navigation command exits INSERT but retains its draft. Reply to agent returns to
the saved draft. Delete task opens the separate confirmation dialog; it does not
delete directly. Other modal forms keep their context-specific controls.

The footer names INSERT and NAVIGATION explicitly. Escape from INSERT keeps your
draft and returns directly to the board. Tab/Shift-Tab switch task panes without
leaving the task; Enter/i resumes INSERT in Conversation.
The Board/Archive tabs remain clickable from INSERT. Opening Archive clears filters
that could hide its tasks; Escape backs out of an archived task to the list, then
from the list to Board. The archive count on its tab is independent of board filters.
