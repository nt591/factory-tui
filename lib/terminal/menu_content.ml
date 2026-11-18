open Model

type mode = Simulation | Fake | Replay | Live of Model.execution_policy

let help ~mode =
  [
    "FACTORY / terminal";
    "";
    "Click a card to inspect chat. Enter opens a task with its reply editor.";
    "Focus Activity and e expands tool output to full terminal width.";
    "hjkl/arrows navigate. Counts repeat movement (for example, 3j).";
    "gg / G: first / last card, or top / bottom of the focused pane.";
    "Ctrl-W then hjkl moves pane focus. Ctrl-W w cycles panes.";
    "Ctrl-W +/- grows/shrinks the focused board/chat region. = resets.";
    "Split preferences last for this launch; zoom keeps them unchanged.";
    "Ctrl-U/D: half-page. Ctrl-B/F: full-page. Tab/Shift-Tab: cycle.";
    "Mouse wheel and Page Up/Down scroll. Home/End: first/last.";
    "Paused chat: click Latest on its border, or End, to follow output.";
    "e expands once; Escape returns a layer. Enter/i in chat composes a reply.";
    "Arrows edit; Home/End move within a line; Escape keeps the draft.";
    (match mode with
    | Live _ -> "n/W creates a workspace task. Setup starts no agent."
    | _ -> "n creates a demo task. W creates a workspace task with SQLite.");
    (match mode with
    | Live _ -> "m edits next-run model. Live execution supports Codex only."
    | _ -> "m edits next-run model. H cycles simulated Codex / Claude.");
    (match mode with
    | Live _ ->
        "Enter sends a task/reply; s retries pending work; x stops; Ctrl-A archives."
    | Replay -> "Replay supplies updates. s cannot start a run; Ctrl-A archives Ready."
    | Fake -> "s starts a local process fixture; x stops; Ctrl-A archives Ready."
    | Simulation -> "s starts a simulated run; x stops; Ctrl-A archives Ready tasks.");
    "M opens and loads gateway models; Ctrl-R refreshes. Uses the gateway key.";
    "b returns to the board. Click Archive to open it; u restores an archived task.";
    "v opens real workspace changes; r refreshes; Escape returns.";
    "Review: [/]: files; h/l: long lines; Ctrl-U/D: half; Ctrl-B/F: page.";
    (match mode with
    | Simulation -> "t expands tools; T toggles readable/raw payload. f pauses demo."
    | _ -> "t expands tools; T toggles readable/raw payload. Updates stay live.");
    "/ searches focused board or chat. S searches chat from any pane.";
    "In chat search: n/N moves matches; Escape clears. Literal search.";
    "";
    "Cards move from events; selected chat stays attached to its task.";
    "Process exit alone never marks a task Ready.";
    "Acceptance does not merge, push, or delete a workspace.";
    "Ctrl-X deletes an idle task after typing delete. Workspace files stay intact.";
    "Startup starts no agent. Live mode and writes require explicit opt-in.";
    "Configured SQLite storage retains chats and drafts.";
    "";
    "Menu: Tab/h/l switches tabs; j/k scrolls; ? or Escape closes.";
  ]

let settings ~mode ~database ~task ~layout =
  [
    "SESSION SETTINGS";
    "";
    ("Execution: "
    ^
    match mode with
    | Live policy ->
        "live Codex / "
        ^ (match policy with
          | Model.Read_only -> "Read-only"
          | Workspace_write -> "Workspace-write")
        ^ " / send to run"
    | Fake -> "local process fixtures"
    | Replay -> "fixture replay"
    | Simulation -> "simulated agents");
    (match mode with
    | Live _ -> "Startup starts no agent. Sending work starts a run under this policy."
    | Replay -> "Replay supplies updates; no process can start from this mode."
    | Fake -> "Only explicit Start runs the local process fixture. No model calls."
    | Simulation -> "Demo runs are simulated; no model or agent process starts.");
    "";
    "STORAGE";
    (match database with
    | None -> "In memory / data is discarded on exit."
    | Some path -> "SQLite / " ^ path);
    "Config: ~/.config/factory-tui/config.toml or --config PATH";
    {|[storage] database = "board.sqlite"|};
    "Database changes take effect on the next launch.";
    "Optional [workspace]: jj, source, parent, revision, model prefill W.";
    "Defaults never create workspaces or enable live execution.";
    "Stored conversations and tool output are sensitive.";
    "";
    "NEXT RUN / SELECTED TASK";
  ]
  @ (match task with
    | None -> [ "Select a task first." ]
    | Some task ->
        [
          task.id ^ " / " ^ task.title;
          ("Harness: " ^ harness_label task.harness
          ^ match mode with Live _ -> " / live Codex only" | _ -> " (simulated)");
          "Model: " ^ task.model;
          (if task.state = Done then "Accepted task / settings are read-only"
           else
             match mode with
             | Live _ -> "m edits model / live Codex only / M gateway catalogue"
             | _ -> "m edits model / H changes harness");
          "Past run settings do not change.";
        ])
  @ [
      "";
      "LAYOUT / STARTUP DEFAULTS";
      ("Board width: "
      ^
      match Pane_layout.board_width layout with
      | None -> "automatic"
      | Some value -> Printf.sprintf "%d%%" value);
      ("Board height: "
      ^
      match Pane_layout.board_height layout with
      | None -> "automatic"
      | Some value -> Printf.sprintf "%d%%" value);
      "[layout] board_width_percent / board_height_percent = 10..90";
      "Ctrl-W +/- adjusts this launch; = restores startup defaults.";
      "Terminal limits keep both regions usable. No config is written.";
      "";
      "Menu: Tab/h/l switches tabs; j/k scrolls; ? or Escape closes.";
    ]
