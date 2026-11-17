open Factory_tui
open Model
let tests = ref 0
let check name condition =
  incr tests;
  if not condition then failwith ("FAILED: " ^ name)
let ok = function Ok x -> x | Error error -> failwith error
let task () = make ~id:"task" ~title:"Implement a feature" ~repository:"fixture"
let run () = ok (start (task ()) "run")
let event ?(run_id = "run") event = {task_id = "task"; run_id; event}
let apply task e = match Model.apply task (event e) with Some task -> task | None -> failwith "Rejected valid event"

let () =
  check "initial state" ((task ()).state = Queued);
  let t = run () in
  check "start does not acknowledge prompts" ((List.hd t.messages).queued);
  let t = ok (send t ~id:"late" "A later instruction") in
  let t = apply t Turn_started in
  check "turn start acknowledges only submitted messages"
    (not (List.hd t.messages).queued && (List.nth t.messages 1).queued);
  check "stale runs rejected" (Model.apply t (event ~run_id:"stale" Turn_completed) = None);
  let t = apply t (Message ("reply", "part")) in
  let t = apply t (Message ("reply", "complete")) in
  check "stream updates replace one item" (List.length t.messages = 3 && (List.nth t.messages 2).text = "complete");
  let t = apply t Turn_completed in
  check "completion does not finish before exit" (t.state = Working);
  let t = apply t (Exited 0) in
  check "completion plus successful exit is Ready" (t.state = Ready);
  check "late events rejected after exit" (Model.apply t (event (Failed "late")) = None);
  check "exit alone is not completion" ((apply (run ()) (Exited 0)).state = Needs_you);
  check "nonzero exit is not Ready" ((apply (apply (run ()) Turn_completed) (Exited 1)).state = Needs_you);
  let failed = apply (apply (apply (run ()) (Failed "error")) Turn_completed) (Exited 0) in
  check "failure is sticky" (failed.state = Needs_you);
  let waiting = apply (apply (apply (run ()) (Input_requested "Question")) Turn_completed) (Exited 0) in
  check "input request prevents Ready" (waiting.state = Needs_you);
  check "interrupt stops run" ((apply (run ()) Interrupted).active = None);
  check "only Ready can be accepted" (Result.is_error (accept (run ())));
  let done_task = ok (accept t) in
  check "accept goes to Done" (done_task.state = Done);
  check "Done is read-only" (Result.is_error (send done_task ~id:"x" "text") && Result.is_error (start done_task "new"));
  check "empty message rejected" (Result.is_error (send (task ()) ~id:"x" "  "));
  let t = apply (run ()) Turn_started |> fun t -> apply t (Tool ("tool", "first")) |> fun t -> apply t Turn_completed |> fun t -> apply t (Exited 0) in
  check "empty pending prompt rejects restart" (Result.is_error (start t "second"));
  let t = ok (send t ~id:"next" "Next turn") |> fun t -> ok (start t "second") in
  let t = match Model.apply t (event ~run_id:"second" (Tool ("tool", "second"))) with Some t -> t | None -> assert false in
  check "tool IDs scoped to runs" (List.length t.tools = 2);
  check "event JSON parses" (Result.is_ok (Events.decode {|{"task_id":"task","run_id":"run","type":"turn.completed"}|}));
  check "malformed JSON rejected" (Result.is_error (Events.decode "not JSON"));
  check "unknown JSON rejected" (Result.is_error (Events.decode {|{"task_id":"task","run_id":"run","type":"future"}|}));
  check "required fields enforced" (Result.is_error (Events.decode {|{"type":"message"}|}));
  check "event objects required" (Result.is_error (Events.decode "[]"));
  check "exit code validated" (Result.is_error (Events.decode {|{"task_id":"task","run_id":"run","type":"process.exited","code":"0"}|}));
  let ui = Controller.create ~external_events:true () in
  List.iter (fun (width, height) ->
    let frame = Ui.render ui ~width ~height in
    check (Printf.sprintf "exact frame %dx%d" width height)
      (Notty.I.width frame.image = width && Notty.I.height frame.image = height);
    List.iter (fun (hit : Ui.hit) ->
      let r = hit.rect in
      check "hitboxes fit terminal" (r.x >= 0 && r.y >= 0 && r.x + r.w <= width && r.y + r.h <= height)) frame.hits)
    [1,1; 20,8; 60,20; 80,24; 120,36; 180,50];
  let frame = Ui.render ui ~width:120 ~height:36 in
  let rendered = Buffer.create 4096 in
  Notty.Render.to_buffer rendered Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  let rendered = Buffer.contents rendered in
  List.iter (fun label -> check ("visible frame content: " ^ label)
    (Controller.contains rendered label)) ["FACTORY"; "Queued"; "Working"; "Needs you"; "Ready"; "T-101"; "conversation"];

  let card = List.find (fun (hit : Ui.hit) -> hit.action = Controller.Select "T-101") frame.hits in
  Ui.mouse ui frame ~now:1. (`Press `Left, (card.rect.x, card.rect.y), []);
  check "mouse selects card" (ui.selected = "T-101" && not ui.zoom);
  Ui.mouse ui frame ~now:1.2 (`Press `Left, (card.rect.x, card.rect.y), []);
  check "double click expands" ui.zoom;
  Controller.key ui (`Escape, []);
  check "Escape returns to board" (not ui.zoom);
  Controller.act ui (Controller.Select "T-102");
  Controller.receive ui {task_id = "T-102"; run_id = "demo-102"; event = Turn_completed};
  Controller.receive ui {task_id = "T-102"; run_id = "demo-102"; event = Exited 0};
  check "automove preserves selected task" (ui.selected = "T-102" && (Option.get (Controller.selected ui)).state = Ready);
  Controller.act ui Controller.Begin_compose;
  Controller.set_input ui "draft survives";
  Controller.key ui (`Escape, []);
  Controller.act ui (Controller.Select "T-101");
  check "drafts isolated by task" (Controller.draft ui = "");
  Controller.act ui (Controller.Select "T-102");
  check "draft retained when task changes" (Controller.draft ui = "draft survives");
  Controller.act ui Controller.Begin_compose;
  Controller.submit ui;
  check "send queues message" ((List.hd (List.rev (Option.get (Controller.selected ui)).messages)).queued);
  Controller.act ui Controller.Begin_search;
  Controller.set_input ui "keyboard";
  check "search filters and selects match" (List.length (Controller.visible ui) = 1 && ui.selected = "T-104");
  Controller.key ui (`Enter, []);
  Controller.key ui (`Escape, []);
  check "Escape clears search" (ui.query = "");
  Controller.act ui Controller.Begin_new;
  Controller.set_input ui "A new simulated task";
  Controller.submit ui;
  check "new tasks enter Queued" ((Option.get (Controller.selected ui)).state = Queued);
  check "terminal controls sanitized" (Controller.clean "\027[31m\000" = " [31m ");
  check "UTF-8 backspace preserves valid text" (Controller.remove_last "a界" = "a");
  check "wide characters wrap by terminal cells" (Ui.wrap 3 "界界" = ["界"; "界"]);
  check "card titles wrap on words" (Ui.wrap_title 24 "Mouse hit-testing and task zoom" = ["Mouse hit-testing and"; "task zoom"]);
  check "newlines wrap" (Ui.wrap 8 "a\nb" = ["a"; "b"]);
  let path = Filename.temp_file "factory-events" ".jsonl" in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    let out = open_out path in
    output_string out {|{"task_id":"task","run_id":"run","type":"turn.completed"}|}; close_out out;
    let source = Events.open_source path in
    Fun.protect ~finally:(fun () -> Unix.close source.fd) (fun () ->
      check "partial replay lines wait" (Events.poll source = []);
      let out = open_out_gen [Open_append; Open_wronly] 0o600 path in output_char out '\n'; close_out out;
      check "appended replay lines consumed" (List.length (Events.poll source) = 1);
      check "replay does not duplicate events" (Events.poll source = [])));
  Printf.printf "Passed %d checks. No live agents or workspace access.\n" !tests
