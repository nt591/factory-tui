open Factory_tui
open Model

let check name condition = if not condition then failwith name
let task id repository state = { (Model.make ~id ~title:id ~repository) with state }

let () =
  let controller = Controller.create ~external_events:true () in
  controller.tasks <-
    [
      task "queued-a" "alpha" Queued;
      task "queued-b" "beta" Queued;
      task "ready-a" "alpha" Ready;
      task "working-b" "beta" Working;
      task "accepted-a" "alpha" Done;
      task "accepted-b" "beta" Done;
    ];
  controller.selected <- "working-b";
  let render () =
    let frame = Ui.render controller ~width:180 ~height:50 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (180, 50) frame.image;
    String.split_on_char '\n' (Buffer.contents buffer)
  in
  let has text pattern = Controller.contains text pattern in
  let rows = render () in
  check "active counters exclude archive tasks"
    (has (List.nth rows 1) "02  Queued"
    && has (List.nth rows 1) "01  Working"
    && has (List.nth rows 1) "01  Ready"
    && has (List.nth rows 2) "4 tasks");
  Controller.act controller (Controller.Repository (Some "alpha"));
  let selected = controller.selected in
  let rows = render () in
  check "repository counters describe displayed cards"
    (has (List.nth rows 1) "01  Queued"
    && has (List.nth rows 1) "00  Working"
    && has (List.nth rows 1) "01  Ready"
    && has (List.nth rows 2) "2 tasks");
  check "repository counts do not close filtered-out selected chat"
    (controller.selected = selected
    && has (String.concat "\n" rows) "working-b / Working / conversation");
  controller.query <- "ready";
  let rows = render () in
  check "query counters match single displayed task"
    (has (List.nth rows 1) "00  Queued"
    && has (List.nth rows 1) "01  Ready"
    && has (List.nth rows 2) "1 tasks");
  controller.query <- "missing";
  let rows = render () in
  check "empty filter produces zero counts"
    (has (List.nth rows 1) "00  Queued"
    && has (List.nth rows 1) "00  Ready"
    && has (List.nth rows 2) "0 tasks");
  controller.query <- "";
  Controller.act controller Controller.Archive_view;
  let rows = render () in
  check "archive count respects repository filter"
    (has (List.nth rows 1) "01  Done" && has (List.nth rows 2) "1 tasks accepted");
  Controller.act controller (Controller.Repository None);
  let rows = render () in
  check "cleared repository exposes full archive count" (has (List.nth rows 1) "02  Done");
  Controller.act controller Controller.Session_board;
  Controller.act controller (Controller.Repository (Some "alpha"));
  let queued = List.find (fun (task : task) -> task.id = "queued-a") controller.tasks in
  let running = Result.get_ok (Model.start queued "counter-run") in
  controller.tasks <-
    List.map
      (fun (task : task) -> if task.id = running.id then running else task)
      controller.tasks;
  let rows = render () in
  check "filtered counters reflect task entering Working"
    (has (List.nth rows 1) "00  Queued" && has (List.nth rows 1) "01  Working");
  List.iter
    (fun event ->
      Controller.receive controller
        { task_id = running.id; run_id = "counter-run"; event })
    [ Turn_started; Turn_completed; Exited 0 ];
  let rows = render () in
  check "filtered counters follow validated automatic movement"
    (has (List.nth rows 1) "00  Working"
    && has (List.nth rows 1) "02  Ready"
    && has (List.nth rows 2) "2 tasks");
  let saved = Controller.snapshot controller in
  ignore (render ());
  check "count calculation does not mutate stored tasks"
    (Controller.snapshot controller = saved);
  Printf.printf "Passed scoped board count checks. Pure tasks and rendering only.\n"
