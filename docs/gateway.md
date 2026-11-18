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
entry remains available through `m`; `M` opens the TUI catalogue picker.

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

## In-app model picker

On a selected nonaccepted task, press `M` to browse gateway model IDs. Opening
and reopening the picker does not read the key or contact the network. Click
Fetch or press Ctrl-R for an explicit background request. The interface remains
responsive while the request runs: Escape closes the modal without discarding
its job. Requests retain the 12-second transport bound; quitting joins a pending
request and can wait for that bound. The catalogue is cached only for this launch.

Type a literal filter, use arrows/Page Up/Down or the modal wheel to select, and
press Enter or click a row to apply the model to the selected task's next run.
No agent starts. Existing run records and drafts are unchanged; accepted tasks
remain read-only. Escape closes without applying. `m` still offers manual entry
when the picker is closed. For a first task, open the workspace form and use its Models button or Ctrl-G.
Selecting returns to the form and fills only the model field; Ctrl-S remains the
separate creation action. Models require an explicit
gateway in live mode; missing configuration/auth errors stay in the modal.

The fixture `model-picker` UI case uses a loopback server and dummy key. It holds
a request to test closing/reopening, filters a 40-model catalogue, applies a model,
checks caching/auth error/retry, and preserves exact drafts/messages/run records.
It is not a real model or gateway compatibility test.

## Real smoke evidence

On November 18, 2026, a user-authorized TUI call through the user's LiteLLM gateway
and Codex 0.166.0 used `azure_ai/gpt-6.1-sol` with recorded low reasoning effort.
The basic arithmetic answer was `4`; the run completed and the card became Ready.
It used disposable jj/storage/HOME/CODEX_HOME and read-only policy; source was
unchanged and the workspace retained only its original README. The safe report is
`docs/verification/live-sol-low-20261118.json`. No key or gateway address is recorded.
This establishes one no-tools completion, not tools/write/resume compatibility.
The 4.93-second confirmation-to-terminal-state observation is not inference time
or first-token latency. Low effort used a temporary executable wrapper; a native
reasoning setting is not implemented yet.

A second user-authorized arithmetic smoke used a local forwarding recorder that
retained only request shape, HTTP/event timing and usage, not raw prompts, response
content, authorization or gateway address. Evidence:
`docs/verification/live-sol-network-20261118.json`. The Responses request had a
56,069-byte body, seven input items and no tools; usage reported 10,869 input and
five output tokens, with zero reasoning tokens. Codex supplied its own base,
skills and multi-agent instructions in addition to the short question.

The proxy observed HTTP headers at 2.94 seconds, first text delta at 3.18 seconds,
and stream completion at 3.31 seconds from its request handler start. Overall TUI
confirmation-to-terminal-state was 4.29 seconds. LiteLLM reported response duration
1,315 ms and overhead 78 ms; those header scopes were not independently verified.
An additional `/analytics/codex/turn-costs` POST returned 404; it overlapped the
Responses call, so its latency must not be added to the completion latency.
These are single-call observations with extra proxy/network overhead, not pure
inference or stable percentile measurements. No further paid calls were needed.
