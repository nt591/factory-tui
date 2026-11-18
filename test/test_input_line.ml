open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let editor =
    Text_edit.create "BEGIN-" |> fun editor ->
    Text_edit.insert editor (String.make 150 'x' ^ "-END")
  in
  let line editor =
    Input_line.render ~width:60 ~label:" Model (next run): "
      ~hint:" [Enter apply / Esc cancel]" editor
  in
  check "long input exposes ending cursor"
    (String.ends_with ~suffix:"-END▏" (line editor));
  let home = Text_edit.home editor in
  check "Home exposes input prefix" (Controller.contains (line home) "▏BEGIN-");
  let middle = Text_edit.right home |> fun editor -> Text_edit.insert editor "é" in
  check "middle cursor is displayed at actual position"
    (Controller.contains (line middle) "Bé▏EGIN-");
  let inside = Text_edit.left editor |> Text_edit.left |> Text_edit.left in
  check "long footer exposes forward text beside cursor"
    (Controller.contains (line inside) "-▏END");

  check "short values retain shortcut hints"
    (Input_line.render ~width:80 ~label:" Search: " ~hint:" [Enter finish]"
       (Text_edit.create "word")
    = " Search: word▏ [Enter finish]");
  List.iter
    (fun columns ->
      let value =
        Input_line.render ~width:columns ~label:"Very long label: " ~hint:" hint" editor
      in
      check "input line fits its terminal width"
        (Notty.I.width (Notty.I.string Notty.A.empty value) <= columns);
      check "positive-width input always retains edit cursor"
        (Controller.contains value "▏"))
    [ 1; 2; 5; 20; 60; 120 ];
  check "zero-width field is empty"
    (Input_line.render ~width:0 ~label:"x" ~hint:"y" editor = "");
  let invalid = Text_edit.create "a\255\027\n\194\128b" in
  let sanitized = Input_line.render ~width:80 ~label:"" ~hint:"" invalid in
  check "single-line input safely renders malformed UTF-8 and controls"
    (sanitized = "a�   b▏");
  let controller = Controller.create ~external_events:true () in
  let task = Model.make ~id:"model-task" ~title:"Instruction" ~repository:"fixture" in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  Controller.act controller Controller.Begin_model;
  Controller.set_input controller (Text_edit.text editor);
  let saved = Controller.snapshot controller in
  let footer () =
    let frame = Ui.render controller ~width:60 ~height:20 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (60, 20) frame.image;
    List.nth (String.split_on_char '\n' (Buffer.contents buffer)) 17
  in
  check "model footer renders actual end cursor" (Controller.contains (footer ()) "-END▏");
  Controller.key controller (`Home, []);
  check "model footer Home exposes beginning" (Controller.contains (footer ()) "▏BEGIN-");
  check "footer navigation leaves captured task settings unchanged"
    (Controller.snapshot controller = saved);
  Controller.key controller (`ASCII 'Z', []);
  Controller.key controller (`Enter, []);
  check "model submission retains complete edited value"
    ((Option.get (Controller.selected controller)).model = "Z" ^ Text_edit.text editor);
  Controller.act controller Controller.Begin_compose;
  Controller.set_input controller "First line\nSecond line";
  Controller.key controller (`Home, []);
  check "visible composer footer does not repeat multiline draft"
    (Controller.contains (footer ()) "editing above"
    && not (Controller.contains (footer ()) "First line"));
  List.iter
    (fun action ->
      let controller = Controller.create ~external_events:true () in
      controller.tasks <- [ task ];
      controller.selected <- task.id;
      let original = Controller.snapshot controller in
      Controller.act controller action;
      let value = "BEGIN-" ^ String.make 160 'x' ^ "-END" in
      Controller.set_input controller value;
      let footer () =
        let frame = Ui.render controller ~width:60 ~height:20 in
        let buffer = Buffer.create 8192 in
        Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (60, 20) frame.image;
        List.nth (String.split_on_char '\n' (Buffer.contents buffer)) 17
      in
      check "search and task footer editors expose ending cursor"
        (Controller.contains (footer ()) "-END▏");
      Controller.key controller (`Home, []);
      check "search and task footer Home expose beginning cursor"
        (Controller.contains (footer ()) "▏BEGIN-");
      Controller.key controller (`End, []);
      check "cursor display does not truncate search or task-title input"
        (Text_edit.text controller.editor = value);
      let saved = Controller.snapshot controller in
      check "footer editing and navigation starts no run or saved-content change"
        (saved.tasks = original.tasks && saved.drafts = original.drafts))
    [ Controller.Begin_search; Controller.Begin_chat_search; Controller.Begin_new ];
  Printf.printf "Passed %d input footer checks. Pure editor/rendering only.\n" !checks
