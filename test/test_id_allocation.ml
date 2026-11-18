open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let task id = Model.make ~id ~title:"Retained task" ~repository:"fixture"

let () =
  let retained = [ task "T-1"; task "T-2" ] in
  check "stale task counter skips retained IDs"
    (Id_allocation.next ~prefix:"T" ~serial:0 retained = ("T-3", 3));
  let with_messages =
    {
      (task "original") with
      messages =
        [
          {
            Model.id = "message-1";
            author = "You";
            text = "Retained reply";
            queued = true;
          };
          {
            Model.id = "demo-run-2/reply";
            author = "Legacy";
            text = "Retained output";
            queued = false;
          };
        ];
    }
  in
  check "reply allocation skips retained message identity"
    (Id_allocation.next ~prefix:"message" ~serial:0 [ with_messages ] = ("message-2", 2));
  check "run allocation reserves retained scoped output namespace"
    (Id_allocation.next ~prefix:"demo-run" ~serial:1 [ with_messages ] = ("demo-run-3", 3));
  let with_tools =
    { with_messages with tools = [ ("live-run-4/nested/tool", "payload") ] }
  in
  check "tool namespaces are reserved"
    (Id_allocation.next ~prefix:"live-run" ~serial:3 [ with_tools ] = ("live-run-5", 5));
  let running = Result.get_ok (Model.start (task "active") "demo-run-1") in
  check "recorded run IDs are reserved across tasks"
    (Id_allocation.next ~prefix:"demo-run" ~serial:0 [ running ] = ("demo-run-2", 2));
  check "integer-limit counter wraps without collision or negative output"
    (Id_allocation.next ~prefix:"T" ~serial:max_int [ task "T-0"; task "T-1" ]
    = ("T-2", 2));
  check "normal noncolliding counter sequence stays unchanged"
    (Id_allocation.next ~prefix:"T" ~serial:200 retained = ("T-201", 201));
  let controller = Controller.create ~external_events:true () in
  let snapshot : Snapshot.t =
    { tasks = retained; drafts = []; selected = "T-1"; serial = 0 }
  in
  let decoded = Result.get_ok (Snapshot.decode (Snapshot.encode snapshot)) in
  Controller.restore controller decoded;
  Controller.act controller Controller.Begin_new;
  Controller.set_input controller "New task after import";
  Controller.submit controller;
  check "restored stale counter creates new task without duplication"
    (controller.selected = "T-3" && List.length controller.tasks = 3);
  check "retained task/message records remain exact"
    (List.filter (fun (t : Model.task) -> t.id <> "T-3") controller.tasks = retained);
  controller.serial <- 0;
  controller.tasks <- [ with_messages ];
  controller.selected <- with_messages.id;
  Controller.act controller Controller.Begin_compose;
  Controller.set_input controller "New reply after import";
  Controller.submit controller;
  check "reply submission skips occupied ID rather than losing draft"
    (List.exists
       (fun (m : Model.message) ->
         m.id = "message-2" && m.text = "New reply after import")
       (Option.get (Controller.selected controller)).messages
    && Controller.draft controller = "");
  let demo = Controller.create () in
  demo.schedules <- [];
  demo.tasks <- controller.tasks;
  demo.selected <- controller.selected;
  demo.serial <- 1;
  Controller.act demo Controller.Start;
  check "demo run starts in unoccupied namespace"
    ((Option.get (Option.get (Controller.selected demo)).active).id = "demo-run-3");
  check "updated snapshot roundtrips with allocated identities"
    (let saved = Controller.snapshot controller in
     Snapshot.decode (Snapshot.encode saved) = Ok saved);
  let directory = Filename.temp_file "factory-stale-counter" "" in
  Sys.remove directory;
  Unix.mkdir directory 0o700;
  Scope.on_exit
    (fun () ->
      Array.iter
        (fun name -> Sys.remove (Filename.concat directory name))
        (Sys.readdir directory);
      Unix.rmdir directory)
    (fun () ->
      let database = Filename.concat directory "board.sqlite" in
      let worker, _ = Result.get_ok (Persistence.start database) in
      Scope.on_exit
        (fun () -> ignore (Persistence.close worker))
        (fun () ->
          ignore (Result.get_ok (Persistence.submit worker snapshot ~events:[]));
          ignore (Result.get_ok (Persistence.flush worker)));
      let worker, loaded = Result.get_ok (Persistence.start database) in
      Scope.on_exit
        (fun () -> ignore (Persistence.close worker))
        (fun () ->
          let controller = Controller.create ~external_events:true () in
          Controller.restore controller (Option.get loaded);
          Controller.act controller Controller.Begin_new;
          Controller.set_input controller "Persisted new task";
          Controller.submit controller;
          ignore
            (Result.get_ok
               (Persistence.submit worker (Controller.snapshot controller) ~events:[]));
          ignore (Result.get_ok (Persistence.flush worker));
          check "SQLite stale-counter restart retains old tasks and saves new unique task"
            (controller.selected = "T-3" && List.length controller.tasks = 3)));
  Printf.printf
    "Passed %d ID allocation checks. Pure identities and temporary SQLite only.\n" !checks
