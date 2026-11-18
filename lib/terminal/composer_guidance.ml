let text ~mode ~editing (task : Model.task) =
  if task.state = Model.Done then "Accepted / read-only"
  else
    let selection = Model.harness_label task.harness ^ " / " ^ task.model in
    let controls =
      if editing then "Enter queues / Ctrl-L newline / Esc keeps draft"
      else
        match mode with
        | Menu_content.Live _ when task.harness <> Model.Codex ->
            "H selects Codex / m model"
        | Live _ -> "m model / live Codex only"
        | Simulation | Fake | Replay -> "m model / H harness"
    in
    selection ^ "  ·  " ^ controls
