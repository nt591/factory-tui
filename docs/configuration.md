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

Ordinary launch is simulation. Config does not enable live agents. A real live
launch separately requires `--live-ui --codex-executable /absolute/path/to/codex`,
SQLite, an explicitly created workspace task and per-run confirmation. Requested
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

Executable and gateway-file paths resolve relative to the config file, with the
same HOME expansion as workspace paths. Reasoning accepts low, medium or high.
All three values are optional. CLI executable/gateway/reasoning options override
these defaults for the current live launch. `--no-config` ignores them.

Configuration never enables live mode or starts a request/run. Use:

```sh
factory-tui --live-ui --config /path/to/config.toml
```

If the config is stored at the default config location, only `--live-ui` is needed.
SQLite remains required; writes still require separate `--workspace-write` and
per-run confirmation. A no-flag launch does not enable live execution. Invalid
Codex settings fail parsing even in a non-live launch rather than being ignored.
`--check-config` previews the defaults without opening the executable or gateway
file and explicitly reports `enables_live_mode: false`.

`examples/live-test.toml` is a user-editable generic template. Copy it to your own
config directory, place the environment-only gateway config beside it, and edit
source/workspace/model paths. Never store an API key in either file. The configs
under `test/configs/` are fixture-only templates copied into temporary directories
by the UI tests; they are not ready-to-run real-provider configurations.

Optional `[projects.NAME]` tables provide project shortcuts; they are not required
for creating folder-rooted or greenfield sessions. See `docs/sessions.md` for
project fields, creation modes, working-root semantics and review limitations.
