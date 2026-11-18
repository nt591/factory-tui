open Factory_tui
open Controller

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  check "normal mode has no editor controls" (Input_controls.items Normal = []);
  List.iter
    (fun input ->
      let items = Input_controls.items input in
      check "editor controls always offer submit and close"
        (List.exists (fun (item : Input_controls.item) -> item.action = Submit) items
        && List.exists (fun (item : Input_controls.item) -> item.action = Close) items);
      check "newline control is reply-only"
        (List.exists (fun (item : Input_controls.item) -> item.action = Newline) items
        = (input = Compose));
      check "submit uses existing Enter path"
        (Input_controls.key ~input Submit = Some (`Enter, []));
      check "close uses existing Escape path"
        (Input_controls.key ~input Close = Some (`Escape, [])))
    [ Compose; Edit_model; New_task; Search; Chat_search ];
  check "normal mode cannot execute stale editor command"
    (Input_controls.key ~input:Normal Submit = None);
  check "single-line mode cannot execute newline"
    (Input_controls.key ~input:Edit_model Newline = None);
  let controller = Controller.create ~external_events:true () in
  let task = Model.make ~id:"input" ~title:"Instruction" ~repository:"fixture" in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  let render width height = Ui.render controller ~width ~height in
  let click frame action =
    let hit =
      List.find (fun (hit : Ui.input_hit) -> hit.action = action) frame.Ui.input_controls
    in
    Ui.mouse controller frame ~now:1. (`Press `Left, (hit.rect.x, hit.rect.y), [])
  in
  Controller.act controller Begin_compose;
  let frame = render 120 36 in
  check "editor footer hides inert normal-mode actions"
    (not (List.exists (fun (hit : Ui.hit) -> hit.rect.y = 34) frame.hits));
  let saved = Controller.snapshot controller in
  click frame Submit;
  check "clicking empty Queue uses validation without discarding editor"
    (controller.input = Compose
    && controller.input_error = Some "Message is empty."
    && (Controller.snapshot controller).tasks = saved.tasks
    && (Controller.snapshot controller).drafts = saved.drafts);
  Controller.set_input controller "First line";
  click (render 120 36) Newline;
  Controller.insert_text controller "Second line";
  check "newline click preserves exact multiline draft"
    (Controller.draft controller = "First line\nSecond line" && controller.input = Compose);
  let frame = render 120 36 in
  click frame Close;
  check "Keep draft click closes editor without sending"
    (controller.input = Normal
    && Controller.draft controller = "First line\nSecond line"
    && (Option.get (Controller.selected controller)).messages = task.messages);
  Controller.act controller Begin_model;
  let saved = Controller.snapshot controller in
  click frame Submit;
  check "stale reply frame cannot submit different editor"
    (controller.input = Edit_model && Controller.snapshot controller = saved);
  Controller.set_input controller "-invalid";
  click (render 120 36) Submit;
  check "model click validates and keeps invalid text"
    (controller.input = Edit_model
    && controller.input_error <> None
    && Text_edit.text controller.editor = "-invalid");
  click (render 120 36) Close;
  check "model cancel retains original setting"
    ((Option.get (Controller.selected controller)).model = task.model
    && controller.input = Normal);
  Controller.act controller Begin_compose;
  click (render 120 36) Submit;
  check "Queue click retains exact message without starting a run"
    (controller.input = Normal
    && Controller.draft controller = ""
    && List.exists
         (fun (message : Model.message) ->
           message.text = "First line\nSecond line" && message.queued)
         (Option.get (Controller.selected controller)).messages
    && (Option.get (Controller.selected controller)).active = None);
  Controller.act controller Begin_chat_search;
  Controller.set_input controller "First";
  click (render 120 36) Submit;
  check "Finish chat search retains query"
    (Chat_search.query controller.chat_search = "First");
  Controller.act controller Begin_chat_search;
  click (render 120 36) Close;
  check "Clear search click removes query" (Chat_search.query controller.chat_search = "");
  Controller.act controller Begin_new;
  Controller.set_input controller "New task";
  let frame = render 120 36 in
  controller.help <- true;
  let modal = render 120 36 in
  let saved = Controller.snapshot controller in
  check "Help hides editor targets" (modal.input_controls = []);
  click frame Submit;
  check "modal rejects stale editor target"
    (controller.input = New_task && Controller.snapshot controller = saved);
  controller.help <- false;
  click (render 120 36) Submit;
  check "Create click adds queued task without execution"
    (controller.input = Normal
    && (Option.get (Controller.selected controller)).title = "New task"
    && (Option.get (Controller.selected controller)).state = Model.Queued
    && (Option.get (Controller.selected controller)).active = None);
  Controller.act controller Begin_compose;
  List.iter
    (fun (width, height) ->
      let frame = render width height in
      check "editor targets fit terminal and contain complete labels"
        (List.for_all
           (fun (hit : Ui.input_hit) ->
             let r = hit.rect in
             r.x >= 0 && r.y >= 0
             && r.x + r.w <= width
             && r.y + r.h <= height
             && List.exists
                  (fun (item : Input_controls.item) ->
                    item.action = hit.action && r.w = String.length item.label + 2)
                  (Input_controls.items hit.input))
           frame.input_controls))
    [ (1, 1); (20, 8); (40, 12); (60, 20); (120, 36); (180, 50) ];
  let frame = render 120 36 in
  Controller.set_input controller "Unsaved reply";
  controller.status <- "Storage error: unsaved conversation";
  click frame Submit;
  check "mouse submission preserves persistence warning"
    (controller.status = "Storage error: unsaved conversation"
    && controller.input = Normal);
  Printf.printf "Passed %d editor-control checks. Pure mouse/input/rendering only.\n"
    !checks
