open Factory_tui
open Model

let tests = ref 0

let check name condition =
  incr tests;
  if not condition then failwith ("FAILED: " ^ name)

let ok = function Ok x -> x | Error error -> failwith error
let task () = make ~id:"task" ~title:"Implement a feature" ~repository:"fixture"
let run () = ok (start (task ()) "run")
let event ?(run_id = "run") event = { task_id = "task"; run_id; event }

let apply task e =
  match Model.apply task (event e) with
  | Some task -> task
  | None -> failwith "Rejected valid event"

let () =
  check "initial state" ((task ()).state = Queued);
  let t = run () in
  check "start does not acknowledge prompts" (List.hd t.messages).queued;
  let t = ok (send t ~id:"late" "A later instruction") in
  let t = apply t Turn_started in
  check "turn start acknowledges only submitted messages"
    ((not (List.hd t.messages).queued) && (List.nth t.messages 1).queued);
  check "stale runs rejected" (Model.apply t (event ~run_id:"stale" Turn_completed) = None);
  let t = apply t (Message ("reply", "part")) in
  let t = apply t (Message ("reply", "complete")) in
  check "stream updates replace one item"
    (List.length t.messages = 3 && (List.nth t.messages 2).text = "complete");
  let t = apply t Turn_completed in
  check "completion does not finish before exit" (t.state = Working);
  let t = apply t (Exited 0) in
  check "completion plus successful exit is Ready" (t.state = Ready);
  check "late events rejected after exit" (Model.apply t (event (Failed "late")) = None);
  check "exit alone is not completion" ((apply (run ()) (Exited 0)).state = Needs_you);
  check "nonzero exit is not Ready"
    ((apply (apply (run ()) Turn_completed) (Exited 1)).state = Needs_you);
  let failed =
    apply (apply (apply (run ()) (Failed "error")) Turn_completed) (Exited 0)
  in
  check "failure is sticky" (failed.state = Needs_you);
  let waiting =
    apply (apply (apply (run ()) (Input_requested "Question")) Turn_completed) (Exited 0)
  in
  check "input request prevents Ready" (waiting.state = Needs_you);
  check "interrupt stops run" ((apply (run ()) Interrupted).active = None);
  check "only Ready can be accepted" (Result.is_error (accept (run ())));
  let done_task = ok (accept t) in
  check "accept goes to Done" (done_task.state = Done);
  check "Done is read-only"
    (Result.is_error (send done_task ~id:"x" "text")
    && Result.is_error (start done_task "new"));
  check "empty message rejected" (Result.is_error (send (task ()) ~id:"x" "  "));
  let t =
    apply (run ()) Turn_started |> fun t ->
    apply t (Tool ("tool", "first")) |> fun t ->
    apply t Turn_completed |> fun t -> apply t (Exited 0)
  in
  check "empty pending prompt rejects restart" (Result.is_error (start t "second"));
  let t = ok (send t ~id:"next" "Next turn") |> fun t -> ok (start t "second") in
  let t =
    match Model.apply t (event ~run_id:"second" (Tool ("tool", "second"))) with
    | Some t -> t
    | None -> assert false
  in
  check "tool IDs scoped to runs" (List.length t.tools = 2);
  check "event JSON parses"
    (Result.is_ok
       (Events.decode {|{"task_id":"task","run_id":"run","type":"turn.completed"}|}));
  check "malformed JSON rejected" (Result.is_error (Events.decode "not JSON"));
  check "unknown JSON rejected"
    (Result.is_error
       (Events.decode {|{"task_id":"task","run_id":"run","type":"future"}|}));
  check "required fields enforced"
    (Result.is_error (Events.decode {|{"type":"message"}|}));
  check "event objects required" (Result.is_error (Events.decode "[]"));
  check "exit code validated"
    (Result.is_error
       (Events.decode
          {|{"task_id":"task","run_id":"run","type":"process.exited","code":"0"}|}));
  let configured =
    ok (set_model (task ()) " model-one ") |> fun t -> ok (set_harness t Claude)
  in
  let running = ok (start configured "configured-run") in
  let first = List.hd running.runs in
  check "run captures model and harness"
    (first.model = "model-one" && first.harness = Claude && first.status = Running
   && first.ended_at = None);
  let changed = ok (set_model running "model-two") |> fun t -> ok (set_harness t Codex) in
  check "editing next run preserves history"
    (List.hd changed.runs = first
    && changed.model = "model-two" && changed.harness = Codex);
  let apply_configured t event =
    Option.get (Model.apply t { task_id = "task"; run_id = "configured-run"; event })
  in
  let changed = apply_configured changed (Message ("item", "answer")) in
  check "message author uses captured harness"
    ((List.hd (List.rev changed.messages)).author = "Claude (simulated)");
  let changed =
    apply_configured changed Turn_started |> fun t ->
    apply_configured t Turn_completed |> fun t -> apply_configured t (Exited 0)
  in
  check "completed history has end timestamp"
    ((List.hd changed.runs).status = Completed && (List.hd changed.runs).ended_at <> None);
  let changed = ok (send changed ~id:"followup" "Next prompt") in
  check "duplicate run IDs rejected" (Result.is_error (start changed "configured-run"));
  let changed = ok (start changed "second-run") in
  check "second run uses next settings"
    ((List.nth changed.runs 1).model = "model-two"
    && (List.nth changed.runs 1).harness = Codex
    && (List.hd changed.runs).model = "model-one");
  List.iter
    (fun value ->
      check "invalid model rejected" (Result.is_error (set_model (task ()) value)))
    [ ""; " "; "-flag"; "bad\nmodel"; String.make 257 'x' ];
  let finished = ok (accept (apply (apply (run ()) Turn_completed) (Exited 0))) in
  check "accepted settings are read-only"
    (Result.is_error (set_model finished "new")
    && Result.is_error (set_harness finished Claude));
  let stopped = apply (run ()) Interrupted in
  check "interrupt recorded in history" ((List.hd stopped.runs).status = Stopped);
  let failed = apply (run ()) (Exited 1) in
  check "failure recorded in history" ((List.hd failed.runs).status = Run_failed);
  let waiting = apply (apply (run ()) (Input_requested "Reply")) (Exited 0) in
  check "input request recorded in history"
    ((List.hd waiting.runs).status = Awaiting_input);
  let settings = Controller.create ~external_events:true () in
  Controller.key settings (`ASCII 'H', []);
  check "H cycles next harness without starting run"
    ((Option.get (Controller.selected settings)).harness = Claude
    && List.length (Option.get (Controller.selected settings)).runs = 1);
  Controller.key settings (`ASCII 'm', []);
  check "m opens model editor" (settings.input = Controller.Edit_model);
  Controller.set_input settings "replacement-model";
  Controller.key settings (`Enter, []);
  check "model editor applies without adding messages"
    ((Option.get (Controller.selected settings)).model = "replacement-model"
    && List.length (Option.get (Controller.selected settings)).messages = 1);
  Controller.key settings (`ASCII 'm', []);
  Controller.set_input settings "invalid\nmodel";
  Controller.key settings (`Enter, []);
  check "invalid model keeps editor open"
    (settings.input = Controller.Edit_model
    && (Option.get (Controller.selected settings)).model = "replacement-model");
  Controller.key settings (`Escape, []);
  check "model edit cancellation returns to normal" (settings.input = Controller.Normal);
  let ui = Controller.create ~external_events:true () in
  List.iter
    (fun (width, height) ->
      let frame = Ui.render ui ~width ~height in
      check
        (Printf.sprintf "exact frame %dx%d" width height)
        (Notty.I.width frame.image = width && Notty.I.height frame.image = height);
      List.iter
        (fun (hit : Ui.hit) ->
          let r = hit.rect in
          check "hitboxes fit terminal"
            (r.x >= 0 && r.y >= 0 && r.x + r.w <= width && r.y + r.h <= height))
        frame.hits)
    [ (1, 1); (20, 8); (60, 20); (80, 24); (120, 36); (180, 50) ];
  let frame = Ui.render ui ~width:120 ~height:36 in
  let rendered = Buffer.create 4096 in
  Notty.Render.to_buffer rendered Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  let rendered = Buffer.contents rendered in
  List.iter
    (fun label ->
      check ("visible frame content: " ^ label) (Controller.contains rendered label))
    [ "FACTORY"; "Queued"; "Working"; "Needs you"; "Ready"; "T-101"; "conversation" ];

  let card =
    List.find (fun (hit : Ui.hit) -> hit.action = Controller.Select "T-101") frame.hits
  in
  Ui.mouse ui frame ~now:1. (`Press `Left, (card.rect.x, card.rect.y), []);
  check "mouse selects card" (ui.selected = "T-101" && not ui.zoom);
  Ui.mouse ui frame ~now:1.2 (`Press `Left, (card.rect.x, card.rect.y), []);
  check "double click expands with editor" (ui.zoom && ui.input = Controller.Compose);
  Controller.key ui (`Escape, []);
  check "first Escape keeps expanded conversation"
    (ui.zoom && ui.input = Controller.Normal);
  Controller.key ui (`Escape, []);
  check "Escape returns to board" (not ui.zoom);
  Controller.act ui (Controller.Select "T-102");
  Controller.receive ui { task_id = "T-102"; run_id = "demo-102"; event = Turn_completed };
  Controller.receive ui { task_id = "T-102"; run_id = "demo-102"; event = Exited 0 };
  check "automove preserves selected task"
    (ui.selected = "T-102" && (Option.get (Controller.selected ui)).state = Ready);
  Controller.act ui Controller.Begin_compose;
  Controller.set_input ui "draft survives";
  Controller.key ui (`Escape, []);
  Controller.act ui (Controller.Select "T-101");
  check "drafts isolated by task" (Controller.draft ui = "");
  Controller.act ui (Controller.Select "T-102");
  check "draft retained when task changes" (Controller.draft ui = "draft survives");
  Controller.act ui Controller.Begin_compose;
  Controller.submit ui;
  check "send queues message"
    (List.hd (List.rev (Option.get (Controller.selected ui)).messages)).queued;
  Controller.act ui Controller.Begin_search;
  Controller.set_input ui "keyboard";
  check "search filters and selects match"
    (List.length (Controller.visible ui) = 1 && ui.selected = "T-104");
  Controller.key ui (`Enter, []);
  Controller.key ui (`Escape, []);
  check "first Escape from conversation returns board focus" (ui.focus = Controller.Board);
  Controller.key ui (`Escape, []);
  check "Escape on board clears search" (ui.query = "");
  Controller.act ui Controller.Begin_new;
  Controller.set_input ui "A new simulated task";
  Controller.submit ui;
  check "new tasks enter Queued" ((Option.get (Controller.selected ui)).state = Queued);
  check "terminal controls sanitized" (Controller.clean "\027[31m\000" = " [31m ");
  check "UTF-8 backspace preserves valid text" (Controller.remove_last "a界" = "a");
  check "wide characters wrap by terminal cells" (Ui.wrap 3 "界界" = [ "界"; "界" ]);
  check "card titles wrap on words"
    (Ui.wrap_title 24 "Mouse hit-testing and task zoom"
    = [ "Mouse hit-testing and"; "task zoom" ]);
  check "newlines wrap" (Ui.wrap 8 "a\nb" = [ "a"; "b" ]);
  let vim = Controller.create ~external_events:true () in
  let key char = Controller.key vim (`ASCII char, []) in
  let ctrl char = Controller.key vim (`ASCII char, [ `Ctrl ]) in
  let select id = Controller.act vim (Controller.Select id) in
  select "T-101";
  key 'j';
  check "vim j selects next card" (vim.selected = "T-105");
  key 'k';
  check "vim k selects previous card" (vim.selected = "T-101");
  key 'l';
  check "vim l selects next column" (vim.selected = "T-102");
  key 'h';
  check "vim h selects previous column" (vim.selected = "T-101");
  key '2';
  key 'j';
  check "counted j moves two cards" (vim.selected = "T-106" && vim.count = 0);
  key 'g';
  check "g awaits second key" (vim.prefix = Controller.Go && vim.selected = "T-106");
  key 'g';
  check "gg selects first card in column" (vim.selected = "T-101");
  key 'G';
  check "G selects last card in column" (vim.selected = "T-106");
  key '9';
  key '9';
  key '9';
  key '9';
  check "counts are bounded" (vim.count = 999);
  key 'k';
  check "large count clamps selection" (vim.selected = "T-101");
  key '2';
  key 'l';
  check "counted horizontal navigation" (vim.selected = "T-103");
  ctrl 'w';
  key 'l';
  check "Ctrl-W l focuses conversation" (vim.focus = Controller.Conversation);
  key 'h';
  check "detail h does not change selected task" (vim.selected = "T-103");
  ctrl 'w';
  key 'l';
  check "Ctrl-W l focuses activity" (vim.focus = Controller.Activity);
  ctrl 'w';
  key 'h';
  check "Ctrl-W h focuses conversation" (vim.focus = Controller.Conversation);
  ctrl 'w';
  key 'k';
  check "Ctrl-W k focuses board" (vim.focus = Controller.Board);
  ctrl 'w';
  key 'j';
  check "Ctrl-W j focuses conversation" (vim.focus = Controller.Conversation);
  ctrl 'w';
  ctrl 'w';
  check "Ctrl-W Ctrl-W cycles panes" (vim.focus = Controller.Activity);
  ctrl 'w';
  ctrl 'h';
  check "Ctrl-W Ctrl-H navigates panes" (vim.focus = Controller.Conversation);
  Controller.key vim (`Tab, [ `Shift ]);
  check "Shift-Tab cycles backwards" (vim.focus = Controller.Board);
  Controller.act vim Controller.Zoom;
  ctrl 'w';
  key 'k';
  check "expanded panes never focus hidden board" (vim.focus = Controller.Conversation);
  Controller.key vim (`Tab, [ `Shift ]);
  check "expanded reverse cycle stays visible" (vim.focus = Controller.Activity);
  Controller.key vim (`Escape, []);
  check "Escape restores board focus" ((not vim.zoom) && vim.focus = Controller.Board);
  select "T-101";
  vim.page_rows <- 2;
  ctrl 'd';
  check "Ctrl-D moves half-page on board" (vim.selected = "T-105" && not vim.archive);
  ctrl 'f';
  check "Ctrl-F moves full-page without pausing" (vim.selected = "T-106" && not vim.paused);
  ctrl 'b';
  check "Ctrl-B moves full-page backwards" (vim.selected = "T-101");
  ctrl 'd';
  ctrl 'u';
  check "Ctrl-U moves half-page backwards" (vim.selected = "T-101");
  Controller.act vim (Controller.Focus Controller.Activity);
  key 'j';
  check "activity j scrolls one row" (vim.scroll = 1);
  key '3';
  key 'j';
  check "counted activity motion" (vim.scroll = 4);
  key 'k';
  check "activity k scrolls up" (vim.scroll = 3);
  key 'g';
  key 'g';
  check "activity gg goes to top" (vim.scroll = 0);
  vim.page_rows <- 10;
  ctrl 'd';
  check "activity half-page uses viewport" (vim.scroll = 5);
  ctrl 'f';
  check "activity full-page uses viewport" (vim.scroll = 15);
  let chat_scroll = Pane_scroll.position vim.pane_scroll Chat in
  Controller.act vim (Controller.Focus Controller.Conversation);
  check "conversation focus does not inherit activity page offset"
    (vim.scroll = chat_scroll && Pane_scroll.position vim.pane_scroll Activity = 15);
  key 'k';
  check "conversation k scrolls back" (vim.scroll = chat_scroll + 1);
  key 'j';
  check "conversation j scrolls forward" (vim.scroll = chat_scroll);
  key 'G';
  check "conversation G resumes following" (vim.scroll = 0);
  key 'g';
  key 'g';
  ignore (Ui.render vim ~width:120 ~height:36);
  check "conversation top scroll clamps to content" (vim.scroll < 1_000_000);
  select "T-101";
  key 'g';
  Controller.key vim (`Escape, []);
  key 'g';
  check "Escape cancels pending gg" (vim.prefix = Controller.Go);
  key '2';
  key 'i';
  check "entering composer clears prefixes"
    (vim.prefix = Controller.No_prefix && vim.count = 0);
  List.iter key [ 'g'; 'g'; 'G'; 'h'; 'j'; 'k'; 'l'; '3' ];
  ctrl 'w';
  ctrl 'd';
  check "vim keys are literal in composer"
    (Controller.draft vim = "ggGhjkl3" && vim.focus = Controller.Conversation);
  Controller.key vim (`Escape, []);
  key '9';
  let frame = Ui.render vim ~width:120 ~height:36 in
  let hit =
    List.find (fun (hit : Ui.hit) -> hit.action = Controller.Select "T-101") frame.hits
  in
  Ui.mouse vim frame ~now:4. (`Press `Left, (hit.rect.x, hit.rect.y), []);
  check "mouse clears pending count" (vim.count = 0 && vim.prefix = Controller.No_prefix);
  key 'g';
  key 'z';
  key 'g';
  check "unknown key cancels gg prefix" (vim.prefix = Controller.Go);
  Controller.key vim (`Escape, []);
  Controller.act vim Controller.Begin_search;
  List.iter key [ 'g'; 'g'; '3'; 'j' ];
  check "search treats motions as text" (vim.query = "gg3j");
  let raw = Controller.create ~external_events:true () in
  let decode text =
    let parser = Notty.Unescape.create () in
    let bytes = Bytes.of_string text in
    Notty.Unescape.input parser bytes 0 (Bytes.length bytes);
    let rec loop () =
      match Notty.Unescape.next parser with
      | `Key key ->
          Controller.key raw key;
          loop ()
      | `Await | `End -> ()
      | _ -> loop ()
    in
    loop ()
  in
  decode "\023l";
  check "terminal Ctrl-W bytes focus conversation" (raw.focus = Controller.Conversation);
  decode "\023k";
  check "terminal Ctrl-W k focuses board" (raw.focus = Controller.Board);
  Controller.act raw (Controller.Select "T-101");
  raw.page_rows <- 2;
  decode "\004";
  check "terminal Ctrl-D bytes navigate" (raw.selected = "T-105" && not raw.archive);
  decode "\003";
  check "terminal Ctrl-C bytes quit" raw.quit;
  let empty = Controller.create ~external_events:true () in
  empty.query <- "no such task";
  Controller.repair_selection empty;
  List.iter
    (fun char -> Controller.key empty (`ASCII char, []))
    [ 'g'; 'g'; 'G'; 'j'; 'h' ];
  check "vim navigation tolerates empty board" (empty.selected = "");
  let layout = Controller.create ~external_events:true () in
  let rendered width height =
    let frame = Ui.render layout ~width ~height in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, height) frame.image;
    (frame, Buffer.contents buffer)
  in
  let _, wide = rendered 180 50 in
  check "wide sidebar lists repositories"
    (Controller.contains wide "REPOSITORIES"
    && Controller.contains wide "All repositories");
  let _, medium = rendered 120 36 in
  check "medium layout keeps visible reply composer"
    (Controller.contains medium "Reply / next turn"
    && Controller.contains medium "Write a reply");
  check "medium board shows multiple queued cards" (Controller.contains medium "T-105");
  let original_selected = layout.selected in
  Controller.act layout (Controller.Repository (Some "factory"));
  check "repository filter narrows board" (List.length (Controller.visible layout) = 2);
  check "repository filter preserves selected chat" (layout.selected = original_selected);
  Controller.key layout (`ASCII 'j', []);
  check "navigation enters filtered tasks" (layout.selected = "T-106");
  Controller.key layout (`ASCII 'b', []);
  check "b returns to all active tasks" (layout.repository = None && not layout.archive);
  Controller.key layout (`ASCII 'R', []);
  check "R cycles repositories" (layout.repository = Some "factory");
  Controller.key layout (`ASCII 'R', []);
  check "R reaches second repository" (layout.repository = Some "factory-tui");
  Controller.key layout (`ASCII 'R', []);
  check "R returns to all repositories" (layout.repository = None);
  Controller.act layout (Controller.Select "T-104");
  Controller.act layout Controller.Accept;
  check "accepted task retains open chat"
    (layout.selected = "T-104" && (Option.get (Controller.selected layout)).state = Done);
  Controller.act layout Controller.Begin_compose;
  check "accepted chat cannot open composer" (layout.input = Controller.Normal);
  Controller.act layout Controller.Archive_view;
  Controller.act layout Controller.Archive_view;
  check "archive sidebar selection is idempotent" layout.archive;
  check "archive retains open chat" (layout.selected = "T-104");
  Controller.act layout Controller.Help;
  ignore (rendered 120 36);
  Controller.key layout (`ASCII 'G', []);
  let _, help_text = rendered 120 36 in
  check "help explains persistence accurately"
    (Controller.contains help_text "Configured SQLite storage");
  Controller.key layout (`Tab, []);
  let frame, settings_text = rendered 120 36 in
  check "Tab opens settings menu"
    (layout.menu_tab = Controller.Settings_tab
    && Controller.contains settings_text "STORAGE");
  check "memory settings are explicit" (Controller.contains settings_text "In memory");
  check "menu blocks underlying hitboxes"
    (List.for_all
       (fun (hit : Ui.hit) ->
         match hit.action with Controller.Menu_tab _ -> true | _ -> false)
       frame.hits);
  layout.database_path <- Some "/tmp/board.sqlite";
  let _, settings_text = rendered 120 36 in
  check "settings shows selected database"
    (Controller.contains settings_text "/tmp/board.sqlite");
  let help_hit =
    List.find
      (fun (hit : Ui.hit) -> hit.action = Controller.Menu_tab Controller.Help_tab)
      frame.hits
  in
  Ui.mouse layout frame ~now:10. (`Press `Left, (help_hit.rect.x, help_hit.rect.y), []);
  check "menu tabs are clickable" (layout.menu_tab = Controller.Help_tab);
  List.iter
    (fun (width, height) ->
      let frame, _ = rendered width height in
      check "menu frame bounds"
        (Notty.I.width frame.image = width && Notty.I.height frame.image = height);
      List.iter
        (fun (hit : Ui.hit) ->
          let r = hit.rect in
          check "menu hit bounds"
            (r.x >= 0 && r.y >= 0 && r.x + r.w <= width && r.y + r.h <= height))
        frame.hits)
    [ (1, 1); (20, 8); (60, 20); (80, 24); (120, 36); (180, 50) ];
  Controller.key layout (`Escape, []);
  check "Escape closes settings without changing task"
    ((not layout.help) && layout.selected = "T-104");
  Controller.act layout (Controller.Select "T-102");
  Controller.receive layout
    { task_id = "T-102"; run_id = "demo-102"; event = Tool ("tool", "Inspect files") };
  let _, collapsed = rendered 120 36 in
  check "tools collapsed by default"
    ((not layout.tools_expanded) && not (Controller.contains collapsed "Inspect files"));
  Controller.key layout (`ASCII 't', []);
  let _, expanded = rendered 120 36 in
  check "t expands tool output"
    (layout.tools_expanded && Controller.contains expanded "Inspect files");
  Controller.key layout (`ASCII 't', []);
  check "t collapses tool output" (not layout.tools_expanded);
  Controller.act layout Controller.Session_board;
  let frame, _ = rendered 180 50 in
  let repo_hit =
    List.find
      (fun (hit : Ui.hit) -> hit.action = Controller.Repository (Some "factory"))
      frame.hits
  in
  Ui.mouse layout frame ~now:11. (`Press `Left, (repo_hit.rect.x, repo_hit.rect.y), []);
  check "sidebar repositories are clickable" (layout.repository = Some "factory");
  Controller.act layout Controller.Session_board;
  let frame, _ = rendered 120 36 in
  let composer =
    List.find (fun (hit : Ui.hit) -> hit.action = Controller.Begin_compose) frame.hits
  in
  Ui.mouse layout frame ~now:12. (`Press `Left, (composer.rect.x, composer.rect.y), []);
  check "visible composer is clickable" (layout.input = Controller.Compose);
  let path = Filename.temp_file "factory-events" ".jsonl" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      let out = open_out path in
      output_string out {|{"task_id":"task","run_id":"run","type":"turn.completed"}|};
      close_out out;
      let source = Events.open_source path in
      Fun.protect
        ~finally:(fun () -> Events.close_source source)
        (fun () ->
          check "partial replay lines wait" (Events.poll source = []);
          let out = open_out_gen [ Open_append; Open_wronly ] 0o600 path in
          output_char out '\n';
          close_out out;
          check "appended replay lines consumed" (List.length (Events.poll source) = 1);
          check "replay does not duplicate events" (Events.poll source = []);
          Events.close_source source;
          Events.close_source source;
          check "closed replay source rejects polling"
            (try
               ignore (Events.poll source);
               false
             with Invalid_argument _ -> true)));
  Printf.printf "Passed %d checks. No live agents or workspace access.\n" !tests
