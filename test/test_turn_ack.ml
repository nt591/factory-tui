open Factory_tui

let check name condition = if not condition then failwith name

let message index queued : Model.message =
  {
    id = Printf.sprintf "message-%05d" index;
    author = "You";
    text = "Short instruction";
    queued;
  }

let apply task =
  Option.get
    (Model.apply task
       { Model.task_id = task.Model.id; run_id = "ack-run"; event = Model.Turn_started })

let make count =
  let messages = List.init count (fun index -> message index (index mod 2 = 0)) in
  let task =
    { (Model.make ~id:"ack" ~title:"Task" ~repository:"fixture") with messages }
  in
  Result.get_ok (Model.start task "ack-run")

let measure () =
  let task = make 20000 in
  let run operation =
    Gc.full_major ();
    let before = Unix.gettimeofday () in
    for _ = 1 to 3 do
      ignore (operation ())
    done;
    (Unix.gettimeofday () -. before) *. 1000.
  in
  let old () =
    List.map
      (fun (message : Model.message) ->
        if List.mem message.id (Option.get task.active).submitted then
          { message with queued = false }
        else message)
      task.messages
  in
  Printf.printf
    "Three acknowledgements, 20,000 messages / 10,000 captured IDs:\n\
     Indexed reducer: %.2f ms\n\
     Previous membership scan: %.2f ms\n\
     Scoped CPU work only; excludes storage, transcript rendering and terminal output.\n"
    (run (fun () -> apply task))
    (run old)

let () =
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--measure" then measure ()
  else
    let task = make 20000 in
    let later = message 20000 true in
    let task = { task with messages = task.messages @ [ later ] } in
    let before = task.messages in
    let acknowledged = apply task in
    check "only captured messages are acknowledged in original order"
      (List.map (fun (m : Model.message) -> m.id) acknowledged.messages
       = List.map (fun (m : Model.message) -> m.id) before
      && List.for_all
           (fun (m : Model.message) -> m.queued = (m.id = later.id))
           acknowledged.messages);
    check "late reply keeps its original record"
      (List.hd (List.rev acknowledged.messages) == later);
    check "already sent history records are reused"
      (List.nth acknowledged.messages 1 == List.nth before 1);
    check "captured queued records alone are rebuilt"
      (List.hd acknowledged.messages != List.hd before);
    let repeated = apply acknowledged in
    check "repeated acknowledgement reuses unchanged transcript list"
      (repeated.messages == acknowledged.messages);
    check "run lifecycle still records every accepted event"
      (repeated.revision = task.revision + 2
      && repeated.active = task.active && repeated.runs = task.runs);
    let cache = Chat_layout.create () in
    let document =
      Chat_layout.update cache ~task_id:task.id ~width:76 acknowledged.messages
    in
    check "repeated acknowledgement does not invalidate wrapped transcript cache"
      (Chat_layout.update cache ~task_id:task.id ~width:76 repeated.messages == document);
    let snapshot : Snapshot.t =
      { tasks = [ task ]; drafts = []; selected = task.id; serial = 0 }
    in
    check "large valid captured reference set decodes exactly"
      (Snapshot.decode (Snapshot.encode snapshot) = Ok snapshot);
    let invalid =
      {
        task with
        active = Some { (Option.get task.active) with submitted = [ "missing" ] };
      }
    in
    check "indexed snapshot validation still rejects missing references"
      (Result.is_error
         (Snapshot.decode (Snapshot.encode { snapshot with tasks = [ invalid ] })));
    let duplicate =
      {
        task with
        active =
          Some
            {
              (Option.get task.active) with
              submitted = [ "message-00000"; "message-00000" ];
            };
      }
    in
    check "indexed snapshot validation still rejects duplicate references"
      (Result.is_error
         (Snapshot.decode (Snapshot.encode { snapshot with tasks = [ duplicate ] })));
    Printf.printf
      "Passed large-turn acknowledgement and reference checks. Pure messages/codec only.\n"
