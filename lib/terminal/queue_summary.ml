type t = { awaiting : int; next : int }

let make (task : Model.task) =
  let captured = Hashtbl.create 16 in
  Option.iter
    (fun (run : Model.run) ->
      List.iter (fun id -> Hashtbl.replace captured id ()) run.submitted)
    task.active;
  List.fold_left
    (fun summary (message : Model.message) ->
      if not message.queued then summary
      else if Hashtbl.mem captured message.id then
        { summary with awaiting = summary.awaiting + 1 }
      else { summary with next = summary.next + 1 })
    { awaiting = 0; next = 0 } task.messages

let title ~width (task : Model.task) =
  let summary = make task in
  let prefix = "Reply / next turn" in
  let text =
    if task.state = Model.Done then prefix
    else if summary.awaiting > 0 then
      Printf.sprintf "%s · %d awaiting ack · %d next" prefix summary.awaiting summary.next
    else if summary.next > 0 then Printf.sprintf "%s · %d queued" prefix summary.next
    else prefix
  in
  Text_layout.ellipsize width text
