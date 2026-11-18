let reason (task : Model.task) =
  if task.state <> Model.Needs_you then None
  else
    match List.fold_left (fun _ record -> Some record) None task.runs with
    | Some record -> (
        match record.Model.status with
        | Awaiting_input -> Some "Reply requested"
        | Run_failed -> Some "Run failed"
        | Stopped -> Some "Run interrupted"
        | Running | Completed -> Some "Needs attention")
    | None -> Some "Needs attention"

let card_text ~updates (task : Model.task) =
  match reason task with
  | Some reason ->
      if updates > 0 then Printf.sprintf "%s / %d new" reason updates else reason
  | None ->
      if updates > 0 then
        Printf.sprintf "%d new update%s" updates (if updates = 1 then "" else "s")
      else
        let queued =
          List.fold_left
            (fun count (message : Model.message) ->
              if message.queued then count + 1 else count)
            0 task.messages
        in
        if queued = 0 then Printf.sprintf "%d messages" (List.length task.messages)
        else Printf.sprintf "%d msg / %d queued" (List.length task.messages) queued
