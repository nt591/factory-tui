open Factory_tui
open Controller
open Model

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let () =
  let task =
    {
      (Model.make ~id:"archive" ~title:"Keep this work" ~repository:"fixture") with
      state = Ready;
    }
  in
  let controller = Controller.create ~external_events:true () in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  controller.drafts <- [ (task.id, "Retained draft") ];
  let saved = Controller.snapshot controller in
  Controller.key controller (`ASCII 'a', []);
  check "plain a cannot archive" (Controller.snapshot controller = saved);
  Controller.key controller (`Function 7, []);
  check "old function-key shortcut cannot archive" (Controller.snapshot controller = saved);
  Controller.act controller Begin_compose;
  Controller.key controller (`ASCII 'a', [ `Ctrl ]);
  check "Ctrl-A during editing cannot archive"
    ((Option.get (Controller.selected controller)).state = Ready);
  Controller.key controller (`Escape, []);
  Controller.key controller (`ASCII 'A', [ `Ctrl ]);
  let accepted = Option.get (Controller.selected controller) in
  check "Ctrl-A archives only Ready work"
    (accepted.state = Done && accepted.revision = task.revision + 1);
  check "archive leaves messages runs draft and identity intact"
    (accepted.messages = task.messages
    && accepted.runs = task.runs && accepted.id = task.id
    && controller.drafts = saved.drafts);
  Controller.key controller (`ASCII 'd', []);
  controller.query <- "hidden";
  controller.repository <- Some "hidden";
  controller.zoom <- true;
  let frame = Ui.render controller ~width:120 ~height:36 in
  let restore = List.find (fun (hit : Ui.hit) -> hit.action = Restore_task) frame.hits in
  check "restoration action is available in archived conversation" (restore.rect.y = 34);
  Ui.mouse controller frame ~now:1. (`Press `Left, (restore.rect.x, restore.rect.y), []);
  let restored = Option.get (Controller.selected controller) in
  check "restore returns selected task to visible session board"
    (restored.state = Ready && (not controller.archive) && (not controller.zoom)
   && controller.focus = Board && controller.query = "" && controller.repository = None
    && Controller.visible controller = [ restored ]);
  check "restore never sends pending data or changes history"
    (restored.messages = task.messages
    && restored.runs = task.runs && restored.active = None
    && Controller.draft controller = "Retained draft");
  check "restored identity roundtrips"
    (ok (Snapshot.decode (Snapshot.encode (Controller.snapshot controller)))
    = Controller.snapshot controller);
  controller.status <- "Storage error: fixture";
  Controller.act controller Accept;
  Controller.act controller Restore_task;
  check "restore preserves storage warning" (controller.status = "Storage error: fixture");
  List.iter
    (fun state ->
      check "only archived tasks restore"
        (Result.is_error (Model.restore { task with state })))
    [ Queued; Working; Needs_you; Ready ];
  let before = Controller.snapshot controller in
  Controller.key controller (`ASCII 'u', []);
  check "restoring already visible task does not change data"
    (Controller.snapshot controller = before);
  Printf.printf
    "Passed %d archive shortcut/restore checks. Pure state/codec/mouse only.\n" !checks
