open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let controller = Controller.create ~external_events:true () in
  controller.focus <- Controller.Conversation;
  let frame = Ui.render controller ~width:180 ~height:50 in
  let before = Controller.snapshot controller in
  let state () =
    ( controller.focus,
      controller.scroll,
      controller.board_scroll,
      controller.sidebar_scroll,
      List.map (Column_scroll.position controller.column_scroll) Model.columns )
  in
  let original = state () in
  List.iter
    (fun point ->
      Ui.mouse controller frame ~now:1. (`Press (`Scroll `Up), point, []);
      check "non-scrollable surface leaves pane state unchanged" (state () = original))
    [ (3, 0); (3, 2); (3, 4); (3, 10); (3, 47); (40, 48); (40, 49); (-1, 8); (180, 8) ];
  let chat, _ =
    List.find (fun (_, focus) -> focus = Controller.Conversation) frame.panes
  in
  Ui.mouse controller frame ~now:2. (`Press (`Scroll `Up), (chat.x + 2, chat.y + 2), []);
  check "wheel over visible chat scrolls history"
    (controller.scroll = 3 && controller.focus = Controller.Conversation);
  let activity, _ =
    List.find (fun (_, focus) -> focus = Controller.Activity) frame.panes
  in
  Ui.mouse controller frame ~now:3.
    (`Press (`Scroll `Down), (activity.x + 2, activity.y + 2), []);
  check "wheel over visible Activity selects its focus"
    (controller.focus = Controller.Activity && controller.scroll = 6);
  let current = state () in
  Ui.mouse controller frame ~now:4.
    (`Press (`Scroll `Up), (chat.x + 2, chat.y + chat.h + 1), []);
  check "wheel over composer does not scroll another pane" (state () = current);
  check "wheel targeting changes no saved task or draft"
    (Controller.snapshot controller = before);
  Controller.act controller (Controller.Focus Controller.Conversation);
  let compact = Ui.render controller ~width:60 ~height:20 in
  let r, _ =
    List.find (fun (_, focus) -> focus = Controller.Conversation) compact.panes
  in
  Ui.mouse controller compact ~now:5. (`Press (`Scroll `Up), (r.x + 1, r.y + 1), []);
  check "compact visible detail receives wheel"
    (controller.focus = Controller.Conversation);
  Controller.act controller (Controller.Focus Controller.Board);
  let list_frame = Ui.render controller ~width:60 ~height:20 in
  Ui.mouse controller list_frame ~now:6. (`Press (`Scroll `Down), (10, 10), []);
  check "compact list wheel still works" (controller.board_scroll = 1);
  List.iter
    (fun (width, height) ->
      let frame = Ui.render controller ~width ~height in
      check "registered scroll panes fit terminal"
        (List.for_all
           (fun ((r : Ui.rect), _) ->
             r.x >= 0 && r.y >= 0 && r.x + r.w <= width && r.y + r.h <= height)
           frame.panes))
    [ (20, 8); (60, 20); (120, 36); (180, 50) ];
  let saved = Controller.snapshot controller in
  Controller.act controller Controller.Help;
  let modal = Ui.render controller ~width:180 ~height:50 in
  let r = Option.get modal.modal_scroll in
  let original = state () in
  List.iter
    (fun point ->
      Ui.mouse controller modal ~now:7. (`Press (`Scroll `Down), point, []);
      check "menu non-content surfaces scroll neither overlay nor background"
        (state () = original && controller.menu_scroll = 0))
    [
      (2, 10);
      (r.x + 2, r.y - 2);
      (r.x + 2, r.y - 1);
      (r.x + 2, r.y + r.h);
      (r.x - 1, r.y + 2);
      (40, 48);
    ];
  Ui.mouse controller modal ~now:8. (`Press (`Scroll `Down), (r.x + 2, r.y + 2), []);
  check "menu content receives wheel without moving background"
    (controller.menu_scroll = 3 && state () = original);
  check "modal wheel changes no saved state" (Controller.snapshot controller = saved);
  List.iter
    (fun (width, height) ->
      let frame = Ui.render controller ~width ~height in
      check "modal content geometry fits tiny and resized terminals"
        (Option.fold ~none:true
           ~some:(fun (r : Ui.rect) ->
             r.x >= 0 && r.y >= 0 && r.w > 0 && r.h > 0
             && r.x + r.w <= width
             && r.y + r.h <= height)
           frame.modal_scroll))
    [ (1, 1); (20, 8); (60, 20); (120, 36); (180, 50) ];
  Printf.printf "Passed %d wheel target checks. Pure frames and mouse input only.\n"
    !checks
