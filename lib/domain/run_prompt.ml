let queued (task : Model.task) =
  List.filter (fun (message : Model.message) -> message.queued) task.messages

let text messages =
  String.concat "\n\n" (List.map (fun (message : Model.message) -> message.text) messages)

let submitted (task : Model.task) submitted_ids =
  let ids = Hashtbl.create (List.length submitted_ids) in
  List.iter (fun id -> Hashtbl.replace ids id ()) submitted_ids;
  List.filter (fun (message : Model.message) -> Hashtbl.mem ids message.id) task.messages

let byte_length messages =
  List.fold_left
    (fun (count, bytes) (message : Model.message) ->
      (count + 1, bytes + String.length message.text + if count = 0 then 0 else 2))
    (0, 0) messages
  |> snd

let captured_text task submitted_ids =
  let expected = Hashtbl.create (List.length submitted_ids) in
  let duplicate_id = ref false in
  List.iter
    (fun id ->
      if Hashtbl.mem expected id then duplicate_id := true;
      Hashtbl.replace expected id 0)
    submitted_ids;
  let messages =
    List.filter
      (fun (message : Model.message) ->
        match Hashtbl.find_opt expected message.id with
        | None -> false
        | Some count ->
            Hashtbl.replace expected message.id (count + 1);
            true)
      task.Model.messages
  in
  if
    submitted_ids = [] || !duplicate_id
    || not (Hashtbl.fold (fun _ count valid -> valid && count = 1) expected true)
  then Error "Captured instruction IDs are missing or duplicated. No process started."
  else Ok (text messages)
