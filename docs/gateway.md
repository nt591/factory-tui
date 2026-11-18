# Gateway configuration boundary

Gateway settings are non-secret and separate from the startup storage config:

```toml
base_url = "https://gateway.example/v1"
key_environment = "FACTORY_GATEWAY_API_KEY"
```

`key_environment` is an environment-variable name, not the key value. Do not paste
credentials into TOML. Only these two string fields are accepted. Unknown fields,
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
