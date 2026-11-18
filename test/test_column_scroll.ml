open Factory_tui
open Model

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let make id state = { (Model.make ~id ~title:id ~repository:"fixture") with state }

let () =
  let controller = Controller.create () in
  controller.schedules <- [];
  controller.tasks <-
    List.init 10 (fun i -> make (Printf.sprintf "queued-%02d" i) Queued)
    @ List.init 10 (fun i -> make (Printf.sprintf "ready-%02d" i) Ready);
  controller.selected <- "queued-00";
  let saved = Controller.snapshot controller in
  let render width height = Ui.render controller ~width ~height in
  let wheel state direction =
    let frame = render 120 36 in
    let r, _, _, _ = List.find (fun (_, s, _, _) -> s = state) frame.columns in
    Ui.mouse controller frame ~now:1. (`Press (`Scroll direction), (r.x + 2, r.y + 2), [])
  in
  wheel Queued `Down;
  check "queued wheel changes only queued offset"
    (Column_scroll.offset controller.column_scroll Queued = 1
    && Column_scroll.offset controller.column_scroll Ready = 0
    && controller.board_scroll = 0);
  wheel Ready `Down;
  wheel Ready `Down;
  check "ready column has independent scroll position"
    (Column_scroll.offset controller.column_scroll Ready = 2
    && Column_scroll.offset controller.column_scroll Queued = 1);
  for _ = 1 to 20 do
    wheel Ready `Down
  done;
  check "column wheel clamps at last page"
    (Column_scroll.offset controller.column_scroll Ready = 8);
  wheel Ready `Up;
  check "up works immediately at bounded end"
    (Column_scroll.offset controller.column_scroll Ready = 7);
  check "wheel leaves selection and saved data intact"
    (Controller.snapshot controller = saved);
  Controller.act controller (Controller.Select "queued-09");
  check "keyboard selection restores follow in target column"
    (Column_scroll.offset controller.column_scroll Queued = 0
    && Column_scroll.offset controller.column_scroll Ready = 7);
  let frame = render 120 36 in
  check "following target selection displays its card"
    (List.exists
       (fun (hit : Ui.hit) -> hit.action = Controller.Select "queued-09")
       frame.hits);
  let active =
    Result.get_ok (Model.start ~simulated:true (make "queued-09" Queued) "run")
  in
  controller.tasks <-
    List.map (fun (t : task) -> if t.id = active.id then active else t) controller.tasks;
  Column_scroll.set controller.column_scroll Ready 7;
  List.iter
    (fun event ->
      Controller.receive controller { task_id = active.id; run_id = "run"; event })
    [ Turn_started; Turn_completed; Exited 0 ];
  check "state movement clears manual destination position"
    (Column_scroll.position controller.column_scroll Ready = None);
  check "automatic move restores follow in destination column"
    (Column_scroll.offset controller.column_scroll Ready = 0
    && (Option.get (Controller.selected controller)).state = Ready);
  let frame = render 120 36 in
  check "moved selected card remains visible"
    (List.exists
       (fun (hit : Ui.hit) -> hit.action = Controller.Select active.id)
       frame.hits);
  Controller.act controller (Controller.Select "ready-09");
  let selected_frame = render 120 36 in
  let r, _, _, _ = List.find (fun (_, s, _, _) -> s = Ready) selected_frame.columns in
  for _ = 1 to 20 do
    let frame = render 120 36 in
    Ui.mouse controller frame ~now:1. (`Press (`Scroll `Up), (r.x + 2, r.y + 2), [])
  done;
  let frame = render 120 36 in
  let _, _, offset, _ = List.find (fun (_, s, _, _) -> s = Ready) frame.columns in
  check "explicit top wheel position does not snap back to selected card"
    (offset = 0 && Column_scroll.position controller.column_scroll Ready = Some 0);
  Controller.act controller (Controller.Select active.id);
  controller.help <- true;
  let frame = render 120 36 in
  let before = Column_scroll.offset controller.column_scroll Ready in
  Ui.mouse controller frame ~now:2. (`Press (`Scroll `Down), (95, 8), []);
  check "Help overlay blocks column wheel"
    (Column_scroll.offset controller.column_scroll Ready = before);
  controller.help <- false;
  Column_scroll.set controller.column_scroll Working 3;
  Controller.act controller (Controller.Select "queued-00");
  Controller.act controller Controller.Start;
  check "explicit Start follows selected task into Working"
    ((Option.get (Controller.selected controller)).state = Working
    && Column_scroll.position controller.column_scroll Working = None);
  Column_scroll.set controller.column_scroll Ready 4;
  let live_task = Option.get (Controller.selected controller) in
  let run_id = (Option.get live_task.active).id in
  Controller.receive controller
    { task_id = live_task.id; run_id; event = Message ("stream", "Stream update") };
  check "stream text does not reset unrelated column position"
    (Column_scroll.position controller.column_scroll Ready = Some 4);
  Controller.act controller Controller.Session_board;
  check "board reset clears independent column offsets"
    (List.for_all
       (fun state -> Column_scroll.offset controller.column_scroll state = 0)
       Model.columns);
  let frame = render 60 20 in
  check "compact list has no column regions" (frame.columns = []);
  Ui.mouse controller frame ~now:3. (`Press (`Scroll `Down), (10, 10), []);
  check "compact list retains its own scroll offset" (controller.board_scroll = 1);
  Printf.printf "Passed %d column scroll checks. Pure frames/events only.\n" !checks
