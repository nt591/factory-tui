open Factory_tui
open Controller

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let () =
  let folder = Filename.temp_file "factory-send" "" in
  Sys.remove folder;
  Unix.mkdir folder 0o700;
  let folder = Unix.realpath folder in
  Fun.protect
    ~finally:(fun () -> Unix.rmdir folder)
    (fun () ->
      let config = ok (Live_runner.configure ~executable:"/bin/sh" ~gateway_file:None) in
      let controller = Controller.create () in
      controller.database_path <- Some "/fixture/not-opened.sqlite";
      let task =
        ok
          (Model.attach_root
             (Model.make ~id:"send" ~title:"Initial instruction" ~repository:"")
             folder)
      in
      controller.tasks <- [ task ];
      controller.selected <- task.id;
      ok (Controller.enable_live controller config);
      Controller.act controller Begin_compose;
      Controller.set_input controller "Follow-up";
      Controller.key controller (`Enter, []);
      let working = Option.get (Controller.selected controller) in
      check "Enter on idle reply starts captured run without popup"
        (working.state = Model.Working && working.active <> None);
      Controller.act controller Begin_compose;
      Controller.set_input controller "Later instruction";
      Controller.key controller (`Enter, []);
      let updated = Option.get (Controller.selected controller) in
      check "reply during work leaves active run and captured IDs unchanged"
        (updated.active = working.active
        && updated.runs = working.runs
        && List.exists
             (fun (m : Model.message) -> m.text = "Later instruction" && m.queued)
             updated.messages);
      Controller.act controller Stop;
      Controller.act controller Begin_compose;
      Controller.set_input controller "";
      Controller.key controller (`Enter, []);
      check "empty submission does not start a run"
        ((Option.get (Controller.selected controller)).state = Model.Needs_you);
      Controller.key controller (`Escape, []);
      let accepted = { task with id = "accepted"; state = Model.Done } in
      controller.tasks <- controller.tasks @ [ accepted ];
      controller.zoom <- true;
      Controller.act controller Toggle_archive;
      check "archive navigation reveals archive board"
        (controller.archive && (not controller.zoom) && controller.focus = Board);
      let creator = Controller.create () in
      creator.database_path <- Some "/fixture/not-opened.sqlite";
      Controller.set_workspace_defaults creator
        {
          Workspace_defaults.empty with
          mode = Folder;
          source = Some folder;
          model = Some "fixture-model";
        };
      Controller.act creator Begin_workspace;
      let form = Option.get creator.workspace_form in
      Workspace_form.key form (`ASCII 'x', []);
      Controller.act creator Send_workspace;
      check "task send captures execution intent" creator.creation_send;
      creator.creation_request <- None;
      Controller.act creator Submit_workspace;
      check "save-only retry clears previous execution intent"
        ((not creator.creation_send) && creator.creation_request <> None);
      let frame = Ui.render controller ~width:60 ~height:20 in
      check "compact archive has visible return control"
        (List.exists
           (fun (hit : Ui.hit) -> hit.rect.y = 18 && hit.action = Session_board)
           frame.hits);
      controller.zoom <- true;
      Controller.key controller (`ASCII 'b', []);
      check "b always returns to visible active board"
        ((not controller.archive) && (not controller.zoom) && controller.focus = Board);
      Controller.act controller Archive_view;
      Controller.key controller (`Escape, []);
      check "Escape returns from archive board" (not controller.archive));
  Printf.printf
    "Passed %d direct-send/archive checks. Pure task state; no process or gateway.\n"
    !checks
