# Implementation audit

This audit checks the requested software-factory workflow, not merely whether the
project compiles. The original objective remains a usable board whose cards move
from updates and open a task chat, with a restrained mock-inspired layout and
accessible help/settings. The staged native-app implementation remains the guide.

## Evidence checked

| Requirement | Current implementation and verification | Result |
| --- | --- | --- |
| Four self-updating columns | `Model.apply` derives Queued/Working/Needs you/Ready. Factory and PTY tests verify automatic movement from both timer and supervised process events. | Implemented |
| Open and explore a task | Controller/Ui selection, split chat/activity, Enter/e and double-click expansion; PTY verifies click, expansion, Escape, and selected identity after movement. | Implemented |
| Readable mock-inspired layout | Bordered cards with wrapped titles, repository sidebar, selected card tint, persistent transcript/composer, collapsed tool output. Rendered PTY captures were inspected at 120x36 and 180x50. | Implemented; user visual preference still matters |
| Help/settings | `?` opens tabbed modal, keyboard/mouse tabs, scrolling, current storage and next-run settings; tests verify modal isolation and content. | Implemented |
| Vim navigation | hjkl, gg/G, counts, Ctrl-W pane selection, half/full-page keys, and mode-specific editing. Tests include actual terminal-decoded control bytes. | Implemented |
| Mouse and resizing | Card selection, expansion, buttons, modal hitboxes, wheel; exact frame/hit bounds from 1x1 through 180x50. Live authorization blocked below 64x13. PTY checks actual escape/input sequences. | Implemented |
| Compose and queue instructions | Abstract Text_edit cursor state, multiline draft, Ctrl-L/Alt-Enter newline, safe bracketed paste, captured submitted messages acknowledged only at turn start. Drafts/queued replies survive persistence. | Implemented; codepoint, not grapheme-cluster editing |
| Settings/history | Next-run model/harness settings do not rewrite captured run records. Requested read/write policy is captured per run and legacy snapshots default read-only. Live Codex-only preflight and active model-capture tests. | Implemented; Claude is simulation only |
| SQLite and restart | Versioned snapshots, separate run rows, ordered events, transaction rollback, exclusive ownership, coalesced bounded writes, shutdown flush, Working recovery. Storage and PTY save/reopen cover real temporary databases. | Implemented |
| Low-effort configuration | Optional default/XDG TOML, explicit file, CLI override/no-config, capped reads and rejected unknown fields. Argument-free startup discovery is in the PTY smoke. | Implemented |
| Supervision | Bounded stdout/stderr/lines/events, monotonic timeout, cancellation/process-group cleanup, checkpoint-before-spawn, bounded queue/separate outcome. Fake-process tests plus confirmed live-mode PTY path. | Implemented within documented process-group limits |
| Codex/provider/resume | Pure preview, explicit headless execution and live UI; exact thread ownership/mismatch checks. Installed Codex 0.166.0 execution/resume passed an isolated loopback Responses fixture. | Implemented; real gateway/UI provider behavior not verified |
| Isolated workspaces | Explicit W form, existing jj source, new outside-source task workspace, exact base, no automatic conversion/fetch, disclosure of source snapshot. Temporary jj tests and PTY create/save/reopen. | Implemented |
| Real changes review | Task-bound abstract background diff job, explicit refresh, actual patch/empty/loading/error states, vertical/horizontal scrolling and return to chat. PTY reads a real added file in a temporary workspace. | Implemented |
| Acceptance is separate | Only Ready can be accepted; no merge/push/delete in acceptance. Controller/review tests verify retained read-only chat and blocked background shortcuts. | Implemented |
| Modularity and formatting | Every library `.ml` has a matching `.mli`. Subsystem folders and Demo namespace; abstract resource handles and native scoped let-bindings. `scripts/format.sh --check` and Dune compilation enforce formatting/interfaces. | Implemented; one Dune library and exposed controller state remain |
| Editor | Project-switch LSP/Conform configuration, pinned editor tools, `.ml`/`.mli` attachment and formatting checks in actual Neovim config. | Verified locally |
| Local distribution | Standalone binary, explicit refusal-to-overwrite install, repeatable archive metadata, transitive opam lock, temporary package/install tests. Extracted binary runs with opam absent from PATH and passes the full PTY smoke. | Implemented for local macOS arm64 |
| Measured footprint | `scripts/measure.py`, fresh build directory and version-launch median; system-only dylib links inspected. No matched GUI measurement exists. | Local measurements only |
| Step-by-step jj commits | `jj log`, local main bookmarks, format/build/tests before increments; no remote/push. | Followed |
| OxCaml | Explicitly deferred at user request; failed old bootstrap and interrupted newer attempt are distinguished in `docs/oxcaml.md`. | Non-blocking TODO |

## Remaining work, not claimed complete

1. **Code-writing sandbox validation and approvals.** Live UI can explicitly
   request workspace-write for isolated tasks, with per-run confirmation, recorded
   policy, and no automatic escalation. Fake-process tests verify editing and a
   real reviewable diff without modifying source. Real Codex OS-sandbox enforcement
   and tool permissions are not proven by those tests. The adapter still uses
   never approvals; interactive approval/steering needs a suitable harness protocol
   rather than pretending exec JSONL provides one.
2. **Real provider compatibility.** Loopback fixtures prove protocol plumbing,
   not a model's tools, reasoning, credentials, billing, or provider behavior.
   Real gateway checks need user-selected configuration and explicit approval;
   no real key or model request is needed for normal tests.
3. **Fresh-machine release validation.** The lock was generated and checked
   against the existing switch; a completely new switch reconstruction, cross-OS
   support, signing, and notarization are not verified. The local archive is not
   represented as a public production release.
4. **Additional usability refinements.** Grapheme-aware editing, configurable
   panes, transcript search, and fully abstract controller view state remain
   candidates. They do not justify claiming current rendering or interaction
   quality from unit tests alone; keep inspecting PTY captures.
5. **Operational limits.** Group cancellation does not contain descendants that
   deliberately escape their group. Abrupt application termination can lose
   writes since the last checkpoint and leave an unassociated created workspace.
   Conversation/tool content is sensitive. These limits remain documented.

The active goal is not marked complete by this audit. The UI and local execution
foundation are verified, but the full software-factory implementation still has
sandbox-validation and provider/release boundaries that must not be replaced with
narrow fixture success claims.

## Repeat the verification

```sh
./scripts/format.sh --check
./scripts/check.sh
python3 scripts/smoke-invocation.py
python3 scripts/smoke-execution.py
uv run --with pyte --with pillow python scripts/smoke-terminal.py \
  --preview /tmp/factory-tui-audit.png
python3 scripts/smoke-package.py
```

Optional installed-agent loopback integration (dummy credentials only):

```sh
python3 scripts/smoke-codex-local.py --codex /absolute/path/to/codex
```

For a packaged binary pass `--binary` to the PTY smoke. Package/installation
checks use temporary destinations. Do not install into the user's PATH, fetch,
push, or contact a real model as a side effect of this audit.
