open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let task = Model.make ~id:"T-101" ~title:"Short title" ~repository:"fixture" in
  check "short row retains familiar spacing"
    (Task_row.text ~width:60 ~selected:true task = " › T-101   Not started Short title");
  let long = { task with title = String.make 150 'x' ^ "TITLE_END" } in
  let row = Task_row.text ~width:60 ~selected:false long in
  check "long title has visible omission marker" (String.ends_with ~suffix:"…" row);
  check "ordinary ID and state remain visible"
    (Controller.contains row "T-101" && Controller.contains row "Not started");
  let long_id = { long with id = String.make 180 'i'; state = Model.Needs_you } in
  let row = Task_row.text ~width:60 ~selected:true long_id in
  check "long ID cannot hide task state" (Controller.contains row "Needs you");
  check "long identity abbreviation is disclosed" (Controller.contains row "…");
  let unicode =
    { long_id with id = "équipe-👩🏽‍💻"; title = "Unicode é 中文 👩🏽‍💻 " ^ String.make 150 'x' }
  in
  List.iter
    (fun width ->
      List.iter
        (fun task ->
          List.iter
            (fun selected ->
              let row = Task_row.text ~width ~selected task in
              check "row fits terminal cells"
                (Notty.I.width (Notty.I.string Notty.A.empty row) <= max 0 width);
              check "row never contains terminal controls"
                (not (String.contains row '\027')))
            [ false; true ])
        [
          task;
          long;
          long_id;
          unicode;
          { task with id = "bad\255\027"; title = "line\nnext" };
        ])
    [ -1; 0; 1; 8; 12; 20; 30; 60; 86 ];
  let controller = Controller.create ~external_events:true () in
  controller.tasks <- [ long ];
  controller.selected <- long.id;
  let saved = Controller.snapshot controller in
  let frame = Ui.render controller ~width:60 ~height:23 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (60, 23) frame.image;
  check "compact frame shows preview omission"
    (Controller.contains (Buffer.contents buffer) "…");
  check "compact card hit retains exact task identity"
    (List.exists
       (fun (hit : Ui.hit) -> hit.action = Controller.Select long.id)
       frame.hits);
  Controller.act controller Controller.Zoom;
  let frame = Ui.render controller ~width:120 ~height:36 in
  Buffer.clear buffer;
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  check "expanded task chat exposes title suffix"
    (Controller.contains (Buffer.contents buffer) "TITLE_END");
  check "preview does not change stored task" (Controller.snapshot controller = saved);
  Printf.printf "Passed %d compact task row checks. Pure tasks/layout only.\n" !checks
