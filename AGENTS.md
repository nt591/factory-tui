# Factory TUI

Use OCaml and Dune. Keep state transitions separate from terminal rendering.
Use jj. Do not push without an explicit request.
Do not edit the in-flight Rust application at ../factory.
Tests must not start agents, read credentials, or modify real workspaces.
Keep simulation labels visible. Accepting a task does not merge or push code.
Run dune build and dune runtest before committing.
Write comments only for non-obvious safety conditions or choices. Use plain English.
