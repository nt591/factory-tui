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

Press `d` to open Archive. Select the task and press **`u`** or click **Restore**
to put it back in Ready and return to the visible session board. This clears board
filters that could hide the restored card, but does not send any retained message
or start an agent. The next send is a separate action. `b` returns to the session
board without restoring a task. Restoration persists across SQLite restart.
