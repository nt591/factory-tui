open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let fill form field text =
  Workspace_form.focus form field;
  for _ = 1 to String.length (Workspace_form.value form field) do
    Workspace_form.key form (`Backspace, [])
  done;
  String.iter (fun char -> Workspace_form.key form (`ASCII char, [])) text

let () =
  let form = Workspace_form.create ~source:"" ~parent:"" ~revision:"" ~model:"" () in
  let values () = List.map (Workspace_form.value form) Workspace_form.fields in
  let validate field =
    Workspace_form.focus form Workspace_form.Task;
    let before = values () in
    check "ordinary validation does not move focus"
      (Result.is_error (Workspace_form.validate form)
      && Workspace_form.current form = Workspace_form.Task);
    check "submission focuses first invalid field"
      (Result.is_error (Workspace_form.validate_submission form)
      && Workspace_form.current form = field);
    check "validation preserves entered values" (values () = before)
  in
  validate Workspace_form.Jj;
  fill form Workspace_form.Jj "/fixture/jj";
  validate Workspace_form.Source;
  fill form Workspace_form.Source "/fixture/source";
  validate Workspace_form.Parent;
  fill form Workspace_form.Parent "/fixture/tasks";
  validate Workspace_form.Revision;
  fill form Workspace_form.Revision "@";
  validate Workspace_form.Model;
  fill form Workspace_form.Model "fixture-model";
  validate Workspace_form.Task;
  fill form Workspace_form.Task "Instruction";
  Workspace_form.focus form Workspace_form.Source;
  check "valid submission preserves chosen field"
    (Workspace_form.validate_submission form = Ok ()
    && Workspace_form.current form = Workspace_form.Source);
  let controller = Controller.create () in
  controller.schedules <- [];
  controller.database_path <- Some "/fixture/db";
  Controller.act controller Controller.Begin_workspace;
  let form = Option.get controller.workspace_form in
  fill form Workspace_form.Jj "";
  Workspace_form.focus form Workspace_form.Task;
  let saved = Controller.snapshot controller in
  Controller.key controller (`ASCII 's', [ `Ctrl ]);
  check "Ctrl-S selects missing executable without starting setup"
    (Workspace_form.current form = Workspace_form.Jj
    && controller.creation_request = None
    && controller.creation_job = None);
  check "error names the selected invalid field"
    (Controller.contains (Workspace_form.status form) "jj executable:");
  let frame = Ui.render controller ~width:60 ~height:20 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (60, 20) frame.image;
  check "invalid field is visible after compact validation"
    (Controller.contains (Buffer.contents buffer) "jj executable");
  check "invalid submission leaves persisted tasks and drafts unchanged"
    (Controller.snapshot controller = saved);
  let error = Workspace_form.status form in
  List.iter
    (fun key -> Workspace_form.key form (key, []))
    [ `Home; `End; `Arrow `Left; `Backspace ];
  check "cursor motion and empty deletion retain validation error"
    (Workspace_form.status form = error);
  Workspace_form.focus form Workspace_form.Task;
  Workspace_form.key form (`ASCII 'x', []);
  check "editing another field does not erase executable error"
    (Workspace_form.status form = error);
  Workspace_form.focus form Workspace_form.Jj;
  Workspace_form.paste_key form (`ASCII '/', []);
  check "actual edit clears only the obsolete failing-field message"
    (Workspace_form.status form
   = "Field edited. Enter on the instruction checks all fields before creating.");
  check "edited feedback does not imply the whole form is valid"
    (Result.is_error (Workspace_form.validate form));
  Controller.key controller (`ASCII 's', [ `Ctrl ]);
  check "resubmission still checks every field"
    (Workspace_form.current form = Workspace_form.Source
    && controller.creation_request = None);
  Workspace_form.report form "Workspace creation failed. Retain the destination.";
  Workspace_form.key form (`ASCII '/', []);
  check "operational failure remains visible while editing"
    (Workspace_form.status form = "Workspace creation failed. Retain the destination.");
  Workspace_form.report form "Storage error: checkpoint failed";
  Workspace_form.key form (`ASCII 'x', []);
  check "editing cannot clear reported storage error"
    (Workspace_form.status form = "Storage error: checkpoint failed");
  Printf.printf "Passed %d field-validation recovery checks. No filesystem operations.\n"
    !checks
