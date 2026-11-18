open Factory_tui

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let fill form field text =
  Workspace_form.focus form field;
  for _ = 1 to String.length (Workspace_form.value form field) do
    Workspace_form.key form (`Backspace, [])
  done;
  String.iter (fun char -> Workspace_form.key form (`ASCII char, [])) text

let () =
  let controller = Controller.create ~external_events:false () in
  Controller.act controller Controller.Begin_workspace;
  check "creation requires durable storage" (controller.workspace_form = None);
  controller.database_path <- Some "/fixture/database";
  Controller.act controller Controller.Begin_workspace;
  let form = Option.get controller.workspace_form in
  check "creation opens form without job"
    (controller.creation_request = None && controller.creation_job = None);
  check "opening form starts no run" (Workspace_form.current form = Workspace_form.Source);
  Controller.key controller (`ASCII 's', []);
  check "shortcut is text while editing"
    (Workspace_form.value form Workspace_form.Source = "s");
  Controller.paste_key controller (`Enter, []);
  Controller.paste_key controller (`ASCII 'q', []);
  check "paste cannot create or quit"
    (Workspace_form.value form Workspace_form.Source = "s q"
    && controller.creation_request = None
    && not controller.quit);
  Controller.key controller (`Tab, []);
  check "Tab moves form field" (Workspace_form.current form = Workspace_form.Parent);
  Controller.key controller (`Tab, [ `Shift ]);
  check "Shift-Tab moves backwards" (Workspace_form.current form = Workspace_form.Source);
  Controller.key controller (`Enter, []);
  check "Enter validates incomplete form instead of advancing"
    (controller.creation_request = None && controller.workspace_form <> None);
  Controller.key controller (`ASCII 's', [ `Ctrl ]);
  check "invalid form stays open without job"
    (controller.creation_request = None && controller.workspace_form <> None);
  List.iter
    (fun (width, height) ->
      let frame = Ui.render controller ~width ~height in
      check "modal frame has terminal bounds"
        (Notty.I.width frame.image = width && Notty.I.height frame.image = height);
      List.iter
        (fun (hit : Ui.hit) ->
          let r = hit.rect in
          check "modal click stays in bounds"
            (r.x >= 0 && r.y >= 0 && r.x + r.w <= width && r.y + r.h <= height);
          check "modal blocks background actions"
            (match hit.action with
            | Controller.Workspace_field _ | Controller.Submit_workspace
            | Controller.Send_workspace | Controller.Cancel_workspace
            | Controller.Open_models | Controller.Open_projects ->
                true
            | _ -> false))
        frame.hits)
    [ (1, 1); (20, 8); (60, 20); (120, 36); (180, 50) ];
  Controller.act controller Toggle_greenfield;
  let greenfield_form = Option.get controller.workspace_form in
  check "greenfield mode can be enabled without source"
    (Workspace_form.greenfield greenfield_form);
  Controller.act controller Toggle_greenfield;
  let frame = Ui.render controller ~width:120 ~height:36 in
  let hit =
    List.find
      (fun (hit : Ui.hit) -> hit.action = Controller.Workspace_field Workspace_form.Jj)
      frame.hits
  in
  Ui.mouse controller frame ~now:1. (`Press `Left, (hit.rect.x, hit.rect.y), []);
  check "form fields clickable" (Workspace_form.current form = Workspace_form.Jj);
  let dialog =
    Workspace_dialog.render form ~busy:false ~status:"fixture" ~width:90 ~height:26
  in
  let click =
    List.find
      (fun (item : Workspace_dialog.hit) -> item.action = Workspace_dialog.Create)
      dialog.hits
  in
  let rendered = Buffer.create 4096 in
  Notty.Render.to_buffer rendered Notty.Cap.dumb (0, 0) (90, 26) dialog.image;
  let rendered = Buffer.contents rendered |> String.split_on_char '\n' in
  check "create hitbox aligns with visible button"
    (Controller.contains (List.nth rendered click.y) "Create task");
  Controller.key controller (`Escape, []);
  check "escape cancels form only"
    (controller.workspace_form = None && not controller.quit);
  let defaults : Workspace_defaults.t =
    {
      mode = Workspace_defaults.Existing;
      jj = Some "/tools/jj";
      source = Some "/configured/source";
      parent = Some "/configured/tasks";
      revision = Some "main@origin";
      model = Some "custom-model";
    }
  in
  Controller.set_workspace_defaults controller defaults;
  let saved = Controller.snapshot controller in
  Controller.act controller Controller.Begin_workspace;
  let form = Option.get controller.workspace_form in
  check "workspace defaults prefill all form fields"
    (Workspace_form.value form Workspace_form.Jj = "/tools/jj"
    && Workspace_form.value form Workspace_form.Source = "/configured/source"
    && Workspace_form.value form Workspace_form.Parent = "/configured/tasks"
    && Workspace_form.value form Workspace_form.Revision = "main@origin"
    && Workspace_form.value form Workspace_form.Model = "custom-model");
  check "workspace defaults never prefill instruction"
    (Workspace_form.value form Workspace_form.Task = "");
  check "prefilling form creates no job or task"
    (controller.creation_request = None
    && controller.creation_job = None
    && Controller.snapshot controller = saved);
  Controller.act controller Controller.Cancel_workspace;
  Controller.set_workspace_defaults controller Workspace_defaults.empty;
  controller.jj_executable <- "";
  let temporary = Filename.temp_file "factory-form" "" in
  Sys.remove temporary;
  Unix.mkdir temporary 0o700;
  let temporary = Unix.realpath temporary in
  let rec remove path =
    if (Unix.lstat path).Unix.st_kind = Unix.S_DIR then (
      Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path);
      Unix.rmdir path)
    else Sys.remove path
  in
  Scope.on_exit
    (fun () -> remove temporary)
    (fun () ->
      let source = Filename.concat temporary "repo" in
      Unix.mkdir source 0o700;
      let result =
        ok
          (Command.run ~executable:"/opt/homebrew/bin/jj"
             ~arguments:[ "git"; "init"; "--colocate" ]
             ~directory:source ~timeout:15. ~max_output:2097152)
      in
      check "temporary source initialized" (result.status = Unix.WEXITED 0);
      let database = Filename.concat temporary "board.sqlite" in
      let worker, _ = ok (Persistence.start database) in
      Scope.on_exit
        (fun () -> ignore (Persistence.close worker))
        (fun () ->
          controller.database_path <- Some database;
          Controller.act controller Controller.Begin_workspace;
          let form = Option.get controller.workspace_form in
          fill form Workspace_form.Jj "/opt/homebrew/bin/jj";
          fill form Workspace_form.Source source;
          fill form Workspace_form.Parent temporary;
          fill form Workspace_form.Task "An isolated workspace task";
          check "valid form passes" (Workspace_form.validate form = Ok ());
          let before = List.length controller.tasks in
          Controller.key controller (`ASCII 'S', [ `Ctrl ]);
          check "Ctrl-S queues explicit request" (controller.creation_request <> None);
          check "submission reports form-local creation state"
            (Workspace_form.status form = "Creating workspace. No agent starts.");
          Controller.poll_creation controller ~storage:(Some worker);
          check "creation job is owned by controller" (controller.creation_job <> None);
          Controller.key controller (`ASCII 'n', []);
          check "busy modal cannot create demo task"
            (List.length controller.tasks = before);
          let deadline = Unix.gettimeofday () +. 5. in
          while controller.creation_job <> None && Unix.gettimeofday () < deadline do
            Controller.poll_creation controller ~storage:(Some worker);
            Thread.delay 0.01
          done;
          check "bounded job completes"
            (controller.creation_job = None && controller.workspace_form = None);
          let task = Option.get (Controller.selected controller) in
          check "new task selected with chat focus"
            (controller.focus = Controller.Conversation
            && List.length controller.tasks = before + 1);
          check "new task queued not running"
            (task.state = Model.Queued && task.runs = [] && task.active = None);
          check "new task contains real isolated workspace"
            (let reference = Option.get task.workspace in
             reference.source = source && Sys.is_directory reference.directory);
          check "task instruction queued"
            ((List.hd task.messages).text = "An isolated workspace task"
            && (List.hd task.messages).queued);
          ok (Persistence.submit worker (Controller.snapshot controller) ~events:[]);
          ok (Persistence.flush worker);
          Controller.act controller Controller.Begin_workspace;
          let form = Option.get controller.workspace_form in
          check "new form remembers source and exact base"
            (let reference = Option.get task.workspace in
             Workspace_form.value form Workspace_form.Source = source
             && Workspace_form.value form Workspace_form.Revision = reference.base);
          check "session jj executable reused"
            (Workspace_form.value form Workspace_form.Jj = "/opt/homebrew/bin/jj");
          Controller.act controller Controller.Cancel_workspace;
          Controller.set_workspace_defaults controller
            { Workspace_defaults.empty with revision = Some "configured-base" };
          Controller.act controller Controller.Begin_workspace;
          let form = Option.get controller.workspace_form in
          check "explicit defaults override saved values only for specified fields"
            (Workspace_form.value form Workspace_form.Revision = "configured-base"
            && Workspace_form.value form Workspace_form.Source = source
            && Workspace_form.value form Workspace_form.Jj = "/opt/homebrew/bin/jj");
          check "new instruction starts blank"
            (Workspace_form.value form Workspace_form.Task = "");
          Controller.act controller Controller.Cancel_workspace;
          let request : Task_creation.request =
            {
              id = task.id;
              greenfield = false;
              folder_root = false;
              jj = "/opt/homebrew/bin/jj";
              source;
              parent = temporary;
              revision = "@";
              model = "coding-large";
              instruction = "Another task";
            }
          in
          let job = Task_creation.start request in
          Task_creation.close job;
          check "failed creation cannot overwrite destination"
            (match Task_creation.result job with Some (Error _) -> true | _ -> false);
          check "failed creation retains original files"
            (Sys.is_directory (Option.get task.workspace).directory);
          Controller.set_workspace_defaults controller Workspace_defaults.empty;
          Controller.act controller Controller.Begin_workspace;
          let form = Option.get controller.workspace_form in
          controller.creation_request <- Some request;
          Controller.poll_creation controller ~storage:(Some worker);
          let deadline = Unix.gettimeofday () +. 5. in
          while controller.creation_job <> None && Unix.gettimeofday () < deadline do
            Controller.poll_creation controller ~storage:(Some worker);
            Thread.delay 0.01
          done;
          check "creation failure leaves form open with its own error"
            (controller.workspace_form <> None
            && controller.creation_job = None
            && Workspace_form.status form = controller.status
            && not (Controller.contains (Workspace_form.status form) "Fill the fields"));
          check "failed form retains source and existing destination"
            (Workspace_form.value form Workspace_form.Source = source
            && Sys.is_directory (Option.get task.workspace).directory);
          Controller.act controller Controller.Cancel_workspace));
  Printf.printf "Passed %d workspace form checks. Temporary repositories only.\n" !checks
