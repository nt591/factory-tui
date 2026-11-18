open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let view ~offset ~following =
  { Chat_viewport.offset; distance = (if following then 0 else 10); following }

let () =
  let history =
    Chat_position.make ~width:76 ~height:8 ~total:40 (view ~offset:3 ~following:false)
  in
  check "paused range uses wrapped transcript rows"
    (Controller.contains history.text "rows 4-11/40");
  check "Latest target aligns with complete label"
    (history.latest = Some (0, 14) && String.sub history.text 0 14 = "[Latest / End]");
  let latest =
    Chat_position.make ~width:76 ~height:8 ~total:40 (view ~offset:32 ~following:true)
  in
  check "following shows range without redundant button"
    (latest.latest = None && Controller.contains latest.text "rows 33-40/40");
  check "fitting transcript has no range"
    ((Chat_position.make ~width:76 ~height:8 ~total:4 (view ~offset:0 ~following:true))
       .text = "");
  check "zero capacity has no footer or target"
    ((Chat_position.make ~width:76 ~height:0 ~total:40 (view ~offset:0 ~following:false))
       .latest = None);
  List.iter
    (fun width ->
      let position =
        Chat_position.make ~width ~height:8 ~total:40 (view ~offset:0 ~following:false)
      in
      check "position text stays within border width"
        (Notty.I.width (Notty.I.string Notty.A.empty position.text) <= max 0 width);
      check "clipped button never has a click target"
        (match position.latest with
        | None -> width < 14
        | Some (offset, length) ->
            offset + length <= width
            && String.sub position.text offset length = "[Latest / End]"))
    [ -1; 0; 1; 13; 14; 20; 40; 76 ];
  let controller = Controller.create ~external_events:true () in
  let task =
    Model.make ~id:"position" ~title:"Initial instruction" ~repository:"fixture"
  in
  let task =
    {
      task with
      messages =
        task.messages
        @ List.init 40 (fun index ->
            {
              Model.id = Printf.sprintf "message-%d" index;
              author = "fixture";
              text = Printf.sprintf "History message %02d" index;
              queued = false;
            });
    }
  in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  Controller.act controller (Controller.Focus Conversation);
  let render width height = Ui.render controller ~width ~height in
  ignore (render 120 36);
  Controller.key controller (`Home, []);
  let frame = render 120 36 in
  let hit =
    List.find (fun (hit : Ui.hit) -> hit.action = Controller.Follow_chat) frame.hits
  in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  let line = List.nth (String.split_on_char '\n' (Buffer.contents buffer)) hit.rect.y in
  let cells =
    List.rev
      (Uuseg_string.fold_utf_8 `Grapheme_cluster
         (fun cells cell -> cell :: cells)
         [] line)
  in
  let label =
    String.concat ""
      (List.filteri
         (fun index _ -> index >= hit.rect.x && index < hit.rect.x + hit.rect.w)
         cells)
  in
  check "rendered Latest label matches its click target" (label = "[Latest / End]");
  let paused_distance = controller.scroll in
  Ui.mouse controller frame ~now:0. (`Press (`Scroll `Down), (hit.rect.x, hit.rect.y), []);
  ignore (render 120 36);
  check "wheel on Latest button does not scroll chat" (controller.scroll = paused_distance);
  let saved = Controller.snapshot controller in
  Controller.act controller (Controller.Focus Activity);
  controller.scroll <- 5;
  ignore (render 120 36);
  let frame = render 120 36 in
  let activity_offset = controller.scroll in
  let hit =
    List.find (fun (hit : Ui.hit) -> hit.action = Controller.Follow_chat) frame.hits
  in
  Ui.mouse controller frame ~now:0. (`Press `Left, (hit.rect.x, hit.rect.y), []);
  let followed = render 120 36 in
  check "Latest focuses chat and follows without changing saved data"
    (controller.focus = Conversation
    && controller.scroll = 0
    && Controller.snapshot controller = saved);
  check "Latest preserves independent Activity reading position"
    (Pane_scroll.position controller.pane_scroll Activity = activity_offset);
  check "following removes Latest target"
    (not
       (List.exists
          (fun (hit : Ui.hit) -> hit.action = Controller.Follow_chat)
          followed.hits));
  Controller.act controller Controller.Begin_chat_search;
  Controller.set_input controller "History message 02";
  Controller.submit controller;
  let frame = render 120 36 in
  let hit =
    List.find (fun (hit : Ui.hit) -> hit.action = Controller.Follow_chat) frame.hits
  in
  Ui.mouse controller frame ~now:1. (`Press `Left, (hit.rect.x, hit.rect.y), []);
  ignore (render 120 36);
  check "Latest keeps search query while resuming follow"
    (Chat_search.query controller.chat_search = "History message 02"
    && controller.scroll = 0);
  Controller.key controller (`Home, []);
  ignore (render 120 36);
  Controller.act controller Controller.Help;
  let modal = render 120 36 in
  check "Help hides all Latest targets"
    (List.for_all (fun (hit : Ui.hit) -> hit.action <> Controller.Follow_chat) modal.hits);
  Controller.key controller (`Escape, []);
  Controller.act controller Controller.Begin_compose;
  let editing = render 120 36 in
  let hit =
    List.find (fun (hit : Ui.hit) -> hit.action = Controller.Follow_chat) editing.hits
  in
  let before = controller.scroll in
  Ui.mouse controller editing ~now:2. (`Press `Left, (hit.rect.x, hit.rect.y), []);
  check "editor ignores border shortcuts"
    (controller.input = Compose && controller.scroll = before);
  Controller.key controller (`Escape, []);
  List.iter
    (fun (width, height) ->
      let frame = render width height in
      check "footer targets stay inside terminal"
        (List.for_all
           (fun (hit : Ui.hit) ->
             let r = hit.rect in
             r.x >= 0 && r.y >= 0 && r.x + r.w <= width && r.y + r.h <= height)
           frame.hits))
    [ (1, 1); (20, 8); (60, 23); (120, 36); (180, 50) ];
  Printf.printf "Passed %d chat position checks. Pure layout/input only.\n" !checks
