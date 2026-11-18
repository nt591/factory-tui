# Gateway configuration boundary

Gateway settings are non-secret and separate from the startup storage config:

```toml
base_url = "https://gateway.example/v1"
key_environment = "FACTORY_GATEWAY_API_KEY"
```

`key_environment` is an environment-variable name, not the key value. Do not paste
credentials into TOML. Use either `base_url` or `base_url_environment`, plus
`key_environment`. Unknown fields,
malformed TOML, oversized files, and invalid endpoints fail without echoing source.
Reads are capped at 64 KiB and must come from a regular file.

Validate a file without opening storage, reading credentials, starting an agent,
or contacting any endpoint:

```sh
./scripts/run.sh --check-gateway examples/gateway.toml
```

Validation requires HTTPS, except for HTTP on localhost, 127.0.0.1, or IPv6 ::1.
Endpoints must have a scheme/host and a valid port. URL credentials, query strings,
fragments, whitespace, invalid escapes, and backslashes are refused. This is
configuration validation, not proof that the endpoint is reachable or compatible.

`Gateway.t` is abstract; constructors validate its contents. `Codex.with_gateway`
adds provider settings with a TOML string encoder: named provider, base URL,
environment-key reference, Responses wire protocol, and no OpenAI authentication
requirement. It never reads the referenced variable. Explicit resume remains on
the same exact thread ID, and prompts remain on stdin. Tests cover both new and
resume forms. The provider is available to explicit `--run-codex` and `--live-ui` paths.
Live UI setup alone starts nothing; per-run confirmation is required.

The installed-Codex headless integration passes a loopback fixture; it uses
isolated temporary CODEX_HOME/workspace and a dummy key. No real gateway call
is approved by a passing config check. Live execution and credential access must
remain explicit user actions, separate from setup and application startup.

## LiteLLM environment and model discovery

An exported shell environment can supply the URL without storing it in TOML:

```toml
base_url_environment = "LITELLM_BASE_URL"
key_environment = "LITELLM_API_KEY"
```

Use `examples/litellm.toml`, which contains only these variable names. The program
inherits exported environment variables; it does not read or source `.zshrc`.
Gateway setup and `--check-gateway` resolve and validate the URL variable but do
not read the API key or make a request. URL/reference validation is not network
compatibility. Literal `base_url` configs continue to work.

List models explicitly from the current shell:

```sh
cd ~/dev/factory-tui
./scripts/run.sh --list-models --gateway examples/litellm.toml
```

This command reads the referenced key and makes one authenticated GET to the
configured base URL plus `/models`. For a base ending in `/v1`, it requests
`/v1/models`; a base at the server root requests `/models`. It does not invent
or retry a `/v1` prefix. Check that your exported URL matches the API base you
intend to use. Model IDs are sorted, deduplicated and emitted as JSON. An empty
catalogue is valid. `compatibility_verified` stays false: a listed model is not
proof that Responses streaming, tools or Codex resume work.

Discovery uses `/usr/bin/curl` with TLS verification and user curl config disabled.
Redirects are not followed. Authorization and URL go through bounded stdin, not
process arguments or temporary files. The key is used in process memory and can
be inherited by the HTTP client; this is not isolation from same-user inspection.
Responses are capped at 1 MiB/10,000 model IDs, with 5-second connection and
10-second request deadlines. The outer process is bounded to 12 seconds and is
reaped on errors. HTTP failures and transport errors do not print untrusted bodies
or stderr. Recognized authentication, endpoint, rate-limit, TLS and connectivity
failures have separate safe diagnostics. Credential echoes in decoded model IDs
are withheld, but this is not general protection against transformed secret data.

No agent, database, workspace creation or model-completion request occurs during
discovery. It cannot be combined with execution/storage/check modes. Manual model
entry remains available through `m`; a TUI catalogue picker is a later integration.

## Read-only live test after discovery

```sh
./scripts/run.sh --live-ui --no-config \
  --database "$HOME/factory-live-test.sqlite" \
  --codex-executable /opt/homebrew/bin/codex \
  --gateway examples/litellm.toml
```

Use a new database, `W` to create a task in an isolated jj workspace, and enter an
exact discovered model ID in the form. Start with an instruction to inspect the
workspace without changing files. `s` opens confirmation; inspect all rows before
confirming. `x` stops. A follow-up is queued with `i` and requires another explicit
confirmation. This launch is read-only; restart with `--workspace-write` only when
you deliberately want edits. Real calls can consume tokens and use your key.
Provider/model protocol compatibility still needs this live verification.

The CLI smoke uses a loopback server and dummy key only:

```sh
python3 scripts/smoke-gateway-models.py
```
