open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let make ?(archive = false) ?repository ?(count = 7) ?(query = "") ?(hidden = false)
      width =
    Board_summary.make ~width ~archive ~repository ~count ~query ~hidden
  in
  check "short summary preserves familiar layout"
    ((make 120).text = " Session board  |  7 tasks  | / search tasks");
  let long = make ~repository:(String.make 180 'r') ~query:(String.make 180 'q') 60 in
  check "long values keep actual count visible" (Controller.contains long.text "7 tasks");
  check "long values keep search action visible"
    (List.exists (fun (hit : Board_summary.hit) -> hit.action = Search) long.hits
    && Controller.contains long.text "/ ");
  let archive = make ~archive:true ~query:(String.make 180 'q') 60 in
  check "archive retains accepted count and view name"
    (Controller.contains archive.text "Archive"
    && Controller.contains archive.text "7 tasks accepted");
  let invalid = make ~repository:"repo\255\027\n" ~query:"query\255\027\n" 120 in
  check "invalid text sanitized before widths"
    (Controller.contains invalid.text "repo�  "
    && Controller.contains invalid.text "query�  ");
  List.iter
    (fun width ->
      List.iter
        (fun archive ->
          let summary =
            make ~archive ~repository:"équipe/long-repository-label"
              ~query:(String.make 200 'q') width
          in
          check "summary width bounded"
            (Notty.I.width (Notty.I.string Notty.A.empty summary.text) <= max 0 width);
          check "summary targets match rendered extent"
            (List.for_all
               (fun (hit : Board_summary.hit) ->
                 hit.x >= 0 && hit.width > 0
                 && hit.x + hit.width
                    <= Notty.I.width (Notty.I.string Notty.A.empty summary.text))
               summary.hits);
          check "search target starts at displayed slash"
            (List.for_all
               (fun (hit : Board_summary.hit) ->
                 if hit.action <> Search then true
                 else
                   let cells =
                     List.rev
                       (Uuseg_string.fold_utf_8 `Grapheme_cluster
                          (fun cells cell -> cell :: cells)
                          [] summary.text)
                   in
                   List.nth cells hit.x = "/")
               summary.hits);
          check "targets never overlap"
            (match summary.hits with [ a; b ] -> a.x + a.width <= b.x | _ -> true))
        [ false; true ])
    [ -1; 0; 1; 10; 20; 30; 40; 60; 120 ];
  List.iter
    (fun width ->
      let summary = make ~hidden:true ~query:(String.make 100 'q') width in
      check "off-board summary retains exact board count"
        (width < 32 || Controller.contains summary.text "7 tasks");
      check "off-board summary stays within available cells"
        (Notty.I.width (Notty.I.string Notty.A.empty summary.text) <= max 0 width);
      let reveal =
        List.find_opt
          (fun (hit : Board_summary.hit) -> hit.action = Reveal_selected)
          summary.hits
      in
      check "off-board action exists only when full button fits"
        (Option.is_some reveal = (width >= 32));
      Option.iter
        (fun (hit : Board_summary.hit) ->
          let cells =
            List.rev
              (Uuseg_string.fold_utf_8 `Grapheme_cluster
                 (fun cells cell -> cell :: cells)
                 [] summary.text)
          in
          let button =
            String.concat ""
              (List.filteri
                 (fun index _ -> index >= hit.x && index < hit.x + hit.width)
                 cells)
          in
          check "off-board target covers its complete visible label"
            (button = "[Show card]" || button = "[Chat off-board / Show card]");
          check "off-board target does not overlap summary controls"
            (List.for_all
               (fun (other : Board_summary.hit) ->
                 other.action = Reveal_selected || other.x + other.width <= hit.x)
               summary.hits))
        reveal)
    [ -1; 0; 1; 20; 31; 32; 40; 60; 69; 70; 120 ];
  let controller = Controller.create ~external_events:true () in
  let repo = "/very/long/" ^ String.make 180 'p' ^ "/project" in
  let task = Model.make ~id:"summary" ~title:(String.make 150 'q') ~repository:repo in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  controller.repository <- Some repo;
  controller.query <- String.make 150 'q';
  let saved = Controller.snapshot controller in
  let render width height = Ui.render controller ~width ~height in
  let frame = render 60 23 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (60, 23) frame.image;
  let row = List.nth (String.split_on_char '\n' (Buffer.contents buffer)) 2 in
  check "UI uses repository suffix and filtered count"
    (Controller.contains row "project" && Controller.contains row "1 tasks");
  let header_hits = List.filter (fun (hit : Ui.hit) -> hit.rect.y = 2) frame.hits in
  let archive =
    List.find (fun (hit : Ui.hit) -> hit.action = Controller.Toggle_archive) header_hits
  in
  Ui.mouse controller frame ~now:0. (`Press `Left, (archive.rect.x, 2), []);
  check "label click toggles only board archive view"
    (controller.archive
    && controller.repository = Some repo
    && (Controller.snapshot controller).tasks = saved.tasks
    && (Controller.snapshot controller).drafts = saved.drafts);
  let frame = render 60 23 in
  let search =
    List.find
      (fun (hit : Ui.hit) -> hit.rect.y = 2 && hit.action = Controller.Begin_search)
      frame.hits
  in
  Ui.mouse controller frame ~now:1. (`Press `Left, (search.rect.x, 2), []);
  check "search click edits exact unchanged query"
    (controller.input = Search && Text_edit.text controller.editor = String.make 150 'q');
  Controller.key controller (`Escape, []);
  controller.help <- true;
  let modal = render 60 23 in
  check "modal hides all summary targets"
    (List.for_all
       (fun (hit : Ui.hit) ->
         hit.action <> Controller.Begin_search && hit.action <> Controller.Toggle_archive)
       modal.hits);
  controller.help <- false;
  List.iter
    (fun (width, height) ->
      let frame = render width height in
      check "tiny summary targets stay bounded"
        (List.for_all
           (fun (hit : Ui.hit) ->
             let r = hit.rect in
             r.x >= 0 && r.y >= 0 && r.x + r.w <= width && r.y + r.h <= height)
           frame.hits))
    [ (1, 1); (20, 8); (60, 23); (120, 36); (180, 50) ];
  let active =
    Model.make ~id:"active" ~title:"Active instruction" ~repository:"fixture"
  in
  let accepted = { active with id = "accepted"; state = Model.Done } in
  controller.tasks <- [ active; accepted ];
  controller.drafts <- [ (active.id, "Retained draft") ];
  Controller.act controller (Controller.Select active.id);
  controller.archive <- true;
  controller.repository <- Some "hidden-repository";
  controller.query <- "hidden-query";
  controller.zoom <- true;
  Chat_search.set_query controller.chat_search "retained transcript query";
  Pane_scroll.remember controller.pane_scroll Chat 7;
  Pane_scroll.remember controller.pane_scroll Activity 9;
  let saved = Controller.snapshot controller in
  let frame = render 120 36 in
  let reveal =
    List.find (fun (hit : Ui.hit) -> hit.action = Controller.Reveal_selected) frame.hits
  in
  let chat_position = Pane_scroll.position controller.pane_scroll Chat in
  let activity_position = Pane_scroll.position controller.pane_scroll Activity in
  check "selected off-board chat offers Show card in expanded layout" (reveal.rect.y = 2);
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  check "off-board chat has explicit visible context"
    (Controller.contains (Buffer.contents buffer) "Chat off-board / Show card");
  Ui.mouse controller frame ~now:3. (`Press `Left, (reveal.rect.x, reveal.rect.y), []);
  check "Show card reveals exact active identity without changing saved data"
    (controller.focus = Board && (not controller.zoom) && (not controller.archive)
   && controller.query = "" && controller.repository = None
    && Controller.visible controller = [ active ]
    && Controller.snapshot controller = saved);
  check "Show card retains transcript query and independent reading positions"
    (Chat_search.query controller.chat_search = "retained transcript query"
    && Pane_scroll.position controller.pane_scroll Chat = chat_position
    && Pane_scroll.position controller.pane_scroll Activity = activity_position);
  let frame = render 120 36 in
  check "visible selected card has no redundant reveal control"
    (not
       (List.exists
          (fun (hit : Ui.hit) -> hit.action = Controller.Reveal_selected)
          frame.hits));
  Controller.act controller (Controller.Select accepted.id);
  controller.repository <- Some "hidden-repository";
  controller.query <- "hidden-query";
  controller.board_scroll <- 100;
  controller.sidebar_scroll <- Some 100;
  let frame = render 180 50 in
  let reveal =
    List.find (fun (hit : Ui.hit) -> hit.action = Controller.Reveal_selected) frame.hits
  in
  Controller.act controller Controller.Help;
  let modal = render 180 50 in
  check "Help hides Show card control"
    (not
       (List.exists
          (fun (hit : Ui.hit) -> hit.action = Controller.Reveal_selected)
          modal.hits));
  Controller.act controller Controller.Close_menu;
  Controller.act controller Controller.Begin_search;
  Ui.mouse controller frame ~now:4. (`Press `Left, (reveal.rect.x, reveal.rect.y), []);
  check "Show card does not discard active input"
    (controller.input = Search && controller.query = "hidden-query");
  Controller.key controller (`Enter, []);
  Ui.mouse controller frame ~now:5. (`Press `Left, (reveal.rect.x, reveal.rect.y), []);
  check "Show card opens accepted card in Archive and resets board scrolling"
    (controller.archive && controller.query = "" && controller.repository = None
    && controller.selected = accepted.id
    && Controller.visible controller = [ accepted ]
    && controller.sidebar_scroll = None
    && controller.board_scroll = 0);
  check "Show card starts no runner or workspace job"
    (controller.live_confirmation = None
    && controller.creation_request = None
    && controller.creation_job = None
    && List.for_all (fun (task : Model.task) -> task.active = None) controller.tasks);
  controller.selected <- "missing";
  controller.query <- "untouched";
  let saved = Controller.snapshot controller in
  Controller.act controller Controller.Reveal_selected;
  check "missing selected identity cannot mutate filters"
    (controller.query = "untouched" && Controller.snapshot controller = saved);
  Printf.printf "Passed %d board summary checks. Pure layout/input only.\n" !checks
