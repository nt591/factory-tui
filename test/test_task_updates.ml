open Factory_tui

let check name condition = if not condition then failwith name

let envelope ?(task_id = "task") ?(run_id = "run") event : Model.envelope =
  { task_id; run_id; event }

let () =
  let updates = Task_updates.create () in
  Task_updates.record updates (envelope (Message ("item", "part")));
  Task_updates.record updates (envelope (Message ("item", "complete")));
  check "stream replacements count one item" (Task_updates.count updates "task" = 1);
  Task_updates.record updates (envelope (Tool ("item", "payload")));
  Task_updates.record updates (envelope ~run_id:"next" (Message ("item", "new attempt")));
  check "message/tool/run identities are separate" (Task_updates.count updates "task" = 3);
  Task_updates.record updates (envelope ~task_id:"other" (Failed "failure"));
  Task_updates.clear updates "task";
  check "viewing one task keeps other update markers"
    (Task_updates.count updates "task" = 0 && Task_updates.count updates "other" = 1);
  Task_updates.reset updates;
  check "markers are launch-local" (Task_updates.count updates "other" = 0);
  let controller = Controller.create ~external_events:true () in
  let first = Model.make ~id:"first" ~title:"First" ~repository:"fixture" in
  let second =
    Result.get_ok
      (Model.start (Model.make ~id:"second" ~title:"Second" ~repository:"fixture") "run")
  in
  controller.tasks <- [ first; second ];
  controller.selected <- first.id;
  Controller.receive controller
    (envelope ~task_id:"second" (Message ("reply", "Background reply")));
  Controller.receive controller
    (envelope ~task_id:"second" (Message ("reply", "Background updated")));
  Controller.receive controller
    (envelope ~task_id:"second" ~run_id:"stale" (Message ("other", "ignored")));
  let saved = Controller.snapshot controller in
  let frame = Ui.render controller ~width:120 ~height:36 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  check "background card badge counts accepted distinct updates"
    (Controller.contains (Buffer.contents buffer) "1 new update"
    && Task_updates.count controller.task_updates "second" = 1);
  let compact = Ui.render controller ~width:60 ~height:14 in
  Buffer.clear buffer;
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (60, 14) compact.image;
  check "compact task list exposes background update badge"
    (Controller.contains (Buffer.contents buffer) "[1 new]");
  check "only viewing board retains update marker"
    (Task_updates.count controller.task_updates "second" = 1);
  Controller.act controller (Controller.Select "second");
  controller.help <- true;
  ignore (Ui.render controller ~width:120 ~height:36);
  check "obscured detail does not acknowledge updates"
    (Task_updates.count controller.task_updates "second" = 1);
  controller.live_confirmation <- Some "second";
  controller.help <- false;
  ignore (Ui.render controller ~width:120 ~height:36);
  check "run confirmation does not mark underlying detail seen"
    (Task_updates.count controller.task_updates "second" = 1);
  controller.live_confirmation <- None;
  controller.help <- false;
  Controller.act controller (Controller.Focus Board);
  ignore (Ui.render controller ~width:60 ~height:14);
  check "board-only small terminal does not acknowledge selected task"
    (Task_updates.count controller.task_updates "second" = 1);
  Controller.act controller Controller.Zoom;
  ignore (Ui.render controller ~width:120 ~height:36);
  check "visible task detail acknowledges update badge"
    (Task_updates.count controller.task_updates "second" = 0);
  check "viewed badges never mutate saved messages or runs"
    ((Controller.snapshot controller).tasks = saved.tasks);
  Controller.receive controller (envelope ~task_id:"second" (Tool ("tool", "new tool")));
  controller.workspace_form <-
    Some (Workspace_form.create ~source:"" ~parent:"" ~revision:"@" ~model:"fixture" ());
  ignore (Ui.render controller ~width:120 ~height:36);
  check "workspace modal retains underlying update badge"
    (Task_updates.count controller.task_updates "second" = 1);
  controller.workspace_form <- None;
  Controller.restore controller (Controller.snapshot controller);
  check "restoring saved tasks does not invent unread history"
    (Task_updates.count controller.task_updates "second" = 0);
  Printf.printf "Passed task-update marker checks. Pure events/rendering only.\n"
