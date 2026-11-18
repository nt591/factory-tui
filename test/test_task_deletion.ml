open Factory_tui
open Model
open Controller

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let ok = function Ok value -> value | Error error -> failwith error
let ctrl_x t = Controller.key t (`ASCII 'X', [ `Ctrl ])
let type_delete t = String.iter (fun char -> Controller.key t (`ASCII char, [])) "delete"

let confirm t =
  type_delete t;
  Controller.key t (`Enter, [])

let task =
  let queued = Model.make ~id:"remove" ~title:"Delete fixture" ~repository:"fixture" in
  let started = ok (Model.start ~simulated:true queued "run") in
  let apply task event =
    Option.get (Model.apply task { task_id = task.id; run_id = "run"; event })
  in
  apply (apply started Turn_completed) (Exited 0)

let other = Model.make ~id:"keep" ~title:"Keep fixture" ~repository:"fixture"

let event id =
  { task_id = id; run_id = "run"; event = Message ("event", "Fixture event") }

let controller () =
  let t = Controller.create ~external_events:true () in
  t.tasks <- [ task; other ];
  t.selected <- task.id;
  t.drafts <- [ (task.id, "Retained draft"); (other.id, "Other draft") ];
  t

let with_directory fn =
  let dir = Filename.temp_file "factory-deletion-test-" "" in
  Sys.remove dir;
  Unix.mkdir dir 0o700;
  Fun.protect
    ~finally:(fun () ->
      Array.iter (fun name -> Sys.remove (Filename.concat dir name)) (Sys.readdir dir);
      Unix.rmdir dir)
    (fun () -> fn dir)

let () =
  let t = controller () in
  let saved = Controller.snapshot t in
  ctrl_x t;
  check "Ctrl-X opens a confirmation without changing task data"
    (t.deletion <> None && Controller.snapshot t = saved);
  Controller.key t (`Enter, []);
  check "empty Enter cannot delete" (Controller.snapshot t = saved);
  Controller.key t (`ASCII 'y', []);
  Controller.key t (`Enter, []);
  check "single-letter confirmation cannot delete" (Controller.snapshot t = saved);
  Controller.key t (`Escape, []);
  check "Escape cancels" (t.deletion = None && Controller.snapshot t = saved);
  ctrl_x t;
  List.iter
    (fun (width, height) ->
      let frame = Ui.render t ~width ~height in
      check "confirmation suppresses background mouse and scroll targets"
        (frame.columns = [] && frame.panes = [] && frame.scroll_panes = []
        && List.for_all (fun (hit : Ui.hit) -> hit.action = Cancel_delete) frame.hits);
      check "confirmation fits the terminal"
        (Notty.I.width frame.image = width && Notty.I.height frame.image = height))
    [ (1, 1); (20, 8); (60, 20); (120, 36); (240, 50) ];
  let frame = Ui.render t ~width:120 ~height:36 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  let rows = String.split_on_char '\n' (Buffer.contents buffer) in
  check "confirmation footer hides background task controls"
    ((not (Controller.contains (List.nth rows 34) "Archive"))
    && not (Controller.contains (List.nth rows 34) "reply"));
  Ui.mouse t frame ~now:0. (`Press `Left, (1, 4), []);
  check "background click cannot select another task" (t.selected = task.id);
  let cancel = List.find (fun (hit : Ui.hit) -> hit.action = Cancel_delete) frame.hits in
  Ui.mouse t frame ~now:0. (`Press `Left, (cancel.rect.x, cancel.rect.y), []);
  check "mouse cancellation preserves data"
    (t.deletion = None && Controller.snapshot t = saved);
  Controller.act t Begin_compose;
  ctrl_x t;
  Controller.key t (`Escape, []);
  check "cancel from insert mode retains editor and draft"
    (t.input = Compose && Controller.draft t = "Retained draft");
  Controller.key t (`Escape, []);
  ctrl_x t;
  String.iter (fun char -> Controller.paste_key t (`ASCII char, [])) "delete";
  Controller.paste_key t (`Enter, []);
  check "paste cannot confirm deletion" (Controller.snapshot t = saved);
  t.storage_events <- [ event task.id; event other.id ];
  t.schedules <- [ (1., event task.id); (1., event other.id) ];
  Controller.act t (Select other.id);
  Controller.key t (`Enter, []);
  check "dialog deletes its captured target, not the later selection"
    (t.tasks = [ other ] && t.selected = other.id);
  check "deletion removes only target drafts/events/schedules"
    (t.drafts = [ (other.id, "Other draft") ]
    && t.storage_events = [ event other.id ]
    && t.schedules = [ (1., event other.id) ]);
  Controller.receive t (event task.id);
  check "late events cannot recreate a deleted task" (t.tasks = [ other ]);
  ctrl_x t;
  confirm t;
  check "deleting the last task leaves a valid empty board"
    (t.tasks = [] && t.selected = "" && t.drafts = [] && (not t.zoom) && t.focus = Board);
  check "empty board round trips"
    (ok (Snapshot.decode (Snapshot.encode (Controller.snapshot t)))
    = Controller.snapshot t);
  List.iter
    (fun state ->
      let t = controller () in
      t.tasks <- [ { task with state; active = None } ];
      ctrl_x t;
      check "idle tasks in all lanes and Archive can be deleted" (t.deletion <> None))
    [ Queued; Needs_you; Ready; Done ];
  List.iter
    (fun setup ->
      let t = controller () in
      setup t;
      ctrl_x t;
      check "active, waiting or unreaped tasks cannot open deletion" (t.deletion = None))
    [
      (fun t -> t.tasks <- [ ok (Model.start ~simulated:true task "running") ]);
      (fun t -> t.tasks <- [ { task with state = Working } ]);
      (fun t -> t.owned_tasks <- [ task.id ]);
      (fun t -> t.live_waiting_tasks <- [ task.id ]);
    ];
  let t = controller () in
  ctrl_x t;
  t.owned_tasks <- [ task.id ];
  confirm t;
  check "confirmation rechecks process ownership"
    (t.tasks = [ task; other ] && t.deletion = None);
  let t = controller () in
  t.status <- "Storage error: fixture";
  ctrl_x t;
  check "storage warning blocks deletion"
    (t.deletion = None && t.status = "Storage error: fixture");
  with_directory (fun dir ->
      let path = Filename.concat dir "board.sqlite" in
      let sentinel = Filename.concat dir "workspace-file" in
      let output = open_out sentinel in
      output_string output "Keep workspace file";
      close_out output;
      let t = controller () in
      t.tasks <- [ { task with session_root = Some dir; repository = dir }; other ];
      let initial = Controller.snapshot t in
      let store = ok (Storage.open_store path) in
      ok (Storage.save store initial ~events:[ event task.id; event other.id ]);
      let db = Sqlite3.db_open ~mode:`NO_CREATE path in
      check "fixture trigger installs"
        (Sqlite3.exec db
           "CREATE TRIGGER refuse_delete BEFORE DELETE ON events BEGIN SELECT \
            RAISE(FAIL,'fixture'); END"
        = Sqlite3.Rc.OK);
      let candidate =
        {
          initial with
          tasks = [ other ];
          drafts = [ (other.id, "Other draft") ];
          selected = other.id;
        }
      in
      check "failed deletion transaction rejects the candidate"
        (Result.is_error (Storage.save store candidate ~events:[]));
      check "failed deletion rolls back snapshot and events"
        (ok (Storage.load store) = Some initial
        && List.length (ok (Storage.read_events store ~after:0L ~limit:10)) = 2);
      ignore (Sqlite3.exec db "DROP TRIGGER refuse_delete");
      ignore (Sqlite3.db_close db);
      Storage.close store;
      let worker, _ = ok (Persistence.start path) in
      t.database_path <- Some path;
      ctrl_x t;
      confirm t;
      check "persistent deletion waits for its checkpoint"
        (Controller.snapshot t = initial && t.deletion_request = Some task.id);
      Controller.poll_deletion t ~storage:(Some worker);
      check "successful checkpoint publishes task deletion"
        (Controller.snapshot t = candidate && t.deletion = None);
      ok (Persistence.close worker);
      let store = ok (Storage.open_store path) in
      check "deletion survives database restart" (ok (Storage.load store) = Some candidate);
      let events = ok (Storage.read_events store ~after:0L ~limit:10) in
      check "task event history is removed and other history stays"
        (List.map snd events = [ event other.id ]);
      Storage.close store;
      let input = open_in sentinel in
      let contents = really_input_string input (in_channel_length input) in
      close_in input;
      check "workspace files remain untouched" (contents = "Keep workspace file"));
  with_directory (fun dir ->
      let path = Filename.concat dir "failed.sqlite" in
      let t = controller () in
      let initial = Controller.snapshot t in
      let store = ok (Storage.open_store path) in
      ok (Storage.save store initial ~events:[ event task.id ]);
      Storage.close store;
      let db = Sqlite3.db_open ~mode:`NO_CREATE path in
      ignore
        (Sqlite3.exec db
           "CREATE TRIGGER fail_delete BEFORE DELETE ON events BEGIN SELECT \
            RAISE(FAIL,'fixture'); END");
      ignore (Sqlite3.db_close db);
      let worker, _ = ok (Persistence.start path) in
      t.database_path <- Some path;
      ctrl_x t;
      confirm t;
      Controller.poll_deletion t ~storage:(Some worker);
      check "failed checkpoint keeps the task, history and draft in memory"
        (Controller.snapshot t = initial
        && t.deletion <> None
        && String.starts_with ~prefix:"Storage error:" t.status);
      check "failed deletion is not reported as success"
        (not (Controller.contains t.status "Task deleted"));
      ignore (Persistence.close worker);
      let store = ok (Storage.open_store path) in
      check "failed checkpoint retains the stored task and event"
        (ok (Storage.load store) = Some initial
        && List.map snd (ok (Storage.read_events store ~after:0L ~limit:10))
           = [ event task.id ]);
      Storage.close store);
  Printf.printf
    "Passed %d task-deletion checks. Temporary SQLite/files; no agents or network.\n"
    !checks
