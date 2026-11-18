# Startup configuration checks

Use an explicit TOML file to keep launching the factory simple:

```toml
[storage]
database = "board.sqlite"

[workspace]
jj = "/absolute/path/to/jj"
source = "/absolute/path/to/source"
parent = "/absolute/path/to/task-workspaces"
revision = "main@origin"
model = "your-model"

[layout]
board_width_percent = 55
board_height_percent = 40
```

All sections are optional. Storage omitted means memory-only. Workspace values
prefill the creation form; they do not create a repository, fetch a revision or
start a run. Layout percentages must be in 10..90. Relative paths in TOML resolve
against the config file's directory. `~/` uses HOME. Keep credentials out of this
file; gateway configuration is separate (`docs/gateway.md`).

## Check, then launch

```sh
factory-tui --check-config /path/to/config.toml
factory-tui --config /path/to/config.toml
```

The check works without a terminal. It prints JSON describing the validated and
resolved settings. It opens only the explicit config file; it does not discover
default config, open/repair SQLite, run jj, create paths, read credentials or call
a gateway. Unknown fields and invalid TOML fail with exit code 2 and no JSON.
Errors do not print source content. Successful JSON intentionally includes the
configured paths and model/revision defaults; inspect it before sharing.

Preview a database override:

```sh
factory-tui --check-config /path/to/config.toml --database /other/board.sqlite
```

The override uses the same path rules as launching the app: relative CLI paths
use the current directory, not the TOML directory. Other execution/check modes,
`--config` and `--no-config` are refused alongside `--check-config`. Validation
success does not establish that paths exist, are writable, name a compatible
SQLite database, or that a source revision/model is usable.

## Explicit live execution

Ordinary launch is the real configured board; --demo explicitly opens simulation.
Startup does not start an agent. A real launch uses configured SQLite and discovers
Codex on PATH (or uses an explicit override).
Enter sends the task/reply; no per-run confirmation dialog is used. Requested
workspace writes additionally require `--workspace-write`. Gateway protocol/model
compatibility remains a separate integration boundary. Checking settings is not
permission to start agents or spend tokens.

The pure config-preview tests and `python3 scripts/smoke-config.py` verify setup
using temporary files, including a deliberately invalid database that must remain
unchanged and an executable sentinel that must never run.

## Saved Codex launch defaults

Keep repeated launch settings in a non-secret `[codex]` section:

```toml
[codex]
executable = "/absolute/path/to/codex"
gateway = "litellm.toml"
reasoning_effort = "low"
```

Optional executable overrides and gateway-file paths resolve relative to the config file, with the
same HOME expansion as workspace paths. Reasoning accepts low, medium or high.
All three values are optional. CLI executable/gateway/reasoning options override
these defaults for the current live launch. `--no-config` ignores them.

Configuration never enables live mode or starts a request/run. Use:

```sh
factory-tui --live-ui --config /path/to/config.toml
```

If the config is stored at the default location, no flags are needed.
SQLite remains required; writes require `--workspace-write`. Startup starts nothing. Invalid
Codex settings fail parsing even in a non-live launch rather than being ignored.
`--check-config` previews the defaults without opening the executable or gateway
file and explicitly reports `enables_live_mode: false`.

`examples/live-test.toml` is a user-editable generic template. Copy it to your own
config directory, place the environment-only gateway config beside it, and edit
model defaults and any optional path overrides. Never store an API key in either file. The configs
under `test/configs/` are fixture-only templates copied into temporary directories
by the UI tests; they are not ready-to-run real-provider configurations.

Optional `[projects.NAME]` tables provide project shortcuts; they are not required
for creating folder-rooted or greenfield sessions. See `docs/sessions.md` for
project fields, creation modes, working-root semantics and review limitations.

## Interactive setup

From a checkout, run:

```sh
./scripts/setup.sh
```

The wizard discovers Codex on PATH and asks for gateway URL/key **environment variable
names**, optional provider-discovered model default, reasoning preference and
storage path. It validates paths and the generated config,
then asks before saving. Model discovery is offered after an explicit notice that
it contacts the gateway
and reads the referenced key. Fetch is the default choice; Skip performs no
request. Setup never initializes repositories, creates workspaces or launches
an agent. A missing local TUI binary is built only to validate the config.
Search the returned catalogue and select a numbered model, or skip the default
and select per task. Retry and manual entry are available if discovery fails.
Do not paste a key into a model or variable-name prompt.

Saved `config.toml` and `gateway.toml` are private (0600); newly created config
folders are 0700. Existing config files—including symlinks—are never overwritten.
For a separate test setup, use `./scripts/setup.sh --config-dir /path/to/new-config`.
Cancelled setup saves no files (an explicitly chosen discovery request may
already have occurred). If publishing either file fails, the wizard removes
only files it created during that save; it does not delete pre-existing files.

Setup saves `[workspace] mode = "folder"` without a source path. New tasks start
in the directory where you launch the TUI; setup never asks you to name a project
or prepare a session folder. The form focuses the task instruction and hides
unused jj, parent and revision fields. Starting directory and model remain editable.

For advanced configurations, `mode = "existing"` or `"greenfield"` still selects
repository creation. Older configs keep their previous mode and explicit source
paths. A saved mode never enables live runs or writes.

After setup, the wizard prints the read-only launch command. For the default
config location this is also:

```sh
./scripts/run.sh --live-ui
```

Enter sends work directly. Add `--workspace-write` deliberately
when needed; folder roots are existing working directories, not isolated copies.

A selected setup model is only the default for future task creation. It does not
change saved tasks or recorded runs. Skipping omits the model from TOML; on a fresh
live board the task form starts with no model and requires a task-specific choice.
Existing task settings and the prior-task prefill remain intact. Discovered IDs
are catalogue entries, not proof of Codex protocol compatibility.

For everyday use, launch from the directory you want the task to work in:

```sh
cd /path/to/your/project
/path/to/factory-tui/scripts/run.sh --live-ui
```

Each created task records its resolved starting directory. Reopening it from a
different directory does not move that task. New tasks without an explicit source
override use the new launch directory. Agents may navigate and create subprojects
with their tools according to the configured execution policy; the TUI does not
automatically create an isolated workspace or expand write permissions.

## Everyday launch and send

Real interactive mode is now the default:

```sh
cd /path/to/project
/path/to/factory-tui/scripts/run.sh
```

No agent runs at startup. Missing config prints setup guidance. `--demo` explicitly
opens simulation; `--live-ui` is retained for compatibility. Default real launch
refuses stored demo-run history: use --demo for that database or a separate real
board. Existing explicit live fixture/import behavior is not silently changed.

Enter sends a new task or idle reply directly—there is no per-run confirmation.
Creating a repository/folder task completes before its run starts. An active run
keeps later replies pending for the next turn; it does not accept stdin injection.
Ctrl-S saves a task without running it. `s` sends/retries pending instructions.
Read-only remains the default filesystem policy; opt into --workspace-write for
writes. Sending through your provider can consume usage. Setup configures provider
defaults, not permission bypass. Archive navigation uses `d` to toggle, `b` to
return to a visible session board, or Escape from the archive board.

Codex and jj executable paths are optional overrides. Normal launch discovers
`codex` on PATH, and new repository tasks discover `jj` on PATH. Setup performs
this discovery without asking you to locate executables. Folder-root tasks need
no jj executable. A missing tool produces install/override guidance rather than
running shell commands or guessing a machine-specific path.
