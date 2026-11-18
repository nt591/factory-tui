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
