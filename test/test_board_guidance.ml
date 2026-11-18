open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let () =
  let config = ok (Live_runner.configure ~executable:"/bin/sh" ~gateway_file:None) in
  let controller = Controller.create () in
  controller.database_path <- Some "/fixture/board.sqlite";
  ok (Controller.initialize_board controller ~saved:None ~live:(Some config));
  check "new live board has no seed tasks"
    (controller.tasks = [] && controller.selected = "");
  check "new live board has no scheduler or drafts"
    (controller.schedules = [] && controller.drafts = []);
  check "new live board is enabled without pending run"
    (controller.live_config <> None && controller.live_confirmation = None);
  let saved = Controller.snapshot controller in
  check "empty board codec works" (ok (Snapshot.decode (Snapshot.encode saved)) = saved);
  let render width height =
    let frame = Ui.render controller ~width ~height in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, height) frame.image;
    (frame, Buffer.contents buffer)
  in
  let frame, text = render 120 36 in
  check "empty live board has actionable guidance"
    (Controller.contains text "Your factory starts here"
    && Controller.contains text "Create workspace task");
  check "workflow includes execution and review"
    (Controller.contains text "confirmation" && Controller.contains text "Review changes");
  check "empty live board has no sample card names"
    ((not (Controller.contains text "T-101"))
    && not (Controller.contains text "Mouse hit-testing"));
  check "rendering onboarding doesn't change snapshot"
    (Controller.snapshot controller = saved);
  let button =
    List.find
      (fun (hit : Ui.hit) -> hit.action = Controller.Begin_workspace && hit.rect.y < 33)
      frame.hits
  in
  let row = List.nth (String.split_on_char '\n' text) button.rect.y in
  check "onboarding hit aligns with visible button"
    (Controller.contains row "Create workspace task");
  Ui.mouse controller frame ~now:1. (`Press `Left, (button.rect.x, button.rect.y), []);
  check "click opens form not job"
    (controller.workspace_form <> None
    && controller.creation_request = None
    && controller.creation_job = None);
  Controller.act controller Controller.Cancel_workspace;
  Controller.key controller (`ASCII 'n', []);
  check "live n opens workspace form not a demo"
    (controller.workspace_form <> None && controller.tasks = []);
  Controller.act controller Controller.Cancel_workspace;
  Controller.key controller (`ASCII 's', []);
  check "empty board cannot queue execution"
    (controller.live_confirmation = None && controller.tasks = []);
  List.iter
    (fun (width, height) ->
      let frame, _ = render width height in
      check "onboarding frame fits terminal"
        (Notty.I.width frame.image = width && Notty.I.height frame.image = height);
      List.iter
        (fun (hit : Ui.hit) ->
          let r = hit.rect in
          check "onboarding hit fits terminal"
            (r.x >= 0 && r.y >= 0 && r.x + r.w <= width && r.y + r.h <= height))
        frame.hits)
    [ (1, 1); (20, 8); (60, 20); (80, 24); (120, 36); (180, 50) ];
  Controller.key controller (`ASCII '?', []);
  check "menu available on empty board" controller.help;
  Controller.key controller (`Tab, []);
  let _, text = render 120 36 in
  check "empty board settings reflect live state"
    (Controller.contains text "live Codex"
    && Controller.contains text "/fixture/board.sqlite");
  Controller.key controller (`Escape, []);
  controller.archive <- true;
  let _, text = render 120 36 in
  check "empty archive has separate guidance"
    (Controller.contains text "Archive is empty"
    && Controller.contains text "Only tasks you accept");
  controller.query <- "hidden";
  let frame, text = render 120 36 in
  check "filtered empty board has separate guidance"
    (Controller.contains text "No matching tasks");
  let button =
    List.find
      (fun (hit : Ui.hit) ->
        hit.action = Controller.Session_board && hit.rect.y > 3 && hit.rect.y < 33)
      frame.hits
  in
  Ui.mouse controller frame ~now:2. (`Press `Left, (button.rect.x, button.rect.y), []);
  check "clear filters restores active board"
    (controller.query = "" && controller.repository = None && not controller.archive);
  let existing = Controller.create () in
  let snapshot = Controller.snapshot existing in
  let restored = Controller.create () in
  restored.database_path <- Some "/fixture/existing.sqlite";
  ok (Controller.initialize_board restored ~saved:(Some snapshot) ~live:(Some config));
  check "existing saved tasks never silently removed"
    (List.length restored.tasks = List.length snapshot.tasks
    && restored.selected = snapshot.selected);
  check "existing interrupted tasks recover safely"
    (List.for_all (fun (task : Model.task) -> task.active = None) restored.tasks
    && restored.schedules = []);
  let accepted =
    {
      (Model.make ~id:"accepted" ~title:"Retained accepted task" ~repository:"fixture") with
      state = Model.Done;
      messages =
        [
          {
            Model.id = "answer";
            author = "Codex";
            text = "Retained answer";
            queued = false;
          };
        ];
    }
  in
  let archived = Controller.create () in
  archived.tasks <- [ accepted ];
  archived.selected <- accepted.id;
  let saved_archive = Controller.snapshot archived in
  let reopened = Controller.create () in
  ok (Controller.initialize_board reopened ~saved:(Some saved_archive) ~live:None);
  check "active restart retains archived chat independently of board"
    (reopened.selected = accepted.id
    && (not reopened.archive)
    && Controller.visible reopened = []);
  Controller.key reopened (`ASCII 'd', []);
  check "opening archive selects the retained task" (reopened.selected = accepted.id);
  Controller.key reopened (`ASCII 'e', []);
  check "archived task can open directly after restart" reopened.zoom;
  let frame = Ui.render reopened ~width:120 ~height:36 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  check "reopened archive zoom renders the retained answer"
    (Controller.contains (Buffer.contents buffer) "Retained answer");
  Controller.act reopened Controller.Begin_compose;
  check "reopened accepted task stays read-only" (reopened.input = Controller.Normal);
  Controller.act reopened Controller.Archive_view;
  check "repeated archive action preserves selected identity"
    (reopened.selected = accepted.id);
  reopened.selected <- "";
  Controller.act reopened Controller.Archive_view;
  check "sidebar archive action repairs an empty selection"
    (reopened.selected = accepted.id);
  reopened.query <- "not-visible";
  Controller.act reopened Controller.Archive_view;
  check "archive filter preserves retained conversation"
    (reopened.selected = accepted.id && Controller.visible reopened = []);
  reopened.query <- "";
  Controller.act reopened Controller.Archive_view;
  check "clearing archive filter preserves selected conversation"
    (reopened.selected = accepted.id);
  let active =
    Model.make ~id:"active" ~title:"Active task" ~repository:"another-fixture"
  in
  reopened.tasks <- [ active; accepted ];
  reopened.zoom <- false;
  Controller.act reopened (Controller.Select active.id);
  Chat_search.set_query reopened.chat_search "retained search";
  Pane_scroll.remember reopened.pane_scroll Chat 7;
  Pane_scroll.remember reopened.pane_scroll Activity 11;
  let check_active_view name =
    check name
      (reopened.selected = active.id
      && Chat_search.query reopened.chat_search = "retained search"
      && Pane_scroll.position reopened.pane_scroll Chat = 7
      && Pane_scroll.position reopened.pane_scroll Activity = 11)
  in
  Controller.act reopened Controller.Archive_view;
  check "archive shows accepted cards while active chat remains open"
    (Controller.visible reopened = [ accepted ]);
  check_active_view "sidebar archive preserves conversation reading state";
  Controller.act reopened Controller.Toggle_archive;
  Controller.act reopened Controller.Toggle_archive;
  check_active_view "archive toggle preserves conversation reading state";
  Controller.act reopened Controller.Session_board;
  check_active_view "session board preserves conversation reading state";
  Controller.act reopened (Controller.Select accepted.id);
  reopened.query <- "hidden";
  Controller.key reopened (`Escape, []);
  check "Escape clears board search without replacing accepted chat"
    (reopened.query = "" && reopened.selected = accepted.id);
  Controller.act reopened (Controller.Select active.id);
  Controller.act reopened Controller.Archive_view;
  Controller.key reopened (`ASCII 'j', []);
  check "explicit archive navigation selects the visible accepted task"
    (reopened.selected = accepted.id);
  Controller.act reopened Controller.Session_board;
  Controller.key reopened (`ASCII 'j', []);
  check "explicit board navigation enters visible active tasks"
    (reopened.selected = active.id);
  reopened.selected <- "missing";
  Controller.act reopened Controller.Archive_view;
  check "archive repairs missing identity from visible tasks"
    (reopened.selected = accepted.id);
  let old_empty = Controller.create () in
  ok (Controller.initialize_board old_empty ~saved:(Some saved) ~live:None);
  check "persisted empty board stays empty in later demo launch" (old_empty.tasks = []);
  let demo = Controller.create () in
  ok (Controller.initialize_board demo ~saved:None ~live:None);
  check "fresh demo launch still has seed cards"
    (List.length demo.tasks = 6 && demo.schedules <> []);
  let guidance =
    Board_guidance.empty ~live:false ~has_tasks:false ~archived:false ~filtered:false
  in
  check "unconfigured empty demo guidance does not imply live calls"
    (guidance.action = Board_guidance.Create_demo
    && List.exists (fun line -> Controller.contains line "simulation") guidance.lines);
  Printf.printf "Passed %d first-run board checks. No process or database access.\n"
    !checks
