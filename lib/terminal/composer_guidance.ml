let width text = Notty.I.width (Notty.I.string Notty.A.empty text)

let text ?width:columns ~mode ~editing (task : Model.task) =
  let selection = Model.harness_label task.harness ^ " / " ^ task.model in
  let controls, compact =
    if task.state = Model.Done then ("Accepted / read-only", "Read-only")
    else if editing then
      ("Enter queues / Ctrl-L newline / Esc keeps draft", "Enter queues")
    else
      match mode with
      | Menu_content.Live _ when task.harness <> Model.Codex ->
          ("H selects Codex / m model", "H selects Codex")
      | Live _ -> ("m model / live Codex only", "live Codex only")
      | Simulation | Fake | Replay -> ("m model / H harness", "m model / H harness")
  in
  let complete =
    if task.state = Model.Done then controls else selection ^ "  ·  " ^ controls
  in
  match columns with
  | None -> complete
  | Some columns when width complete <= columns -> complete
  | Some columns ->
      (* Editing and mode controls take priority over a long model identifier. *)
      let controls = if width controls <= columns then controls else compact in
      let separator = " · " in
      let remaining = columns - width controls - width separator in
      let visible =
        if task.state <> Model.Done && remaining >= 4 then
          controls ^ separator ^ Text_layout.ellipsize remaining selection
        else controls
      in
      Text_layout.ellipsize columns visible
