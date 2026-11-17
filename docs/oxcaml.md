# OxCaml experiment: deferred

OxCaml is an optional future improvement, not a prerequisite for the factory UI.
Continue implementation with the verified project-local OCaml 5.3.0 switch,
ocamllsp 1.23.1, and ocamlformat 0.29.0. Do not introduce OxCaml-only syntax or
change the editor/compiler defaults until the compatibility checks below pass.

## What happened on November 17, 2026

Host: macOS 26.7.1 (25G241), Apple Silicon, with Command Line Tools whose compiler
reported SDK version 27.0 in bootstrap commands.

1. The website's installation recipe selected `ocaml-variants.5.2.0+ox` and
   `oxcaml-compiler.5.2.0minus39` in a separate named switch. Its bundled Dune
   3.20.2 bootstrap executable crashed with SIGSEGV (exit 139) while building
   `dune.install`. This occurred before compiling the Factory TUI or installing
   its application dependencies. It was a compiler-toolchain bootstrap failure,
   not an application build failure.
2. A second separate switch, `factory-ox`, selected `ocaml-variants.5.4.0+ox`
   and `oxcaml-compiler.5.4.0-ox9` from the OxCaml opam repository. It used these
   configure overrides, which resolved a similar issue in the standard compiler:

   ```sh
   ac_cv_func_pipe2=no ac_cv_func_dup3=no ac_cv_func_accept4=no \
     ac_cv_func_ppoll=no MACOSX_DEPLOYMENT_TARGET=14.0
   ```

   This attempt passed the bundled Dune 3.23.1 bootstrap and reached the OxCaml
   compiler build. It was deliberately interrupted to defer the experiment at
   the user's request. There is no evidence that this compiler attempt would
   have failed. Application dependencies, tests, LSP, and formatter were not
   validated under it.

The first crash is consistent with the earlier standard-OCaml SDK/runtime
mismatch: standard Dune and ocamlbuild crashed in `caml_unix_pipe`, and a compiler
rebuild disabling unavailable Unix functions fixed them. The OxCaml crash itself
was not examined with a debugger, so this remains a likely cause, not a proven
root cause. Do not describe OxCaml generally as broken or incompatible with the app.

Opam removed both unsuccessful switch registrations. During cancellation of the
second build its automatic cleanup reported a nonempty directory, so unregistered
build remnants may remain under `~/.opam/factory-ox`. No matching compiler process
remained when checked after cancellation. The standard project switch was not
modified by either experiment.

Local diagnostics, if still available:

- `~/.opam/log/oxcaml-compiler-82607-693371.out`: first bootstrap crash.
- `~/.opam/log/oxcaml-compiler-2404-c0484b.out`: second compiler build/interruption.

Logs are local diagnostic artifacts, not tracked repo files. Paths may disappear
when opam cleans its cache.

## TODO: retry after the main implementation

- Use an isolated named switch and the repository's current supported compiler;
  do not rely on the old website recipe without checking package versions.
- Confirm host/SDK compatibility. Debug any bootstrap crash before changing the
  application or prescribing a workaround as a general fix.
- Install application dependencies and matching OxCaml-aware editor tools.
- Build into `_build-ox`, leaving `_build` and the project `_opam` unchanged.
- Run all unit tests and the full PTY smoke, including SQLite, process cancellation,
  shutdown, and save/reopen. Verify `.ml`/`.mli` LSP attachment, hover, and formatting.
- Only then consider mode annotations or local allocation at a concrete boundary.
  Measure allocation/runtime behavior rather than claiming an automatic speedup.

The build scripts already accept `FACTORY_OPAM_SWITCH` and `FACTORY_BUILD_DIR`;
the terminal smoke accepts `--binary`. These are testing hooks, not a claim that
an OxCaml build is supported today.
