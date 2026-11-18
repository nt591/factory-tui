open Factory_tui
open Model

let check name condition = if not condition then failwith name

let () =
  let controller = Controller.create ~external_events:true () in
  let task =
    Result.get_ok
      (Model.start
         (Model.make ~id:"running" ~title:"Active task" ~repository:"fixture")
         "run")
  in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  controller.database_path <- Some "/fixture/db";
  controller.workspace_form <-
    Some (Workspace_form.create ~source:"" ~parent:"" ~revision:"@" ~model:"fixture" ());
  let form = Option.get controller.workspace_form in
  let render () =
    let frame = Ui.render controller ~width:120 ~height:36 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
    Buffer.contents buffer
  in
  Controller.receive controller
    { task_id = task.id; run_id = "run"; event = Turn_started };
  check "run updates leave form setup guidance intact"
    (Workspace_form.status form
   = "Enter sends the task. Tab moves fields. Ctrl-S saves without running.");
  Controller.act controller Controller.Submit_workspace;
  let validation = Workspace_form.status form in
  check "form owns its validation error" (Controller.contains validation "absolute paths");
  List.iter
    (fun event ->
      Controller.receive controller { task_id = task.id; run_id = "run"; event })
    [ Turn_completed; Exited 0 ];
  check "completion cannot overwrite form validation"
    (Workspace_form.status form = validation
    && Controller.contains controller.status "Run complete.");
  let text = render () in
  check "modal status row shows creation error instead of unrelated completion"
    (Controller.contains text validation);
  check "failed form never creates a request or job"
    (controller.creation_request = None && controller.creation_job = None);
  Workspace_form.report form "Creating workspace. No agent starts.";
  check "reporting creation does not alter field values"
    (Workspace_form.value form Workspace_form.Source = "");
  let before = Controller.snapshot controller in
  Controller.act controller Controller.Cancel_workspace;
  check "cancelling releases form-local status" (controller.workspace_form = None);
  check "form reporting and cancel do not change snapshots"
    (Controller.snapshot controller = before);
  Printf.printf "Passed form-local status checks. Pure events and rendering only.\n"
