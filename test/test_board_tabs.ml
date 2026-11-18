open Factory_tui
open Controller

let check name value = if not value then failwith name

let () =
  List.iter
    (fun width ->
      List.iter
        (fun count ->
          let tabs = Board_tabs.make ~width ~archive:true ~count in
          check "both destinations fit normal compact widths"
            (width < 19 || List.length tabs = 2);
          check "only Archive is active"
            (List.for_all
               (fun (item : Board_tabs.item) ->
                 item.active = (item.destination = Archive))
               tabs);
          check "tab targets stay in bounds"
            (List.for_all
               (fun (item : Board_tabs.item) ->
                 item.x >= 0 && item.x + item.width <= width)
               tabs))
        [ 0; 12; 123456 ])
    [ 1; 18; 19; 20; 27; 40; 60; 120 ];
  let t = Controller.create ~external_events:true () in
  let active = Model.make ~id:"active" ~title:"Current work" ~repository:"fixture" in
  let archived = { active with id = "archived"; state = Model.Done } in
  t.tasks <- [ active; archived ];
  t.selected <- active.id;
  t.repository <- Some "missing";
  t.query <- "missing";
  Controller.act t Begin_compose;
  let saved = Controller.snapshot t in
  List.iter
    (fun width ->
      let frame = Ui.render t ~width ~height:36 in
      let archive =
        List.find
          (fun (hit : Ui.hit) -> hit.rect.y = 1 && hit.action = Archive_view)
          frame.hits
      in
      Ui.mouse t frame ~now:0. (`Press `Left, (archive.rect.x, archive.rect.y), []);
      check "Archive tab is usable while composing"
        (t.archive && t.focus = Board && t.input = Normal && not t.zoom);
      check "Archive tab clears stale filters"
        (t.query = "" && t.repository = None && Controller.visible t = [ archived ]);
      Controller.key t (`Enter, []);
      check "Enter opens an archived card read-only"
        (t.zoom && t.input = Normal && t.selected = archived.id);
      Controller.key t (`Escape, []);
      check "Escape returns to Archive list before leaving area"
        (t.archive && (not t.zoom) && t.focus = Board);
      Controller.key t (`Escape, []);
      check "another Escape returns to Board" ((not t.archive) && t.focus = Board);
      check "destination navigation preserves tasks and drafts"
        ((Controller.snapshot t).tasks = saved.tasks
        && (Controller.snapshot t).drafts = saved.drafts);
      Controller.act t (Select active.id);
      Controller.act t Begin_compose)
    [ 60; 120; 240 ];
  Printf.printf
    "Passed persistent destination tabs and archive-layer checks. Pure UI/state.\n"
