# Factory TUI

Use OCaml and Dune. Keep state transitions separate from terminal rendering.
Use jj. Commit tested increments and move the local main bookmark to each
completed commit. Do not push without an explicit request.
Follow docs/implementation.md. Keep its status accurate in each implementation
commit. Do not skip safety gates to match the native application feature list.
Do not edit the in-flight Rust application at ../factory.
Tests must not start agents, read credentials, or modify real workspaces.
Keep simulation labels visible. Accepting a task does not merge or push code.
Run scripts/format.sh --check, dune build, and dune runtest before committing.
Use scripts/format.sh to format OCaml and Dune files. Keep the ocamlformat
version in .ocamlformat and scripts/setup-editor.sh consistent.
Write comments only for non-obvious safety conditions or choices. Use plain English.

Live execution must be explicitly enabled and explicitly started. Setup must
not start an agent or import credentials. Acceptance does not merge, push, or
delete a workspace. Use fake harnesses and temporary workspaces for tests.

Add an explicit .mli for each core module. Export supported entry points, not
implementation helpers. Keep resource handles abstract. Expose records only
when callers need their structure for state reduction, rendering, or persistence.
