open Factory_tui
open Model

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let ok = function Ok value -> value | Error error -> failwith error
let task = make ~id:"attention" ~title:"Instruction" ~repository:"fixture"

let finish events =
  List.fold_left
    (fun task event ->
      Option.get (apply task { task_id = task.id; run_id = "run"; event }))
    (ok (start task "run"))
    events

let () =
  List.iter
    (fun (events, reason) ->
      let task = finish events in
      check "attention reason follows recorded terminal outcome"
        (Task_attention.reason task = Some reason);
      check "attention reason remains visible alongside update count"
        (Task_attention.card_text ~updates:2 task = reason ^ " / 2 new");
      check "compact preview includes reason and exact task remains unchanged"
        (Controller.contains (Task_row.text ~width:76 ~selected:true task) reason))
    [
      ([ Input_requested "Question"; Exited 0 ], "Reply requested");
      ([ Failed "Failure"; Turn_completed; Exited 0 ], "Run failed");
      ([ Exited 0 ], "Run failed");
      ([ Interrupted ], "Run interrupted");
    ];
  let no_record = { task with state = Needs_you } in
  check "legacy state without record does not invent reason"
    (Task_attention.reason no_record = Some "Needs attention");
  let stopped = finish [ Interrupted ] in
  let retried =
    ok (send stopped ~id:"retry" "Another attempt") |> fun task ->
    ok (start task "retry-run")
  in
  let failed =
    Option.get
      (apply retried { task_id = task.id; run_id = "retry-run"; event = Exited 1 })
  in
  check "newest attempt wins without rewriting earlier outcome"
    (Task_attention.reason failed = Some "Run failed"
    && (List.hd failed.runs).status = Stopped);
  let ready = finish [ Turn_completed; Exited 0 ] in
  check "Ready never advertises old attention reason" (Task_attention.reason ready = None);
  check "ordinary metadata and badges remain unchanged"
    (Task_attention.card_text ~updates:0 task = "Not started"
    && Task_attention.card_text ~updates:1 ready = "1 new update");
  let controller = Controller.create ~external_events:true () in
  controller.tasks <- [ failed ];
  controller.selected <- failed.id;
  let saved = Controller.snapshot controller in
  let frame = Ui.render controller ~width:120 ~height:36 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  check "board renders recorded reason"
    (Controller.contains (Buffer.contents buffer) "Run failed");
  ignore (Ui.render controller ~width:60 ~height:23);
  check "reason rendering does not change run history or messages"
    (Controller.snapshot controller = saved);
  Printf.printf "Passed %d task attention checks. Pure lifecycle/layout only.\n" !checks
