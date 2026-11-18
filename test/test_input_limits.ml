open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let controller = Controller.create ~external_events:true () in
  Controller.act controller Controller.Begin_compose;
  let full = String.make 65536 'a' in
  Controller.set_input controller full;
  let saved = Controller.snapshot controller in
  Controller.insert_text controller "b";
  let frame = Ui.render controller ~width:120 ~height:36 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  check "rejection is visible while editing, not hidden behind status"
    (Controller.contains (Buffer.contents buffer) "Edit not applied / limit 64 KiB");
  Controller.key controller (`Arrow `Left, []);
  check "cursor motion does not dismiss unapplied-edit warning"
    (controller.input_limit = Some 65536);
  Controller.key controller (`End, []);
  let editor = controller.editor in
  check "full draft rejection is visible"
    (Controller.contains controller.status "64 KiB"
    && Controller.contains controller.status "not applied");
  check "full draft rejection keeps editor and saved draft exact"
    (controller.editor == editor
    && Controller.draft controller = full
    && Controller.snapshot controller = saved);
  Controller.set_input controller (full ^ "b");
  check "direct oversized assignment is atomic"
    (controller.editor == editor && Controller.snapshot controller = saved);
  Controller.set_input controller (String.make 30000 '\255');
  controller.status <- "Storage error: fixture";
  Controller.set_input controller (full ^ "b");
  check "input-limit feedback does not erase storage failure"
    (controller.status = "Storage error: fixture" && controller.input_limit = Some 65536);
  controller.status <- "fixture";
  check "UTF8 repair cannot bypass accepted-byte limit"
    (controller.editor == editor && Controller.snapshot controller = saved);
  Controller.key controller (`Backspace, []);
  Controller.insert_text controller "b";
  check "successful text edit clears limit warning" (controller.input_limit = None);
  check "editing can recover from limit rejection"
    (Controller.draft controller = String.make 65535 'a' ^ "b"
    && Text_edit.text controller.editor = Controller.draft controller);
  Controller.set_input controller (String.make 65535 'a');
  Controller.insert_text controller "é";
  check "multi-byte cluster is rejected as a whole at limit"
    (Controller.draft controller = String.make 65535 'a'
    && Text_edit.text controller.editor = Controller.draft controller);
  Controller.set_input controller "start\255end";
  check "normalized editor and saved draft use the same repaired text"
    (Controller.draft controller = "start�end"
    && Text_edit.text controller.editor = Controller.draft controller);
  let before = Controller.snapshot controller in
  Controller.insert_text controller "";
  check "empty insertion changes no draft" (Controller.snapshot controller = before);
  Controller.act controller Controller.Begin_chat_search;
  Controller.set_input controller (String.make 256 'q');
  let editor = controller.editor in
  Controller.insert_text controller "x";
  check "chat query limit leaves search and editor synchronized"
    (controller.editor == editor
    && Chat_search.query controller.chat_search = String.make 256 'q'
    && Controller.contains controller.status "256 bytes");
  Controller.set_input controller (String.make 100 '\255');
  check "repaired chat query is validated before applying"
    (controller.editor == editor
    && Chat_search.query controller.chat_search = String.make 256 'q');
  Controller.key controller (`Backspace, []);
  Controller.insert_text controller "x";
  check "chat query can recover without losing synchronization"
    (Chat_search.query controller.chat_search = Text_edit.text controller.editor
    && String.ends_with ~suffix:"x" (Chat_search.query controller.chat_search));
  List.iter
    (fun action ->
      Controller.key controller (`Escape, []);
      Controller.act controller action;
      Controller.set_input controller "value";
      let original = Text_edit.text controller.editor
      and cursor = Text_edit.cursor controller.editor in
      let saved = Controller.snapshot controller in
      Controller.set_input controller (String.make 65537 'x');
      check "all footer inputs reject atomically"
        (Text_edit.text controller.editor = original
        && Text_edit.cursor controller.editor = cursor
        && Controller.snapshot controller = saved);
      check "footer input rejection is disclosed"
        (Controller.contains controller.status "not applied"))
    [ Controller.Begin_model; Controller.Begin_search; Controller.Begin_new ];
  Controller.key controller (`Escape, []);
  controller.query <- "";
  Controller.act controller (Controller.Select "T-102");
  Controller.act controller Controller.Begin_compose;
  Controller.set_input controller "retained";
  Controller.set_input controller (String.make 65537 'x');
  Controller.submit controller;
  check "submission cannot send rejected or stale editor content"
    (List.exists
       (fun (message : Model.message) -> message.text = "retained" && message.queued)
       (Option.get (Controller.selected controller)).messages);
  Printf.printf "Passed %d input-limit checks. Pure input/state only.\n" !checks
