open Factory_tui

let check name condition = if not condition then failwith name

let () =
  let controller = Controller.create ~external_events:true () in
  controller.tasks <-
    List.init 40 (fun index ->
        Model.make ~id:(string_of_int index) ~title:"Sidebar fixture"
          ~repository:(Printf.sprintf "repo-%02d" index));
  controller.selected <- "0";
  let render width height =
    let frame = Ui.render controller ~width ~height in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, height) frame.image;
    (frame, String.split_on_char '\n' (Buffer.contents buffer))
  in
  let frame, rows = render 180 20 in
  check "only visible repositories have sidebar hits"
    (List.for_all
       (fun (hit : Ui.hit) ->
         match hit.action with
         | Controller.Repository _ when hit.rect.x = 1 ->
             hit.rect.y >= 4 && hit.rect.y < 16
         | _ -> true)
       frame.hits);
  check "clipped sidebar does not create footer repository hits"
    (not
       (List.exists
          (fun (hit : Ui.hit) ->
            hit.rect.y >= 17
            && match hit.action with Controller.Repository _ -> true | _ -> false)
          frame.hits));
  check "overflow sidebar shows range cue"
    (Controller.contains (List.nth rows 15) "1-4/41");
  let before = Controller.snapshot controller in
  let rectangle, _ = Option.get frame.sidebar in
  let board_scroll = controller.board_scroll in
  Ui.mouse controller frame ~now:1.
    (`Press (`Scroll `Down), (rectangle.x, rectangle.y), []);
  let frame, rows = render 180 20 in
  check "sidebar wheel scrolls repositories only"
    (controller.sidebar_scroll = Some 3 && controller.board_scroll = board_scroll);
  check "sidebar cue advances with repository rows"
    (Controller.contains (List.nth rows 15) "4-7/41");
  check "sidebar scroll preserves task snapshot" (Controller.snapshot controller = before);
  let hit =
    List.find
      (fun (hit : Ui.hit) -> hit.action = Controller.Repository (Some "repo-05"))
      frame.hits
  in
  Ui.mouse controller frame ~now:2. (`Press `Left, (hit.rect.x, hit.rect.y), []);
  check "visible repository remains clickable" (controller.repository = Some "repo-05");
  Controller.act controller (Controller.Repository (Some "repo-39"));
  let frame, rows = render 180 20 in
  check "filter selection follows final repository into view"
    (controller.sidebar_scroll = None
    && List.exists (fun row -> Controller.contains row "repo-39") rows
    && List.exists
         (fun (hit : Ui.hit) -> hit.action = Controller.Repository (Some "repo-39"))
         frame.hits);
  Controller.act controller Controller.Next_repository;
  let _, rows = render 180 20 in
  check "repository cycle returns to visible all filter"
    (controller.repository = None
    && List.exists (fun row -> Controller.contains row "All repositories") rows);
  List.iter
    (fun height ->
      let frame, _ = render 180 height in
      check "sidebar hits stay inside body after resize"
        (List.for_all
           (fun (hit : Ui.hit) ->
             match hit.action with
             | Controller.Repository _ when hit.rect.x = 1 ->
                 hit.rect.y >= 4 && hit.rect.y < max 4 (height - 4)
             | _ -> true)
           frame.hits))
    [ 8; 10; 12; 16; 20; 36; 50 ];
  let frame, _ = render 120 36 in
  check "hidden sidebar has no scroll region" (frame.sidebar = None);
  let frame, _ = render 180 20 in
  let r, _ = Option.get frame.sidebar in
  Controller.act controller Controller.Help;
  let modal, _ = render 180 20 in
  let before = controller.sidebar_scroll in
  Ui.mouse controller modal ~now:3. (`Press (`Scroll `Down), (r.x, r.y), []);
  check "menu owns wheel input over sidebar"
    (controller.sidebar_scroll = before && controller.menu_scroll = 3);
  Printf.printf
    "Passed sidebar clipping, scroll, selection and modal checks. Pure rendering only.\n"
