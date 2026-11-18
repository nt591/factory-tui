open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let image_text frame width height =
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, height) frame.Ui.image;
  Buffer.contents buffer

let window controller key =
  Controller.key controller (`ASCII 'w', [ `Ctrl ]);
  Controller.key controller (`ASCII key, [])

let () =
  let preferences = Pane_layout.create () in
  let choose width height detail_focused =
    Pane_layout.choose ~preferences ~width ~height ~detail_focused ()
  in
  check "default stacked split is unchanged" (choose 120 30 false = Pane_layout.Stacked 16);
  check "board grows by requested rows"
    (Pane_layout.resize preferences ~detail:false ~delta:3 = Changed
    && choose 120 30 false = Stacked 19);
  check "detail growth takes space from board"
    (Pane_layout.resize preferences ~detail:true ~delta:2 = Changed
    && choose 120 30 true = Stacked 17);
  check "stacked preference scales with terminal height" (choose 120 60 true = Stacked 34);
  check "board cannot hide detail"
    (Pane_layout.resize preferences ~detail:false ~delta:1000 = Changed
    && choose 120 60 true = Stacked 50
    && Pane_layout.resize preferences ~detail:false ~delta:1 = At_limit);
  let clamped = choose 120 30 true in
  check "usable terminals reserve editor room when board is enlarged"
    (match clamped with Stacked top -> 30 - top >= 10 | _ -> false);
  ignore (choose 120 60 true);
  check "detail cannot hide board"
    (Pane_layout.resize preferences ~detail:true ~delta:1000 = Changed
    && choose 120 60 true = Stacked 9);
  check "wide split has an independent default" (choose 200 60 true = Side_by_side 116);
  check "wide chat grows by requested columns"
    (Pane_layout.resize preferences ~detail:true ~delta:8 = Changed
    && choose 200 60 true = Side_by_side 108);
  check "width constraints do not erase a preferred ratio"
    (choose 155 60 true = Side_by_side 88 && choose 200 60 true = Side_by_side 108);
  check "wide preference survives a temporary compact layout"
    (choose 60 8 false = Board
    && Pane_layout.resize preferences ~detail:false ~delta:3 = No_split
    && choose 200 60 true = Side_by_side 108);
  check "minimum stacked height keeps both regions visible"
    (choose 60 17 false = Stacked 9);
  check "small focused editor remains the only detail pane" (choose 60 17 true = Detail);
  Pane_layout.hide preferences;
  check "hidden split cannot be resized"
    (Pane_layout.resize preferences ~detail:true ~delta:1 = No_split);
  check "zoom does not erase preferences" (choose 200 60 true = Side_by_side 108);
  check "extreme positive delta stays bounded"
    (Pane_layout.resize preferences ~detail:false ~delta:max_int = Changed
    && choose 200 60 true = Side_by_side 136);
  check "extreme negative delta stays bounded"
    (Pane_layout.resize preferences ~detail:true ~delta:min_int = At_limit);
  Pane_layout.reset preferences;
  check "reset restores both orientation defaults"
    (choose 200 60 true = Side_by_side 116 && choose 120 30 false = Stacked 16);
  List.iter
    (fun (width, height) ->
      List.iter
        (fun detail_focused ->
          ignore (choose width height detail_focused);
          ignore (Pane_layout.resize preferences ~detail:detail_focused ~delta:999);
          let layout = choose width height detail_focused in
          check "adjusted split stays within content constraints"
            (match layout with
            | Side_by_side left -> left >= 88 && width - left >= 64
            | Stacked top -> top >= 9 && height - top >= if height >= 21 then 10 else 8
            | Board | Detail -> true))
        [ false; true ])
    [ (1, 1); (60, 17); (120, 21); (154, 50); (155, 30); (200, 60); (1000, 1000) ];
  let configured =
    match Pane_layout.make_defaults ~board_width:(Some 55) ~board_height:(Some 40) with
    | Ok defaults -> defaults
    | Error error -> failwith error
  in
  check "invalid programmatic defaults rejected"
    (Result.is_error (Pane_layout.make_defaults ~board_width:(Some 0) ~board_height:None));
  Pane_layout.set_defaults preferences configured;
  check "configured height applied" (choose 120 30 false = Stacked 12);
  check "configured width applied independently" (choose 200 60 true = Side_by_side 110);
  ignore (Pane_layout.resize preferences ~detail:true ~delta:5);
  check "runtime width overrides configured default"
    (choose 200 60 true = Side_by_side 105);
  Pane_layout.reset preferences;
  check "reset returns to configured defaults, not automatic"
    (choose 200 60 true = Side_by_side 110 && choose 120 30 false = Stacked 12);
  check "configured height scales with resize" (choose 120 60 false = Stacked 24);
  check "configured proportions clamp without losing preference"
    (choose 155 60 false = Side_by_side 88 && choose 200 60 false = Side_by_side 110);
  Pane_layout.set_defaults preferences Pane_layout.automatic;
  check "removing configured defaults restores automatic sizes"
    (choose 120 30 false = Stacked 16 && choose 200 60 false = Side_by_side 116);
  let controller = Controller.create ~external_events:true () in
  let saved = Controller.snapshot controller in
  let original = Ui.render controller ~width:120 ~height:36 in
  let original_text = image_text original 120 36 in
  window controller '+';
  let larger = Ui.render controller ~width:120 ~height:36 in
  let r, _, _, _ = List.hd larger.columns in
  let original_r, _, _, _ = List.hd original.columns in
  check "keyboard resizes rendered board" (r.h = original_r.h + 1);
  check "resize keeps task and run state unchanged"
    (Controller.snapshot controller = saved);
  window controller '=';
  let reset = Ui.render controller ~width:120 ~height:36 in
  check "reset restores board and chat geometry"
    (List.map (fun (r, _, _, _) -> r) reset.columns
     = List.map (fun (r, _, _, _) -> r) original.columns
    && reset.panes = original.panes);
  Controller.key controller (`ASCII '3', []);
  window controller '+';
  let count_frame = Ui.render controller ~width:120 ~height:36 in
  let first_rect =
    let r, _, _, _ = List.hd count_frame.columns in
    r
  in
  let original_rect =
    let r, _, _, _ = List.hd original.columns in
    r
  in
  check "numeric count survives Ctrl-W prefix" (first_rect.h = original_rect.h + 3);
  Controller.act controller (Controller.Focus Conversation);
  window controller '+';
  let smaller_board = Ui.render controller ~width:120 ~height:36 in
  let r, _, _, _ = List.hd smaller_board.columns in
  check "focused conversation grows its region" (r.h = first_rect.h - 1);
  Controller.act controller Controller.Zoom;
  ignore (Ui.render controller ~width:120 ~height:36);
  window controller '+';
  check "zoom explains why primary split is unavailable"
    (Controller.contains controller.status "No board/chat split");
  Controller.key controller (`Escape, []);
  let returned = Ui.render controller ~width:120 ~height:36 in
  check "return from zoom restores adjusted split"
    (returned.columns = smaller_board.columns);
  controller.status <- "Storage error: fixture failure";
  window controller '+';
  ignore (Ui.render controller ~width:120 ~height:36);
  check "pane adjustment does not hide storage failure"
    (controller.status = "Storage error: fixture failure");
  window controller '=';
  check "reset does not hide storage failure"
    (controller.status = "Storage error: fixture failure");
  let modal_layout = Ui.render controller ~width:120 ~height:36 in
  Controller.act controller Controller.Help;
  let menu_before = Controller.snapshot controller in
  window controller '+';
  check "menu input does not resize behind modal"
    (Controller.snapshot controller = menu_before);
  Controller.key controller (`Escape, []);
  check "menu leaves pane geometry unchanged"
    ((Ui.render controller ~width:120 ~height:36).columns = modal_layout.columns);
  Controller.act controller Controller.Begin_compose;
  Controller.paste_key controller (`ASCII '+', []);
  check "composer keeps resize characters literal" (Controller.draft controller = "+");
  Controller.key controller (`Escape, []);
  let active_before = (Option.get (Controller.selected controller)).active in
  controller.help <- true;
  ignore (Ui.render controller ~width:120 ~height:36);
  window controller '+';
  check "Help overlay isolates pane prefix"
    ((Option.get (Controller.selected controller)).active = active_before);
  controller.help <- false;
  controller.status <- "fixture";
  Pane_layout.set_defaults controller.pane_layout configured;
  ignore (Ui.render controller ~width:120 ~height:36);
  window controller '+';
  ignore (Ui.render controller ~width:120 ~height:36);
  window controller '=';
  let configured_frame = Ui.render controller ~width:120 ~height:36 in
  let r, _, _, _ = List.hd configured_frame.columns in
  check "render uses configured reset dimensions" (r.h = 12);
  check "reset status names configured defaults"
    (controller.status = "Configured pane sizes restored.");
  check "configured layout does not alter persisted data"
    ((Controller.snapshot controller).tasks = saved.tasks);
  List.iter
    (fun (width, height) ->
      ignore (Ui.render controller ~width ~height);
      window controller '+';
      let frame = Ui.render controller ~width ~height in
      check "resized image dimensions remain exact"
        (Notty.I.width frame.image = width && Notty.I.height frame.image = height);
      check "resized mouse targets remain bounded"
        (List.for_all
           (fun (hit : Ui.hit) ->
             let r = hit.rect in
             r.x >= 0 && r.y >= 0 && r.x + r.w <= width && r.y + r.h <= height)
           frame.hits))
    [ (1, 1); (20, 8); (60, 23); (120, 36); (180, 50); (240, 60) ];
  check "initial frame contains board and chat"
    (Controller.contains original_text "conversation"
    && Controller.contains original_text "Queued");
  Printf.printf "Passed %d adjustable pane checks. Pure layouts and input only.\n" !checks
