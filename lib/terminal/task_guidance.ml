open Model

let selection ~live ~replay (task : task) =
  let guidance =
    match task.state with
    | Done ->
        if task.workspace <> None then
          "Accepted task. Chat is read-only; v reviews retained workspace changes."
        else "Accepted task. Chat is read-only; d opens the archive."
    | Ready -> "Ready for review. a accepts without merging; i queues a follow-up."
    | Working ->
        if replay then
          "Replay updates are active. i queues a reply; no process can start."
        else "Run in progress. i queues a reply for the next turn; x stops."
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
        else if live then
          "Instructions queued. s opens live confirmation; nothing runs automatically."
        else "Instructions queued. s starts a simulated or local fixture run."
  in
  task.id ^ " / " ^ guidance
