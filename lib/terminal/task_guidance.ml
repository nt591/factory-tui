open Model

let selection ~live ~replay (task : task) =
  let guidance =
    match task.state with
    | Done ->
        if task.workspace <> None then
          "Archived task. Chat is read-only; u restores to Ready; v reviews retained \
           changes."
        else
          "Archived task. Chat is read-only; u restores to Ready; b returns to the \
           session board."
    | Ready -> "Ready for review. Ctrl-A archives without merging; i queues a follow-up."
    | Working ->
        if replay then
          "Replay updates are active. i queues a reply; no process can start."
        else "Run in progress. i sends a reply for the next turn; x stops."
    | (Queued | Needs_you) when replay ->
        "Replay controls updates. Inspect chat; no process can start."
    | (Queued | Needs_you) when live && task.workspace = None && task.session_root = None
      ->
        "Live runs require a workspace task. W creates one; no agent starts during setup."
    | (Queued | Needs_you) when live && task.harness <> Codex ->
        "Live execution supports Codex only. H selects Codex without starting a run."
    | Queued | Needs_you ->
        if not (List.exists (fun (message : message) -> message.queued) task.messages)
        then "Inspect the conversation. i queues an instruction before another run."
        else if live then "Pending instructions. s sends them; Enter sends a reply."
        else "Instructions queued. s starts a simulated or local fixture run."
  in
  task.id ^ " / " ^ guidance
