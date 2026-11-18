let next ~prefix ~serial tasks =
  let occupied = Hashtbl.create 64 in
  let add id =
    Hashtbl.replace occupied id ();
    String.iteri
      (fun index char ->
        if char = '/' then Hashtbl.replace occupied (String.sub id 0 index) ())
      id
  in
  List.iter
    (fun (task : Model.task) ->
      add task.id;
      List.iter (fun (message : Model.message) -> add message.id) task.messages;
      List.iter (fun (id, _) -> add id) task.tools;
      List.iter (fun (run : Model.run_record) -> add run.run_id) task.runs;
      Option.iter (fun (run : Model.run) -> add run.id) task.active)
    tasks;
  let rec available serial =
    (* Imported counters can reach the integer limit. Probe retained IDs after wrap. *)
    let serial = if serial = max_int then 0 else serial + 1 in
    let id = Printf.sprintf "%s-%d" prefix serial in
    if Hashtbl.mem occupied id then available serial else (id, serial)
  in
  available (max 0 serial)
