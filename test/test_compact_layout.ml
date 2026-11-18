open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let choose width height focused =
    Pane_layout.choose ~width ~height ~detail_focused:focused
  in
  check "short board focus selects overview" (choose 60 14 false = Pane_layout.Board);
  check "short detail focus selects detail" (choose 60 14 true = Pane_layout.Detail);
  check "stack threshold retains both panes" (choose 60 17 false = Pane_layout.Stacked 9);
  check "short stack cannot hide focused composer" (choose 60 17 true = Pane_layout.Detail);
  check "tall detail focus retains split panes"
    (choose 60 21 true = Pane_layout.Stacked 10);
  check "wide threshold retains side-by-side panes"
    (choose 155 14 true = Pane_layout.Side_by_side 89);
  let controller = Controller.create ~external_events:true () in
  let task =
    Model.make ~id:"compact" ~title:"Compact instruction" ~repository:"fixture"
  in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  let render width height =
    let frame = Ui.render controller ~width ~height in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, height) frame.image;
    (frame, Buffer.contents buffer)
  in
  let _, text = render 60 20 in
  check "short startup retains a navigable board"
    (Controller.contains text "Tasks / click");
  Controller.key controller (`ASCII 'i', []);
  Controller.set_input controller "Visible compact reply";
  let _, text = render 60 20 in
  check "compact compose renders chat and editor"
    (Controller.contains text "Compact instruction"
    && Controller.contains text "Reply / next turn"
    && Controller.contains text "Visible compact reply");
  check "compact compose does not force persistent zoom" (not controller.zoom);
  List.iter
    (fun height ->
      let _, text = render 60 height in
      check "reply editor stays visible across compact stack thresholds"
        (Controller.contains text "Reply / next turn"
        && Controller.contains text "Visible compact reply"))
    [ 16; 17; 20; 21; 22; 23; 24; 25; 26; 27; 30 ];
  Controller.key controller (`Escape, []);
  Controller.key controller (`Tab, []);
  let _, text = render 60 20 in
  check "compact Activity focus renders activity"
    (Controller.contains text "compact / activity"
    && Controller.contains text "next: Codex");
  Controller.key controller (`Tab, []);
  let _, text = render 60 20 in
  check "Tab restores compact board" (Controller.contains text "Tasks / click");
  check "focus switching keeps draft"
    (Controller.draft controller = "Visible compact reply");
  Controller.key controller (`ASCII 'S', []);
  let _, text = render 60 20 in
  check "compact search renders its target chat"
    (Controller.contains text "Compact instruction" && Controller.contains text "/chat");
  Controller.key controller (`Escape, []);
  let saved = Controller.snapshot controller in
  List.iter
    (fun (width, height) ->
      List.iter
        (fun focus ->
          Controller.act controller (Controller.Focus focus);
          let frame, _ = render width height in
          check "compact focus frame fits terminal"
            (Notty.I.width frame.image = width && Notty.I.height frame.image = height);
          List.iter
            (fun (hit : Ui.hit) ->
              let r = hit.rect in
              check "compact focus hits fit terminal"
                (r.x >= 0 && r.y >= 0 && r.x + r.w <= width && r.y + r.h <= height))
            frame.hits)
        [ Controller.Board; Controller.Conversation; Controller.Activity ])
    [ (1, 1); (20, 8); (60, 20); (80, 24); (120, 36); (180, 50) ];
  check "layout and focus changes do not rewrite persisted tasks or drafts"
    (Controller.snapshot controller = saved);
  Printf.printf "Passed %d compact layout checks. Rendering and input only.\n" !checks
