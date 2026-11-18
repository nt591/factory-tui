let text ~width ~mode ~paused =
  let full, compact =
    match mode with
    | Menu_content.Simulation -> ("SIMULATION", "SIMULATION")
    | Fake -> ("FAKE HARNESS / NO MODEL CALLS", "FAKE / NO MODEL")
    | Replay -> ("FIXTURE REPLAY", "REPLAY")
    | Live Model.Read_only -> ("LIVE ENABLED / SEND TO RUN", "LIVE READ")
    | Live Model.Workspace_write -> ("LIVE WRITE / SEND TO RUN", "LIVE WRITE")
  in
  let updates = if paused then "[PAUSED]" else "[UPDATING]" in
  (* Mode takes priority over the app title when the terminal cannot show both. *)
  if width >= 60 then Printf.sprintf " FACTORY / terminal     %s  %s" full updates
  else Printf.sprintf "%s | FACTORY %s" compact updates
