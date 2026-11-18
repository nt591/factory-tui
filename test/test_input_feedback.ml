open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let render controller =
  let frame = Ui.render controller ~width:120 ~height:36 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  List.nth (String.split_on_char '\n' (Buffer.contents buffer)) 35

let () =
  let controller = Controller.create ~external_events:true () in
  Controller.act controller Controller.Begin_compose;
  Controller.set_input controller "   ";
  let saved = Controller.snapshot controller in
  let editor = controller.editor in
  Controller.submit controller;
  check "empty reply error is visible while editor stays open"
    (Controller.contains (render controller) "Message is empty."
    && controller.input = Compose);
  check "invalid submission preserves draft cursor and messages"
    (controller.editor == editor
    && (Controller.snapshot controller).tasks = saved.tasks
    && (Controller.snapshot controller).drafts = saved.drafts);
  Controller.key controller (`Arrow `Left, []);
  check "cursor movement keeps validation feedback"
    (controller.input_error = Some "Message is empty.");
  Controller.insert_text controller "Valid reply";
  check "actual text edit clears validation feedback" (controller.input_error = None);
  Controller.submit controller;
  check "successful reply exits editor without error"
    (controller.input = Normal && controller.input_error = None
    && List.exists
         (fun (m : Model.message) -> m.text = "  Valid reply " && m.queued)
         (Option.get (Controller.selected controller)).messages);
  Controller.act controller Controller.Begin_model;
  Controller.set_input controller "-bad-model";
  let model = (Option.get (Controller.selected controller)).model in
  Controller.submit controller;
  check "invalid model feedback appears below editor"
    (Controller.contains (render controller) "Enter a model ID"
    && controller.input = Edit_model);
  check "model validation cannot change next-run settings"
    ((Option.get (Controller.selected controller)).model = model);
  controller.status <- "Storage error: fixture failure";
  Controller.submit controller;
  check "field error does not overwrite persistence warning"
    (controller.status = "Storage error: fixture failure"
    && controller.input_error <> None);
  Controller.key controller (`Escape, []);
  check "Escape exposes existing persistence status"
    (Controller.contains controller.status "Storage error:");
  Controller.act controller Controller.Begin_new;
  Controller.set_input controller "";
  let count = List.length controller.tasks in
  Controller.submit controller;
  check "empty task instruction has visible actionable feedback"
    (Controller.contains (render controller) "Enter a task instruction"
    && controller.input = New_task
    && List.length controller.tasks = count);
  Controller.insert_text controller "New task";
  check "new task edit clears stale validation" (controller.input_error = None);
  Controller.submit controller;
  check "valid task creation preserves normal behavior"
    (controller.input = Normal
    && (Option.get (Controller.selected controller)).title = "New task");
  Controller.act controller Controller.Begin_model;
  check "new input action starts without old validation" (controller.input_error = None);
  Controller.set_input controller "";
  Controller.submit controller;
  controller.input_limit <- Some 65536;
  check "limit rejection takes priority when both errors exist"
    (Controller.contains (render controller) "Edit not applied / limit 64 KiB");
  Printf.printf
    "Passed %d input-validation feedback checks. Pure editor/rendering only.\n" !checks
