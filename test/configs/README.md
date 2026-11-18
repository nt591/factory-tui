# Fixture launch configurations

The UI fixtures copy these configs into private temporary directories. They
create the matching fake executables, source/workspace parents and gateway
config there. Relative paths resolve against that temporary config directory.
Do not launch these against real agents or treat the fixture model as available.

- `live-fixture.toml`: continuous workspace/run/review/restart test, low reasoning.
- `model-picker.toml`: model catalogue fixture with a loopback gateway/dummy key.

Both use explicit `--live-ui`; config loading starts no process or request.
For user-run live tests, start from `examples/live-test.toml` instead. Real calls
can incur usage and require explicit run confirmation.
