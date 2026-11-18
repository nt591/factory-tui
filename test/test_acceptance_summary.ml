open Factory_tui
open Model

let check name condition = if not condition then failwith name
let ok = function Ok value -> value | Error error -> failwith error

let () =
  let task =
    ok (start (make ~id:"accept" ~title:"Original" ~repository:"fixture") "run")
  in
  let task =
    Option.get (apply task { task_id = task.id; run_id = "run"; event = Turn_started })
  in
  let task = ok (send task ~id:"later" "Pending follow-up") in
  let ready =
    List.fold_left
      (fun task event ->
        Option.get (apply task { task_id = task.id; run_id = "run"; event }))
      task [ Turn_completed; Exited 0 ]
  in
  let summary = Acceptance_summary.make ~draft:"Unsent draft" ready in
  check "pending summary counts only queued messages and nonempty draft"
    (summary = { queued = 1; draft = true });
  check "empty draft does not create pending marker"
    ((Acceptance_summary.make ~draft:"   " ready).draft = false);
  let controller = Controller.create ~external_events:true () in
  controller.tasks <- [ ready ];
  controller.selected <- ready.id;
  controller.drafts <- [ (ready.id, "Unsent draft") ];
  let before = Controller.snapshot controller in
  Controller.act controller Accept;
  let accepted = Option.get (Controller.selected controller) in
  check "acceptance retains queued messages draft and run records"
    (accepted.state = Done
    && accepted.messages = ready.messages
    && accepted.runs = ready.runs
    && controller.drafts = before.drafts);
  check "acceptance status discloses unsent retained work"
    (Controller.contains controller.status "1 queued retained"
    && Controller.contains controller.status "draft retained"
    && Controller.contains controller.status "not sent.");
  Controller.act controller Zoom;
  let frame = Ui.render controller ~width:120 ~height:36 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  check "accepted inspection keeps pending summary visible"
    (Controller.contains (Buffer.contents buffer) "1 queued retained"
    && Controller.contains (Buffer.contents buffer) "draft retained");
  check "retained draft footer never offers unavailable editing"
    (Controller.contains (Buffer.contents buffer) "Draft retained / read-only"
    && not (Controller.contains (Buffer.contents buffer) "i to edit"));
  check "accepted pending work cannot become a run or composer"
    (not
       (List.exists
          (fun (hit : Ui.hit) -> List.mem hit.action [ Start; Begin_compose ])
          frame.hits));
  let saved = Controller.snapshot controller in
  let loaded = ok (Snapshot.decode (Snapshot.encode saved)) in
  controller.archive <- true;
  Controller.restore controller loaded;
  check "restart preserves exact pending archived data"
    ((Option.get (Controller.selected controller)).messages = ready.messages
    && Controller.draft controller = "Unsent draft");
  List.iter
    (fun width ->
      check "read-only pending title is bounded"
        (Notty.I.width
           (Notty.I.string Notty.A.empty (Acceptance_summary.title ~width summary))
        <= max 0 width))
    [ 0; 10; 20; 40; 76 ];
  controller.tasks <- [ ready ];
  controller.selected <- ready.id;
  controller.status <- "Storage error: unsaved";
  Controller.act controller Accept;
  check "acceptance does not hide a persistence warning"
    (controller.status = "Storage error: unsaved");
  Printf.printf
    "Passed acceptance pending-work disclosure checks. Pure state/codec/layout only.\n"
