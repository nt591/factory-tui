open Factory_tui
open Model

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let running () =
  let controller = Controller.create () in
  let task =
    ok (start (make ~id:"task" ~title:"Instruction" ~repository:"fixture") "run")
  in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  controller.status <- "Waiting for the durable checkpoint.";
  controller

let receive controller event =
  Controller.receive controller { task_id = "task"; run_id = "run"; event }

let has controller text = Controller.contains controller.Controller.status text

let () =
  let controller = running () in
  receive controller Turn_started;
  check "turn start replaces checkpoint status" (has controller "Run started.");
  check "running status explains stopping and queuing"
    (has controller "x stops" && has controller "replies queue");
  receive controller Turn_completed;
  check "turn completion alone does not report process success"
    (not (has controller "Run complete."));
  receive controller (Exited 0);
  check "validated exit offers review and acceptance"
    (has controller "Run complete."
    && has controller "v reviews changes"
    && has controller "a accepts without merging");
  let completed = controller.status in
  receive controller (Failed "late failure");
  check "late failure does not replace completion guidance" (controller.status = completed);
  List.iter
    (fun (events, label) ->
      let controller = running () in
      List.iter (receive controller) events;
      check label
        (has controller "Run needs attention."
        && has controller "Inspect the chat"
        && has controller "i queues a reply"))
    [
      ([ Exited 0 ], "exit without completion needs attention");
      ([ Turn_completed; Exited 1 ], "nonzero exit needs attention");
      ([ Failed "private error"; Turn_completed; Exited 0 ], "failed turn needs attention");
      ( [ Input_requested "Question"; Turn_completed; Exited 0 ],
        "input request needs attention" );
    ];
  Controller.act controller Controller.Accept;
  check "acceptance replaces completion guidance with read-only status"
    (has controller "Task accepted."
    && has controller "Chat is read-only."
    && not (has controller "a accepts"));
  let stopped = running () in
  receive stopped Interrupted;
  check "interruption offers a retry without claiming completion"
    (has stopped "Run stopped." && has stopped "s retries");
  let background = running () in
  background.selected <- "other";
  let original = background.status in
  receive background Turn_started;
  receive background Turn_completed;
  receive background (Exited 0);
  check "background outcome does not replace selected task status"
    (background.status = original);
  let stale = running () in
  let original = stale.status in
  List.iter
    (fun event ->
      Controller.receive stale { task_id = "task"; run_id = "old-run"; event })
    [ Turn_started; Turn_completed; Exited 1; Interrupted ];
  check "stale run events do not change status" (stale.status = original);
  Printf.printf "Passed %d run status checks. Pure events only.\n" !checks
