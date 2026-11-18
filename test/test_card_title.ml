open Factory_tui

let check name condition = if not condition then failwith name

let () =
  let title =
    "Implement a complete software factory workflow with persistent task channels and \
     retain the final instruction sentinel CARD_END"
  in
  let task = Model.make ~id:"long-card" ~title ~repository:"fixture" in
  let controller = Controller.create ~external_events:true () in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  let saved = Controller.snapshot controller in
  let render () =
    let frame = Ui.render controller ~width:120 ~height:36 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
    (frame, String.split_on_char '\n' (Buffer.contents buffer))
  in
  let frame, rows = render () in
  check "long card title marks hidden rows" (Controller.contains (List.nth rows 6) "…");
  check "card retains task hit target"
    (List.exists
       (fun (hit : Ui.hit) -> hit.action = Controller.Select task.id)
       frame.hits);
  check "preview truncation leaves original task intact"
    (Controller.snapshot controller = saved);
  Controller.key controller (`ASCII 'e', []);
  let _, rows = render () in
  check "opening card exposes complete instruction"
    (Controller.contains (String.concat "\n" rows) "CARD_END");
  check "zoom does not replace task title with preview"
    ((Option.get (Controller.selected controller)).title = title);
  check "zoom keeps saved full instruction" (Controller.snapshot controller = saved);
  Printf.printf "Passed long-card preview checks. Pure rendering/input only.\n"
