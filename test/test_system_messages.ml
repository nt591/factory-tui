open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let ids (task : Model.task) =
  List.map (fun (message : Model.message) -> message.id) task.messages

let () =
  let task =
    Model.make ~id:"notices" ~title:"Original instruction" ~repository:"fixture"
  in
  let first = Model.system task "First diagnostic" in
  let second = Model.system first "Second diagnostic" in
  let third = Model.system second "Third diagnostic" in
  check "ordinary notice retains established ID"
    (List.nth (ids first) 1 = "notices/system/0");
  check "same-revision notices have distinct stable identities"
    (ids third
    = [ "notices/prompt"; "notices/system/0"; "notices/system/0/1"; "notices/system/0/2" ]
    );
  check "notices retain prior message records"
    (List.hd first.messages == List.hd task.messages
    && List.nth third.messages 1 == List.nth first.messages 1);
  check "notices do not consume queued instructions"
    (Run_prompt.queued third = Run_prompt.queued task
    && third.revision = task.revision
    && third.state = task.state);
  check "notice content stays in chronological order"
    (List.map (fun (message : Model.message) -> message.text) third.messages
    = [
        "Original instruction";
        "First diagnostic";
        "Second diagnostic";
        "Third diagnostic";
      ]);
  let colliding =
    {
      task with
      messages =
        task.messages
        @ [
            {
              Model.id = "notices/system/0";
              author = "You";
              text = "Queued user reply";
              queued = true;
            };
            {
              Model.id = "notices/system/0/1";
              author = "Legacy";
              text = "Retained imported message";
              queued = false;
            };
          ];
    }
  in
  let collision_result = Model.system colliding "Another diagnostic" in
  check "notice cannot overwrite user or imported identity"
    (List.hd (List.rev (ids collision_result)) = "notices/system/0/2"
    && List.filter
         (fun (message : Model.message) -> message.author <> "Factory")
         collision_result.messages
       = colliding.messages);
  let many =
    List.fold_left
      (fun task index -> Model.system task (Printf.sprintf "Diagnostic %d" index))
      task (List.init 200 Fun.id)
  in
  check "many same-revision notices keep unique IDs"
    (List.length (List.sort_uniq String.compare (ids many)) = List.length many.messages);
  let controller = Controller.create ~external_events:true () in
  controller.tasks <- [ third ];
  controller.selected <- third.id;
  let saved = Controller.snapshot controller in
  let decoded = Result.get_ok (Snapshot.decode (Snapshot.encode saved)) in
  check "same-revision notices roundtrip the strict snapshot codec" (decoded = saved);
  Controller.restore controller decoded;
  Controller.act controller Controller.Zoom;
  let frame = Ui.render controller ~width:120 ~height:36 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  check "restored chat shows every diagnostic"
    (List.for_all
       (Controller.contains (Buffer.contents buffer))
       [ "First diagnostic"; "Second diagnostic"; "Third diagnostic" ]);
  let directory = Filename.temp_file "factory-system-messages" "" in
  Sys.remove directory;
  Unix.mkdir directory 0o700;
  let database = Filename.concat directory "board.sqlite" in
  Scope.on_exit
    (fun () ->
      Array.iter
        (fun name -> Sys.remove (Filename.concat directory name))
        (Sys.readdir directory);
      Unix.rmdir directory)
    (fun () ->
      let worker, _ = Result.get_ok (Persistence.start database) in
      let () =
        Scope.on_exit
          (fun () -> ignore (Persistence.close worker))
          (fun () ->
            ignore (Result.get_ok (Persistence.submit worker saved ~events:[]));
            ignore (Result.get_ok (Persistence.flush worker)))
      in
      let reopened, loaded = Result.get_ok (Persistence.start database) in
      Scope.on_exit
        (fun () -> ignore (Persistence.close reopened))
        (fun () ->
          check "SQLite reopen retains all notices with exact identities"
            (loaded = Some saved)));
  Printf.printf
    "Passed %d Factory notice identity checks. Pure messages and temporary SQLite only.\n"
    !checks
