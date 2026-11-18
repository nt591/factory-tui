open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let () =
  let task = Model.make ~id:"queue" ~title:"Initial instruction" ~repository:"fixture" in
  check "new task counts initial queued instruction"
    (Queue_summary.make task = { awaiting = 0; next = 1 });
  let task = ok (Model.send task ~id:"second" "Second instruction") in
  check "idle queue title names queued messages"
    (Queue_summary.title ~width:76 task = "Reply / next turn · 2 queued");
  let running = ok (Model.start task "run") in
  check "captured instructions await acknowledgement, not next turn"
    (Queue_summary.make running = { awaiting = 2; next = 0 });
  let running = ok (Model.send running ~id:"later" "Later reply") in
  check "later reply is separate from unacknowledged capture"
    (Queue_summary.make running = { awaiting = 2; next = 1 });
  check "composer distinguishes both queues"
    (Queue_summary.title ~width:76 running = "Reply / next turn · 2 awaiting ack · 1 next");
  let acknowledged =
    Option.get
      (Model.apply running
         { Model.task_id = task.id; run_id = "run"; event = Turn_started })
  in
  check "acknowledgement removes captured count only"
    (Queue_summary.make acknowledged = { awaiting = 0; next = 1 });
  let stopped =
    Option.get
      (Model.apply running
         { Model.task_id = task.id; run_id = "run"; event = Interrupted })
  in
  check "interruption returns unacknowledged instructions to next queue"
    (Queue_summary.make stopped = { awaiting = 0; next = 3 });
  let history =
    {
      task with
      messages =
        List.map
          (fun (message : Model.message) -> { message with queued = false })
          task.messages;
    }
  in
  check "sent history has no queued count"
    (Queue_summary.title ~width:76 history = "Reply / next turn");
  let done_task = { running with state = Model.Done; active = None } in
  check "accepted task does not advertise a next run"
    (Queue_summary.title ~width:76 done_task = "Reply / next turn");
  List.iter
    (fun width ->
      check "queue title fits border cells"
        (Notty.I.width (Notty.I.string Notty.A.empty (Queue_summary.title ~width running))
        <= max 0 width))
    [ -1; 0; 1; 10; 20; 40; 76 ];
  let controller = Controller.create ~external_events:true () in
  controller.tasks <- [ running ];
  controller.selected <- task.id;
  Controller.act controller Controller.Zoom;
  let saved = Controller.snapshot controller in
  let render () =
    let frame = Ui.render controller ~width:120 ~height:36 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
    Buffer.contents buffer
  in
  check "UI exposes captured and next-turn queue counts"
    (Controller.contains (render ()) "2 awaiting ack · 1 next");
  Controller.act controller Controller.Begin_compose;
  Controller.set_input controller "Unsent draft";
  check "unsent editor draft is not counted as a queued message"
    (Controller.contains (render ()) "2 awaiting ack · 1 next");
  let after_draft = Controller.snapshot controller in
  ignore (render ());
  check "queue calculation changes no saved state"
    (Controller.snapshot controller = after_draft && saved.tasks = after_draft.tasks);
  Controller.submit controller;
  check "submitted reply updates next-turn count"
    (Controller.contains (render ()) "2 awaiting ack · 2 next");
  Controller.receive controller
    { Model.task_id = task.id; run_id = "run"; event = Turn_started };
  check "UI acknowledgement preserves later queue"
    (Controller.contains (render ()) "Reply / next turn · 2 queued");
  Printf.printf "Passed %d queue-summary checks. Pure tasks and rendering only.\n" !checks
