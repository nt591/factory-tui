open Factory_tui
open Model

let check name condition = if not condition then failwith name
let ok = function Ok value -> value | Error error -> failwith error

let apply task event =
  Option.get (Model.apply task { task_id = task.id; run_id = "run"; event })

let () =
  let task = make ~id:"task" ~title:"Original instruction" ~repository:"fixture" in
  let retained = ok (send task ~id:"run/reply" "Queued instruction with colliding ID") in
  check "run cannot claim retained user-message namespace"
    (Result.is_error (start retained "run"));
  let tool_history = { task with tools = [ ("run/tool", "retained payload") ] } in
  check "run cannot claim retained tool namespace"
    (Result.is_error (start tool_history "run"));
  let nested =
    {
      task with
      messages =
        task.messages
        @ [
            {
              id = "run/nested/reply";
              author = "Codex (simulated)";
              text = "Old output";
              queued = false;
            };
          ];
    }
  in
  check "nested run ID cannot reuse earlier scoped item"
    (Result.is_error (start nested "run/nested"));
  let running = ok (start task "run") in
  check "new reply cannot occupy active output namespace"
    (Result.is_error (send running ~id:"run/new" "Later reply"));
  check "unrelated reply ID remains valid"
    (Result.is_ok (send running ~id:"later" "Later reply"));
  let partial = apply running (Message ("reply", "partial")) in
  let complete = apply partial (Message ("reply", "complete")) in
  check "legitimate same-run output still replaces its stream item"
    (List.length complete.messages = 2 && (List.nth complete.messages 1).text = "complete");
  let corrupt =
    {
      running with
      messages =
        running.messages
        @ [
            {
              id = "run/reply";
              author = "You";
              text = "Retained user reply";
              queued = true;
            };
          ];
    }
  in
  let rejected = apply corrupt (Message ("reply", "must not overwrite")) in
  check "reducer guard preserves colliding instruction exactly"
    (List.find (fun (message : message) -> message.id = "run/reply") rejected.messages
    = List.find (fun (message : message) -> message.id = "run/reply") corrupt.messages);
  check "collision is disclosed and marks attempted run failed"
    ((Option.get rejected.active).failed
    && List.exists
         (fun (message : message) ->
           message.author = "Factory" && Controller.contains message.text "conflicts")
         rejected.messages);
  let finished = apply (apply rejected Turn_completed) (Exited 0) in
  check "output collision cannot finish Ready even after success events"
    (finished.state = Needs_you);
  let snapshot : Snapshot.t =
    { tasks = [ finished ]; drafts = []; selected = task.id; serial = 0 }
  in
  check "collision failure leaves valid retained conversation snapshot"
    (Snapshot.decode (Snapshot.encode snapshot) = Ok snapshot);
  let sent =
    {
      corrupt with
      messages =
        List.map
          (fun (message : message) -> { message with queued = false })
          corrupt.messages;
    }
  in
  let rejected = apply sent (Message ("reply", "must not overwrite sent history")) in
  check "already-sent user history is equally protected"
    ((List.nth rejected.messages 1).text = "Retained user reply");
  let controller = Controller.create ~external_events:true () in
  controller.tasks <- [ corrupt ];
  controller.selected <- task.id;
  Controller.receive controller
    { task_id = task.id; run_id = "run"; event = Message ("reply", "conflicting stream") };
  Controller.act controller Zoom;
  let frame = Ui.render controller ~width:120 ~height:36 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  check "chat renders retained reply and collision warning"
    (Controller.contains (Buffer.contents buffer) "Retained user reply"
    && Controller.contains (Buffer.contents buffer) "conflicts"
    && Controller.contains (Buffer.contents buffer) "changed.");
  Printf.printf
    "Passed stream identity protection checks. Pure reducer/codec/rendering only.\n"
