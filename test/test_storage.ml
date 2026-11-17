open Factory_tui
open Model
let checks = ref 0
let check name condition = incr checks; if not condition then failwith name
let ok = function Ok value -> value | Error error -> failwith error
let snapshot () : Snapshot.t = { tasks = Demo.seed (); drafts = ["T-102", "Keep this draft"]; selected = "T-102"; serial = 255 }
let sql db sql = if Sqlite3.exec db sql <> Sqlite3.Rc.OK then failwith "Test SQL failed"
let with_temp fn =
  let dir = Filename.temp_file "factory-storage" "" in
  Sys.remove dir; Unix.mkdir dir 0o700;
  Fun.protect ~finally:(fun () ->
    Array.iter (fun name -> Sys.remove (Filename.concat dir name)) (Sys.readdir dir);
    Unix.rmdir dir) (fun () -> fn dir)
let () =
  if Array.length Sys.argv = 3 && Sys.argv.(1) = "--probe" then (
    match Storage.open_store Sys.argv.(2) with
    | Error _ -> exit 0 | Ok store -> Storage.close store; exit 1);
  let initial = snapshot () in
  check "snapshot round trip" (ok (Snapshot.decode (Snapshot.encode initial)) = initial);
  check "invalid snapshot fails" (Result.is_error (Snapshot.decode "{}"));
  let recovered = Snapshot.recover initial in
  let task = List.find (fun (t : task) -> t.id = "T-102") recovered.tasks in
  check "restart moves Working to Needs you" (task.state = Needs_you && task.active = None);
  check "restart retains queued messages" ((List.hd task.messages).queued);
  check "restart records interruption" ((List.hd task.runs).status = Stopped && (List.hd task.runs).ended_at <> None);
  check "recovery is idempotent" (Snapshot.recover recovered = recovered);
  check "recovery retains draft and selection" (recovered.drafts = initial.drafts && recovered.selected = initial.selected);
  let duplicate = {initial with tasks = initial.tasks @ [List.hd initial.tasks]} in
  check "duplicate task IDs rejected" (Result.is_error (Snapshot.decode (Snapshot.encode duplicate)));
  let broken = {task with state = Working; active = None} in
  check "invalid run state rejected" (Result.is_error (Snapshot.decode (Snapshot.encode {initial with tasks = [broken]})));
  let event = {task_id = "T-102"; run_id = "demo-102"; event = Message ("message", "Sensitive 'text'\n界")} in
  check "event codec round trip" (ok (Events.decode (Events.encode event)) = event);
  with_temp (fun dir ->
    let path = Filename.concat dir "board.sqlite" in
    check "relative paths rejected" (Result.is_error (Storage.open_store "board.sqlite"));
    let store = ok (Storage.open_store path) in
    Fun.protect ~finally:(fun () -> Storage.close store) (fun () ->
      check "new database is empty" (ok (Storage.load store) = None);
      check "private database permissions" ((Unix.stat path).Unix.st_perm land 0o077 = 0);
      check "private lock permissions" ((Unix.stat (path ^ ".lock")).Unix.st_perm land 0o077 = 0);
      check "same-process exclusive ownership" (Result.is_error (Storage.open_store path));
      let pid = Unix.create_process Sys.executable_name [|Sys.executable_name; "--probe"; path|] Unix.stdin Unix.stdout Unix.stderr in
      let _, status = Unix.waitpid [] pid in
      check "cross-process exclusive ownership" (status = Unix.WEXITED 0);
      ok (Storage.save store initial ~events:[event; {event with event = Turn_completed}]);
      check "database snapshot round trip" (ok (Storage.load store) = Some initial);
      let page = ok (Storage.read_events store ~after:0L ~limit:1) in
      check "ordered event page" (List.length page = 1 && snd (List.hd page) = event);
      let rest = ok (Storage.read_events store ~after:(fst (List.hd page)) ~limit:10) in
      check "event cursor advances" (List.length rest = 1 && (snd (List.hd rest)).event = Turn_completed);
      check "invalid event limits rejected" (Result.is_error (Storage.read_events store ~after:0L ~limit:1025));
      let db = Sqlite3.db_open ~mode:`NO_CREATE path in
      Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) (fun () ->
        let count = Sqlite3.prepare db "SELECT count(*) FROM runs" in
        check "run records stored separately" (Sqlite3.step count = Sqlite3.Rc.ROW && Sqlite3.column_int count 0 = 3);
        ignore (Sqlite3.finalize count);
        sql db "CREATE TRIGGER fail_event BEFORE INSERT ON events BEGIN SELECT RAISE(ABORT,'fixture'); END";
        check "write failure is reported" (Result.is_error (Storage.save store recovered ~events:[event]));
        check "failed batch rolls back snapshot" (ok (Storage.load store) = Some initial);
        check "failed batch rolls back events" (List.length (ok (Storage.read_events store ~after:0L ~limit:10)) = 2);
        sql db "DROP TRIGGER fail_event";
        check "invalid snapshot not saved" (Result.is_error (Storage.save store duplicate ~events:[]));
        sql db "BEGIN IMMEDIATE";
        check "busy write fails with bounded wait" (Result.is_error (Storage.save store recovered ~events:[]));
        sql db "ROLLBACK";
        ok (Storage.save store recovered ~events:[])));
    Storage.close store;
    check "closed handle refuses load" (Result.is_error (Storage.load store));
    let store = ok (Storage.open_store path) in
    check "saved recovery survives reopening" (ok (Storage.load store) = Some recovered);
    Storage.close store;
    let foreign = Filename.concat dir "foreign.sqlite" in
    let db = Sqlite3.db_open foreign in sql db "CREATE TABLE unrelated(value TEXT)"; ignore (Sqlite3.db_close db);
    check "foreign database refused" (Result.is_error (Storage.open_store foreign));
    let future = Filename.concat dir "future.sqlite" in
    let db = Sqlite3.db_open future in sql db "PRAGMA user_version=99"; ignore (Sqlite3.db_close db);
    check "future schema refused" (Result.is_error (Storage.open_store future));
    let symlink = Filename.concat dir "link.sqlite" in Unix.symlink path symlink;
    check "symlink database refused" (Result.is_error (Storage.open_store symlink));
    let corrupt = Filename.concat dir "corrupt.sqlite" in
    let store = ok (Storage.open_store corrupt) in Storage.close store;
    let db = Sqlite3.db_open corrupt in sql db "INSERT INTO snapshot VALUES(1,'bad json')"; ignore (Sqlite3.db_close db);
    let store = ok (Storage.open_store corrupt) in
    check "corrupt snapshot fails without replacement" (Result.is_error (Storage.load store)); Storage.close store);
  with_temp (fun dir ->
    let path = Filename.concat dir "worker.sqlite" in
    let worker, loaded = ok (Persistence.start path) in
    check "new worker loads no snapshot" (loaded = None);
    check "worker owns database" (Result.is_error (Persistence.start path));
    for serial = 1 to 200 do
      ok (Persistence.submit worker {initial with serial} ~events:[{event with event = Tool (string_of_int serial, "fixture")}])
    done;
    ok (Persistence.flush worker);
    ok (Persistence.close worker);
    check "closed worker rejects saves" (Result.is_error (Persistence.submit worker initial ~events:[]));
    let store = ok (Storage.open_store path) in
    check "coalesced worker saves final snapshot" ((Option.get (ok (Storage.load store))).serial = 200);
    check "coalescing preserves every event" (List.length (ok (Storage.read_events store ~after:0L ~limit:1024)) = 200);
    Storage.close store;
    let worker, loaded = ok (Persistence.start path) in
    let restored = Controller.create () in Controller.restore restored (Option.get loaded);
    check "UI restore retains drafts" (Controller.draft restored = "Keep this draft");
    check "UI restore recovers interrupted run" ((Option.get (Controller.selected restored)).state = Needs_you && restored.schedules = []);
    ok (Persistence.submit worker recovered ~events:[]);
    ok (Persistence.close worker);
    let store = ok (Storage.open_store path) in
    check "close drains final save" (ok (Storage.load store) = Some recovered);
    Storage.close store;
    let worker, _ = ok (Persistence.start path) in
    let db = Sqlite3.db_open path in
    sql db "CREATE TRIGGER fail_save BEFORE INSERT ON snapshot BEGIN SELECT RAISE(ABORT,'fixture'); END";
    ok (Persistence.submit worker initial ~events:[]);
    check "flush returns worker write failure" (Result.is_error (Persistence.flush worker));
    check "worker error is visible" (Persistence.error worker <> None);
    check "failed worker rejects saves" (Result.is_error (Persistence.submit worker initial ~events:[]));
    check "close returns worker failure" (Result.is_error (Persistence.close worker));
    ignore (Sqlite3.db_close db));
  Printf.printf "Passed %d storage checks. Temporary files only.\n" !checks
