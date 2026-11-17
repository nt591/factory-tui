# Module boundaries

Each library module has an explicit interface. The compiler checks implementations
against these interfaces during the normal Dune build.

- `Model`: immutable task/run/event data and lifecycle transitions. Records and
  variants are public because reducers, codecs, and rendering inspect them.
- `Snapshot`: the persistence payload, encode/decode, restart recovery, and the
  run-record encoder used by the SQL store. JSON parsing helpers remain private.
- `Events`: replay envelope encode/decode and an abstract file/FIFO source. Callers
  close the source through an idempotent operation, not its raw descriptor.
- `Harness`: normalized decoded event plus raw JSON. Parser exceptions and helpers
  stay private. Unknown events can be inspected without extending the public type.
- `Process`: configuration, outcome, and a bounded runner. Spawn bindings, clocks,
  descriptors, signal handling, and cleanup helpers remain private.
- `Run_handle`: abstract background ownership with cancel, drain, outcome, close.
  Queue, mutex, and worker thread cannot be accessed by callers.
- `Storage` and `Persistence`: abstract database and background-worker ownership.
  Callers cannot access SQLite handles, advisory locks, or internal queues.
- `Controller`: actions, UI state, and supported interaction/lifecycle operations.
  Its mutable state record is public because the current renderer and app loop
  read and update it. Navigation algorithms and command dispatch helpers remain
  private. This is not yet an abstract controller with a read-only view model.
- `Ui`: frame/hitbox data, render, mouse dispatch, and tested text wrapping. Theme,
  borders, image composition, and pane rendering helpers stay private.
- `Fake_runner`: abstract ownership of fixture runs with poll/close. Its fixed
  script, running handles, and checkpoint details remain private.
- `App`: snapshot and interactive entry points only.
- `Demo`: seed data and timed fixture events only.

No functor is required for these boundaries. Keep modules small and add a functor
only when a concrete dependency must be parameterized; do not expose internals to
make tests convenient. Current integration tests use the same public interfaces
as the application. Resource handles stay abstract even in tests.
