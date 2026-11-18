open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let full = "/" ^ String.make 65535 'a' in
  let form =
    Workspace_form.create ~jj:"/jj" ~source:full ~parent:"/parent" ~revision:"@"
      ~model:"fixture" ()
  in
  let original = Workspace_form.cursor_parts form Source in
  Workspace_form.key form (`ASCII 'x', []);
  check "form identifies rejected field edit"
    (Controller.contains (Workspace_form.status form)
       "Source repository: Edit not applied / 64 KiB limit");
  check "rejected insertion retains field and cursor"
    (Workspace_form.value form Source = full
    && Workspace_form.cursor_parts form Source = original);
  Workspace_form.key form (`Arrow `Left, []);
  check "cursor movement retains rejection feedback"
    (Controller.contains (Workspace_form.status form) "Edit not applied");
  Workspace_form.key form (`End, []);
  Workspace_form.focus form Parent;
  Workspace_form.key form (`ASCII 'x', []);
  check "other field edits cannot dismiss source rejection"
    (Controller.contains (Workspace_form.status form)
       "Source repository: Edit not applied");
  Workspace_form.report form "Workspace creation failed; retain its directory.";
  check "operational report remains visible beside rejection"
    (Controller.contains (Workspace_form.status form) "Workspace creation failed"
    && Controller.contains (Workspace_form.status form) "Edit not applied");
  Workspace_form.focus form Source;
  Workspace_form.key form (`Backspace, []);
  check "actual edit in rejected field clears limit feedback"
    (not (Controller.contains (Workspace_form.status form) "Edit not applied"));
  check "clearing rejection preserves operational report"
    (Controller.contains (Workspace_form.status form) "Workspace creation failed");
  Workspace_form.paste_key form (`Uchar (Uchar.of_int 0xe9), []);
  check "multi-byte paste rejection retains the whole field"
    (Workspace_form.value form Source = String.sub full 0 65535
    && Controller.contains (Workspace_form.status form) "Edit not applied");
  Workspace_form.key form (`Backspace, []);
  Workspace_form.paste_key form (`Uchar (Uchar.of_int 0xe9), []);
  check "smaller repaired field accepts complete Unicode character"
    (String.length (Workspace_form.value form Source) = 65536
    && String.ends_with ~suffix:"é" (Workspace_form.value form Source));
  check "accepted paste clears field warning"
    (not (Controller.contains (Workspace_form.status form) "Edit not applied"));
  let controller = Controller.create ~external_events:true () in
  controller.workspace_form <- Some form;
  Workspace_form.key form (`ASCII 'x', []);
  let saved = Controller.snapshot controller in
  let frame = Ui.render controller ~width:120 ~height:36 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  check "dialog renders rejection before unrelated background status"
    (Controller.contains (Buffer.contents buffer) "Edit not applied / 64 KiB limit");
  check "rendering rejection creates no task or request"
    (Controller.snapshot controller = saved
    && controller.creation_request = None
    && controller.creation_job = None);
  Workspace_form.key form (`Backspace, []);
  let invalid =
    Workspace_form.create ~source:"relative" ~parent:"/parent" ~revision:"@"
      ~model:"fixture" ()
  in
  ignore (Workspace_form.validate_submission invalid);
  check "ordinary field-validation behavior remains"
    (Workspace_form.current invalid = Jj
    && Controller.contains (Workspace_form.status invalid) "absolute paths");
  Printf.printf "Passed %d form-limit checks. Pure form/rendering only.\n" !checks
