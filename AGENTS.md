# Factory TUI

Use OCaml and Dune. Keep state transitions separate from terminal rendering.
Use jj. Commit tested increments and move the local main bookmark to each
completed commit. Push tested increments to origin/main as authorized by the user. Do not push
unverified working-copy changes or force-update remote history.
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

Place task/lifecycle types in lib/domain, persistence in lib/storage, harness
and process code in lib/agent, and UI/controller/startup code in lib/terminal.
Keep seed fixtures, timed demo events, and fake runners in lib/demo behind the
Demo namespace. Demo runners use callbacks, not a direct Controller dependency.
Workspace creation and review APIs belong in lib/workspace. Use temporary jj
repositories in tests; never automatically initialize or fetch a real repository.
Shared small helpers belong in lib/support. Use Scope let@ bindings to flatten
cleanup scopes when nested callbacks obscure the control flow. Preserve lexical
cleanup order and Fun.protect exception behavior.
Keep .ml/.mli pairs together. The library uses include_subdirs unqualified, so
module basenames must remain unique. Update documented paths with file moves.

Keep factory_tui.opam.locked current when application dependencies change.
Package/install tests must use temporary destinations, not the user's PATH.

Use native child fixtures for plain process I/O checks. Keep shell/jj integration
tests where that behavior is the tested boundary. Do not increase timeouts or
serialize the full suite to hide a launch failure; document its evidence and scope.

For a full fixture-only UI audit, use scripts/check-ui.py through uv with pyte and
Pillow, and select a new output directory. It runs PTYs sequentially against one
binary. Inspect the report scope and relevant preview images before claiming UI
coverage. --binary skips format/build/unit gates. Do not run build/format/package
commands concurrently with its PTYs. Installed-agent checks remain separate opt-in
commands and are not part of this suite.

Vim-style navigation and insert mode are sufficient. Do not add keybindings solely
for Vim parity. Prioritize the factory workflow, readable task/chat views, reliable
updates, and simple input behavior.
