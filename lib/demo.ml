open Model

let start_exn task run_id =
  match start task run_id with Ok t -> t | Error e -> failwith e

let seed () =
  let task id title repo = make ~id ~title ~repository:repo in
  let working =
    start_exn (task "T-102" "Build the event reducer" "factory-tui") "demo-102"
  in
  let waiting =
    start_exn (task "T-103" "Choose a workspace policy" "factory") "demo-103"
  in
  let apply_exn task run_id event =
    match apply task { task_id = task.id; run_id; event } with
    | Some t -> t
    | None -> failwith "Invalid demo event"
  in
  let waiting = apply_exn waiting "demo-103" Turn_started in
  let waiting =
    apply_exn waiting "demo-103" (Input_requested "One workspace per task, or per run?")
  in
  let waiting = apply_exn waiting "demo-103" (Exited 0) in
  let ready =
    start_exn (task "T-104" "Add keyboard navigation" "factory-tui") "demo-104"
  in
  let ready = apply_exn ready "demo-104" Turn_started in
  let ready =
    apply_exn ready "demo-104"
      (Message
         ( "reply",
           "Navigation tests pass. Ready for your review. Acceptance does not merge or \
            push." ))
  in
  let ready = apply_exn ready "demo-104" Turn_completed in
  let ready = apply_exn ready "demo-104" (Exited 0) in
  [
    task "T-101" "Mouse hit-testing and task zoom" "factory-tui";
    working;
    waiting;
    ready;
    task "T-105" "Persist conversations safely" "factory-tui";
    task "T-106" "Review harness cancellation" "factory";
  ]

let schedule task_id run_id =
  let e time event = (time, { task_id; run_id; event }) in
  [
    e 0.5 Turn_started;
    e 1.2 (Message ("reply", "Inspecting the task and building a plan..."));
    e 2.4
      (Tool
         ( "inspect",
           "read files: lib/model.ml\nInspect run identity and delivery acknowledgments."
         ));
    e 3.6 (Message ("reply", "The plan is ready. Implementing the reducer and tests."));
    e 5.0 (Tool ("tests", "dune runtest\nSimulation: all fixture checks pass."));
    e 6.5
      (Message
         ( "reply",
           "Implementation and fixture checks are complete. Ready for your review." ));
    e 7.0 Turn_completed;
    e 7.2 (Exited 0);
  ]
